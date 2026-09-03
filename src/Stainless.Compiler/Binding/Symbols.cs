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

    /// <summary>
    /// True when the body writes to this parameter, or to something inside it.
    ///
    /// A parameter is borrowed, so ordinarily it owns nothing and costs no
    /// reference traffic. Writing to one breaks that: the release of what was
    /// there would fall on a reference the caller still owns. So a parameter
    /// that is written to is retained on entry and released on exit, becoming
    /// the private copy the write already assumed it was.
    /// </summary>
    public bool IsAssigned { get; set; }

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

    /// <summary>
    /// The declared parameter types, without the implicit receiver. This is
    /// what distinguishes one overload from another, and what an interface
    /// requirement is matched against.
    /// </summary>
    public IEnumerable<TypeSymbol> ParameterTypes =>
        Parameters.Where(p => !p.IsThis).Select(p => p.Type);

    /// <summary>True when this takes exactly these parameter types.</summary>
    public bool Accepts(IReadOnlyList<TypeSymbol> parameters) =>
        ParameterTypes.SequenceEqual(parameters);

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

    /// <summary>The property this is the getter or setter of, or null.</summary>
    public PropertySymbol? Accessor { get; set; }

    /// <summary>
    /// True when the body is the compiler's rather than the programmer's: the
    /// <c>get;</c> and <c>set;</c> of an automatic property, which read and
    /// write the hidden field and do nothing else.
    /// </summary>
    public bool IsAutoAccessor { get; init; }

    private string? _mangledName;

    /// <summary>The symbol name the linker sees. See docs/abi.md.</summary>
    /// <summary>
    /// The enclosing C++ namespace, for a declaration with C++ linkage.
    /// </summary>
    public IReadOnlyList<string> CppNamespace { get; set; } = [];

    /// <summary>
    /// The linker name, when something other than this compiler decides it.
    ///
    /// A C++ name is mangled by a scheme that depends on the target, so it is
    /// computed once the ABI is known and stamped here rather than derived on
    /// demand the way a Stainless name is.
    /// </summary>
    public string? ForeignName { get; set; }

    /// <summary>
    /// True for a function this program calls but does not contain: it came
    /// from a referenced library's metadata, so it is declared to the emitter
    /// and never defined by it.
    /// </summary>
    public bool IsExternal { get; init; }

    /// <summary>
    /// The property this accessor belongs to, as the metadata named it. The
    /// property symbol itself is rebuilt from the accessor pair afterwards.
    /// </summary>
    public string? MetadataAccessor { get; init; }

    public string MangledName =>
        _mangledName ??= ForeignName ?? RuntimeSymbol ?? Mangler.Mangle(this);

    public bool HasBody => Body is not null || IsAutoAccessor;

    public override string ToString() =>
        $"{ReturnType.Name} {(ContainingType is null ? "" : ContainingType.Name + ".")}{Name}" +
        $"({string.Join(", ", Parameters.Where(p => !p.IsThis))})";
}

/// <summary>
/// A property: field-shaped syntax over a pair of methods.
///
/// The getter and setter are ordinary <see cref="FunctionSymbol"/>s, which is
/// the whole trick. A property therefore costs nothing new in the ABI, occupies
/// vtable slots like any other method when an interface declares it, and needs
/// no support at all in the emitter. Only an automatic property owns storage,
/// and that storage is an ordinary field the source cannot name.
/// </summary>
public sealed class PropertySymbol
{
    public required string Name { get; init; }
    public required TypeSymbol Type { get; init; }
    public required NamedTypeSymbol ContainingType { get; init; }
    public required Source.SourceSpan Span { get; init; }
    public bool IsPublic { get; init; }

    public FunctionSymbol? Getter { get; set; }
    public FunctionSymbol? Setter { get; set; }

    /// <summary>The generated storage of an automatic property; null otherwise.</summary>
    public FieldSymbol? BackingField { get; set; }

    /// <summary>Attributes written on the property, shared with its backing field.</summary>
    public List<AppliedAttribute> Attributes { get; } = [];

    /// <summary>True when the compiler supplies both the storage and the accessors.</summary>
    public bool IsAuto => BackingField is not null;

    public override string ToString() => $"{ContainingType.Name}.{Name}";
}

/// <summary>
/// Module-level storage, initialized once before <c>Main</c> runs.
///
/// Unlike a <see cref="ConstantSymbol"/> this has an address and a real
/// initializer, so the order the initializers run in matters. Because Stainless
/// compiles the whole program at once, that order is computed rather than
/// guessed: see the topological sort in the binder.
/// </summary>
public sealed class StaticSymbol(string name, TypeSymbol type, string moduleName)
{
    public string Name { get; } = name;
    public TypeSymbol Type { get; } = type;
    public string ModuleName { get; } = moduleName;
    public bool IsPublic { get; init; }

    public required Source.SourceSpan Span { get; init; }

    /// <summary>The initializer, bound in pass 8 like any other body.</summary>
    public BoundExpression? Initializer { get; set; }

    /// <summary>The statics this one's initializer reads, for ordering.</summary>
    public List<StaticSymbol> DependsOn { get; } = [];

    public string QualifiedName =>
        string.IsNullOrEmpty(ModuleName) ? Name : ModuleName + "." + Name;

    public override string ToString() => $"{Type.Name} {QualifiedName}";
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

    /// <summary>The type this is a method of, or null for a free function.</summary>
    public NamedTypeSymbol? ContainingType { get; init; }

    /// <summary>
    /// The type arguments already in force where this template was declared.
    ///
    /// A generic method inside a generic class sees two sets of parameters: the
    /// class's, fixed when the class was instantiated, and its own, inferred at
    /// each call. This holds the first so the second can be merged onto it.
    /// </summary>
    public IReadOnlyDictionary<string, TypeSymbol> OuterSubstitution { get; init; } =
        new Dictionary<string, TypeSymbol>(StringComparer.Ordinal);

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
    public Dictionary<string, StaticSymbol> Statics { get; } = new(StringComparer.Ordinal);

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
