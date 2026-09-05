// Stainless - an experimental systems language.
// Copyright (C) 2026 Brandon Scott
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

using Stainless.Binding;
using Xunit;

namespace Stainless.UnitTests;

/// <summary>
/// The IR, read as text.
///
/// A program that runs proves the two halves of a call agree with each other,
/// which they would if both were wrong in the same way. These read what was
/// actually written -- which retain, which offset, how many copies of a
/// literal -- and none of it is visible from a program's output.
/// </summary>
public class EmitterTests
{
    // -------------------------------------------------------- reproducibility

    /// <summary>
    /// The same source emits the same text, twice, through two independent
    /// binds.
    ///
    /// Nothing else can catch this. A hash table walked in insertion order
    /// gives a stable build on one machine and a different one on the next, and
    /// every end-to-end case would keep passing on both.
    /// </summary>
    [Fact]
    public void TheSameSourceEmitsTheSameText()
    {
        const string source = """
            public class C { public int A; public C() { A = 1; } }
            public interface I { int F(); }
            public class D : C, I { public int F() { return A; } }
            public struct S { public int X; public double Y; }
            public int G(S s) { var d = new D(); return d.F() + s.X; }
            """;

        Assert.Equal(Front.ModuleIr(source), Front.ModuleIr(source));
    }

    // ------------------------------------------------------------------ ARC

    /// <summary>
    /// A local holding an object releases it at the end of its scope. Getting
    /// this wrong is a leak, which a test program does not notice.
    /// </summary>
    [Fact]
    public void ALocalReleasesWhatItHeld()
    {
        string body = Front.TestFunction(
            Front.ModuleIr("public class C { }\npublic void F() { var c = new C(); }"), "F");

        Assert.Contains("call void @sl_retain(", body);
        Assert.Contains("call void @sl_release(", body);
    }

    /// <summary>
    /// A function that touches no reference emits no counting at all, which is
    /// what makes ARC cost nothing where it is not needed.
    /// </summary>
    [Fact]
    public void ArithmeticCountsNothing()
    {
        string body = Front.TestFunction(
            Front.ModuleIr("public int F(int a, int b) { return a + b * 2; }"), "F");

        Assert.DoesNotContain("sl_retain", body);
        Assert.DoesNotContain("sl_release", body);
    }

    /// <summary>
    /// A weak reference goes through its own retain. There are three retains --
    /// object, weak and COM -- and open-coding the choice anywhere is how they
    /// drift apart.
    /// </summary>
    [Fact]
    public void AWeakReferenceUsesTheWeakRetain()
    {
        string ir = Front.ModuleIr(
            """
            public class C { }
            public class Holder { public weak C? Other; }
            public void F(Holder h, C c) { h.Other = c; }
            """);

        Assert.Contains("sl_weak_retain", Front.TestFunction(ir, "F"));
    }

    // ------------------------------------------------------------------ COM

    private const string ComSource = """
        import Standard.Com;

        [Guid("11111111-1111-1111-1111-111111111111")]
        public com interface IFirst { int A(); }

        [Guid("22222222-2222-2222-2222-222222222222")]
        public com interface ISecond : IFirst { int C(); }

        public com class Thing : ISecond
        {
            int field;
            public int A() { return field; }
            public int C() { return field; }
        }

        public int Borrow(IFirst i) { return i.A(); }
        public int Hold(IFirst i) { var mine = i; return mine.A(); }
        """;

    /// <summary>
    /// A COM reference is counted through AddRef and Release rather than
    /// through the object's own count, because the object on the other end may
    /// not be one of ours.
    /// </summary>
    [Fact]
    public void AComReferenceIsCountedThroughAddRef()
    {
        string body = Front.TestFunction(Front.ModuleIr(ComSource), "Hold");

        Assert.Contains("sl_com_retain", body);
        Assert.Contains("sl_com_release", body);
        Assert.DoesNotContain("call void @sl_retain(", body);
    }

    /// <summary>
    /// And a parameter is borrowed for the length of the call, so taking one
    /// counts nothing at all. A COM AddRef costs a call into somebody else's
    /// code, which makes this worth more here than it is for an object.
    /// </summary>
    [Fact]
    public void ABorrowedComReferenceIsNotCounted()
    {
        string body = Front.TestFunction(Front.ModuleIr(ComSource), "Borrow");

        Assert.DoesNotContain("sl_com_retain", body);
        Assert.DoesNotContain("sl_com_release", body);
    }

    /// <summary>
    /// Every COM vtable starts with the same three runtime functions, whichever
    /// interface it is for. That is what makes a Stainless object usable as an
    /// IUnknown by anything that has never heard of Stainless.
    /// </summary>
    [Fact]
    public void EveryComVtableStartsWithIUnknown()
    {
        string ir = Front.ModuleIr(ComSource);

        foreach (string table in Lines(ir, "@_SLcomvt_Test_Thing_"))
            Assert.Contains(
                "[ptr @sl_com_object_query, ptr @sl_com_object_add_ref, " +
                "ptr @sl_com_object_release,", table);
    }

    /// <summary>
    /// A tear-off holds its own distance back to the object, and each vtable
    /// slot is a thunk that subtracts exactly that.
    ///
    /// The distance is per tear-off, not per method: an inherited method
    /// reached through the derived interface needs a different thunk from the
    /// same method reached through the base one, because the two `this`
    /// pointers are sixteen bytes apart.
    /// </summary>
    [Fact]
    public void EachTearOffHasItsOwnAdjustor()
    {
        string ir = Front.ModuleIr(ComSource);

        // Header 24, one int rounded up to 32, then two tear-offs of 16 --
        // so ISecond's methods walk back 32 and IFirst's walk back 48. The
        // distance belongs to the tear-off, not to the method: `A` is
        // inherited and appears in both tables, with a different thunk in each.
        Assert.Contains("@_SLadj_Test_Thing_Test_ISecond_3(ptr %self)", ir);
        Assert.Contains("@_SLadj_Test_Thing_Test_IFirst_3(ptr %self)", ir);

        Assert.Equal(2, Occurrences(ir, "ptr %self, i64 -32"));
        Assert.Equal(1, Occurrences(ir, "ptr %self, i64 -48"));
    }

    /// <summary>
    /// The tear-offs are written when the object is made: each holds its
    /// vtable pointer and, next to it, its own distance from the header.
    /// </summary>
    [Fact]
    public void MakingAComObjectWritesItsTearOffs()
    {
        string body = Front.TestFunction(
            Front.ModuleIr(ComSource + "\npublic int Make() { var t = new Thing(); return t.A(); }"),
            "Make");

        Assert.Contains("store ptr @_SLcomvt_Test_Thing_Test_ISecond,", body);
        Assert.Contains("store ptr @_SLcomvt_Test_Thing_Test_IFirst,", body);
        Assert.Contains("store i64 32, ptr", body);
        Assert.Contains("store i64 48, ptr", body);
    }

    /// <summary>
    /// A GUID folds to sixteen bytes at compile time. It is emitted as the C
    /// layout -- a word, two halves and eight bytes -- rather than as text to
    /// be parsed at startup.
    /// </summary>
    [Fact]
    public void AGuidIsAConstant()
    {
        string iid = Lines(Front.ModuleIr(ComSource), "@_SLiid_Test_IFirst").Single();

        Assert.Contains("{ i32, i16, i16, [8 x i8] }", iid);
        Assert.Contains("i32 286331153", iid);
        Assert.Contains("[8 x i8] c\"\\11\\11\\11\\11\\11\\11\\11\\11\"", iid);
    }

    // -------------------------------------------------------------- literals

    /// <summary>
    /// Identical literals share one object, and it is immortal: a count of -1
    /// is what makes releasing a literal harmless without a branch.
    /// </summary>
    [Fact]
    public void IdenticalLiteralsShareOneImmortalObject()
    {
        string ir = Front.ModuleIr(
            """
            import Standard.Console;
            public void F() { Console.WriteLine("shared"); Console.WriteLine("shared"); }
            """);

        var objects = Lines(ir, "@.strobj").Where(l => l.Contains("c\"shared")).ToList();

        Assert.Single(objects);
        Assert.Contains("{ i64 -1, i64 -1,", objects[0]);
    }

    // ------------------------------------------------------------ dispatch

    /// <summary>
    /// An abstract class that implements an interface gets a null slot for the
    /// method it did not supply, exactly as the virtual table already did.
    ///
    /// It used to get a pointer to a symbol nothing defined, so the whole
    /// program failed at the linker with a message about the generated IR. The
    /// slot can never be reached: an abstract class has no instances, and a
    /// derived one fills it in its own table.
    /// </summary>
    [Fact]
    public void AnAbstractImplementationIsANullSlot()
    {
        string ir = Front.ModuleIr(
            """
            public interface IShape { int Area(); int Sides(); }

            public abstract class Shape : IShape {
                public abstract int Area();
                public int Sides() { return 4; }
            }

            public class Square : Shape {
                public override int Area() { return 1; }
            }
            """);

        string table = Lines(ir, "@_SLvt_Test_Shape_Test_IShape").Single();
        Assert.Contains("ptr null", table);

        // The derived class supplies it, so its own table has no null.
        string derived = Lines(ir, "@_SLvt_Test_Square_Test_IShape").Single();
        Assert.DoesNotContain("ptr null", derived);
    }

    /// <summary>
    /// And nothing in the module names a symbol it does not define. This is the
    /// property the abstract slot broke, stated once for the whole module
    /// rather than for one table.
    /// </summary>
    [Fact]
    public void EveryInternalSymbolNamedIsDefined()
    {
        string ir = Front.ModuleIr(
            """
            public interface IShape { int Area(); }
            public abstract class Shape : IShape { public abstract int Area(); }
            public class Square : Shape { public override int Area() { return 1; } }
            """);

        var defined = new HashSet<string>(StringComparer.Ordinal);
        foreach (string line in AllLines(ir))
        {
            if (line.StartsWith("define", StringComparison.Ordinal) ||
                line.StartsWith("declare", StringComparison.Ordinal))
            {
                int at = line.IndexOf('@', StringComparison.Ordinal);
                if (at >= 0) defined.Add(NameAt(line, at));
            }
            else if (line.StartsWith("@", StringComparison.Ordinal))
            {
                defined.Add(NameAt(line, 0));
            }
        }

        // Every '@name' used in a constant must be one of those.
        foreach (string line in AllLines(ir))
        {
            if (!line.StartsWith("@", StringComparison.Ordinal)) continue;

            for (int at = line.IndexOf('@', 1); at > 0; at = line.IndexOf('@', at + 1))
                Assert.Contains(NameAt(line, at), defined);
        }
    }

    /// <summary>The symbol name beginning at <paramref name="at"/>.</summary>
    private static string NameAt(string line, int at)
    {
        int end = at + 1;
        while (end < line.Length &&
               (char.IsLetterOrDigit(line[end]) || line[end] is '_' or '.' or '$'))
            end++;
        return line[at..end];
    }

    // ------------------------------------------------------------- guards

    /// <summary>
    /// A division by something that might be zero is checked, because both
    /// dividing by zero and INT_MIN / -1 are undefined in LLVM rather than
    /// merely wrong.
    /// </summary>
    [Fact]
    public void ADivisionByAnUnknownIsGuarded() =>
        Assert.Contains("icmp eq i32",
            Front.TestFunction(Front.ModuleIr("public int D(int a, int b) { return a / b; }"), "D"));

    /// <summary>
    /// And a division by a constant that cannot be either is not, so the guard
    /// costs nothing where it cannot fire.
    /// </summary>
    [Fact]
    public void ADivisionByASafeConstantIsNotGuarded()
    {
        string body = Front.TestFunction(
            Front.ModuleIr("public int D(int a) { return a / 2; }"), "D");

        Assert.Contains("sdiv", body);
        Assert.DoesNotContain("sl_divide_by_zero", body);
    }

    // ----------------------------------------------------------- bit-fields

    /// <summary>
    /// The two ABIs pack bit-fields differently: Microsoft opens a new storage
    /// unit when the declared type changes size, Itanium packs across. Both are
    /// emitted from the same source, and the sizes have to differ.
    ///
    /// Both ABIs are named rather than one being left to the default, which is
    /// the host's: on Linux the default *is* Itanium, so comparing it against
    /// Itanium compared a thing with itself and failed for the right reason.
    /// </summary>
    [Fact]
    public void TheTwoAbisPackBitFieldsDifferently()
    {
        const string source = """
            public struct Packed
            {
                public uint A : 3;
                public byte B : 2;
            }
            public uint Read(Packed p) { return p.A; }
            """;

        Assert.NotEqual(
            SizeUnder(source, CppAbi.Microsoft),
            SizeUnder(source, CppAbi.Itanium));
    }

    private static int SizeUnder(string source, CppAbi abi)
    {
        var program = Front.BindModule(source, out var diagnostics, abi);
        Assert.Empty(Front.Codes(diagnostics));
        return program.Structs.First(s => s.Name == "Packed").Size;
    }

    // ------------------------------------------------------------- the module

    /// <summary>
    /// A shared library declares the runtime it calls rather than defining it,
    /// and every declaration is written once however many places call it.
    /// </summary>
    [Fact]
    public void RuntimeFunctionsAreDeclaredOnce()
    {
        string ir = Front.ModuleIr(
            """
            public class C { }
            public void F() { var a = new C(); var b = new C(); }
            public void G() { var c = new C(); }
            """);

        Assert.Single(Lines(ir, "declare void @sl_retain("));
        Assert.Single(Lines(ir, "declare ptr @sl_alloc("));
    }

    /// <summary>
    /// The module names no target.
    ///
    /// Deliberate: a triple or a data layout written here would pin the IR to
    /// the machine that produced it, and the whole point of emitting text is
    /// that whichever clang is on the machine can compile it.
    /// </summary>
    [Fact]
    public void TheModuleNamesNoTarget()
    {
        string ir = Front.ModuleIr("public int F() { return 0; }");

        Assert.DoesNotContain("\ntarget triple", ir);
        Assert.DoesNotContain("\ntarget datalayout", ir);
    }

    /// <summary>How many times a fragment appears in the whole module.</summary>
    private static int Occurrences(string ir, string fragment)
    {
        int count = 0;
        for (int at = ir.IndexOf(fragment, StringComparison.Ordinal); at >= 0;
             at = ir.IndexOf(fragment, at + 1, StringComparison.Ordinal))
            count++;
        return count;
    }

    /// <summary>Every line of the IR.</summary>
    private static string[] AllLines(string ir) => ir.Split('\n');

    /// <summary>Every line of the IR that starts with a given prefix.</summary>
    private static List<string> Lines(string ir, string prefix) =>
        ir.Split('\n').Where(l => l.StartsWith(prefix, StringComparison.Ordinal)).ToList();
}
