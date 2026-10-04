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

using Stainless.Bindgen;
using Xunit;

namespace Stainless.UnitTests;

/// <summary>
/// The bindings generator's reading of what clang prints, against the
/// spellings the macOS SDK's headers actually produce.
/// </summary>
public class BindgenTests
{
    private static readonly CType Void = new CBuiltin("void");

    [Theory]
    [InlineData("unsigned long long", "unsigned long long")]
    [InlineData("long unsigned int", "unsigned long")]
    [InlineData("signed char", "signed char")]
    [InlineData("const char", "char")]
    [InlineData("_Bool", "bool")]
    public void ABuiltinIsReadWhateverOrderItsWordsAreIn(string spelling, string name) =>
        Assert.Equal(new CBuiltin(name), CTypeParser.Parse(spelling));

    [Fact]
    public void QualifiersAndNullabilityAreDropped() =>
        Assert.Equal(new CPointer(new CTypedef("CFStringRef")),
            CTypeParser.Parse("const CFStringRef _Nullable * _Nonnull"));

    [Fact]
    public void AFunctionPointerIsAPointerToAFunction() =>
        Assert.Equal(
            new CPointer(new CFunction(new CPointer(Void), [new CPointer(Void)], false)),
            CTypeParser.Parse("const void *(*)(const void *)"));

    [Fact]
    public void NullabilityInsideAFunctionPointerIsDropped() =>
        Assert.Equal(
            new CPointer(new CFunction(new CPointer(Void), [new CPointer(Void)], false)),
            CTypeParser.Parse("void * _Null_unspecified (* _Null_unspecified)(void * _Null_unspecified)"));

    [Fact]
    public void ANullabilityQualifierBeforeADeclaratorLeavesTheDeclarator() =>
        Assert.Equal(
            new CPointer(new CFunction(new CTypedef("CFStringRef"), [new CPointer(Void)], false)),
            CTypeParser.Parse("CFStringRef  _Null_unspecified (* _Null_unspecified)(void * _Null_unspecified)"));

    [Fact]
    public void AFunctionTypeHasItsParametersAndWhetherItIsVariadic() =>
        Assert.Equal(
            new CFunction(new CTypedef("CFStringRef"), [new CTypedef("CFAllocatorRef"), new CTypedef("CFStringRef")], true),
            CTypeParser.Parse("CFStringRef (CFAllocatorRef, CFStringRef, ...)"));

    [Fact]
    public void ABlockIsAFunctionBehindACaret() =>
        Assert.Equal(new CBlock(new CFunction(Void, [], false)), CTypeParser.Parse("void (^)(void)"));

    [Theory]
    [InlineData("char [16]", 16L)]
    [InlineData("unsigned char[256]", 256L)]
    public void AnArrayKeepsItsLength(string spelling, long length) =>
        Assert.Equal(length, Assert.IsType<CArray>(CTypeParser.Parse(spelling)).Length);

    [Fact]
    public void ArraysNestRightToLeft()
    {
        var outer = Assert.IsType<CArray>(CTypeParser.Parse("char[16][256]"));
        Assert.Equal(16L, outer.Length);
        Assert.Equal(256L, Assert.IsType<CArray>(outer.Element).Length);
    }

    [Fact]
    public void APointerToAnArrayIsNotAnArrayOfPointers()
    {
        Assert.IsType<CPointer>(CTypeParser.Parse("int (*)[3]"));
        Assert.IsType<CArray>(CTypeParser.Parse("int *[3]"));
    }

    [Theory]
    [InlineData("CF_AVAILABLE(10_2, 2_0) CFStringRef", "CFStringRef")]
    [InlineData("CF_RETURNS_RETAINED SecKeyRef", "SecKeyRef")]
    [InlineData("CF_REFINED_FOR_SWIFT const CFStringRef", "CFStringRef")]
    public void AnAttributeMacroBeforeATypeIsSkipped(string spelling, string type) =>
        Assert.Equal(new CTypedef(type), CTypeParser.Parse(spelling));

    [Fact]
    public void ATypedefInCapitalsFollowedByParametersIsAFunctionType() =>
        Assert.Equal(
            new CFunction(new CTypedef("CSSM_RETURN"), [new CTypedef("CSSM_CC_HANDLE")], false),
            CTypeParser.Parse("CSSM_RETURN (CSSM_CC_HANDLE)"));

    [Fact]
    public void AnUnnamedRecordIsKnownByWhereItIs() =>
        Assert.Equal(
            new CAnonymous(CTagKind.Struct, "(unnamed struct at /SDK/CFBase.h:12:3)"),
            CTypeParser.Parse("struct (unnamed struct at /SDK/CFBase.h:12:3)"));

    [Fact]
    public void AnUnnamedRecordInsideAnotherIsKnownByItsOwnPlace() =>
        Assert.Equal(
            new CAnonymous(CTagKind.Union, "(unnamed at /SDK/MIDIMessages.h:601:4)"),
            CTypeParser.Parse("union MIDIUniversalMessage::(anonymous union)::(unnamed struct)::(anonymous at /SDK/MIDIMessages.h:601:4)"));

    [Theory]
    [InlineData("long double")]
    [InlineData("__int128")]
    [InlineData("id<NSCopying>")]
    [InlineData("__attribute__((__vector_size__(4 * sizeof(float)))) float")]
    public void WhatABindingCannotSpellIsSaidToBeSo(string spelling) =>
        Assert.IsType<CUnsupported>(CTypeParser.Parse(spelling));

    // ------------------------------------------------------------ the fixture

    /// <summary>What the generator writes for each declaration in Bindgen/fixture.h, by name.</summary>
    private static readonly Lazy<(Dictionary<string, string> Written, List<Skipped> Skips)> Fixture = new(() =>
    {
        var translation = AstReader.ReadFile(Path.Combine(AppContext.BaseDirectory, "Bindgen", "fixture.json"));
        var writer = new Writer(translation, new HashSet<string>());
        var written = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var declaration in translation.Declarations.Where(d => d.File.EndsWith("fixture.h", StringComparison.Ordinal)))
            if (writer.Write(declaration) is { } emitted)
                written.TryAdd(declaration.Name.Length > 0 ? declaration.Name : emitted.Key, emitted.Text);
        return (written, writer.Skips);
    });

    private static string Written(string name) =>
        Fixture.Value.Written.TryGetValue(name, out string? text)
            ? text.ReplaceLineEndings("\n")
            : throw new Xunit.Sdk.XunitException($"'{name}' was not written: {string.Join(", ", Fixture.Value.Written.Keys)}");

    [Fact]
    public void ATypedefOfAPrimitiveIsAnAlias() =>
        Assert.Equal("public using Index = long;\n", Written("Index"));

    [Fact]
    public void AStructIsItsFieldsInOrder() =>
        Assert.Equal("public struct Range\n{\n    public Index location;\n    public Index length;\n}\n", Written("Range"));

    [Fact]
    public void AStructWithNoTagTakesItsTypedefsName() =>
        Assert.StartsWith("public struct Point\n{\n    public double x;", Written("Point"));

    [Fact]
    public void AnOpaqueStructIsDeclaredAndItsPointerAliased()
    {
        Assert.Equal("public struct __Opaque;\n", Written("__Opaque"));
        Assert.Equal("public using OpaqueRef = __Opaque*;\n", Written("OpaqueRef"));
    }

    [Fact]
    public void AUnionHoldsAnInlineArray() =>
        Assert.Equal("public union Word\n{\n    public int whole;\n    public short[2] halves;\n}\n", Written("Word"));

    [Fact]
    public void BitFieldsKeepTheirWidths() =>
        Assert.Contains("    public uint kind : 3;\n", Written("Flags"));

    [Fact]
    public void APackedStructIsPacked() =>
        Assert.StartsWith("[Packed]\npublic struct Wire\n", Written("Wire"));

    [Fact]
    public void AnAnonymousMemberIsInlineAndANamedOneIsGivenAType()
    {
        string holder = Written("Holder");
        Assert.Contains("    public union\n    {\n        public int asInt;\n        public float asFloat;\n    }\n", holder);
        Assert.Contains("public struct HolderPair\n{\n    public int a;\n    public int b;\n}\n", holder);
        Assert.Contains("    public HolderPair pair;\n", holder);
        Assert.Contains("    public byte[16] name;\n", holder);
    }

    [Fact]
    public void AnEnumKeepsItsTypeAndLosesItsPrefix() =>
        Assert.Equal("public enum Compare : long\n{\n    Less = -1,\n    Same = 0,\n    More = 1,\n}\n", Written("Compare"));

    [Fact]
    public void AFlagEnumIsFlags() =>
        Assert.StartsWith("[Flags]\npublic enum Options : uint\n{\n    None = 0,\n    Fast = 1,\n    Safe = 2,\n", Written("Options"));

    [Fact]
    public void AnEnumWithNoNameIsConstants() =>
        Assert.Equal("public const int kNotFound = -1;\n", Written("constants kNotFound"));

    [Fact]
    public void AFunctionPointerIsADelegateAndABlockAClosure()
    {
        Assert.Equal("public delegate void Callback(void* arg0, Index arg1);\n", Written("Callback"));
        Assert.Equal("public objc closure void Handler(Index arg0);\n", Written("Handler"));
    }

    [Fact]
    public void AVariableAndAVariadicFunctionAreExtern()
    {
        Assert.Equal("public extern \"C\" OpaqueRef kDefaultOpaque;\n", Written("kDefaultOpaque"));
        Assert.Equal("public extern \"C\" Index RangeEnd(Range range, byte* label, ...);\n", Written("RangeEnd"));
    }

    [Fact]
    public void AnUnnamedBlockIsNamedAfterItsFunctionAndParameter() =>
        Assert.Equal(
            "public objc closure void PerformBlock();\n\npublic extern \"C\" void Perform(PerformBlock block);\n",
            Written("Perform"));

    [Fact]
    public void AnInlineFunctionIsSkippedWithItsReason() =>
        Assert.Contains(Fixture.Value.Skips, s => s.Name == "Twice" && s.Reason.Contains("inline", StringComparison.Ordinal));

    [Theory]
    [InlineData(new[] { "kCFCompareLessThan", "kCFCompareEqualTo", "kCFCompareGreaterThan" }, new[] { "LessThan", "EqualTo", "GreaterThan" })]
    [InlineData(new[] { "kCFNumberSInt8Type", "kCFNumberSInt16Type", "kCFNumberFloatType" }, new[] { "SInt8Type", "SInt16Type", "FloatType" })]
    [InlineData(new[] { "kCGImageAlphaNone", "kCGImageAlphaPremultipliedLast" }, new[] { "None", "PremultipliedLast" })]
    [InlineData(new[] { "kAudio_UnimplementedError", "kAudio_FileNotFoundError" }, new[] { "UnimplementedError", "FileNotFoundError" })]
    [InlineData(new[] { "kThing1", "kThing2" }, new[] { "Thing1", "Thing2" })]
    [InlineData(new[] { "Red", "Green" }, new[] { "Red", "Green" })]
    [InlineData(new[] { "kOnly" }, new[] { "kOnly" })]
    public void EnumeratorsLoseThePrefixTheyShareAtAWordBoundary(string[] names, string[] expected) =>
        Assert.Equal(expected, Writer.MemberNames([.. names]));
}
