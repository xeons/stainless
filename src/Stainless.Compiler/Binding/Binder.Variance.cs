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
/// <c>in</c> and <c>out</c> on an interface's or a delegate's type parameters.
///
/// Monomorphized, <c>IEnumerable&lt;Dog&gt;</c> and
/// <c>IEnumerable&lt;Animal&gt;</c> are two interfaces with two ids, and an
/// object implementing the first has no table for the second. Two things make
/// the conversion sound anyway. Each slot of the two holds a function that
/// differs only in which reference types it names, and a reference is one
/// pointer whatever its type, so the first's functions answer the second's
/// calls. And the program is whole, so every class that could be behind the
/// converted reference is known: each is given a table for the second built
/// from its functions for the first, before anything is emitted.
///
/// A delegate or a closure needs no table at all. It is a function pointer,
/// with its receiver for a closure, and the same pointer answers either type.
/// </summary>
public sealed partial class Binder
{
    /// <summary>The template each instantiated delegate or closure came from.</summary>
    private readonly Dictionary<NamedTypeSymbol, GenericDelegateTemplate> _delegateTemplates = [];

    /// <summary>The template an instantiation came from, of either kind, or null.</summary>
    private object? GenericOrigin(NamedTypeSymbol type) =>
        (object?)type.Template ?? _delegateTemplates.GetValueOrDefault(type);

    /// <summary>What each type parameter of an instantiation's template was written with.</summary>
    private IReadOnlyList<Variance> VarianceOf(NamedTypeSymbol type) => GenericOrigin(type) switch
    {
        GenericTypeTemplate template => template.Declaration.TypeParameterVariance,
        GenericDelegateTemplate template => template.Declaration.TypeParameterVariance,
        _ => [],
    };

    /// <summary>
    /// True when <paramref name="from"/> may stand for <paramref name="to"/>
    /// because they are instantiations of one variant template: each argument
    /// the same, or, where the parameter is <c>out</c>, one that converts to
    /// the other with no instruction, and where it is <c>in</c>, the other way.
    /// Only a reference converts with no instruction, so an argument that is a
    /// value has to be the same, as in C#.
    /// </summary>
    private bool IsVarianceConvertible(TypeSymbol from, TypeSymbol to)
    {
        if (from is not NamedTypeSymbol source || to is not NamedTypeSymbol target) return false;
        if (source.Equals(target)) return false;

        var origin = GenericOrigin(source);
        if (origin is null || !ReferenceEquals(origin, GenericOrigin(target))) return false;

        var variance = VarianceOf(source);
        if (variance.All(v => v == Variance.None)) return false;

        for (int i = 0; i < source.TypeArguments.Count; i++)
        {
            var given = source.TypeArguments[i];
            var wanted = target.TypeArguments[i];
            if (given.Equals(wanted)) continue;

            bool fits = (i < variance.Count ? variance[i] : Variance.None) switch
            {
                Variance.Out => IsReferenceWidening(given, wanted),
                Variance.In => IsReferenceWidening(wanted, given),
                _ => false,
            };

            if (!fits) return false;
        }

        return true;
    }

    /// <summary>
    /// The interface an implementer really has that stands for
    /// <paramref name="wanted"/> by variance, or null. The first in the order
    /// the implementer lists them, when more than one would do.
    /// </summary>
    private InterfaceTypeSymbol? VarianceSource(NamedTypeSymbol implementer, InterfaceTypeSymbol wanted)
    {
        if (wanted.Template is null) return null;

        var held = implementer is InterfaceTypeSymbol self
            ? implementer.AllInterfaces().Prepend(self)
            : implementer.AllInterfaces();

        return held.FirstOrDefault(i =>
            ReferenceEquals(i.Template, wanted.Template) && IsVarianceConvertible(i, wanted));
    }

    // ================================================================ tables

    /// <summary>
    /// Makes sure that each generic instantiation called through a variant
    /// interface has its counterpart on the interface each class really
    /// implements, so the fixpoint instantiates the class's template for it.
    /// Answers whether that made anything.
    /// </summary>
    private bool CompleteVariantGenericSlots()
    {
        int before = _instantiatedFunctions.Count;

        foreach (var (classType, wanted, source) in StoodFor())
            foreach (var slot in wanted.GenericSlots.ToList())
                CounterpartOf(slot, source);

        return _instantiatedFunctions.Count != before;
    }

    /// <summary>
    /// Every class, with each variant interface it stands for without
    /// implementing it and the interface it implements that stands in.
    /// </summary>
    private List<(ClassTypeSymbol Class, InterfaceTypeSymbol Wanted, InterfaceTypeSymbol Source)> StoodFor()
    {
        var variant = _interfaces
            .Where(i => i.Template is not null && VarianceOf(i).Any(v => v != Variance.None))
            .GroupBy(i => i.Template!)
            .ToDictionary(g => g.Key, g => g.ToList());

        var found = new List<(ClassTypeSymbol, InterfaceTypeSymbol, InterfaceTypeSymbol)>();
        if (variant.Count == 0) return found;

        foreach (var classType in _classes.ToList())
        {
            var held = classType.AllInterfaces().ToList();
            var answered = new HashSet<InterfaceTypeSymbol>(held);

            // The order the class lists them decides between two that would do.
            foreach (var source in held)
            {
                if (source.Template is null || !variant.TryGetValue(source.Template, out var kin))
                    continue;

                foreach (var wanted in kin)
                    if (!answered.Contains(wanted) && IsVarianceConvertible(source, wanted))
                    {
                        answered.Add(wanted);
                        found.Add((classType, wanted, source));
                    }
            }
        }

        return found;
    }

    /// <summary>The same instantiation of the same template, on another instantiation of its interface.</summary>
    private FunctionSymbol? CounterpartOf(FunctionSymbol slot, InterfaceTypeSymbol on)
    {
        var template = on.GenericMethods.FirstOrDefault(t =>
            ReferenceEquals(t.Declaration, slot.Template!.Declaration));

        return template is null
            ? null
            : InstantiateFunction(template, slot.TypeArguments, template.Declaration.Span);
    }

    /// <summary>
    /// Gives each class a table for every variant interface it stands for
    /// without implementing: slot for slot, its own functions for the
    /// interface it really implements.
    /// </summary>
    private void BuildVarianceTables()
    {
        foreach (var (classType, wanted, source) in StoodFor())
        {
            var sourceDeclared = source.Methods.Where(m => !m.IsStatic).ToList();
            var slots = new List<FunctionSymbol?>();

            foreach (var slot in wanted.DispatchSlots)
            {
                // A declared member is at the same position in both, since
                // both were declared from one template; a generic
                // instantiation is found by what it instantiates.
                var counterpart = slot.Template is null
                    ? sourceDeclared[slots.Count]
                    : CounterpartOf(slot, source);

                slots.Add(counterpart is null ? null : classType.ImplementationOf(counterpart));
            }

            classType.VarianceTables[wanted] = slots;
        }
    }

    // ============================================================ validity

    /// <summary>
    /// Every variant parameter appears only where its variance lets it: an
    /// <c>out</c> one where a value comes out, an <c>in</c> one where a value
    /// goes in. C#'s CS1961, and for the reason C# has it: otherwise the
    /// conversion the word allows would hand a method a value of the wrong
    /// type.
    /// </summary>
    private void CheckVarianceDeclarations()
    {
        foreach (var module in _modules.Values)
        {
            foreach (var template in module.GenericTypes.Values)
            {
                var declaration = template.Declaration;
                var variant = VariantParameters(declaration.TypeParameters, declaration.TypeParameterVariance);
                if (variant.Count == 0) continue;

                // An interface extending another hands out what the other does.
                foreach (var extended in declaration.Implements)
                    CheckVariantUse(extended, Position.Output, variant, template.Scope,
                        $"'{template.Name}' extends it");

                foreach (var member in declaration.Members)
                    CheckVariantMember(member, variant, template.Scope);
            }

            foreach (var template in module.GenericDelegates.Values)
            {
                var declaration = template.Declaration;
                var variant = VariantParameters(declaration.TypeParameters ?? [], declaration.TypeParameterVariance);
                if (variant.Count == 0) continue;

                CheckVariantUse(declaration.ReturnType, Position.Output, variant, template.Scope,
                    $"'{template.Name}' returns it");
                foreach (var parameter in declaration.Parameters)
                    CheckVariantUse(parameter.Type, ParameterPosition(parameter), variant,
                        template.Scope, $"'{template.Name}' takes it as '{parameter.Name}'");
            }
        }
    }

    /// <summary>Where a type is written, as variance sees it.</summary>
    private enum Position { Output, Input, Invariant }

    private static Dictionary<string, Variance> VariantParameters(
        IReadOnlyList<string> parameters, IReadOnlyList<Variance> variance)
    {
        var found = new Dictionary<string, Variance>(StringComparer.Ordinal);
        for (int i = 0; i < parameters.Count && i < variance.Count; i++)
            if (variance[i] != Variance.None)
                found[parameters[i]] = variance[i];
        return found;
    }

    /// <summary>
    /// A <c>ref</c> or <c>out</c> parameter is read and written both, so it is
    /// neither way round.
    /// </summary>
    private static Position ParameterPosition(ParameterSyntax parameter) =>
        parameter.Mode is ParameterMode.Ref or ParameterMode.Out ? Position.Invariant : Position.Input;

    /// <summary>One member of a variant interface. A static one is not reached through a reference.</summary>
    private void CheckVariantMember(
        Declaration member, Dictionary<string, Variance> variant, FileScope scope)
    {
        if (member.Modifiers.HasFlag(Modifiers.Static)) return;

        switch (member)
        {
            case FunctionDeclSyntax function:
            {
                // A method's own parameters hide the interface's of that name.
                var visible = new Dictionary<string, Variance>(variant, StringComparer.Ordinal);
                foreach (string own in function.TypeParameters) visible.Remove(own);

                CheckVariantUse(function.ReturnType, Position.Output, visible, scope,
                    $"'{function.Name}' returns it");
                foreach (var parameter in function.Parameters)
                    CheckVariantUse(parameter.Type, ParameterPosition(parameter), visible, scope,
                        $"'{function.Name}' takes it as '{parameter.Name}'");
                break;
            }

            case PropertyDeclSyntax property:
            {
                bool reads = property.Accessors.Any(a => a.IsGetter);
                bool writes = property.Accessors.Any(a => !a.IsGetter);
                var position = reads && writes ? Position.Invariant
                    : writes ? Position.Input
                    : Position.Output;

                CheckVariantUse(property.Type, position, variant, scope,
                    $"'{property.Name}' is {(position == Position.Invariant ? "read and written" : position == Position.Input ? "written" : "read")}");
                foreach (var index in property.Indices)
                    CheckVariantUse(index.Type, Position.Input, variant, scope,
                        $"'{property.Name}' takes it as '{index.Name}'");
                break;
            }
        }
    }

    /// <summary>
    /// Walks one written type, flipping the position through an <c>in</c>
    /// parameter of whatever it instantiates and fixing it through anything
    /// that is not variant.
    /// </summary>
    private void CheckVariantUse(
        TypeSyntax type, Position position, Dictionary<string, Variance> variant,
        FileScope scope, string where)
    {
        switch (type)
        {
            case NamedTypeSyntax { Name.Parts.Count: 1, TypeArguments.Count: 0 } named
                when variant.TryGetValue(named.Name.Parts[0], out var written):
            {
                bool fits = written switch
                {
                    Variance.Out => position == Position.Output,
                    Variance.In => position == Position.Input,
                    _ => true,
                };
                if (fits) return;

                string word = written == Variance.Out ? "out" : "in";
                diagnostics.Error("SL0801", named.Span,
                    $"'{named.Name.Text}' is '{word}', so it may appear only where a value " +
                    (written == Variance.Out ? "comes out" : "goes in") + $", and {where}" +
                    (position == Position.Invariant
                        ? " where a value both goes in and comes out"
                        : written == Variance.Out ? ", which puts it where one goes in" : ", which puts it where one comes out") +
                    $". Remove '{word}', or move '{named.Name.Text}'");
                return;
            }

            case NamedTypeSyntax { TypeArguments.Count: > 0 } constructed:
            {
                var arguments = constructed.TypeArguments;
                var ofTemplate =
                    (FindGenericType(constructed.Name, scope) is { Declaration.Kind: TypeDeclKind.Interface } contract
                        ? contract.Declaration.TypeParameterVariance
                        : FindGenericDelegate(constructed.Name, scope)?.Declaration.TypeParameterVariance)
                    ?? [];

                for (int i = 0; i < arguments.Count; i++)
                {
                    var through = i < ofTemplate.Count ? ofTemplate[i] : Variance.None;
                    var inner = through switch
                    {
                        Variance.Out => position,
                        Variance.In => position switch
                        {
                            Position.Output => Position.Input,
                            Position.Input => Position.Output,
                            _ => Position.Invariant,
                        },
                        _ => Position.Invariant,
                    };
                    CheckVariantUse(arguments[i], inner, variant, scope, where);
                }
                return;
            }

            // The same pointer whether it may be null or not.
            case NullableTypeSyntax nullable:
                CheckVariantUse(nullable.Element, position, variant, scope, where);
                return;

            // An array is written through as well as read, and the rest are
            // values holding what they hold.
            case ArrayTypeSyntax array:
                CheckVariantUse(array.Element, Position.Invariant, variant, scope, where);
                return;
            case SliceTypeSyntax slice:
                CheckVariantUse(slice.Element, Position.Invariant, variant, scope, where);
                return;
            case FixedArrayTypeSyntax inline:
                CheckVariantUse(inline.Element, Position.Invariant, variant, scope, where);
                return;
            case PointerTypeSyntax pointer:
                CheckVariantUse(pointer.Element, Position.Invariant, variant, scope, where);
                return;
            case WeakTypeSyntax weak:
                CheckVariantUse(weak.Element, Position.Invariant, variant, scope, where);
                return;
            case TupleTypeSyntax tuple:
                foreach (var element in tuple.Elements)
                    CheckVariantUse(element, Position.Invariant, variant, scope, where);
                return;
        }
    }
}
