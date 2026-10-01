// Stainless - an experimental general-purpose language.
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
    ///
    /// The +1 <c>new</c> made is the local's, moved in: a retain as it is
    /// stored and a release as the statement ends would be a pair of atomics
    /// that cancel.
    /// </summary>
    [Fact]
    public void ALocalReleasesWhatItHeld()
    {
        string body = Front.TestFunction(
            Front.ModuleIr("public class C { }\npublic void F() { var c = new C(); }"), "F");

        Assert.DoesNotContain("call void @sl_retain(", body);
        Assert.Equal(1, Occurrences(body, "call void @sl_release("));
    }

    /// <summary>
    /// An enum's text is one function however often it is written, a switch
    /// with a literal for each named value, and nothing for an enum nobody
    /// writes.
    /// </summary>
    [Fact]
    public void AnEnumWrittenTwiceHasOneTextFunction()
    {
        string ir = Front.ModuleIr(
            """
            public enum Level { Low, High, Same = 1 }
            public enum Unused { Nothing }
            public String F(Level level) => $"{level} {Level.High}" + level.ToText();
            """);

        Assert.Equal(1, Occurrences(ir, "define private ptr @_SLtextE"));
        Assert.Equal(3, Occurrences(Front.TestFunction(ir, "F"), "call ptr @_SLtextE"));
        Assert.Contains("switch i32 %value, label %unnamed [", ir);
        Assert.Equal(2, Occurrences(ir, ", label %named."));
        Assert.DoesNotContain("Unused", ir);
    }

    /// <summary>
    /// A value that is already the caller's is handed back without a retain,
    /// and one that is borrowed is retained once.
    /// </summary>
    [Fact]
    public void AReturnMovesWhatItWasHanded()
    {
        string ir = Front.ModuleIr(
            """
            public class C { }
            public C Make() { return new C(); }
            public C Pass() { return Make(); }
            public C Keep(C c) { return c; }
            """);

        string pass = Front.TestFunction(ir, "Pass");
        Assert.DoesNotContain("sl_retain", pass);
        Assert.DoesNotContain("sl_release", pass);

        Assert.Equal(1, Occurrences(Front.TestFunction(ir, "Keep"), "call void @sl_retain("));
    }

    /// <summary>
    /// A conditional merges one +1 from either arm: the arm that made its
    /// value moves it, the arm that borrowed retains, and the local the merge
    /// initializes takes it without another count.
    /// </summary>
    [Fact]
    public void AConditionalMergesOneOwnedValue()
    {
        string body = Front.TestFunction(
            Front.ModuleIr(
                """
                public class C { }
                public void F(bool flag, C other) { var c = flag ? new C() : other; }
                """),
            "F");

        Assert.Equal(1, Occurrences(body, "call void @sl_retain("));
        Assert.Equal(1, Occurrences(body, "call void @sl_release("));
    }

    /// <summary>
    /// A fresh value assigned as a statement is moved into its slot, which
    /// releases only what the slot held before.
    /// </summary>
    [Fact]
    public void AnAssignmentMovesAFreshValue()
    {
        string body = Front.TestFunction(
            Front.ModuleIr(
                """
                public class C { }
                public class Holder { public C? Held; }
                public void F(Holder h) { h.Held = new C(); }
                """),
            "F");

        Assert.DoesNotContain("call void @sl_retain(", body);
        Assert.Equal(1, Occurrences(body, "call void @sl_release("));
    }

    /// <summary>
    /// A swap holds each value with a reference of its own, and each store is
    /// handed that reference: two retains and two releases, as the spec says.
    /// </summary>
    [Fact]
    public void ASwapHandsEachHeldValueToItsStore()
    {
        string ir = Front.ModuleIr(
            """
            public class C { }
            public void F(C x, C y) { var a = x; var b = y; (a, b) = (b, a); }
            public void G(C x, C y) { var a = x; var b = y; }
            """);

        string swapped = Front.TestFunction(ir, "F");
        string kept = Front.TestFunction(ir, "G");

        foreach (string call in (string[])["call void @sl_retain(", "call void @sl_release("])
            Assert.Equal(2, Occurrences(swapped, call) - Occurrences(kept, call));
    }

    /// <summary>
    /// A conditional over values that run no code runs none itself, so storing
    /// one into an element needs no hold on the array while it is found. A
    /// hold there was a retain and a release per store, in the loop where
    /// such a store usually is.
    /// </summary>
    [Fact]
    public void StoringAConditionalHoldsNothing()
    {
        string body = Front.TestFunction(
            Front.ModuleIr(
                """
                public class Holder { public int[] Items; public Holder() { Items = new int[4]; } }
                public void F(Holder h, int x) { h.Items[0] = x > 0 ? x : -1; }
                """),
            "F");

        Assert.DoesNotContain("call void @sl_retain(", body);
    }

    /// <summary>
    /// A null or a String literal has nothing to count, so storing one costs
    /// no retain.
    /// </summary>
    [Fact]
    public void AnUncountedValueIsStoredWithoutARetain()
    {
        string body = Front.TestFunction(
            Front.ModuleIr(
                """
                public class Holder { public String? Name; }
                public void F(Holder h) { h.Name = null; h.Name = "named"; }
                """),
            "F");

        Assert.DoesNotContain("call void @sl_retain(", body);
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

        // Every '@name' used in a constant must be one of those. The bytes of
        // a string constant are text, and an '@' among them names nothing.
        foreach (string line in AllLines(ir))
        {
            if (!line.StartsWith("@", StringComparison.Ordinal)) continue;

            string code = System.Text.RegularExpressions.Regex.Replace(line, "c\"[^\"]*\"", "c\"\"");
            for (int at = code.IndexOf('@', 1); at > 0; at = code.IndexOf('@', at + 1))
                Assert.Contains(NameAt(code, at), defined);
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

    // ------------------------------------------------------------- generics

    private const string CopyAll = """
        extern "C" byte* memmove(byte* to, byte* from, nuint count);

        public class C { }

        public void CopyAll<T>(T[] to, T[] from)
        {
            if (!RuntimeHelpers.IsReferenceOrContainsReferences<T>())
            {
                if (from.Length != 0u)
                    memmove((byte*)&to[0u], (byte*)&from[0u], from.Length * sizeof(T));
            }
            else
            {
                for (nuint i = 0u; i < from.Length; i++)
                    to[i] = from[i];
            }
        }

        public void CopyBytes(byte[] to, byte[] from) => CopyAll(to, from);
        public void CopyObjects(C[] to, C[] from) => CopyAll(to, from);
        """;

    /// <summary>
    /// Each instantiation answers the question with a constant, and the arm
    /// an <c>if</c> on it does not take emits nothing: the bytes' copy is a
    /// <c>memmove</c> with no loop beside it.
    /// </summary>
    [Fact]
    public void AReferenceFreeInstantiationKeepsOnlyItsArm()
    {
        string body = Front.Function(Front.ModuleIr(CopyAll), "@_SL4Test7CopyAllG1h");

        Assert.Contains("call ptr @memmove(", body);
        Assert.DoesNotContain("for.", body);
        Assert.DoesNotContain("IsReferenceOrContainsReferences", body);
    }

    /// <summary>
    /// And the instantiation over a class keeps the loop, which counts every
    /// reference it copies, and has no <c>memmove</c> to go wrong.
    /// </summary>
    [Fact]
    public void AReferenceInstantiationKeepsOnlyTheLoop()
    {
        string body = Front.Function(Front.ModuleIr(CopyAll), "@_SL4Test7CopyAllG1C6Test_C");

        Assert.DoesNotContain("memmove", body);
        Assert.Contains("for.body", body);
        Assert.Contains("call void @sl_retain(", body);
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
    ///
    /// Matched on the symbol rather than the whole prefix: a declaration
    /// carries attributes now, and this test is about how many there are.
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

        Assert.Single(Declarations(ir, "sl_retain"));
        Assert.Single(Declarations(ir, "sl_alloc"));
    }

    /// <summary>
    /// What the optimiser is told about the runtime.
    ///
    /// A bare <c>declare</c> is the most pessimistic thing LLVM can be handed:
    /// a call that may unwind, may not return, and may touch every byte the
    /// program can reach. These say what is true instead -- and the two that
    /// are deliberately left pessimistic are the point of the test, because
    /// claiming otherwise about either would be a miscompilation rather than a
    /// missed optimisation.
    /// </summary>
    [Theory]
    // Provably nothing but the header of the object it was handed.
    [InlineData("sl_retain", "memory(argmem: readwrite)")]
    [InlineData("sl_weak_retain", "memory(argmem: readwrite)")]
    [InlineData("sl_make_immortal", "memory(argmem: readwrite)")]
    // Fresh calloc memory, so it aliases nothing.
    [InlineData("sl_alloc", "noalias")]
    [InlineData("sl_array_alloc", "noalias")]
    // Reads type tables and writes nothing.
    [InlineData("sl_is_instance", "memory(read)")]
    // Ends in sl_fail, which ends in abort.
    [InlineData("sl_array_bounds_fail", "noreturn")]
    [InlineData("sl_divide_by_zero", "noreturn")]
    public void ARuntimeDeclarationSaysWhatIsTrueOfIt(string symbol, string attribute)
    {
        string ir = Front.ModuleIr("public class C { }\npublic void F() { var a = new C(); }");
        Assert.Contains(attribute, Assert.Single(Declarations(ir, symbol)));
    }

    /// <summary>
    /// <c>sl_release</c> runs <c>type->destroy</c> -- an arbitrary user
    /// destructor, which may touch anything and call anything -- so it gets
    /// <c>nounwind</c> and no memory clause at all. The COM pair makes an
    /// indirect call into foreign code and gets neither.
    /// </summary>
    [Theory]
    [InlineData("sl_release")]
    [InlineData("sl_com_release")]
    [InlineData("sl_com_retain")]
    public void ACallThatMayRunAnythingClaimsNothingAboutMemory(string symbol)
    {
        // Every runtime entry point is declared whether or not this module
        // reaches it, so one class is enough to get all three.
        string ir = Front.ModuleIr("public class C { }\npublic void F() { var a = new C(); }");

        Assert.DoesNotContain("memory(", Assert.Single(Declarations(ir, symbol)));
    }

    /// <summary>Declarations of one runtime symbol, however they are spelled.</summary>
    private static List<string> Declarations(string ir, string symbol) =>
        ir.Split('\n')
            .Where(l => l.StartsWith("declare ", StringComparison.Ordinal) &&
                        l.Contains("@" + symbol + "(", StringComparison.Ordinal))
            .ToList();

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

    /// <summary>The module for one target, emitted with a resource blob.</summary>
    private static string ModuleIrFor(TargetPlatform target, string body, byte[]? resourceBlob = null)
    {
        var before = TargetPlatform.Current;
        TargetPlatform.Current = target;
        try
        {
            var program = Front.BindModule(body, out var diagnostics);
            Assert.False(diagnostics.HasErrors);

            return Front.Verified(
                new Emit.LlvmEmitter(forSharedLibrary: true, resourceBlob: resourceBlob)
                    .Emit(Lowering.Lowerer.Lower(program))
                    .ReplaceLineEndings("\n"));
        }
        finally
        {
            TargetPlatform.Current = before;
        }
    }

    /// <summary>
    /// The compiled resources go in a section of their own, named the way each
    /// format names one. A PE keeps them in its resource directory instead,
    /// and has none.
    /// </summary>
    [Theory]
    [InlineData("x64-windows", null)]
    [InlineData("x64-linux", ".rsrc")]
    [InlineData("arm64-linux", ".rsrc")]
    [InlineData("arm64-macos", "__DATA_CONST,__sl_rsrc")]
    [InlineData("x64-macos", "__DATA_CONST,__sl_rsrc")]
    public void TheResourceSectionFollowsTheObjectFormat(string target, string? section) =>
        Assert.Equal(section, Emit.LlvmEmitter.ResourceSection(TargetPlatform.Parse(target)!));

    [Fact]
    public void AResourceBlobIsPlacedInTheFormatsSection()
    {
        string ir = ModuleIrFor(TargetPlatform.Arm64MacOS, "public int F() => 0;", [1, 2, 3]);

        Assert.Contains(
            "@sl_resource_blob = constant [3 x i8] c\"\\01\\02\\03\", section \"__DATA_CONST,__sl_rsrc\"\n",
            ir);
        Assert.Contains("@sl_resource_blob_size = constant i64 3\n", ir);
    }

    /// <summary>
    /// An empty blob still defines the symbol, so that `Standard.Resources`
    /// links, and is given no section to make an empty one of.
    /// </summary>
    [Fact]
    public void AnEmptyResourceBlobHasTheSymbolAndNoSection()
    {
        string ir = ModuleIrFor(TargetPlatform.X64Linux, "public int F() => 0;", []);

        Assert.Contains("@sl_resource_blob = constant [0 x i8] c\"\"\n", ir);
        Assert.Contains("@sl_resource_blob_size = constant i64 0\n", ir);
    }

    /// <summary>
    /// Apple's arm64 ABI requires a frame record in x29, so every definition
    /// keeps a frame pointer on that target, as clang's do, at every level.
    /// Elsewhere a release build keeps none.
    /// </summary>
    [Fact]
    public void ArmMacOSKeepsAFramePointerInEveryFunctionThatCalls()
    {
        const string body = "public int G() => 1;\npublic int F() => G() + 1;";

        string mac = ModuleIrFor(TargetPlatform.Arm64MacOS, body);
        Assert.Contains("attributes #0 = { \"frame-pointer\"=\"non-leaf\" }", mac);
        Assert.Contains(" #0 {", Front.TestFunction(mac, "F").Split('\n')[0]);

        Assert.DoesNotContain("frame-pointer", ModuleIrFor(TargetPlatform.Arm64Linux, body));
        Assert.DoesNotContain("frame-pointer", ModuleIrFor(TargetPlatform.X64MacOS, body));
    }

    /// <summary>
    /// A library's statics are initialized from a constructor, which Mach-O
    /// does not order after the runtime's. The initializer asks the runtime to
    /// start before anything else it does.
    /// </summary>
    [Fact]
    public void ALibrarysInitializerStartsTheRuntimeFirst()
    {
        string ir = Front.ModuleIr("public static class Held { public static int[] Values = new int[4]; }");

        var initializer = ir[ir.IndexOf("define internal void @_SLstatics()", StringComparison.Ordinal)..]
            .Split('\n')
            .Skip(1)
            .SkipWhile(l => !l.StartsWith("  ", StringComparison.Ordinal) || l.Contains(" = alloca "))
            .First();

        Assert.Equal("  call void @sl_runtime_init()", initializer);
        Assert.Single(Declarations(ir, "sl_runtime_init"));
        Assert.Contains("i32 65535, ptr @_SLstatics", ir);
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

    // ------------------------------------------------------------------ asm

    /// <summary>The IR of function <c>F</c>, with the module body built for a target.</summary>
    private static string AsmFunction(TargetPlatform target, string body)
    {
        var before = TargetPlatform.Current;
        TargetPlatform.Current = target;
        try
        {
            return Front.TestFunction(Front.ModuleIr("public void F()\n{\n" + body + "\n}"), "F");
        }
        finally
        {
            TargetPlatform.Current = before;
        }
    }

    /// <summary>
    /// The whole call, for the target whose rules the constraint string is
    /// most of: outputs, then inputs, then the Win64 volatile set, then the
    /// flags. Every block gets the same clobbers, operands or not.
    /// </summary>
    [Fact]
    public void AnX64WindowsBlockClobbersTheWin64VolatileSet()
    {
        string body = AsmFunction(TargetPlatform.X64Windows,
            "long a = 1; long r = 0;\nasm (in rcx = a, out rax = r) { mov rax, rcx }");

        Assert.Contains(
            "call i64 asm inteldialect \" mov rax, rcx \", " +
            "\"={rax},{rcx},~{rax},~{rcx},~{rdx},~{r8},~{r9},~{r10},~{r11}," +
            "~{xmm0},~{xmm1},~{xmm2},~{xmm3},~{xmm4},~{xmm5},~{dirflag},~{fpsr},~{flags}\"(i64 ",
            body);
    }

    [Fact]
    public void AnX64LinuxBlockClobbersTheSystemVVolatileSet()
    {
        string body = AsmFunction(TargetPlatform.X64Linux, "asm { nop }");

        Assert.Contains(
            "call void asm inteldialect \" nop \", " +
            "\"~{rax},~{rcx},~{rdx},~{rsi},~{rdi},~{r8},~{r9},~{r10},~{r11}," +
            "~{xmm0},~{xmm1},~{xmm2},~{xmm3},~{xmm4},~{xmm5},~{xmm6},~{xmm7}," +
            "~{xmm8},~{xmm9},~{xmm10},~{xmm11},~{xmm12},~{xmm13},~{xmm14},~{xmm15}," +
            "~{dirflag},~{fpsr},~{flags}\"()",
            body);
    }

    [Fact]
    public void AnX86BlockClobbersThreeRegistersAndEveryVectorRegister()
    {
        string body = AsmFunction(TargetPlatform.X86Linux, "asm { nop }");

        Assert.Contains(
            "\"~{eax},~{ecx},~{edx},~{xmm0},~{xmm1},~{xmm2},~{xmm3},~{xmm4},~{xmm5}," +
            "~{xmm6},~{xmm7},~{dirflag},~{fpsr},~{flags}\"()",
            body);
    }

    /// <summary>
    /// ARM64 has one syntax, so no dialect. x18 is clobbered on Linux and not
    /// on Windows or macOS, and the link register is spelled the one way LLVM
    /// acts on.
    /// </summary>
    [Fact]
    public void AnArm64BlockClobbersByItsSystem()
    {
        string linux = AsmFunction(TargetPlatform.Arm64Linux, "asm { nop }");
        string windows = AsmFunction(TargetPlatform.Arm64Windows, "asm { nop }");
        string macos = AsmFunction(TargetPlatform.Arm64MacOS, "asm { nop }");

        Assert.Contains("~{x17},~{lr},~{v0},", macos);
        Assert.DoesNotContain("x18", macos);

        Assert.Contains("call void asm \" nop \", \"~{x0},", linux);
        Assert.Contains("~{x17},~{x18},~{lr},~{v0},", linux);
        Assert.Contains("~{v7},~{v16},", linux);
        Assert.Contains("~{v31},~{nzcv}\"()", linux);

        Assert.Contains("~{x17},~{lr},~{v0},", windows);
        Assert.DoesNotContain("x18", windows);
        Assert.DoesNotContain("inteldialect", windows);
    }

    /// <summary>
    /// On ARM64 x30 is <c>lr</c> as an operand as well as a clobber, and a vector
    /// register is spelled by the value it carries rather than by what was
    /// written.
    /// </summary>
    [Fact]
    public void Arm64OperandsAreSpelledTheWayLlvmBindsThem()
    {
        string body = AsmFunction(TargetPlatform.Arm64Linux,
            "long l = 0; float f = 0.0f; double d = 0.0;\n" +
            "asm (inout x30 = l, inout v1 = f, inout d2 = f, inout v3 = d) { nop }");

        Assert.Contains(
            "call { i64, float, float, double } asm \" nop \", " +
            "\"={lr},={s1},={s2},={d3},{lr},{s1},{s2},{d3},~{x0},", body);
    }

    /// <summary>
    /// A value narrower than its register is extended by its own signedness,
    /// and one read back narrower is the low bits; a bool is whether the
    /// register is anything but zero.
    /// </summary>
    [Fact]
    public void NarrowOperandsAreExtendedAndTruncated()
    {
        string body = AsmFunction(TargetPlatform.X64Windows,
            "int s = -1; uint u = 1; bool b = true; short o = 0; bool r = false;\n" +
            "asm (in rcx = s, in rdx = u, in r8b = b, out ax = o, out r9 = r) { nop }");

        Assert.Contains("sext i32 ", body);
        Assert.Contains(" to i64", body);
        Assert.Contains("zext i32 ", body);
        Assert.Contains("zext i1 ", body);
        Assert.Contains(" to i8", body);
        Assert.Contains("call { i16, i64 } asm", body);
        Assert.Contains("icmp ne i64 ", body);
    }

    /// <summary>
    /// A literal that fits the register is given the register's width, so
    /// nothing needs extending; a pointer travels as one.
    /// </summary>
    [Fact]
    public void LiteralsAndPointersNeedNoConversion()
    {
        string body = AsmFunction(TargetPlatform.X64Windows,
            "int* p = null;\nasm (in al = 200, in rsi = p) { nop }");

        Assert.Contains("\"{al},{rsi},", body);
        Assert.Contains("(i8 200, ptr ", body);
    }

    /// <summary>
    /// Several outputs come back as a struct and are unpacked in the order
    /// written, each into the address worked out before the block.
    /// </summary>
    [Fact]
    public void SeveralOutputsAreUnpackedInOrder()
    {
        string body = AsmFunction(TargetPlatform.X64Windows,
            "long low = 0; long high = 0;\nasm (out rax = low, out rdx = high) { rdtsc }");

        Assert.Contains("call { i64, i64 } asm inteldialect \" rdtsc \", \"={rax},={rdx},", body);
        Assert.Contains("extractvalue { i64, i64 } ", body);
        Assert.Contains(", 0", body);
        Assert.Contains(", 1", body);
    }

    /// <summary>
    /// The text is escaped for an LLVM string — a quote, a backslash, a
    /// newline, anything outside printable ASCII — and a carriage return is
    /// dropped, so a file saved with either line ending emits the same IR.
    /// </summary>
    // ------------------------------------------------------------- matching

    /// <summary>
    /// A switch over constants of an integer, a char or an enum is one LLVM
    /// <c>switch</c>, with an arm per label and nothing compared first, so a
    /// jump table stays LLVM's decision. The patterns it is written with are
    /// lowered by the same tree every other switch is.
    /// </summary>
    [Theory]
    [InlineData("int", "1", "2", "3", "switch i32 ")]
    [InlineData("char", "'a'", "'b'", "'c'", "switch i8 ")]
    [InlineData("Level", "Level.Low", "Level.Mid", "Level.High", "switch i32 ")]
    public void AConstantSwitchIsOneLlvmSwitch(string type, string first, string second, string third, string wanted)
    {
        string body = Front.TestFunction(Front.ModuleIr($$"""
            public enum Level { Low, Mid, High }
            public int F({{type}} value)
            {
                switch (value)
                {
                    case {{first}}: return 10;
                    case {{second}}: case {{third}}: return 20;
                    default: return 30;
                }
            }
            """), "F");

        Assert.Equal(1, Occurrences(body, wanted));
        Assert.Equal(4, Occurrences(body, ", label %"));
        Assert.DoesNotContain("icmp eq", body);
    }

    /// <summary>
    /// A switch over a variant is one <c>switch</c> over its tag, whether its
    /// labels name cases, name cases and bind their payloads, or are patterns
    /// that ask the case first.
    /// </summary>
    [Theory]
    [InlineData("case Circle c: return c.Radius; case Square: return 1.0;")]
    [InlineData("case Circle { Radius: > 1.0 }: return 2.0; case Circle c: return c.Radius; case Square: return 1.0;")]
    public void AVariantSwitchDispatchesOnItsTag(string sections)
    {
        string body = Front.TestFunction(Front.ModuleIr($$"""
            public variant Shape { Circle(double Radius); Square(double Side); }
            public double F(Shape shape)
            {
                switch (shape)
                {
                    {{sections}}
                }
                return 0.0;
            }
            """), "F");

        Assert.Equal(1, Occurrences(body, "switch i8 "));
    }

    /// <summary>
    /// A switch expression asks each question once on any path: a later arm
    /// that asks for the same case as an earlier one is not asked again.
    /// </summary>
    [Fact]
    public void ASwitchExpressionAsksACaseOnce()
    {
        string body = Front.TestFunction(Front.ModuleIr("""
            public variant Shape { Circle(double Radius); Square(double Side); }
            public double F(Shape shape) => shape switch
            {
                Circle { Radius: > 1.0 } => 2.0,
                Circle c => c.Radius,
                Square s => s.Side,
            };
            """), "F");

        Assert.Equal(1, Occurrences(body, "icmp eq i8"));
    }

    [Theory]
    [InlineData("mov rax, 1\r\nret", "mov rax, 1\\0Aret")]
    [InlineData(".ascii \"a\\b\"", ".ascii \\22a\\5Cb\\22")]
    [InlineData("\tnop # é", "\\09nop # \\C3\\A9")]
    public void AsmTextIsEscapedForAnLlvmString(string text, string escaped) =>
        Assert.Equal(escaped, Emit.LlvmEmitter.AsmString(text));

    /// <summary>
    /// The high half of a product and the optimisation barrier are written
    /// inline, never as calls to a symbol that nothing defines.
    /// </summary>
    [Fact]
    public void InlineIntrinsicsLeaveNoCallBehind()
    {
        string ir = Front.ModuleIr("""
            import Standard.Bits;
            public ulong High(ulong a, ulong b) => MultiplyHigh(a, b);
            public ulong Hidden(ulong a) => OpaqueCopy(a);
            """);

        Assert.Contains("mul i128", ir);
        Assert.Contains("asm \"\", \"=r,0\"", ir);
        Assert.DoesNotContain("@sl.multiply_high", ir);
        Assert.DoesNotContain("@sl.opaque", ir);
    }

    /// <summary>
    /// A library built for Stainless consumers exports what its metadata
    /// describes. The standard library compiled in beside it stays internal:
    /// a consumer compiles its own.
    /// </summary>
    [Fact]
    public void AMetadataLibraryExportsOnlyItsOwnModules()
    {
        var program = Front.Bind("""
            module Test;
            public class Circle
            {
                public double Radius;
                public virtual double Area() => Radius * Radius;
            }
            """, out var diagnostics, shared: true);
        Assert.False(diagnostics.HasErrors);

        string ir = new Emit.LlvmEmitter(forSharedLibrary: true, consumerModules: new HashSet<string> { "Test" })
            .Emit(Lowering.Lowerer.Lower(program));

        var exported = ir.Split('\n')
            .Where(l => l.StartsWith("define ", StringComparison.Ordinal)
                        && !l.StartsWith("define internal", StringComparison.Ordinal)
                        && l.Contains("@_SL", StringComparison.Ordinal))
            .ToList();

        Assert.Contains(exported, l => l.Contains("@_SL4Test6Circle4Area", StringComparison.Ordinal));
        Assert.DoesNotContain(exported, l => l.Contains("@_SL8Standard", StringComparison.Ordinal));
    }

    // ------------------------------------------------------------ reflection

    /// <summary>
    /// A field table says, per field, whether zero bytes are a value of its
    /// type, whether its elements' are, and whether the maker MUST supply it.
    /// Reflection refuses a null and checks what it makes by these bits alone,
    /// so a wrong one is a null handed out with nothing to notice.
    /// </summary>
    [Fact]
    public void AFieldTableSaysWhichFieldsHaveNoZeroValue()
    {
        string ir = Front.ModuleIr("""
            import Standard.Reflection;
            [Reflect]
            public class C
            {
                public String Name;
                public String? Nick;
                public int Count;
                public required String Title;
                public String[] Tags;
                public int[]? Counts;
                public required int Rank { get; set; }
                public C() { Name = ""; Tags = []; }
            }
            """);

        // PROPERTY 1, NO_ZERO 2, REQUIRED 4, ELEMENT_NO_ZERO 8.
        Assert.Equal([2, 0, 0, 6, 10, 0, 5], FieldFlags(ir, "C"));
    }

    /// <summary>
    /// A constructor marked <c>[SetsRequiredMembers]</c> answers for every
    /// required member, so reflection, which runs it, is asked for none.
    /// </summary>
    [Fact]
    public void AConstructorSettingRequiredMembersLeavesTheMakerNone()
    {
        string ir = Front.ModuleIr("""
            import Standard.Reflection;
            [Reflect]
            public class C
            {
                public required String Title;
                [SetsRequiredMembers]
                public C() { Title = ""; }
            }
            """);

        Assert.Equal([2], FieldFlags(ir, "C"));
    }

    /// <summary>
    /// A reflected class <c>new C()</c> could make has a maker that runs the
    /// constructor, and one it could not has none, so reflection has no way
    /// to make it at all.
    /// </summary>
    [Fact]
    public void OnlyAClassNewCouldMakeHasAMaker()
    {
        string ir = Front.ModuleIr("""
            import Standard.Reflection;
            [Reflect]
            public class Made { public String Name; public Made() { Name = ""; } }
            [Reflect]
            public class Argued { public String Name; public Argued(String name) { Name = name; } }
            [Reflect]
            public abstract class Abstract { public int X; }
            """);

        string maker = Front.Function(ir, "@_SLmake_Test_Made(");
        Assert.Contains("call ptr @sl_alloc(ptr @_SLtiTest_Made)", maker);
        Assert.Matches(@"call void @_SL4Test4Made\S*\(ptr %object\)", maker);

        Assert.EndsWith("ptr @_SLmake_Test_Made }", TypeInfoLine(ir, "Made"));
        Assert.EndsWith("ptr null }", TypeInfoLine(ir, "Argued"));
        Assert.EndsWith("ptr null }", TypeInfoLine(ir, "Abstract"));
    }

    private static string TypeInfoLine(string ir, string type) =>
        ir.Split('\n').Single(l => l.StartsWith($"@_SLtiTest_{type} = ", StringComparison.Ordinal));

    /// <summary>The flags column of each row of a reflected class's field table.</summary>
    private static List<int> FieldFlags(string ir, string type)
    {
        string info = TypeInfoLine(ir, type);
        var table = System.Text.RegularExpressions.Regex.Match(info, @"ptr (@\.meta\.fields\.\d+)")
            .Groups[1].Value;
        string rows = ir.Split('\n').Single(l => l.StartsWith(table + " = ", StringComparison.Ordinal));

        return System.Text.RegularExpressions.Regex.Matches(rows, @"i32 (\d+) }")
            .Select(m => int.Parse(m.Groups[1].Value, System.Globalization.CultureInfo.InvariantCulture))
            .ToList();
    }

    /// <summary>
    /// A foreign function declared to return a never-null reference is held
    /// to it where it is called: a null stops the program there. One declared
    /// to return an optional is not asked.
    /// </summary>
    [Theory]
    [InlineData("String", true)]
    [InlineData("int[]", true)]
    [InlineData("String?", false)]
    public void AForeignResultIsCheckedForNull(string type, bool isChecked)
    {
        string body = Front.TestFunction(Front.ModuleIr(
            $"extern \"C\" {type} c_find(int wanted);\n" +
            $"public {type} F() => c_find(1);"), "F");

        Assert.Equal(isChecked, body.Contains("call void @sl_foreign_null(", StringComparison.Ordinal));
    }
}
