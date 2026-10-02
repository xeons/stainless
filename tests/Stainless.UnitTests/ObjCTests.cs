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
using Stainless.Emit;
using Stainless.Lowering;
using Xunit;

namespace Stainless.UnitTests;

/// <summary>
/// Objective-C: what a declaration means, who owns what a message returns,
/// and the IR a send becomes. The IR is asked for as a Mac would build it,
/// from whatever machine runs the suite.
/// </summary>
public class ObjCTests
{
    private const string Declarations = """
        import Standard.ObjC;

        [ObjCRoot]
        public extern objc class NSObject
        {
            [Selector("alloc")] public static Self Alloc();
            [Selector("init")] public Self Init();
            [Selector("new")] public static Self New();
        }

        public extern objc class NSString : NSObject
        {
            [Selector("stringWithUTF8String:")] public static Self FromUtf8(byte* text);
            [Selector("length")] public nuint Length { get; }
            [Selector("copy")] public NSString Copy();
            [Selector("isEqualToString:")] public bool IsEqualToString(NSString other);
        }

        public struct Wide { public double A; public double B; public double C; public double D; }

        public extern objc class Shapes : NSObject
        {
            [Selector("spread")] public Wide Spread { get; }
            [Selector("makeTwin:")] public bool MakeTwin(out Shapes? twin);
        }

        """;

    private static string IrFor(TargetPlatform target, string body)
    {
        var before = TargetPlatform.Current;
        TargetPlatform.Current = target;
        try
        {
            var program = Front.BindModule(Declarations + body, out var diagnostics);
            Assert.Empty(Front.Codes(diagnostics).Where(c => !c.StartsWith("SL0377", StringComparison.Ordinal)));

            var abi = target.IsWindows ? CppAbi.Microsoft : CppAbi.Itanium;
            return Front.Verified(
                new LlvmEmitter(forSharedLibrary: true, abi: abi)
                    .Emit(Lowerer.Lower(program))
                    .ReplaceLineEndings("\n"));
        }
        finally
        {
            TargetPlatform.Current = before;
        }
    }

    private static string[] CodesFor(string body)
    {
        var before = TargetPlatform.Current;
        TargetPlatform.Current = TargetPlatform.Arm64MacOS;
        try
        {
            return Front.ModuleCodes(Declarations + body);
        }
        finally
        {
            TargetPlatform.Current = before;
        }
    }

    // ------------------------------------------------------------ families

    [Theory]
    [InlineData("alloc", "alloc")]
    [InlineData("allocWithZone:", "alloc")]
    [InlineData("new", "new")]
    [InlineData("newObject", "new")]
    [InlineData("copy", "copy")]
    [InlineData("copyWithZone:", "copy")]
    [InlineData("mutableCopy", "mutableCopy")]
    [InlineData("init", "init")]
    [InlineData("initWithFrame:", "init")]
    [InlineData("_init", "init")]
    [InlineData("__newThing", "new")]
    public void ASelectorIsInTheFamilyItBeginsWith(string selector, string family) =>
        Assert.Equal(family, Binder.FamilyOf(selector));

    [Theory]
    [InlineData("initialize")]
    [InlineData("newer")]
    [InlineData("copyright")]
    [InlineData("allocated")]
    [InlineData("description")]
    [InlineData("stringWithUTF8String:")]
    public void ALowerCaseLetterAfterTheWordEndsTheFamily(string selector) =>
        Assert.Null(Binder.FamilyOf(selector));

    // ------------------------------------------------------------ binding

    [Fact]
    public void SelfIsTheClassTheCallNamed()
    {
        var before = TargetPlatform.Current;
        TargetPlatform.Current = TargetPlatform.Arm64MacOS;
        try
        {
            var program = Front.BindModule(
                Declarations + "public nuint Use() => NSString.Alloc().Init().Length;",
                out var diagnostics);
            Assert.DoesNotContain("SL0251", Front.Codes(diagnostics));
            Assert.Empty(Front.Codes(diagnostics).Where(c => c.StartsWith("SL02", StringComparison.Ordinal)));
            Assert.NotNull(program);
        }
        finally
        {
            TargetPlatform.Current = before;
        }
    }

    [Fact]
    public void AnObjectConvertsUpwardsFreelyAndDownwardsOnlyByACast()
    {
        Assert.Empty(CodesFor("public AnyObject Up(NSString s) => s;"));
        Assert.Empty(CodesFor("public NSObject Up(NSString s) => s;"));
        Assert.Empty(CodesFor("public NSString Down(NSObject o) => (NSString)o;"));
        Assert.NotEmpty(CodesFor("public NSString Down(NSObject o) => o;"));
        Assert.NotEmpty(CodesFor("public NSString Wrong(String s) => s;"));
    }

    [Fact]
    public void APointerBecomesAnObjectOnlyByACast()
    {
        Assert.Empty(CodesFor("public NSString Adopt(byte* p) => (NSString)p;"));
        Assert.NotEmpty(CodesFor("public NSString Adopt(byte* p) => p;"));
    }

    [Fact]
    public void AMethodOfAStainlessClassStillRefusesAnAttribute() =>
        Assert.Contains("SL0728", Front.ModuleCodes("""
            public class Plain
            {
                [Selector("run")]
                public void Run() { }
            }
            """));

    // ------------------------------------------------------------ sends

    [Fact]
    public void ASendLoadsItsSelectorAndCallsObjcMsgSend()
    {
        string ir = IrFor(TargetPlatform.Arm64MacOS, "public nuint Use(NSString s) => s.Length;");

        Assert.Contains("load ptr, ptr @sl.objc.selref.", ir);
        Assert.Contains("call i64 @objc_msgSend(ptr", ir);
        Assert.Contains("section \"__DATA,__objc_selrefs,literal_pointers,no_dead_strip\"", ir);
        Assert.Contains("c\"length\\00\", section \"__TEXT,__objc_methname,cstring_literals\"", ir);
        Assert.Contains("!\"Objective-C Image Info Section\"", ir);
    }

    [Fact]
    public void AClassMessageGoesToTheClassTheCallNamed()
    {
        string ir = IrFor(TargetPlatform.Arm64MacOS, "public NSString Make() => NSString.Alloc().Init();");

        Assert.Contains("@\"OBJC_CLASS_$_NSString\"", ir);
        Assert.DoesNotContain("@\"OBJC_CLASS_$_NSObject\"", ir);
    }

    [Fact]
    public void AnObjectHandedBackAtZeroIsClaimedAndAPlusOneIsNot()
    {
        string claimed = Front.TestFunction(
            IrFor(TargetPlatform.Arm64MacOS, "public NSString Make() => NSString.FromUtf8(\"x\");"), "Make");
        Assert.Contains("mov\\09fp, fp", claimed);
        Assert.Contains("notail call ptr @objc_retainAutoreleasedReturnValue", claimed);

        string copied = Front.TestFunction(
            IrFor(TargetPlatform.Arm64MacOS, "public NSString Twice(NSString s) => s.Copy();"), "Twice");
        Assert.DoesNotContain("objc_retainAutoreleasedReturnValue", copied);
    }

    [Fact]
    public void IntelClaimsWithNoMarker()
    {
        string claimed = Front.TestFunction(
            IrFor(TargetPlatform.X64MacOS, "public NSString Make() => NSString.FromUtf8(\"x\");"), "Make");
        Assert.Contains("notail call ptr @objc_retainAutoreleasedReturnValue", claimed);
        Assert.DoesNotContain("asm sideeffect", claimed);
    }

    [Fact]
    public void AnInitConsumesItsReceiver()
    {
        string made = Front.TestFunction(
            IrFor(TargetPlatform.Arm64MacOS, "public NSString Make() => NSString.Alloc().Init();"), "Make");

        Assert.DoesNotContain("objc_release", made);
        Assert.DoesNotContain("objc_retain(", made);
    }

    [Fact]
    public void BoolIsAByteOnIntelAndABitOnAppleSilicon()
    {
        const string body = "public bool Same(NSString a, NSString b) => a.IsEqualToString(b);";

        Assert.Contains("call zeroext i1 @objc_msgSend",
            Front.TestFunction(IrFor(TargetPlatform.Arm64MacOS, body), "Same"));
        Assert.Contains("call signext i8 @objc_msgSend",
            Front.TestFunction(IrFor(TargetPlatform.X64MacOS, body), "Same"));
    }

    [Fact]
    public void ABigStructComesBackThroughStretOnIntelOnly()
    {
        const string body = "public double First(Shapes s) => s.Spread.A;";

        Assert.Contains("@objc_msgSend_stret(ptr sret",
            Front.TestFunction(IrFor(TargetPlatform.X64MacOS, body), "First"));
        Assert.DoesNotContain("objc_msgSend_stret",
            Front.TestFunction(IrFor(TargetPlatform.Arm64MacOS, body), "First"));
    }

    [Fact]
    public void AnOutObjectIsWrittenBackThroughATemporary()
    {
        string twin = Front.TestFunction(IrFor(TargetPlatform.Arm64MacOS, """
            public bool Twin(Shapes s)
            {
                Shapes? made;
                return s.MakeTwin(out made);
            }
            """), "Twin");

        Assert.Contains("%send.writeback.", twin);
        Assert.Contains("call ptr @objc_retain(", twin);
    }

    [Fact]
    public void AReadonlyObjCStaticIsNeverMadeImmortal()
    {
        string ir = IrFor(TargetPlatform.Arm64MacOS,
            "static readonly NSString Shared = NSString.FromUtf8(\"x\");\npublic NSString Get() => Shared;");

        // The store into it, and what follows: never the call that would write
        // over the object's isa.
        var lines = ir.Split('\n');
        int stored = Array.FindIndex(lines, l => l.Contains("store ptr") && l.Contains("@_SLstatic_Test_Shared"));
        Assert.True(stored > 0);
        Assert.DoesNotContain("sl_make_immortal", lines[stored + 1]);
    }
}
