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

    // ------------------------------------------------------------ defined classes

    /// <summary>The definition whose line names <paramref name="fragment"/>, through its closing brace.</summary>
    private static string Definition(string ir, string fragment)
    {
        int start = ir.IndexOf("define ", ir.IndexOf(fragment, StringComparison.Ordinal) is var at && at < 0
            ? throw new InvalidOperationException($"'{fragment}' is not in the IR")
            : ir.LastIndexOf('\n', at) + 1, StringComparison.Ordinal);
        int end = ir.IndexOf("\n}\n", start, StringComparison.Ordinal);
        return ir[start..end];
    }

    [Fact]
    public void AProtocolMemberIsAnsweredByName()
    {
        string ir = IrFor(TargetPlatform.Arm64MacOS, """
            public objc interface Shape
            {
                [Selector("area")] double Area();
            }

            public objc class Square : NSObject, Shape
            {
                public double Area() => 4.0;
            }
            """);

        Assert.Contains("define internal double @\"\\01-[Test.Square area]\"(ptr %self, ptr %_cmd)", ir);
        Assert.Contains("c\"d16@0:8\\00\"", ir);
    }

    [Fact]
    public void AnOverrideTakesItsBasesSelectorAndOwnership()
    {
        string ir = IrFor(TargetPlatform.Arm64MacOS, """
            public objc class Mine : NSString
            {
                public override NSString Copy() => NSString.FromUtf8("x");
                public override nuint Length => 3u;
            }
            """);

        // copy is in the copy family, so the IMP hands its +1 straight back.
        Assert.DoesNotContain("objc_autoreleaseReturnValue", Definition(ir, "-[Test.Mine copy]"));
        Assert.Contains("define internal i64 @\"\\01-[Test.Mine length]\"", ir);
    }

    [Fact]
    public void AnOverrideOfNothingAndAnUnmarkedReplacementAreRefused()
    {
        Assert.Contains("SL0921", CodesFor("""
            public objc class Mine : NSObject
            {
                public override long Missing() => 1;
            }
            """));
        Assert.Contains("SL0921", CodesFor("""
            public objc class Mine : NSString
            {
                [Selector("length")] public nuint Size => 3u;
            }
            """));
    }

    [Fact]
    public void AFieldIsReadThroughTheIvarOffset()
    {
        string ir = IrFor(TargetPlatform.Arm64MacOS, """
            public objc class Counter : NSObject
            {
                long _count = 3;
                [Selector("count")] public long Count => _count;
            }
            """);

        Assert.Contains("@\"OBJC_IVAR_$_Test.Counter._sl\" = hidden global i32 8, section \"__DATA, __objc_ivar\"", ir);
        Assert.Contains("load i32, ptr @\"OBJC_IVAR_$_Test.Counter._sl\"", ir);
        Assert.Contains("@\"\\01-[Test.Counter .cxx_construct]\"", ir);
    }

    [Fact]
    public void AConstructorIsAnInitThatChecksItsSuperclassAnswer()
    {
        string ir = IrFor(TargetPlatform.Arm64MacOS, """
            public objc class Made : NSObject
            {
                [Selector("initWithValue:")] public Made(long value) { }
            }

            public Made Make() => new Made(2);
            """);

        Assert.Contains("define internal ptr @\"\\01-[Test.Made initWithValue:]\"(ptr %self, ptr %_cmd, i64 %arg.value)", ir);
        Assert.Contains("call ptr @objc_alloc(ptr", ir);
        Assert.Contains("@objc_msgSendSuper(ptr", ir);
        Assert.Contains("call void @sl_objc_init_replaced(", ir);
    }

    [Fact]
    public void AFieldWithNoZeroValueNeedsAnInitializer() =>
        Assert.Contains("SL0813", CodesFor("""
            public objc class Unset : NSObject
            {
                String _name;
            }
            """));

    [Theory]
    [InlineData("[Selector(\"take:b:c:\")] public long Take(long a, double b, bool c) => a;", "q36@0:8q16d24B32")]
    [InlineData("[Selector(\"take:\")] public void Take(Wide wide) { }", "v48@0:8{Wide=dddd}16")]
    [InlineData("[Selector(\"take:\")] public void Take(Wide* wide) { }", "v24@0:8^{Wide=dddd}16")]
    [InlineData("[Selector(\"take:s:c:\")] public void Take(byte* text, Selector sel, Class cls) { }", "v40@0:8*16:24#32")]
    [InlineData("[Selector(\"take:b:\")] public NSString Take(short a, byte b) => NSString.FromUtf8(\"x\");", "@24@0:8s16C20")]
    public void ATypeIsEncodedAsClangEncodesIt(string member, string encoding)
    {
        string ir = IrFor(TargetPlatform.Arm64MacOS, $$"""
            public objc class Encoded : NSObject
            {
                {{member}}
            }
            """);

        Assert.Contains($"c\"{encoding}\\00\", section \"__TEXT,__objc_methtype,cstring_literals\"", ir);
    }

    [Fact]
    public void AWeakReferenceToAnObjectIsABox()
    {
        string ir = IrFor(TargetPlatform.Arm64MacOS, """
            public class Holder
            {
                public weak NSString? Held;
            }

            public bool Gone(Holder holder, NSString text)
            {
                holder.Held = text;
                return holder.Held == null;
            }
            """);

        string gone = Front.TestFunction(ir, "Gone");
        Assert.Contains("call ptr @sl_objc_weak_new(ptr", gone);
        Assert.Contains("call ptr @sl_objc_weak_load(ptr", gone);
        Assert.DoesNotContain("sl_weak_retain", gone);
    }

    [Fact]
    public void AWeakReferenceIsComparedAsWhatItReadsAs()
    {
        var program = Front.BindModule("""
            public class Thing { }
            public bool Gone(weak Thing? loose) => loose == null;
            """, out var diagnostics);
        Assert.Empty(Front.Codes(diagnostics));

        string ir = new LlvmEmitter(forSharedLibrary: true).Emit(Lowerer.Lower(program));
        Assert.Contains("call ptr @sl_weak_load(ptr", Front.TestFunction(ir, "Gone"));
    }

    // ------------------------------------------------------------ blocks

    private const string BlockDeclarations = """
        public objc closure void Seen(AnyObject item, bool flag);

        public extern objc class Taker : NSObject
        {
            [Selector("take:")] public static void Take(Seen seen);
        }

        public class Counter
        {
            public long Count;
        }

        """;

    [Fact]
    public void ALambdaBecomesABlockCopiedToTheHeap()
    {
        string ir = IrFor(TargetPlatform.Arm64MacOS, BlockDeclarations + """
            public void Use(Counter counter) => Taker.Take((AnyObject item, bool flag) => counter.Count++);
            """);

        string use = Front.TestFunction(ir, "Use");
        Assert.Contains("store ptr @_NSConcreteStackBlock, ptr", use);
        Assert.Contains("store i32 1107296256, ptr", use);
        Assert.Contains("call ptr @_Block_copy(ptr", use);
        Assert.Contains("i64 0, i64 48, ptr @sl.block.copy, ptr @sl.block.dispose", ir);
        Assert.Contains("call void @sl_retain(ptr %receiver)", Definition(ir, "@sl.block.copy"));
    }

    [Fact]
    public void ABlocksSignatureIsEncodedAsClangEncodesIt()
    {
        string arm = IrFor(TargetPlatform.Arm64MacOS, BlockDeclarations + """
            public void Use() => Taker.Take((AnyObject item, bool flag) => { });
            """);
        Assert.Contains("c\"v20@?0@8B16\\00\"", arm);
        Assert.Contains("c\"v24@0:8@?16\\00\"", IrFor(TargetPlatform.Arm64MacOS, BlockDeclarations + """
            public objc class Keeper : NSObject
            {
                [Selector("keep:")] public void Keep(Seen seen) { }
            }
            """));

        string intel = IrFor(TargetPlatform.X64MacOS, BlockDeclarations + """
            public void Use() => Taker.Take((AnyObject item, bool flag) => { });
            """);
        Assert.Contains("c\"v20@?0@8c16\\00\"", intel);
        Assert.Contains("(ptr %block, ptr %arg.item, i8 signext %arg.flag)", intel);
    }

    [Fact]
    public void ACallThroughABlockGoesThroughItsInvokeFunction()
    {
        string ir = IrFor(TargetPlatform.Arm64MacOS, BlockDeclarations + """
            public void Call(Seen seen, AnyObject item) => seen(item, true);
            """);

        string call = Front.TestFunction(ir, "Call");
        Assert.Contains("getelementptr inbounds { ptr, i32, i32, ptr, ptr, ptr, ptr }, ptr %", call);
        Assert.Contains("i32 0, i32 3", call);
        Assert.Contains("i1 zeroext true)", call);
    }

    [Fact]
    public void ABlockAMethodIsHandedIsCopiedFirst()
    {
        string ir = IrFor(TargetPlatform.Arm64MacOS, BlockDeclarations + """
            public objc class Keeper : NSObject
            {
                Seen? _held;
                [Selector("keep:")] public void Keep(Seen seen) => _held = seen;
            }
            """);

        string imp = Definition(ir, "-[Test.Keeper keep:]");
        Assert.Contains("call ptr @objc_retainBlock(ptr %arg.seen)", imp);
        Assert.Contains("call void @objc_release(ptr", imp);
    }

    [Fact]
    public void WhatABlockCarriesCrossesAsAMessagesArgumentsDo()
    {
        Assert.Contains("SL0907", CodesFor("public objc closure void Writes(out long result);"));
        Assert.Contains("SL0907", CodesFor("public objc closure void Named(String name);"));
        Assert.Empty(CodesFor("public objc closure NSString? Named(NSString name, bool* stop);"));
    }
}
