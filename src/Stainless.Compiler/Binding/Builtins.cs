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

using Stainless.Source;
using Stainless.Syntax;

namespace Stainless.Binding;

/// <summary>
/// The types and functions the compiler provides itself, arranged as ordinary
/// modules so that name resolution, visibility and overloading need no special
/// cases.
///
/// Their bodies live in runtime/stainless_rt.c. Each one is declared with C
/// linkage and a fixed runtime symbol, so a call to <c>text.ByteLength()</c>
/// lowers to exactly <c>call @sl_string_byte_length(ptr)</c> and nothing more.
/// </summary>
public sealed class Builtins
{
    public const string TextModuleName = "Standard.Text";
    public const string ConsoleModuleName = "Standard.Console";

    /// <summary>
    /// Markers the language itself understands, rather than a library feature
    /// to opt into. It is auto-imported, because needing an import to say
    /// <c>[Flags]</c> would make a rule about enums look like a dependency.
    /// </summary>
    public const string StandardModuleName = "Standard";

    public ModuleSymbol Text { get; }
    public ModuleSymbol Console { get; }
    public ModuleSymbol Standard { get; }

    /// <summary>
    /// <c>[Flags]</c>: the enum is a set of bits rather than a choice among
    /// alternatives, which is what makes <c>|</c>, <c>&amp;</c>, <c>^</c> and
    /// <c>~</c> meaningful on it.
    /// </summary>
    public AttributeTypeSymbol Flags { get; }

    /// <summary>
    /// <c>[Packed]</c>: lay this type out with no padding at all, and give it an
    /// alignment of one. It is a rule about layout rather than a library
    /// feature, so it needs no import, exactly as <c>[Flags]</c> does not.
    /// </summary>
    public AttributeTypeSymbol Packed { get; }

    /// <summary>
    /// <c>[Align(N)]</c>: give this type an alignment of at least N. It raises
    /// and never lowers, the way C's <c>alignas</c> does.
    /// </summary>
    public AttributeTypeSymbol Align { get; }

    public ClassTypeSymbol String { get; }
    public ClassTypeSymbol Utf16String { get; }
    public ClassTypeSymbol StringBuilder { get; }

    public FunctionSymbol StringConcat { get; }
    public FunctionSymbol StringEquals { get; }

    /// <summary>
    /// Ordering and hashing for the types that cannot implement an interface.
    ///
    /// A primitive is not a class, so <c>int</c> cannot be declared to
    /// implement <c>IComparable&lt;int&gt;</c>. The binder recognises
    /// <c>CompareTo</c> and <c>HashCode</c> on one anyway and lowers each to
    /// one of these, which is what lets <c>Sort(numbers)</c> work on a
    /// <c>List&lt;int&gt;</c> without the language growing operator constraints.
    /// </summary>
    public FunctionSymbol CompareLong { get; }
    public FunctionSymbol CompareULong { get; }
    public FunctionSymbol CompareDouble { get; }
    public FunctionSymbol CompareText { get; }
    public FunctionSymbol HashInteger { get; }
    public FunctionSymbol HashDouble { get; }
    public FunctionSymbol HashText { get; }

    private static readonly SourceText BuiltinSource = new("<builtin>", "");
    private static readonly SourceSpan BuiltinSpan = new(BuiltinSource, 0, 0);

    private static readonly PointerTypeSymbol BytePointer = new(PrimitiveTypeSymbol.Byte);
    private static readonly PointerTypeSymbol UShortPointer = new(PrimitiveTypeSymbol.UShort);

    public Builtins()
    {
        Text = new ModuleSymbol(TextModuleName);
        Console = new ModuleSymbol(ConsoleModuleName);
        Standard = new ModuleSymbol(StandardModuleName);

        Flags = new AttributeTypeSymbol
        {
            SimpleName = "Flags",
            ModuleName = StandardModuleName,
            IsPublic = true,
        };
        Flags.SetLayout(0, 1);
        Standard.Types[Flags.SimpleName] = Flags;

        Packed = new AttributeTypeSymbol
        {
            SimpleName = "Packed",
            ModuleName = StandardModuleName,
            IsPublic = true,
        };
        Packed.SetLayout(0, 1);
        Standard.Types[Packed.SimpleName] = Packed;

        Align = new AttributeTypeSymbol
        {
            SimpleName = "Align",
            ModuleName = StandardModuleName,
            IsPublic = true,
        };
        Align.Fields.Add(new FieldSymbol("Bytes", PrimitiveTypeSymbol.Int, Align, 0)
        {
            IsPublic = true,
        });
        Align.SetLayout(4, 4);
        Standard.Types[Align.SimpleName] = Align;

        String = new ClassTypeSymbol
        {
            SimpleName = "String",
            ModuleName = TextModuleName,
            IsPublic = true,
            IsIntrinsic = true,
        };
        String.SetLayout(0, 8);

        Utf16String = new ClassTypeSymbol
        {
            SimpleName = "Utf16String",
            ModuleName = TextModuleName,
            IsPublic = true,
            IsIntrinsic = true,
        };
        Utf16String.SetLayout(0, 8);

        // Mutable text. Its bytes are a separate growable allocation, so `new`
        // goes through a runtime factory rather than the usual sl_alloc.
        StringBuilder = new ClassTypeSymbol
        {
            SimpleName = "StringBuilder",
            ModuleName = TextModuleName,
            IsPublic = true,
            IsIntrinsic = true,
            RuntimeFactory = "sl_string_builder_new",
        };
        StringBuilder.SetLayout(0, 8);

        Text.Types[String.SimpleName] = String;
        Text.Types[Utf16String.SimpleName] = Utf16String;
        Text.Types[StringBuilder.SimpleName] = StringBuilder;

        // --- String methods ------------------------------------------------
        Method(String, "ByteLength", PrimitiveTypeSymbol.NUInt, "sl_string_byte_length");
        Method(String, "CodePointCount", PrimitiveTypeSymbol.NUInt, "sl_string_code_point_count");
        Method(String, "IsEmpty", PrimitiveTypeSymbol.Bool, "sl_string_is_empty");
        Method(String, "ToPointer", BytePointer, "sl_string_pointer");
        Method(String, "ToUtf16", Utf16String, "sl_string_to_utf16");
        Method(String, "Substring", String, "sl_string_substring",
            ("start", PrimitiveTypeSymbol.NUInt), ("length", PrimitiveTypeSymbol.NUInt));

        // --- Utf16String methods -------------------------------------------
        Method(Utf16String, "UnitCount", PrimitiveTypeSymbol.NUInt, "sl_utf16_unit_count");
        Method(Utf16String, "ToPointer", UShortPointer, "sl_utf16_pointer");
        Method(Utf16String, "ToText", String, "sl_utf16_to_string");

        // --- StringBuilder methods ------------------------------------------
        Method(StringBuilder, "Append", PrimitiveTypeSymbol.Void, "sl_string_builder_append",
            ("text", String));
        Method(StringBuilder, "AppendLine", PrimitiveTypeSymbol.Void, "sl_string_builder_append_line",
            ("text", String));
        Method(StringBuilder, "AppendInteger", PrimitiveTypeSymbol.Void,
            "sl_string_builder_append_integer", ("value", PrimitiveTypeSymbol.Long));
        Method(StringBuilder, "AppendDouble", PrimitiveTypeSymbol.Void,
            "sl_string_builder_append_double", ("value", PrimitiveTypeSymbol.Double));
        Method(StringBuilder, "ByteLength", PrimitiveTypeSymbol.NUInt,
            "sl_string_builder_byte_length");
        Method(StringBuilder, "IsEmpty", PrimitiveTypeSymbol.Bool, "sl_string_builder_is_empty");
        Method(StringBuilder, "Clear", PrimitiveTypeSymbol.Void, "sl_string_builder_clear");
        Method(StringBuilder, "ToText", String, "sl_string_builder_to_string");

        // --- Standard.Text free functions -----------------------------------
        Function(Text, "FromInteger", String, "sl_string_from_integer",
            ("value", PrimitiveTypeSymbol.Long));
        Function(Text, "FromInteger", String, "sl_string_from_integer",
            ("value", PrimitiveTypeSymbol.NUInt));
        Function(Text, "FromBool", String, "sl_string_from_bool",
            ("value", PrimitiveTypeSymbol.Bool));
        Function(Text, "FromDouble", String, "sl_string_from_double",
            ("value", PrimitiveTypeSymbol.Double));
        Function(Text, "FromBytes", String, "sl_string_from_bytes",
            ("data", BytePointer), ("byteLength", PrimitiveTypeSymbol.NUInt));
        Function(Text, "FromNullTerminated", String, "sl_string_from_null_terminated",
            ("text", BytePointer));

        // The way back from a platform that speaks UTF-16. A wide API writes into
        // a buffer the caller owns, so what comes back is a pointer and a length
        // rather than a Utf16String, and the pair is what these two take.
        Function(Text, "FromUtf16", String, "sl_string_from_utf16",
            ("units", UShortPointer), ("unitCount", PrimitiveTypeSymbol.NUInt));
        Function(Text, "FromNullTerminatedUtf16", String,
            "sl_string_from_null_terminated_utf16", ("units", UShortPointer));

        // Operators. These are resolved by the binder, not written by hand.
        StringConcat = Function(Text, "Concat", String, "sl_string_concat",
            ("left", String), ("right", String));
        StringEquals = Function(Text, "Equals", PrimitiveTypeSymbol.Bool, "sl_string_equals",
            ("left", String), ("right", String));

        // --- ordering and hashing --------------------------------------------
        // Hidden: they live in the auto-imported Standard module but are not
        // public, so nothing can name them and the emitter still declares them.
        CompareLong = Hidden("CompareLong", PrimitiveTypeSymbol.Int, "sl_compare_long",
            ("left", PrimitiveTypeSymbol.Long), ("right", PrimitiveTypeSymbol.Long));
        CompareULong = Hidden("CompareULong", PrimitiveTypeSymbol.Int, "sl_compare_ulong",
            ("left", PrimitiveTypeSymbol.ULong), ("right", PrimitiveTypeSymbol.ULong));
        CompareDouble = Hidden("CompareDouble", PrimitiveTypeSymbol.Int, "sl_compare_double",
            ("left", PrimitiveTypeSymbol.Double), ("right", PrimitiveTypeSymbol.Double));
        CompareText = Hidden("CompareText", PrimitiveTypeSymbol.Int, "sl_string_compare",
            ("left", String), ("right", String));

        HashInteger = Hidden("HashInteger", PrimitiveTypeSymbol.NUInt, "sl_hash_integer",
            ("value", PrimitiveTypeSymbol.ULong));
        HashDouble = Hidden("HashDouble", PrimitiveTypeSymbol.NUInt, "sl_hash_double",
            ("value", PrimitiveTypeSymbol.Double));
        HashText = Hidden("HashText", PrimitiveTypeSymbol.NUInt, "sl_string_hash",
            ("value", String));

        // --- Standard.Console ------------------------------------------------
        Function(Console, "Write", PrimitiveTypeSymbol.Void, "sl_console_write",
            ("text", String));
        Function(Console, "WriteLine", PrimitiveTypeSymbol.Void, "sl_console_write_line",
            ("text", String));
        Function(Console, "WriteError", PrimitiveTypeSymbol.Void, "sl_console_write_error",
            ("text", String));
    }

    public bool IsString(TypeSymbol type) => ReferenceEquals(type, String);

    /// <summary>Registers the built-in modules so imports and lookups can find them.</summary>
    public void RegisterInto(Dictionary<string, ModuleSymbol> modules)
    {
        modules[Text.Name] = Text;
        modules[Console.Name] = Console;
        modules[Standard.Name] = Standard;
    }

    /// <summary>
    /// Standard.Text is visible in every file without an import, because string
    /// literals produce a <c>String</c> whether the program asked for one or not.
    /// Standard.Console is not: printing is a choice.
    /// </summary>
    public void AutoImportInto(FileScope scope)
    {
        if (scope.Module == Text || scope.Module == Console) return;
        scope.Imports[TextModuleName] = Text;
        scope.Imports["Text"] = Text;
        scope.Imports[StandardModuleName] = Standard;
    }

    private FunctionSymbol Method(
        ClassTypeSymbol owner,
        string name,
        TypeSymbol returnType,
        string runtimeSymbol,
        params (string Name, TypeSymbol Type)[] parameters)
    {
        var symbol = Declare(Text, name, returnType, runtimeSymbol, owner, parameters);
        owner.Methods.Add(symbol);
        return symbol;
    }

    /// <summary>
    /// A runtime function the binder calls but no source can name: it goes into
    /// the module so the emitter declares it, and is not public so lookup skips
    /// it.
    /// </summary>
    private FunctionSymbol Hidden(
        string name,
        TypeSymbol returnType,
        string runtimeSymbol,
        params (string Name, TypeSymbol Type)[] parameters)
    {
        var symbol = Declare(Standard, name, returnType, runtimeSymbol, null, parameters, isPublic: false);
        return symbol;
    }

    private FunctionSymbol Function(
        ModuleSymbol module,
        string name,
        TypeSymbol returnType,
        string runtimeSymbol,
        params (string Name, TypeSymbol Type)[] parameters) =>
        Declare(module, name, returnType, runtimeSymbol, containingType: null, parameters);

    private static FunctionSymbol Declare(
        ModuleSymbol module,
        string name,
        TypeSymbol returnType,
        string runtimeSymbol,
        NamedTypeSymbol? containingType,
        (string Name, TypeSymbol Type)[] parameters,
        bool isPublic = true)
    {
        var symbol = new FunctionSymbol
        {
            Name = name,
            ModuleName = module.Name,
            ReturnType = returnType,
            Linkage = LinkageKind.ExternC,
            RuntimeSymbol = runtimeSymbol,
            Kind = containingType is null ? FunctionKind.Function : FunctionKind.Method,
            ContainingType = containingType,
            IsPublic = isPublic,
            Span = BuiltinSpan,
        };

        if (containingType is not null)
            symbol.Parameters.Add(new ParameterSymbol("this", containingType, 0) { IsThis = true });

        foreach (var (parameterName, parameterType) in parameters)
            symbol.Parameters.Add(
                new ParameterSymbol(parameterName, parameterType, symbol.Parameters.Count));

        module.Functions.Add(symbol);
        return symbol;
    }
}
