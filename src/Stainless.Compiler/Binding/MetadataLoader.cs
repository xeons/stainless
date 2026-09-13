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
/// <param name="sliceOf">
/// How to reach this compilation's <c>T[:]</c>, and <paramref name="tupleOf"/>
/// its <c>(A, B)</c>. Both are structural but named, so the binder interns
/// them: a library's <c>int[:]</c> has to be the very symbol a consumer's own
/// source resolves to, or the two would not compare equal.
/// </param>
public sealed class MetadataLoader(
    DiagnosticBag diagnostics,
    Builtins builtins,
    MetadataTypeNames.SliceFactory? sliceOf = null,
    MetadataTypeNames.TupleFactory? tupleOf = null)
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
                // A closure's two fields are the compiler's, so they are built
                // here rather than read: the metadata carries the signature,
                // and the representation is this compilation's business on both
                // sides of the boundary.
                MetadataKind.Closure => NewClosure(described),
                MetadataKind.Delegate => new DelegateTypeSymbol
                {
                    SimpleName = name, ModuleName = described.Module, IsPublic = true,
                },

                MetadataKind.Class => new ClassTypeSymbol
                {
                    SimpleName = name, ModuleName = described.Module, IsPublic = true,
                    ExternalTypeInfo = described.TypeInfoSymbol,
                    ExternalDestroy = described.DestroySymbol,
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

            symbol.IsThreadsafe = described.IsThreadsafe;
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

        // Signatures before members, because a member may be typed with a
        // closure and a closure may be typed with anything.
        foreach (var (described, symbol) in pending)
            if (described.Kind is MetadataKind.Closure or MetadataKind.Delegate)
                FillSignature(described, symbol);

        foreach (var (described, symbol) in pending) FillMembers(described, symbol, modules);

        // Events after members: an event is its storage and its two methods,
        // and it is put back together out of them.
        foreach (var (described, symbol) in pending) LoadEvents(described, symbol);

        // Last, because a slot may be filled by a method this class inherited
        // rather than declared, so the whole chain has to have its members
        // before any of them can be looked up.
        foreach (var (described, symbol) in pending)
            if (symbol is ClassTypeSymbol classType) FillVirtualTable(described, classType);

        foreach (var reference in references)
        foreach (var function in reference.Functions)
        {
            var module = Module(modules, function.Module ?? "");
            module.Functions.Add(Declare(function, module.Name, containingType: null));
        }
    }

    /// <summary>
    /// Rebuilds a referenced class's dispatch table from the symbols the
    /// metadata named.
    ///
    /// This is what lets a class be derived from across a library boundary: the
    /// binder appends to a base's table without caring where the table came
    /// from, so handing it the same list the library built is the whole of the
    /// work. A slot may be filled by a method this class inherited rather than
    /// declared, so the lookup walks up.
    ///
    /// An abstract slot is null on both sides and stays null: the class holding
    /// it cannot be made, and every concrete class below it has filled it in.
    /// </summary>
    private void FillVirtualTable(MetadataType described, ClassTypeSymbol classType)
    {
        foreach (string? slot in described.VirtualTable)
        {
            if (slot is null)
            {
                // Nothing to call, and nothing that can be: only an abstract
                // class carries one, and it is never instantiated.
                classType.VirtualTable.Add(AbstractSlot(classType));
                continue;
            }

            if (Find(classType, slot) is { } method)
            {
                classType.VirtualTable.Add(method);
                continue;
            }

            diagnostics.Error("SL0546", ReferencedSpan,
                $"'{classType.QualifiedName}' has a dispatch slot filled by '{slot}', which its " +
                "metadata does not describe. The library and its metadata were written by the " +
                "same compilation, so this file has been edited or is not the one that library " +
                "produced");

            classType.VirtualTable.Add(AbstractSlot(classType));
        }
    }

    /// <summary>The method with this linker name, in a class or above it.</summary>
    private static FunctionSymbol? Find(ClassTypeSymbol classType, string symbol)
    {
        for (var type = classType; type is not null; type = type.BaseClass)
            foreach (var method in type.Methods)
                if (string.Equals(method.MangledName, symbol, StringComparison.Ordinal))
                    return method;

        return null;
    }

    /// <summary>
    /// A stand-in for a slot with nothing in it, so the table keeps its length.
    /// The length is what a derived class appends after, and a table one short
    /// would put a derived method in a slot the base is already dispatching.
    /// </summary>
    private static FunctionSymbol AbstractSlot(ClassTypeSymbol classType) =>
        new()
        {
            Name = "<abstract>",
            ModuleName = classType.ModuleName,
            ReturnType = PrimitiveTypeSymbol.Void,
            Linkage = LinkageKind.Stainless,
            ContainingType = classType,
            IsAbstract = true,
            IsVirtual = true,
            IsExternal = true,
            Span = ReferencedSpan,
        };

    /// <summary>
    /// Rebuilds a closure type: two fields and a layout, exactly as the binder
    /// builds one from a declaration.
    ///
    /// The signature is filled in later, with everything else that names a
    /// type, because a closure may take a type described after it.
    /// </summary>
    private ClosureTypeSymbol NewClosure(MetadataType described)
    {
        var closure = new ClosureTypeSymbol
        {
            SimpleName = described.Name,
            ModuleName = described.Module,
            IsPublic = true,
            Span = ReferencedSpan,
        };

        closure.Function = new FieldSymbol(
            ClosureTypeSymbol.FunctionFieldName,
            new PointerTypeSymbol(PrimitiveTypeSymbol.Byte), closure, 0);

        closure.Receiver = new FieldSymbol(
            ClosureTypeSymbol.ReceiverFieldName, builtins.Bound, closure, 1);

        closure.Fields.Add(closure.Function);
        closure.Fields.Add(closure.Receiver);

        closure.Function.Offset = 0;
        closure.Receiver.Offset = 8;
        closure.SetLayout(16, 8);

        return closure;
    }

    /// <summary>
    /// Fills in a closure's or a delegate's signature, once every type it may
    /// name exists.
    /// </summary>
    private void FillSignature(MetadataType described, NamedTypeSymbol symbol)
    {
        var returns = described.Returns is null ? null : Resolve(described.Returns);

        if (returns is null)
        {
            diagnostics.Error("SL0418", ReferencedSpan,
                $"'{symbol.QualifiedName}' returns '{described.Returns}', which this program " +
                "does not know");
            returns = ErrorTypeSymbol.Instance;
        }

        var signature = new List<ParameterSymbol>();

        for (int i = 0; i < described.Signature.Count; i++)
        {
            var parameter = described.Signature[i];
            var parameterType = Resolve(parameter.Type);

            if (parameterType is null)
            {
                diagnostics.Error("SL0418", ReferencedSpan,
                    $"'{symbol.QualifiedName}' takes a '{parameter.Type}', which this program " +
                    "does not know");
                parameterType = ErrorTypeSymbol.Instance;
            }

            signature.Add(new ParameterSymbol(parameter.Name, parameterType, i)
            {
                Mode = parameter.Mode,
            });
        }

        if (symbol is ClosureTypeSymbol closure)
        {
            closure.ReturnType = returns;
            closure.Signature.AddRange(signature);
            return;
        }

        var asDelegate = (DelegateTypeSymbol)symbol;
        asDelegate.ReturnType = returns;
        asDelegate.Signature.AddRange(signature);
    }

    /// <summary>
    /// Reconnects an event to the storage and the two methods it was written
    /// as, both of which crossed as ordinary members of the type.
    ///
    /// Looked up by name because that is what the writer guarantees: the
    /// storage is named after the event and the methods are <c>add_</c> and
    /// <c>remove_</c> in front of it, which is the same rule that keeps them
    /// apart from a hand-written method of the same name (SL0552).
    /// </summary>
    private void LoadEvents(MetadataType described, NamedTypeSymbol symbol)
    {
        foreach (var described_ in described.Events)
        {
            if (Resolve(described_.Type) is not ClosureTypeSymbol closure)
            {
                diagnostics.Error("SL0418", ReferencedSpan,
                    $"the event '{symbol.QualifiedName}.{described_.Name}' is of type " +
                    $"'{described_.Type}', which this program does not know as a closure");
                continue;
            }

            var backing = symbol.Fields.FirstOrDefault(
                f => f.IsBackingField && f.Name == described_.Name);

            var add = symbol.Methods.FirstOrDefault(m => m.Name == "add_" + described_.Name);
            var remove = symbol.Methods.FirstOrDefault(m => m.Name == "remove_" + described_.Name);

            if (backing is null || add is null || remove is null)
            {
                diagnostics.Error("SL0557", ReferencedSpan,
                    $"the event '{symbol.QualifiedName}.{described_.Name}' is described without " +
                    "the storage and methods it is made of. Metadata is generated from the " +
                    "library it describes; rebuild the library rather than editing the file");
                continue;
            }

            var declared = new EventSymbol
            {
                Name = described_.Name,
                Type = closure,
                ContainingType = symbol,
                Span = ReferencedSpan,
                IsPublic = described_.IsPublic,
                IsProtected = described_.IsProtected,
                BackingField = backing,
                Add = add,
                Remove = remove,
            };

            add.Event = declared;
            remove.Event = declared;

            symbol.Events.Add(declared);
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
        // A return type that does not resolve was silently becoming 'void',
        // which is the one answer that is never right: a call would bind, and
        // the value it was meant to produce would simply not be there.
        var returns = Resolve(described.Returns);
        if (returns is null)
        {
            diagnostics.Error("SL0418", ReferencedSpan,
                $"'{described.Name}' returns a '{described.Returns}', which this program " +
                "does not know");
            returns = ErrorTypeSymbol.Instance;
        }

        var symbol = new FunctionSymbol
        {
            Name = described.Name,
            ModuleName = moduleName,
            ReturnType = returns,
            Linkage = LinkageKind.Stainless,
            Kind = described.Kind,
            ContainingType = containingType,
            IsPublic = true,
            IsVariadic = described.IsVariadic,
            IsStatic = described.IsStatic,

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

        if (containingType is not null && !described.IsStatic)
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
        MetadataTypeNames.Read(
            written,
            name => _byQualifiedName.TryGetValue(name, out var found) ? found : Intrinsic(name),
            sliceOf,
            tupleOf);

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
