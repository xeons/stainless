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
public sealed class ModuleSymbol(string name)
{
    public string Name { get; } = name;

    public Dictionary<string, NamedTypeSymbol> Types { get; } = new(StringComparer.Ordinal);
    public List<FunctionSymbol> Functions { get; } = [];
    public Dictionary<string, ConstantSymbol> Constants { get; } = new(StringComparer.Ordinal);

    /// <summary>Modules whose public members are visible here, keyed by the name used to reach them.</summary>
    public Dictionary<string, ModuleSymbol> Imports { get; } = new(StringComparer.Ordinal);

    public CompilationUnitSyntax? Syntax { get; set; }

    public IEnumerable<FunctionSymbol> FindFunctions(string name) =>
        Functions.Where(f => f.Name == name && f.ContainingType is null);

    public override string ToString() => Name;
}
