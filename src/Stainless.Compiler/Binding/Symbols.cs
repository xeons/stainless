using Stainless.Syntax;

namespace Stainless.Binding;

public enum FunctionKind { Function, Method, Constructor, Destructor }

public sealed class ParameterSymbol(string name, TypeSymbol type, int index)
{
    public string Name { get; } = name;
    public TypeSymbol Type { get; } = type;
    public int Index { get; } = index;

    /// <summary>True for the implicit receiver of a method, constructor or destructor.</summary>
    public bool IsThis { get; init; }

    public override string ToString() => $"{Type.Name} {Name}";
}

public sealed class LocalSymbol(string name, TypeSymbol type, bool isConst)
{
    public string Name { get; } = name;
    public TypeSymbol Type { get; } = type;
    public bool IsConst { get; } = isConst;
    public override string ToString() => $"{Type.Name} {Name}";
}

public sealed class FunctionSymbol
{
    public required string Name { get; init; }
    public required string ModuleName { get; init; }
    public required TypeSymbol ReturnType { get; init; }
    public required LinkageKind Linkage { get; init; }
    public FunctionKind Kind { get; init; } = FunctionKind.Function;
    public NamedTypeSymbol? ContainingType { get; init; }
    public bool IsPublic { get; init; }
    public bool IsVariadic { get; init; }

    public List<ParameterSymbol> Parameters { get; } = [];

    /// <summary>The body to bind, or null for an <c>extern "C"</c> declaration.</summary>
    public BlockSyntax? Body { get; init; }

    /// <summary>Where the declaration came from, for diagnostics.</summary>
    public required Source.SourceSpan Span { get; init; }

    /// <summary>
    /// For built-ins: the exact symbol implemented in the runtime. Set, it
    /// bypasses mangling entirely, so <c>String.ByteLength</c> lowers straight
    /// to <c>sl_string_byte_length</c>.
    /// </summary>
    public string? RuntimeSymbol { get; init; }

    /// <summary>
    /// The type arguments this function was instantiated with. They take part in
    /// mangling, so <c>Max&lt;int&gt;</c> and <c>Max&lt;double&gt;</c> stay
    /// distinct symbols even when the parameters alone would not tell them apart.
    /// </summary>
    public IReadOnlyList<TypeSymbol> TypeArguments { get; init; } = [];

    /// <summary>
    /// The file this was declared in. A module may span files with different
    /// imports, so a body must be bound against its own file's view.
    /// </summary>
    public FileScope? Scope { get; init; }

    private string? _mangledName;

    /// <summary>The symbol name the linker sees. See docs/abi.md.</summary>
    public string MangledName => _mangledName ??= RuntimeSymbol ?? Mangler.Mangle(this);

    public bool HasBody => Body is not null;

    public override string ToString() =>
        $"{ReturnType.Name} {(ContainingType is null ? "" : ContainingType.Name + ".")}{Name}" +
        $"({string.Join(", ", Parameters.Where(p => !p.IsThis))})";
}

/// <summary>A module-level <c>const</c>, folded to a value at bind time.</summary>
public sealed class ConstantSymbol(string name, TypeSymbol type, object? value)
{
    public string Name { get; } = name;
    public TypeSymbol Type { get; } = type;
    public object? Value { get; } = value;
    public bool IsPublic { get; init; }
}

/// <summary>
/// One source file. Modules are the unit of visibility and the reason Stainless
/// needs no headers: a module's public surface is computed from its own source,
/// then consumed directly by importers.
/// </summary>
/// <summary>
/// A generic declaration, kept as syntax rather than symbols.
///
/// Stainless monomorphizes: nothing about a template is checked until it is
/// instantiated, at which point it becomes an ordinary type or function with
/// the type arguments substituted in. That is why the template holds a syntax
/// node and a list of parameter names, and no resolved members at all.
/// </summary>
public sealed class GenericTypeTemplate(
    string name, FileScope scope, TypeDeclSyntax declaration)
{
    public string Name { get; } = name;
    public FileScope Scope { get; } = scope;
    public ModuleSymbol Module => Scope.Module;
    public TypeDeclSyntax Declaration { get; } = declaration;
    public IReadOnlyList<string> Parameters => Declaration.TypeParameters;
    public bool IsPublic => Declaration.Modifiers.HasFlag(Modifiers.Public);

    public override string ToString() => $"{Name}<{string.Join(", ", Parameters)}>";
}

public sealed class GenericFunctionTemplate(
    string name, FileScope scope, FunctionDeclSyntax declaration)
{
    public string Name { get; } = name;
    public FileScope Scope { get; } = scope;
    public ModuleSymbol Module => Scope.Module;
    public FunctionDeclSyntax Declaration { get; } = declaration;
    public IReadOnlyList<string> Parameters => Declaration.TypeParameters;
    public bool IsPublic => Declaration.Modifiers.HasFlag(Modifiers.Public);

    public override string ToString() => $"{Name}<{string.Join(", ", Parameters)}>";
}

public sealed class ModuleSymbol(string name)
{
    public string Name { get; } = name;

    public Dictionary<string, NamedTypeSymbol> Types { get; } = new(StringComparer.Ordinal);

    /// <summary>Generic declarations, awaiting instantiation.</summary>
    public Dictionary<string, GenericTypeTemplate> GenericTypes { get; } = new(StringComparer.Ordinal);
    public List<GenericFunctionTemplate> GenericFunctions { get; } = [];
    public List<FunctionSymbol> Functions { get; } = [];
    public Dictionary<string, ConstantSymbol> Constants { get; } = new(StringComparer.Ordinal);

    public IEnumerable<FunctionSymbol> FindFunctions(string name) =>
        Functions.Where(f => f.Name == name && f.ContainingType is null);

    public override string ToString() => Name;
}

/// <summary>
/// One source file's view of the program: the module its declarations join,
/// plus the imports written in that file.
///
/// Imports are per-file rather than per-module, as in C#. A module may be split
/// across several files, and adding an import to one of them must not quietly
/// change how a sibling resolves names.
/// </summary>
public sealed class FileScope(ModuleSymbol module)
{
    public ModuleSymbol Module { get; } = module;

    /// <summary>Modules reachable from this file, keyed by the name used to reach them.</summary>
    public Dictionary<string, ModuleSymbol> Imports { get; } = new(StringComparer.Ordinal);

    public override string ToString() => Module.Name;
}
