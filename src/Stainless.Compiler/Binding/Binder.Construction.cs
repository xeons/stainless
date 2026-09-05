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
/// The operators that ask a question about a type rather than about a
/// value -- <c>sizeof</c>, <c>alignof</c>, <c>offsetof</c>, <c>typeof</c>,
/// <c>iidof</c> and a cast -- and <c>new</c>, which answers one with an
/// object. Visibility lives here too, since <c>new</c> is where it is
/// most often violated.
/// </summary>
public sealed partial class Binder
{
    private BoundExpression BindSizeof(SizeofSyntax syntax)
    {
        var measured = ResolveType(syntax.Type, _currentScope!);
        return new BoundSizeof(syntax.Span, PrimitiveTypeSymbol.NUInt, measured);
    }

    private BoundExpression BindAlignof(AlignofSyntax syntax)
    {
        var measured = ResolveType(syntax.Type, _currentScope!);
        return new BoundAlignof(syntax.Span, PrimitiveTypeSymbol.NUInt, measured);
    }

    /// <summary>
    /// <c>offsetof(T, Field)</c>, which is C's, and answers the same number for
    /// a struct. For a class it counts from the start of the allocation, so the
    /// result is what to add to the reference you hold -- a class reference
    /// points at the object header, and the fields follow it.
    /// </summary>
    private BoundExpression BindOffsetof(OffsetofSyntax syntax)
    {
        var owner = ResolveType(syntax.Type, _currentScope!);
        if (owner.IsError()) return new BoundErrorExpression(syntax.Span);

        if (owner is not NamedTypeSymbol named || owner is InterfaceTypeSymbol)
        {
            diagnostics.Error("SL0480", syntax.Type.Span,
                $"'offsetof' needs a struct, union, variant or class, and " +
                $"'{owner.Name}' is none of those");
            return new BoundErrorExpression(syntax.Span);
        }

        var field = named.Fields.FirstOrDefault(f => f.Name == syntax.Field);
        if (field is null)
        {
            diagnostics.Error("SL0481", syntax.FieldSpan,
                $"'{named.Name}' has no field named '{syntax.Field}'");
            return new BoundErrorExpression(syntax.Span);
        }

        if (field.IsBitField)
        {
            diagnostics.Error("SL0482", syntax.FieldSpan,
                $"'{named.Name}.{field.Name}' is a bit-field, which has no byte " +
                "offset of its own; C refuses this too");
            return new BoundErrorExpression(syntax.Span);
        }

        return new BoundOffsetof(syntax.Span, PrimitiveTypeSymbol.NUInt, named, field);
    }

    /// <summary>
    /// <c>typeof(T)</c>. The result is a handle to metadata the compiler laid
    /// down for T, so T must have been marked [Reflect].
    /// </summary>
    private BoundExpression BindTypeof(TypeofSyntax syntax)
    {
        var measured = ResolveType(syntax.Type, _currentScope!);
        if (measured.IsError()) return new BoundErrorExpression(syntax.Span);

        if (TypeHandle is not { } handle)
        {
            diagnostics.Error("SL0347", syntax.Span,
                "'typeof' needs Standard.Reflection, which is not part of this compilation");
            return new BoundErrorExpression(syntax.Span);
        }

        if (measured is not NamedTypeSymbol { IsReflected: true } reflected)
        {
            diagnostics.Error("SL0346", syntax.Span,
                $"'{measured.Name}' carries no metadata, so 'typeof' cannot name it; " +
                "mark its declaration '[Reflect]'");
            return new BoundErrorExpression(syntax.Span);
        }

        return new BoundTypeof(syntax.Span, handle, reflected);
    }

    private BoundExpression BindIidof(IidofSyntax syntax)
    {
        var named = ResolveType(syntax.Type, _currentScope!);
        if (named.IsError()) return new BoundErrorExpression(syntax.Span);

        if (named is not ComInterfaceTypeSymbol comInterface)
        {
            diagnostics.Error("SL0542", syntax.Span,
                $"'{named.Name}' is not a com interface, so it has no IID; 'iidof' names the " +
                "'[Guid]' written on a 'com interface' declaration");
            return new BoundErrorExpression(syntax.Span);
        }

        return new BoundIidof(
            syntax.Span, new PointerTypeSymbol(_builtins.Guid), comInterface);
    }

    private BoundExpression BindCast(CastSyntax syntax)
    {
        var targetType = ResolveType(syntax.Type, _currentScope!);
        var operand = BindExpression(syntax.Operand);
        if (operand.Type.IsError() || targetType.IsError())
            return new BoundErrorExpression(syntax.Span);

        var kind = ClassifyConversion(operand.Type, targetType, explicitCast: true);
        if (kind is null)
        {
            diagnostics.Error("SL0243", syntax.Span,
                $"cannot convert '{operand.Type.Name}' to '{targetType.Name}'");
            return new BoundErrorExpression(syntax.Span);
        }

        return kind == ConversionKind.Identity && operand.Type.Equals(targetType)
            ? operand
            : new BoundConversion(syntax.Span, targetType, operand, kind.Value);
    }

    private BoundExpression BindNew(NewSyntax syntax)
    {
        var type = ResolveType(syntax.Type, _currentScope!);
        if (type.IsError()) return new BoundErrorExpression(syntax.Span);

        if (type is not ClassTypeSymbol classType)
        {
            diagnostics.Error("SL0244", syntax.Span,
                $"'{type.Name}' is not a class; only classes are heap allocated. " +
                type switch
                {
                    StructTypeSymbol => "Declare a struct as a plain value instead.",
                    InterfaceTypeSymbol => "An interface has no implementation to construct; " +
                                           "create a class that implements it.",
                    _ => "Use a pointer and an allocator for raw memory.",
                });
            return new BoundErrorExpression(syntax.Span);
        }

        if (classType.IsAbstract)
        {
            diagnostics.Error("SL0514", syntax.Span,
                $"'{classType.Name}' is abstract, so there is no such object to make; " +
                "it exists to be derived from. Make one of its derived classes instead");
            return new BoundErrorExpression(syntax.Span);
        }

        // A runtime-provided class is built by its factory, not by sl_alloc.
        if (classType.RuntimeFactory is not null)
        {
            if (syntax.Arguments.Count > 0)
                diagnostics.Error("SL0308", syntax.Span,
                    $"'new {classType.Name}()' takes no arguments");
            return new BoundNew(syntax.Span, classType, constructor: null, []);
        }

        var arguments = syntax.Arguments.Select(BindExpression).ToList();

        if (classType.Constructors.Count == 0)
        {
            if (arguments.Count > 0)
                diagnostics.Error("SL0245", syntax.Span,
                    $"'{classType.Name}' has no constructor, so 'new {classType.Name}()' takes no arguments");

            // Constructors are not inherited, but a class that declares none is
            // one whose only construction is its base's -- so that is what runs.
            // A class with no way to run one reported that where it was
            // declared, so nothing is said again here.
            TryImplicitBaseConstructor(classType, out var inherited);
            return new BoundNew(syntax.Span, classType, inherited, []);
        }

        var constructor = ResolveOverload(classType.Constructors, arguments, syntax.Span, $"new {classType.Name}");
        if (constructor is null) return new BoundErrorExpression(syntax.Span);

        var converted = ConvertArguments(constructor, arguments, syntax.Arguments);
        return new BoundNew(syntax.Span, classType, constructor, converted);
    }

    /// <summary>
    /// The base constructor a class chains to when it does not say which.
    ///
    /// It is the nearest one up the chain, skipping any class that declares no
    /// constructor at all -- such a class has nothing to run, and its own base
    /// still does. A class that declares only constructors taking arguments has
    /// to be named explicitly, because there is no obvious one to pick.
    /// </summary>
    private bool TryImplicitBaseConstructor(
        ClassTypeSymbol classType, out FunctionSymbol? chained)
    {
        chained = null;

        // Nothing up the chain declares one, so there is nothing to run and
        // nothing to complain about.
        if (NearestConstructing(classType) is not { } ancestor) return true;

        chained = ancestor.Constructors.FirstOrDefault(c => !c.Parameters.Any(p => !p.IsThis));
        return chained is not null;
    }

    /// <summary>
    /// The nearest class up the chain that declares a constructor, or null.
    ///
    /// A class that declares none has nothing of its own to run, and its base
    /// still does, so <c>base(...)</c> reaches past it -- which is also what
    /// C# means by the implicit constructor such a class is given.
    /// </summary>
    private static ClassTypeSymbol? NearestConstructing(ClassTypeSymbol classType)
    {
        for (var current = classType.BaseClass; current is not null; current = current.BaseClass)
            if (current.Constructors.Count > 0) return current;

        return null;
    }

    /// <summary>
    /// True when the code being bound may reach a <c>protected</c> member of
    /// <paramref name="owner"/>: it is inside a class that derives from it.
    /// </summary>
    private bool CanReachProtected(NamedTypeSymbol owner) =>
        owner is ClassTypeSymbol ownerClass &&
        _currentFunction?.ContainingType is ClassTypeSymbol here &&
        here.DerivesFrom(ownerClass);

    /// <summary>
    /// Whether a member of <paramref name="owner"/> with this visibility can be
    /// named from where binding is.
    ///
    /// Public is everywhere. Anything else is its module's, which is what
    /// privacy has always meant here -- a module is the unit of it. Protected
    /// adds the one exception: a class deriving from the owner may reach it
    /// wherever that class lives, because a base class handing something to its
    /// derived classes and to nobody else is the whole of what the word is for.
    /// </summary>
    private bool CanReach(bool isPublic, bool isProtected, NamedTypeSymbol owner) =>
        isPublic
        || owner.ModuleName == _currentModule!.Name
        || (isProtected && CanReachProtected(owner));

    /// <summary>How a diagnostic should describe a member that could not be reached.</summary>
    private static string NotVisible(NamedTypeSymbol owner, string member, bool isProtected) =>
        isProtected
            ? $"'{owner.Name}.{member}' is protected, so only '{owner.Name}' and classes " +
              "deriving from it may name it"
            : $"'{owner.Name}.{member}' is not public";

    /// <summary>
    /// Flattens a chain of member accesses back into a dotted name, so that
    /// <c>A.B.Thing</c> can be recognised as a module path. Returns null as soon
    /// as anything other than a plain name appears in the chain.
    /// </summary>
    private static IReadOnlyList<string>? FlattenName(ExpressionSyntax expression) => expression switch
    {
        NameSyntax name => name.Name.Parts,
        MemberAccessSyntax member when FlattenName(member.Target) is { } prefix =>
            [.. prefix, member.Member],
        _ => null,
    };

    /// <summary>
    /// Resolves a member-access target to a module, or null when it names a value.
    /// A local, parameter or field always wins over a module of the same name.
    /// </summary>
    private ModuleSymbol? ResolveModulePrefix(ExpressionSyntax target)
    {
        if (FlattenName(target) is not { } parts) return null;

        if (LookupLocal(parts[0]) is not null) return null;
        if (_currentFunction?.Parameters.Any(p => p.Name == parts[0] && !p.IsThis) == true) return null;
        if (_currentFunction?.ContainingType?.FindField(parts[0]) is not null) return null;
        if (_currentFunction?.ContainingType?.FindProperty(parts[0]) is not null) return null;

        string name = string.Join('.', parts);
        if (_currentScope!.Imports.TryGetValue(name, out var module)) return module;
        return _modules.TryGetValue(name, out module) ? module : null;
    }

    /// <summary>
    /// Resolves a member-access target to an enum type, or null when it names a
    /// value. Like <see cref="ResolveModulePrefix"/> a local of the same name
    /// wins, so an enum called <c>Level</c> never shadows a variable.
    /// </summary>
    /// <summary>
    /// The variant a <c>Shape.Circle</c> is qualified by, or null.
    ///
    /// Only a variant already named as a type, so a generic one is not reachable
    /// this way: type arguments cannot be written at a call, which is the same
    /// reason <c>Ok(x)</c> takes its type from where it is going.
    /// </summary>
    private VariantTypeSymbol? ResolveVariantPrefix(ExpressionSyntax target)
    {
        if (FlattenName(target) is not { } parts) return null;

        // A value of that name is nearer than a type of it, exactly as for an
        // enum: `shape.Circle` tests a variant, `Shape.Circle` builds one.
        if (LookupLocal(parts[0]) is not null) return null;
        if (_currentFunction?.Parameters.Any(p => p.Name == parts[0] && !p.IsThis) == true) return null;
        if (_currentFunction?.ContainingType?.FindField(parts[0]) is not null) return null;
        if (_currentFunction?.ContainingType?.FindProperty(parts[0]) is not null) return null;

        if (parts.Count == 1)
        {
            if (_currentScope!.Module.Types.TryGetValue(parts[0], out var local))
                return local as VariantTypeSymbol;

            foreach (var imported in _currentScope.Imports.Values)
                if (imported.Types.TryGetValue(parts[0], out var found) &&
                    found is VariantTypeSymbol { IsPublic: true } visible)
                    return visible;

            return null;
        }

        string moduleName = string.Join(".", parts.Take(parts.Count - 1));
        return _modules.TryGetValue(moduleName, out var module) &&
               module.Types.TryGetValue(parts[^1], out var qualified) &&
               qualified is VariantTypeSymbol { IsPublic: true } reachable
            ? reachable
            : null;
    }

    private EnumTypeSymbol? ResolveEnumPrefix(ExpressionSyntax target)
    {
        if (FlattenName(target) is not { } parts) return null;

        if (LookupLocal(parts[0]) is not null) return null;
        if (_currentFunction?.Parameters.Any(p => p.Name == parts[0] && !p.IsThis) == true) return null;
        if (_currentFunction?.ContainingType?.FindField(parts[0]) is not null) return null;
        if (_currentFunction?.ContainingType?.FindProperty(parts[0]) is not null) return null;

        // Either a bare name in this module, or one qualified by its module.
        if (parts.Count == 1)
        {
            if (_currentScope!.Module.Types.TryGetValue(parts[0], out var local))
                return local as EnumTypeSymbol;

            var visible = _currentScope.Imports.Values.Distinct()
                .Select(m => m.Types.TryGetValue(parts[0], out var t) && t.IsPublic ? t : null)
                .OfType<EnumTypeSymbol>()
                .Distinct()
                .ToList();

            return visible.Count == 1 ? visible[0] : null;
        }

        string moduleName = string.Join('.', parts.Take(parts.Count - 1));
        ModuleSymbol? module =
            _currentScope!.Imports.TryGetValue(moduleName, out var imported) ? imported
            : _modules.TryGetValue(moduleName, out var known) ? known
            : null;

        if (module is null) return null;
        return module.Types.TryGetValue(parts[^1], out var candidate) && candidate.IsPublic
            ? candidate as EnumTypeSymbol
            : null;
    }

    private BoundExpression BindNewArray(NewArraySyntax syntax)
    {
        var element = ResolveType(syntax.ElementType, _currentScope!);
        var length = BindExpression(syntax.Length);

        if (element.IsError() || length.Type.IsError()) return new BoundErrorExpression(syntax.Span);

        if (element.IsVoid())
        {
            diagnostics.Error("SL0310", syntax.Span, "there is no array of 'void'");
            return new BoundErrorExpression(syntax.Span);
        }

        if (length.Type is not PrimitiveTypeSymbol { IsInteger: true })
        {
            diagnostics.Error("SL0312", syntax.Length.Span,
                $"an array length must be an integer, but this is '{length.Type.Name}'");
            return new BoundErrorExpression(syntax.Span);
        }

        return new BoundNewArray(syntax.Span, ArrayOf(element),
            BindConversion(length, PrimitiveTypeSymbol.NUInt, syntax.Length.Span));
    }
}
