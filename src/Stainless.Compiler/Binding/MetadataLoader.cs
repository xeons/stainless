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

using Stainless.Driver;
using Stainless.Source;
using Stainless.Syntax;

namespace Stainless.Binding;

/// <summary>
/// Turns a referenced library's metadata into symbols, so a compilation can
/// bind against a library it has no source for.
///
/// What comes out is deliberately indistinguishable from a declaration the
/// binder made itself, except in one respect: every function is external, so
/// nothing here is ever emitted as a definition. The library already has the
/// code; this compilation only needs to know how to call it.
/// </summary>
public sealed class MetadataLoader(DiagnosticBag diagnostics)
{
    private static readonly SourceText Referenced = new("<referenced>", "");
    private static readonly SourceSpan ReferencedSpan = new(Referenced, 0, 0);

    private readonly Dictionary<string, NamedTypeSymbol> _byQualifiedName =
        new(StringComparer.Ordinal);

    /// <summary>
    /// Declares everything the metadata describes into <paramref name="modules"/>.
    ///
    /// Types come first and members second, because a method may name a type
    /// declared later in the same file — the same reason the binder itself has
    /// separate passes for the two.
    /// </summary>
    public void Load(IReadOnlyList<ModuleMetadata> references, Dictionary<string, ModuleSymbol> modules)
    {
        var pending = new List<(MetadataType Metadata, NamedTypeSymbol Symbol)>();

        // A base may be described after the class deriving from it, so the
        // relation is recorded here and joined up once every name exists.
        var bases = new List<(ClassTypeSymbol Derived, string Base)>();

        // An alias names a type, and the type may be described after it.
        var aliases = new List<(AliasSymbol Alias, string Target)>();

        foreach (var reference in references)
        foreach (var described in reference.Types)
        {
            var module = Module(modules, described.Module);
            string name = described.Name;

            // An alias is a name in its own table, not a type in the type one.
            if (described.Kind == MetadataKind.Alias)
            {
                if (module.Aliases.ContainsKey(name) || module.Types.ContainsKey(name))
                {
                    diagnostics.Error("SL0417", ReferencedSpan,
                        $"'{described.Module}.{name}' is declared both in this program and in " +
                        $"the referenced library '{reference.Library}'; a referenced type " +
                        "cannot be redeclared");
                    continue;
                }

                var declared = new AliasSymbol(name, described.Module)
                {
                    IsPublic = true,
                    Span = ReferencedSpan,
                };

                module.Aliases[name] = declared;
                if (described.AliasTarget is { } target) aliases.Add((declared, target));
                continue;
            }

            if (module.Types.ContainsKey(name))
            {
                diagnostics.Error("SL0417", ReferencedSpan,
                    $"'{described.Module}.{name}' is declared both in this program and in the " +
                    $"referenced library '{reference.Library}'; a referenced type cannot be " +
                    "redeclared");
                continue;
            }

            NamedTypeSymbol symbol = described.Kind switch
            {
                MetadataKind.Class => new ClassTypeSymbol
                {
                    SimpleName = name, ModuleName = described.Module, IsPublic = true,
                    ExternalTypeInfo = described.TypeInfoSymbol,
                },
                MetadataKind.Union => new UnionTypeSymbol
                {
                    SimpleName = described.Name,
                    ModuleName = described.Module,
                    IsPublic = true,
                },

                MetadataKind.Struct => new StructTypeSymbol
                {
                    SimpleName = name, ModuleName = described.Module, IsPublic = true,
                    IsOpaque = described.IsOpaque,
                },
                _ => new EnumTypeSymbol
                {
                    SimpleName = name, ModuleName = described.Module, IsPublic = true,
                },
            };

            symbol.SetLayout(described.Size, described.Alignment);

            if (described.Base is not null && symbol is ClassTypeSymbol derived)
                bases.Add((derived, described.Base));
            module.Types[name] = symbol;
            _byQualifiedName[symbol.QualifiedName] = symbol;
            pending.Add((described, symbol));
        }

        foreach (var (derived, baseName) in bases)
            if (_byQualifiedName.TryGetValue(baseName, out var found) &&
                found is ClassTypeSymbol inheritedFrom)
                derived.BaseClass = inheritedFrom;

        foreach (var (alias, target) in aliases)
            alias.Target = Resolve(target) ?? ErrorTypeSymbol.Instance;

        foreach (var (described, symbol) in pending) FillMembers(described, symbol, modules);

        foreach (var reference in references)
        foreach (var function in reference.Functions)
        {
            var module = Module(modules, function.Module ?? "");
            module.Functions.Add(Declare(function, module.Name, containingType: null));
        }
    }

    private static ModuleSymbol Module(Dictionary<string, ModuleSymbol> modules, string name)
    {
        if (modules.TryGetValue(name, out var existing)) return existing;

        var module = new ModuleSymbol(name);
        modules[name] = module;
        return module;
    }

    private void FillMembers(
        MetadataType described, NamedTypeSymbol symbol, Dictionary<string, ModuleSymbol> modules)
    {
        if (symbol is EnumTypeSymbol enumType)
        {
            if (described.Underlying is { } underlying &&
                Resolve(underlying) is PrimitiveTypeSymbol integer)
                enumType.UnderlyingType = integer;

            foreach (var member in described.Members)
                enumType.Members.Add(new EnumMemberSymbol(member.Name, enumType, member.Value));

            return;
        }

        foreach (var field in described.Fields)
        {
            if (Resolve(field.Type) is not { } fieldType)
            {
                diagnostics.Error("SL0418", ReferencedSpan,
                    $"'{symbol.QualifiedName}.{field.Name}' has type '{field.Type}', which this " +
                    "program does not know; the library was built against something this one " +
                    "does not reference");
                continue;
            }

            symbol.Fields.Add(new FieldSymbol(field.Name, fieldType, symbol, symbol.Fields.Count)
            {
                IsPublic = field.IsPublic,
                IsBackingField = field.IsBackingField,
                Offset = field.Offset,
                BitWidth = field.BitWidth,
                BitOffset = field.BitOffset,
            });
        }

        var owner = Module(modules, symbol.ModuleName);

        foreach (var method in described.Methods)
        {
            var declared = Declare(method, symbol.ModuleName, symbol);

            // A method belongs to its module's function list as well as its
            // type's, which is where the emitter finds what to declare.
            owner.Functions.Add(declared);

            switch (method.Kind)
            {
                case FunctionKind.Constructor when symbol is ClassTypeSymbol constructed:
                    constructed.Constructors.Add(declared);
                    break;

                case FunctionKind.Destructor when symbol is ClassTypeSymbol destroyed:
                    destroyed.Destructor = declared;
                    break;

                default:
                    symbol.Methods.Add(declared);
                    break;
            }
        }

        // An accessor pair is a property again, so the consumer writes `p.X`
        // rather than naming the lowering.
        foreach (var group in symbol.Methods
                     .Where(m => m.MetadataAccessor is not null)
                     .GroupBy(m => m.MetadataAccessor!, StringComparer.Ordinal))
        {
            var getter = group.FirstOrDefault(m => !m.ReturnType.IsVoid());
            var setter = group.FirstOrDefault(m => m.ReturnType.IsVoid());
            if (getter is null && setter is null) continue;

            var property = new PropertySymbol
            {
                Name = group.Key,
                Type = getter?.ReturnType
                       ?? setter!.Parameters.First(p => !p.IsThis).Type,
                ContainingType = symbol,
                Span = ReferencedSpan,
                IsPublic = true,
                Getter = getter,
                Setter = setter,
            };

            foreach (var accessor in group) accessor.Accessor = property;
            symbol.Properties.Add(property);
        }
    }

    private FunctionSymbol Declare(
        MetadataFunction described, string moduleName, NamedTypeSymbol? containingType)
    {
        var symbol = new FunctionSymbol
        {
            Name = described.Name,
            ModuleName = moduleName,
            ReturnType = Resolve(described.Returns) ?? PrimitiveTypeSymbol.Void,
            Linkage = LinkageKind.Stainless,
            Kind = described.Kind,
            ContainingType = containingType,
            IsPublic = true,
            IsVariadic = described.IsVariadic,

            // A virtual method has to stay virtual across the boundary, or a
            // consumer would call the declaration rather than the object's own
            // implementation -- the one thing dispatch exists to prevent.
            IsVirtual = described.VirtualSlot >= 0,
            VirtualSlot = described.VirtualSlot,
            Span = ReferencedSpan,

            // The library decided this name. Re-deriving it would work today and
            // would be a second copy of the mangling scheme to keep in step.
            ForeignName = described.Symbol,
            IsExternal = true,
            MetadataAccessor = described.Accessor,
        };

        if (containingType is not null)
        {
            TypeSymbol receiver = containingType is ClassTypeSymbol reference
                ? reference
                : new PointerTypeSymbol(containingType);
            symbol.Parameters.Add(new ParameterSymbol("this", receiver, 0) { IsThis = true });
        }

        foreach (var parameter in described.Parameters)
        {
            var type = Resolve(parameter.Type);
            if (type is null)
            {
                diagnostics.Error("SL0418", ReferencedSpan,
                    $"'{described.Name}' takes a '{parameter.Type}', which this program does " +
                    "not know");
                type = ErrorTypeSymbol.Instance;
            }

            symbol.Parameters.Add(
                new ParameterSymbol(parameter.Name, type, symbol.Parameters.Count)
                {
                    Mode = parameter.Mode,
                });
        }

        return symbol;
    }

    /// <summary>
    /// Resolves a written type against the types the metadata declared, and
    /// against the intrinsic ones every program has.
    /// </summary>
    private TypeSymbol? Resolve(string written) =>
        MetadataTypeNames.Read(written, name =>
            _byQualifiedName.TryGetValue(name, out var found) ? found : Intrinsic(name));

    private NamedTypeSymbol? Intrinsic(string qualifiedName) =>
        _intrinsics.TryGetValue(qualifiedName, out var found) ? found : null;

    private readonly Dictionary<string, NamedTypeSymbol> _intrinsics =
        new(StringComparer.Ordinal);

    /// <summary>
    /// Registers the types every compilation already has, so a library's
    /// <c>String</c> resolves to this program's rather than to a second copy.
    /// </summary>
    public void RegisterIntrinsics(IEnumerable<ModuleSymbol> modules)
    {
        foreach (var type in modules.SelectMany(m => m.Types.Values))
            _intrinsics[type.QualifiedName] = type;
    }
}
