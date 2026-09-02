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

    public ModuleSymbol Text { get; }
    public ModuleSymbol Console { get; }

    public ClassTypeSymbol String { get; }
    public ClassTypeSymbol Utf16String { get; }
    public ClassTypeSymbol StringBuilder { get; }

    public FunctionSymbol StringConcat { get; }
    public FunctionSymbol StringEquals { get; }

    private static readonly SourceText BuiltinSource = new("<builtin>", "");
    private static readonly SourceSpan BuiltinSpan = new(BuiltinSource, 0, 0);

    private static readonly PointerTypeSymbol BytePointer = new(PrimitiveTypeSymbol.Byte);
    private static readonly PointerTypeSymbol UShortPointer = new(PrimitiveTypeSymbol.UShort);

    public Builtins()
    {
        Text = new ModuleSymbol(TextModuleName);
        Console = new ModuleSymbol(ConsoleModuleName);

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

        // Operators. These are resolved by the binder, not written by hand.
        StringConcat = Function(Text, "Concat", String, "sl_string_concat",
            ("left", String), ("right", String));
        StringEquals = Function(Text, "Equals", PrimitiveTypeSymbol.Bool, "sl_string_equals",
            ("left", String), ("right", String));

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
    }

    /// <summary>
    /// Standard.Text is visible everywhere without an import, because string
    /// literals produce a <c>String</c> whether the program asked for one or not.
    /// Standard.Console is not: printing is a choice.
    /// </summary>
    public void AutoImportInto(ModuleSymbol module)
    {
        if (module == Text || module == Console) return;
        module.Imports[TextModuleName] = Text;
        module.Imports["Text"] = Text;
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
        (string Name, TypeSymbol Type)[] parameters)
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
            IsPublic = true,
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
