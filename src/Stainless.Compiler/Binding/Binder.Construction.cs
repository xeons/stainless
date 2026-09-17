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
            // A cast runs a declared conversion of either word: writing the
            // cast is never wrong, and for an explicit one it is the only
            // spelling there is.
            if (UserConversion(operand, targetType, allowExplicit: true, syntax.Span) is { } converted)
                return converted;

            // The one com pairing refused for a reason the types alone do not
            // show, so the reason is said.
            string hint = operand.Type is ComInterfaceTypeSymbol fromCom &&
                          targetType is ComInterfaceTypeSymbol toCom &&
                          (!fromCom.HasUnknown || !toCom.HasUnknown)
                ? $"; '{(fromCom.HasUnknown ? toCom : fromCom).Name}' is '[NoUnknown]', so " +
                  "there is no QueryInterface to ask"
                : "";

            diagnostics.Error("SL0243", syntax.Span,
                $"cannot convert '{operand.Type.Name}' to '{targetType.Name}'{hint}");
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

        if (type is ClassTypeSymbol { IsStaticClass: true })
        {
            diagnostics.Error("SL0583", syntax.Span,
                $"'{type.Name}' is a static class, so there is nothing to make one of: its " +
                "members belong to the type. Call them on the type itself");
            return new BoundErrorExpression(syntax.Span);
        }

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

        // BindArgument rather than BindExpression: a constructor call takes
        // `ref`, `out` and `name:` like any other, and BindExpression has no
        // case for those -- it would answer with an error expression and no
        // diagnostic, which is how `new Rect(left: 1, ...)` came to compile
        // and construct a rectangle of zeroes.
        var arguments = syntax.Arguments.Select(BindArgument).ToList();

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

            return WithObjectInitializer(
                syntax, classType, new BoundNew(syntax.Span, classType, inherited, []));
        }

        var constructor = ResolveOverload(
            classType.Constructors, arguments, syntax.Span, $"new {classType.Name}", syntax.Arguments);
        if (constructor is null) return new BoundErrorExpression(syntax.Span);

        // A constructor's visibility is a visibility like any other, and it was
        // being ignored: `public` on one meant nothing, so a type could not
        // insist on being made through a factory. That is the shape a Result-
        // returning `Open` needs -- without it the factory is advice.
        if (!CanReach(constructor.IsPublic, constructor.IsProtected, classType))
            diagnostics.Error("SL0572", syntax.Span,
                $"'{classType.Name}' has no constructor that can be reached from here; " +
                "the ones it declares belong to its own module. There is usually a " +
                "function that makes one and says what went wrong if it could not");

        var parameters = constructor.Parameters.Where(p => !p.IsThis).ToList();

        int[]? map = MapArguments(
            parameters, arguments.Count, syntax.Arguments, constructor.IsVariadic, out string? why);

        if (map is null)
        {
            diagnostics.Error("SL0601", syntax.Span,
                $"'new {classType.Name}' does not fit: " +
                (why ?? "the names do not match its parameters"));
            return new BoundErrorExpression(syntax.Span);
        }

        var (ordered, spans) = Arrange(
            constructor, parameters, arguments, syntax.Arguments, map, syntax.Span);

        var converted = ConvertArguments(constructor, ordered, spans);

        return WithObjectInitializer(
            syntax, classType, new BoundNew(syntax.Span, classType, constructor, converted));
    }

    /// <summary>
    /// <c>new Panel { Width = 3 }</c> and <c>new List&lt;int&gt; { 1, 2 }</c>:
    /// the object, and the writes or additions the braces asked for.
    ///
    /// <para>
    /// It lowers to exactly what it is short for -- the construction held in a
    /// name, then one write or one <c>Add</c> per entry, then the name. So
    /// nothing here can do what the written-out form could not, which is the
    /// property worth having: an initializer is a way of writing, and not a
    /// second way of building.
    /// </para>
    ///
    /// <para>
    /// <b>Which kind it is comes from the entries.</b> Named ones write members
    /// and bare ones are added, and the two may not be mixed: a brace list that
    /// did both would be two different things at once, and the reader would
    /// have to look at the type to see which each entry was.
    /// </para>
    ///
    /// <para>
    /// <c>Add</c> is found <b>by name rather than by interface</b>, which is
    /// the rule <c>foreach</c> already keeps for <c>GetEnumerator</c>: a type
    /// can be built up this way without <c>Standard.Collections</c> appearing
    /// anywhere in the program.
    /// </para>
    /// </summary>
    private BoundExpression WithObjectInitializer(
        NewSyntax syntax, ClassTypeSymbol classType, BoundExpression creation)
    {
        if (syntax.Initializer is not { } initializer) return creation;

        if (initializer.Entries.Count == 0) return creation;

        bool named = initializer.Entries[0].Name is not null;

        foreach (var entry in initializer.Entries)
            if (entry.Name is not null != named)
            {
                diagnostics.Error("SL0618", entry.Span,
                    named
                        ? "this entry has no name, and the ones before it write members; a " +
                          "brace list either writes members or adds elements, and cannot be " +
                          "half of each"
                        : "this entry names a member, and the ones before it are elements to " +
                          "add; a brace list either writes members or adds elements, and " +
                          "cannot be half of each");
                return new BoundErrorExpression(syntax.Span);
            }

        // Held in a name, because every entry works on the same object and the
        // construction may not be evaluated again.
        var held = new LocalSymbol(SyntheticName("made"), classType, isConst: true);
        var reading = new BoundLocalAccess(syntax.Span, held);

        var writes = new List<BoundExpression>();

        foreach (var entry in initializer.Entries)
        {
            var written = named
                ? BindMemberInitializer(classType, reading, entry)
                : BindElementAddition(classType, reading, entry);

            if (written is null) return new BoundErrorExpression(syntax.Span);
            writes.Add(written);
        }

        return new BoundLet(syntax.Span, held, creation,
            new BoundSequence(syntax.Span, writes, reading));
    }

    /// <summary>
    /// <c>Name = value</c>: the write it is short for, against the object just
    /// made. A property goes through its setter, as it does anywhere else.
    /// </summary>
    private BoundExpression? BindMemberInitializer(
        ClassTypeSymbol classType, BoundExpression receiver, InitializerEntrySyntax entry)
    {
        string name = entry.Name!;

        if (classType.FindProperty(name) is { } property)
        {
            if (property.Setter is null)
            {
                diagnostics.Error("SL0618", entry.NameSpan,
                    $"'{classType.Name}.{name}' has no setter, so there is nothing here to " +
                    "write; a brace list writes members the way an assignment does");
                return null;
            }

            if (!CanReach(property.IsPublic, property.IsProtected, property.ContainingType))
            {
                diagnostics.Error("SL0249", entry.NameSpan,
                    NotVisible(property.ContainingType, name, property.IsProtected));
                return null;
            }

            var value = BindConversion(BindExpression(entry.Value), property.Type, entry.Value.Span);
            if (value.Type.IsError()) return null;

            NoteMemberWritten(property);
            return new BoundPropertyAssignment(entry.Span, receiver, property, value);
        }

        if (classType.FindField(name) is { IsBackingField: false } field)
        {
            if (!CanReach(field.IsPublic, field.IsProtected, field.ContainingType))
            {
                diagnostics.Error("SL0249", entry.NameSpan,
                    NotVisible(field.ContainingType, name, field.IsProtected));
                return null;
            }

            var value = BindConversion(BindExpression(entry.Value), field.Type, entry.Value.Span);
            if (value.Type.IsError()) return null;

            var target = new BoundFieldAccess(entry.NameSpan, receiver, field);
            return new BoundAssignment(entry.Span, target, value);
        }

        diagnostics.Error("SL0618", entry.NameSpan,
            $"'{classType.Name}' has no field or property named '{name}' to write");
        return null;
    }

    /// <summary>
    /// A bare entry: <c>Add(value)</c> on the object just made, found by name
    /// the way <c>foreach</c> finds <c>GetEnumerator</c>.
    /// </summary>
    private BoundExpression? BindElementAddition(
        ClassTypeSymbol classType, BoundExpression receiver, InitializerEntrySyntax entry)
    {
        var candidates = classType.FindMethods("Add").Where(m => !m.IsStatic).ToList();

        if (candidates.Count == 0)
        {
            diagnostics.Error("SL0618", entry.Span,
                $"'{classType.Name}' has no 'Add' method, so there is nothing for an element " +
                "here to be added with; a brace list of values is a call to 'Add' per value");
            return null;
        }

        var argument = BindExpression(entry.Value);
        if (argument.Type.IsError()) return null;

        var chosen = ResolveOverload(
            candidates, [argument], entry.Span, $"{classType.Name}.Add");

        if (chosen is null) return null;

        var converted = ConvertArguments(chosen, [argument], [entry.Value.Span]);
        return new BoundCall(entry.Span, chosen, receiver, converted);
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
    ///
    /// A loop rather than the recursion this reads as, because the chain is as
    /// long as the source says and the parser builds it without recursing:
    /// <c>x.a.a.a...</c> is a postfix loop there, so nothing upstream bounds
    /// the depth and a long enough one ended the process here. Walking down
    /// and reversing costs one list and cannot overflow.
    /// </summary>
    private static IReadOnlyList<string>? FlattenName(ExpressionSyntax expression)
    {
        var trailing = new List<string>();

        while (expression is MemberAccessSyntax member)
        {
            trailing.Add(member.Member);
            expression = member.Target;
        }

        if (expression is not NameSyntax name) return null;
        if (trailing.Count == 0) return name.Name.Parts;

        trailing.Reverse();
        return [.. name.Name.Parts, .. trailing];
    }

    /// <summary>
    /// Resolves a member-access target to a module, or null when it names a value.
    /// A local, parameter or field always wins over a module of the same name.
    /// </summary>
    private ModuleSymbol? ResolveModulePrefix(ExpressionSyntax target)
    {
        if (FlattenName(target) is not { } parts) return null;

        if (NamesAValue(parts[0])) return null;

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
        if (NamesAValue(parts[0])) return null;

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

    /// <summary>
    /// The class or struct a <c>FileStream.Open</c> is qualified by, or null.
    ///
    /// Only a type reached by a name that is not already a value: a local
    /// called <c>Socket</c> wins over the type of that name, exactly as it does
    /// for an enum or a variant. A generic type is not reachable this way,
    /// because type arguments cannot be written at a call.
    /// </summary>
    /// <summary>
    /// The type a dotted name in expression position means, or null.
    ///
    /// Four spellings reach one type, and they are tried in this order because
    /// each is nearer than the last: `Outer.Inner` written out, `Inner` from
    /// inside `Outer`, a plain name in this module or an import, and a name
    /// qualified by its module.
    ///
    /// A nested type is looked for before the module path for a reason worth
    /// keeping: a type in this file called `Outer` is a surer thing than a
    /// module of that name somebody imported.
    /// </summary>
    private TypeSymbol? TypeNamed(IReadOnlyList<string> parts)
    {
        var module = _currentScope!.Module;
        string whole = string.Join('.', parts);

        if (parts.Count > 1)
        {
            if (module.Types.TryGetValue(whole, out var nestedHere)) return nestedHere;

            foreach (var imported in _currentScope.Imports.Values.Distinct())
                if (imported.Types.TryGetValue(whole, out var nestedThere) && nestedThere.IsPublic)
                    return nestedThere;
        }

        if (parts.Count == 1)
        {
            if (module.Types.TryGetValue(parts[0], out var local)) return local;

            if (Enclosing() is { } within &&
                module.Types.TryGetValue(within + "." + parts[0], out var sibling))
                return sibling;

            var visible = _currentScope.Imports.Values.Distinct()
                .Select(m => m.Types.TryGetValue(parts[0], out var t) && t.IsPublic ? t : null)
                .Where(t => t is not null)
                .Distinct()
                .ToList();

            return visible.Count == 1 ? visible[0] : null;
        }

        string moduleName = string.Join('.', parts.Take(parts.Count - 1));
        ModuleSymbol? owner =
            _currentScope.Imports.TryGetValue(moduleName, out var imported2) ? imported2
            : _modules.TryGetValue(moduleName, out var known) ? known
            : null;

        return owner is not null &&
               owner.Types.TryGetValue(parts[^1], out var qualified) &&
               (owner == module || qualified.IsPublic)
            ? qualified
            : null;
    }

    private NamedTypeSymbol? ResolveTypePrefix(ExpressionSyntax target)
    {
        if (FlattenName(target) is not { } parts) return null;
        if (NamesAValue(parts[0])) return null;

        return TypeNamed(parts) as NamedTypeSymbol;
    }

    /// <summary>
    /// Whether a name already means storage here. A local, a parameter, a field
    /// or a property is nearer than any type or module of the same name, which
    /// is what keeps a variable called <c>Level</c> from being shadowed by an
    /// enum of that name.
    /// </summary>
    private bool NamesAValue(string name) =>
        LookupLocal(name) is not null ||
        _currentFunction?.Parameters.Any(p => p.Name == name && !p.IsThis) == true ||
        _currentFunction?.ContainingType?.FindField(name) is not null ||
        _currentFunction?.ContainingType?.FindProperty(name) is not null;

    private EnumTypeSymbol? ResolveEnumPrefix(ExpressionSyntax target)
    {
        if (FlattenName(target) is not { } parts) return null;

        if (NamesAValue(parts[0])) return null;

        // `Widget.State` is one name when `State` is nested in `Widget`, and a
        // module and a type when it is not. TypeNamed tries them in that order.
        if (TypeNamed(parts) is EnumTypeSymbol named) return named;

        if (parts.Count == 1) return null;

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
