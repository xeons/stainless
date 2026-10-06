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
/// A generic method that is dispatched: one of an interface, or one of a
/// class written <c>virtual</c>, <c>abstract</c> or <c>override</c>.
///
/// C# compiles one body and lets the runtime make an instantiation when a
/// call first needs it. Here every instantiation is a function of its own, and
/// a table slot holds a function, so each instantiation the program calls gets
/// a slot of its own. That is sound because the program is whole: every call
/// is bound before anything is emitted, so the set of instantiations called
/// through <c>IVisitor.Visit&lt;R&gt;</c> is known, and so is every class that
/// could be behind the reference. Each of those classes has its own template
/// instantiated at each of them.
///
/// It is a fixpoint rather than a pass, because instantiating a class's
/// template binds a body that may call another instantiation, or make an
/// instance of another generic class that implements the interface. It ends
/// because every step adds an instantiation, and <see cref="RefuseRunawayInstantiation"/>
/// bounds how many there can be.
///
/// What it does not reach is another binary. An interface and a class
/// implementing one never cross a library boundary (SL0420, SL0545), and a
/// class with a dispatched generic method does not either (SL0799): the
/// library's slots were numbered without the consumer's instantiations.
/// </summary>
public sealed partial class Binder
{
    /// <summary>
    /// Instantiations of class templates that begin a slot: <c>virtual</c> or
    /// <c>abstract</c>, never <c>override</c>. Numbered once the fixpoint ends.
    /// </summary>
    private readonly List<FunctionSymbol> _genericVirtualRoots = [];

    /// <summary>
    /// Templates already reported as not matching what they stand for. The
    /// first instantiation says it; the rest would say it again.
    /// </summary>
    private readonly HashSet<GenericFunctionTemplate> _mismatchReported = [];

    /// <summary>
    /// Every generic template of this name that a value of this type reaches,
    /// the nearest first, with one further away dropped when a nearer one
    /// stands for it.
    /// </summary>
    private static List<GenericFunctionTemplate> GenericMethodsNamed(NamedTypeSymbol type, string name)
    {
        IEnumerable<NamedTypeSymbol> chain = type switch
        {
            ClassTypeSymbol classType => classType.SelfAndBases(),
            InterfaceTypeSymbol contract => contract.AllInterfaces().Prepend(contract),
            _ => [type],
        };

        var found = new List<GenericFunctionTemplate>();
        foreach (var owner in chain)
            foreach (var template in owner.GenericMethods.Where(m => m.Name == name))
                if (!found.Any(nearer => nearer.HasShapeOf(template)))
                    found.Add(template);

        return found;
    }

    /// <summary>
    /// Records a new instantiation of a dispatched template: a slot of its
    /// interface, a slot of its class's family, or, for an override, the slot
    /// the template it replaces begins -- which is instantiated too, so the
    /// slot exists whichever of the two a call happened to name.
    /// </summary>
    private void RegisterDispatched(
        GenericFunctionTemplate template, FunctionSymbol instance, SourceSpan span)
    {
        var root = template.Root;

        if (root != template)
        {
            instance.Overridden = InstantiateFunction(root, instance.TypeArguments, span);
            return;
        }

        if (template.ContainingType is InterfaceTypeSymbol contract)
            Remember(contract.GenericSlots, instance);
        else
            Remember(_genericVirtualRoots, instance);
    }

    /// <summary>
    /// Gives every class each instantiation it can be reached through, and
    /// answers whether that made anything new to bind.
    /// </summary>
    private bool CompleteGenericDispatch()
    {
        int before = _instantiatedFunctions.Count;

        for (int i = 0; i < _interfaces.Count; i++)
        {
            var contract = _interfaces[i];
            for (int s = 0; s < contract.GenericSlots.Count; s++)
            {
                var required = contract.GenericSlots[s];
                for (int c = 0; c < _classes.Count; c++)
                {
                    var classType = _classes[c];
                    if (classType.GenericImplementations.ContainsKey(required)) continue;
                    if (!classType.AllInterfaces().Contains(contract)) continue;

                    classType.GenericImplementations[required] =
                        ImplementInterfaceInstantiation(classType, required);
                }
            }
        }

        for (int r = 0; r < _genericVirtualRoots.Count; r++)
        {
            var root = _genericVirtualRoots[r];
            var owner = (ClassTypeSymbol)root.ContainingType!;

            for (int c = 0; c < _classes.Count; c++)
            {
                var classType = _classes[c];
                if (classType.GenericImplementations.ContainsKey(root)) continue;
                if (!classType.DerivesFrom(owner)) continue;

                classType.GenericImplementations[root] = OverrideOf(classType, root);
            }
        }

        return _instantiatedFunctions.Count != before || PendingCount > 0;
    }

    /// <summary>
    /// What answers an interface's instantiation on one class: the class's own
    /// template of that shape instantiated at the same arguments, or the
    /// interface's default, or nothing on a class that is abstract.
    /// </summary>
    private FunctionSymbol? ImplementInterfaceInstantiation(
        ClassTypeSymbol classType, FunctionSymbol required)
    {
        var template = classType.SelfAndBases()
            .SelectMany(c => c.GenericMethods)
            .FirstOrDefault(t => !t.Declaration.Modifiers.HasFlag(Modifiers.Static) &&
                                 t.HasShapeOf(required.Template!));

        if (template is null) return required.HasBody ? required : null;

        var span = classType.Span ?? template.Declaration.Span;
        var found = InstantiateFunction(template, required.TypeArguments, span);
        if (found is null) return null;

        if (!SameSignature(found, required) && _mismatchReported.Add(template))
            diagnostics.Report(Codes.ImplementationSignatureMismatch, template.Declaration.Span,
                $"'{classType.Name}.{found.Name}' does not match " +
                $"'{required.ContainingType!.Name}.{required.Name}' when both are " +
                $"'<{string.Join(", ", required.TypeArguments.Select(t => t.Name))}>': expected " +
                $"'{required.ReturnType.Name} {required.Name}(" +
                string.Join(", ", required.Parameters.Where(p => !p.IsThis).Select(Spelled)) +
                ")'",
                [classType, required.ContainingType,
                 .. SignatureTypes(required), .. SignatureTypes(found)]);

        return found;
    }

    /// <summary>
    /// What answers a virtual instantiation on one class of its family: the
    /// nearest template that replaces the one the slot began with, at the same
    /// arguments.
    /// </summary>
    private FunctionSymbol? OverrideOf(ClassTypeSymbol classType, FunctionSymbol root)
    {
        var template = classType.SelfAndBases()
            .SelectMany(c => c.GenericMethods)
            .FirstOrDefault(t => t.IsDispatched && t.Root == root.Template);

        if (template is null) return null;

        var found = InstantiateFunction(
            template, root.TypeArguments, classType.Span ?? template.Declaration.Span);
        if (found is null || found == root) return found;

        if (!SignaturesAgree(found, root) && _mismatchReported.Add(template))
            diagnostics.Report(Codes.OverrideSignatureMismatch, template.Declaration.Span,
                $"'{classType.Name}.{found.Name}' does not match what it overrides when both " +
                $"are '<{string.Join(", ", root.TypeArguments.Select(t => t.Name))}>'; " +
                $"expected '{root.ReturnType.Name} {root.Name}(" +
                string.Join(", ", root.Parameters.Where(p => !p.IsThis).Select(Spelled)) + ")'",
                [classType, .. SignatureTypes(root), .. SignatureTypes(found)]);

        return found;
    }

    /// <summary>
    /// Numbers each virtual instantiation's slot, once there will be no more.
    ///
    /// After everything any class in the family already has, so no slot a
    /// class numbered in pass 5 moves: a table is padded to the new slot, and
    /// each class's own answer goes in it.
    /// </summary>
    private void NumberGenericVirtualSlots()
    {
        foreach (var root in _genericVirtualRoots)
        {
            var owner = (ClassTypeSymbol)root.ContainingType!;
            var family = _classes.Where(c => c.DerivesFrom(owner)).ToList();

            int slot = family.Max(c => c.VirtualTable.Count);
            root.VirtualSlot = slot;

            foreach (var classType in family)
            {
                // Null is a slot this class leaves empty: an abstract class's,
                // or one padded past, which no call through this class reaches.
                while (classType.VirtualTable.Count <= slot) classType.VirtualTable.Add(null!);

                var answer = classType.GenericImplementations.GetValueOrDefault(root);
                classType.VirtualTable[slot] = answer!;
                if (answer is not null) answer.VirtualSlot = slot;
            }
        }
    }

    // ============================================================ pass 5

    /// <summary>
    /// The words about overriding, on a class's generic methods: what an
    /// <c>override</c> replaces, and what a concrete class leaves unanswered.
    /// </summary>
    private void ResolveGenericOverrides(ClassTypeSymbol classType, TypeDeclSyntax declaration)
    {
        var inheritedTemplates = classType.BaseClass?.SelfAndBases()
            .SelectMany(c => c.GenericMethods)
            .ToList() ?? [];

        foreach (var template in classType.GenericMethods)
        {
            var modifiers = template.Declaration.Modifiers;
            var inherited = inheritedTemplates.FirstOrDefault(t => t.HasShapeOf(template));

            if (modifiers.HasFlag(Modifiers.Abstract) && template.Declaration.Body is not null)
                diagnostics.Report(Codes.AbstractMemberHasBody, template.Declaration.Span,
                    $"'{template.Name}' is abstract, so it cannot have a body; " +
                    "a derived class supplies one");

            if (modifiers.HasFlag(Modifiers.Abstract) && !classType.IsAbstract)
                diagnostics.Report(Codes.AbstractMemberInConcreteClass, template.Declaration.Span,
                    $"'{classType.Name}.{template.Name}' is abstract, so '{classType.Name}' " +
                    "must be abstract too; a class with a method that has no body cannot be made",
                    classType);

            if (modifiers.HasFlag(Modifiers.Override))
            {
                if (inherited is null)
                    diagnostics.Report(Codes.OverrideHasNoBase, template.Declaration.Span,
                        $"'{classType.Name}.{template.Name}' is marked 'override' and nothing " +
                        "it inherits is a generic method of that name, type parameters and " +
                        "parameters",
                        classType);
                else if (!inherited.IsDispatched)
                    diagnostics.Report(Codes.OverriddenMethodNotVirtual, template.Declaration.Span,
                        $"'{inherited.ContainingType!.Name}.{template.Name}' is not virtual, so " +
                        "it cannot be overridden; mark it 'virtual' or 'abstract'",
                        inherited.ContainingType);
                else
                    template.Overridden = inherited;

                continue;
            }

            if (inherited is not null)
                diagnostics.Report(Codes.InheritedMemberHiddenWithoutOverride,
                    template.Declaration.Span,
                    
                    $"'{classType.Name}.{template.Name}' has the same name, type parameters and " +
                    $"parameters as '{inherited.ContainingType!.Name}.{inherited.Name}'" +
                    (inherited.IsDispatched
                        ? "; write 'override' to replace it"
                        : ", which is not virtual; rename one of them, or mark the inherited " +
                          "one 'virtual' and this one 'override'"),
                    classType, inherited.ContainingType);
        }

        if (classType.IsAbstract) return;

        // Each abstract template in the chain has a nearer one replacing it.
        foreach (var owner in classType.SelfAndBases().Skip(1))
            foreach (var missing in owner.GenericMethods.Where(t =>
                         t.Declaration.Modifiers.HasFlag(Modifiers.Abstract)))
            {
                var answered = classType.SelfAndBases()
                    .TakeWhile(c => c != owner)
                    .SelectMany(c => c.GenericMethods)
                    .Any(t => t.Declaration.Body is not null && t.Root == missing.Root);

                if (!answered)
                    diagnostics.Report(Codes.AbstractMemberNotImplemented,
                        classType.Span ?? declaration.Span,
                        
                        $"'{classType.Name}' does not implement abstract " +
                        $"'{owner.Name}.{missing.Name}'; add 'public override' with the same " +
                        "type parameters and parameters",
                        classType, owner);
            }
    }

    /// <summary>
    /// Each generic method of an interface has, on a class implementing it, a
    /// public generic method of the same shape or a default body. Whether the
    /// two agree in their types is known only per instantiation, and is
    /// checked there.
    /// </summary>
    private void VerifyGenericImplements(
        ClassTypeSymbol classType, InterfaceTypeSymbol interfaceType, SourceSpan span)
    {
        foreach (var required in interfaceType.GenericMethods.Where(t => t.IsDispatched))
        {
            var found = classType.SelfAndBases()
                .SelectMany(c => c.GenericMethods)
                .FirstOrDefault(t => !t.Declaration.Modifiers.HasFlag(Modifiers.Static) &&
                                     t.HasShapeOf(required));

            if (found is null)
            {
                if (required.Declaration.Body is not null || classType.IsAbstract) continue;

                diagnostics.Report(Codes.InterfaceMemberNotImplemented, span,
                    $"'{classType.Name}' does not implement '{interfaceType.Name}.{required.Name}'; " +
                    $"add a public generic method '{required.Name}' taking " +
                    $"{required.Parameters.Count} type parameter" +
                    (required.Parameters.Count == 1 ? "" : "s") +
                    $" and {required.Declaration.Parameters.Count} parameter" +
                    (required.Declaration.Parameters.Count == 1 ? "" : "s"),
                    classType, interfaceType);
                continue;
            }

            if (!found.IsPublic)
                diagnostics.Report(Codes.ImplementationNotPublic, found.Declaration.Span,
                    $"'{classType.Name}.{found.Name}' implements " +
                    $"'{interfaceType.Name}.{required.Name}' and must therefore be public",
                    classType, interfaceType);
        }
    }
}
