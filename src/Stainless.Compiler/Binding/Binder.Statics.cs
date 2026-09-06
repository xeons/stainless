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
/// Module-level storage, and the order its initializers must run in.
/// </summary>
public sealed partial class Binder
{
    // ============================================================ statics

    private void DeclareStatic(
        FileScope scope, StaticDeclSyntax declaration, NamedTypeSymbol? containingType = null)
    {
        var module = scope.Module;

        if (containingType is null &&
            (module.Statics.ContainsKey(declaration.Name) ||
             module.Constants.ContainsKey(declaration.Name)))
        {
            diagnostics.Error("SL0201", declaration.Span,
                $"'{declaration.Name}' is already declared in module '{module.Name}'");
            return;
        }

        if (containingType is not null &&
            (containingType.FindStatic(declaration.Name) is not null ||
             containingType.FindStorage(declaration.Name) is not null ||
             containingType.FindProperty(declaration.Name) is not null))
        {
            diagnostics.Error("SL0205", declaration.Span,
                $"'{containingType.Name}' already declares a member named '{declaration.Name}'");
            return;
        }

        var type = ResolveType(declaration.Type, scope);

        var symbol = new StaticSymbol(declaration.Name, type, module.Name)
        {
            IsPublic = declaration.Modifiers.HasFlag(Modifiers.Public),
            IsReadonly = declaration.IsReadonly,
            ContainingType = containingType,
            Span = declaration.Span,
        };

        if (containingType is not null) containingType.Statics.Add(symbol);
        else module.Statics[declaration.Name] = symbol;

        // The substitution is copied rather than referenced: the binder reuses
        // one dictionary as it walks in and out of instantiations, and this has
        // to be what T meant here.
        _staticSyntax[symbol] = (declaration, scope,
            new Dictionary<string, TypeSymbol>(_substitution, StringComparer.Ordinal));
    }

    /// <summary>
    /// Binds the initializer of every static not yet bound.
    ///
    /// Called from pass 10 and again from pass 11, because the set of statics
    /// is not closed until monomorphization is: instantiating
    /// <c>Holder&lt;int&gt;</c> declares its statics, and that instantiation
    /// can be asked for by a body bound after this pass would have run. So the
    /// table is drained by difference rather than walked once, and
    /// <see cref="OrderStatics"/> is what happens when it is finally empty.
    /// </summary>
    private void BindStatics()
    {
        var previousSubstitution = _substitution;

        // Binding one initializer can instantiate a generic and so declare more
        // statics, which is why this is a loop over what is left rather than a
        // walk of what was there.
        while (true)
        {
            var waiting = _staticSyntax
                .Where(entry => !_boundStatics.Contains(entry.Key))
                .ToList();
            if (waiting.Count == 0) break;

            foreach (var (symbol, (declaration, scope, substitution)) in waiting)
            {
                _boundStatics.Add(symbol);

                _currentScope = scope;
                _currentFunction = null;
                _substitution = substitution;

                var value = BindConversion(
                    BindExpression(declaration.Value), symbol.Type, declaration.Value.Span);
                symbol.Initializer = value;

                // A static outlives every thread, so whatever it holds is
                // reachable from all of them at once. Said, not refused: a
                // program with one thread has no race to have, and the compiler
                // cannot see which kind it is looking at.
                if (!IsSendable(symbol.Type))
                    ReportNotSendable(symbol.Type, declaration.Span, $"static '{symbol.Name}'");
            }
        }

        _currentScope = null;
        _substitution = previousSubstitution;
    }

    /// <summary>
    /// Decides what order the initializers run in, once every static is known.
    ///
    /// C++ cannot do this and calls the result a fiasco; Swift avoids it by
    /// making every static lazy and paying a guard check on every access, which
    /// has to become atomic the moment threads exist. Stainless compiles the
    /// whole program at once, so it can simply look at the dependency graph and
    /// sort it -- no guard, no per-access cost, and a compile error rather than
    /// a runtime mystery when the graph has a cycle.
    /// </summary>
    private void OrderStatics()
    {
        foreach (var (symbol, _) in _staticSyntax)
            CollectStaticDependencies(symbol, symbol.Initializer);

        _staticOrder = SortStatics();
    }

    /// <summary>
    /// <c>static Name() { }</c>: a block that runs once, before <c>Main</c>.
    ///
    /// C# runs one lazily before the type is first used, behind a guard checked
    /// on every static access -- a guard that has to become atomic the moment
    /// threads exist. This runs in the same pass the field initializers do, so
    /// there is no guard and no per-access cost, and the price is that "before
    /// first use" becomes "before Main". A program that can tell those apart is
    /// timing its own startup.
    ///
    /// It runs after every static field's initializer, which is C#'s order too,
    /// and among themselves they run in declaration order.
    /// </summary>
    private void DeclareStaticConstructor(
        FileScope scope, NamedTypeSymbol type, StaticConstructorDeclSyntax declaration)
    {
        if (type.StaticConstructor is not null)
        {
            diagnostics.Error("SL0209", declaration.Span,
                $"'{type.Name}' already declares a 'static {type.SimpleName}()'; there is one " +
                "moment before 'Main' at which a type is set up, so there is one block for it");
            return;
        }

        var symbol = new FunctionSymbol
        {
            Name = "cctor",
            ModuleName = scope.Module.Name,
            ReturnType = PrimitiveTypeSymbol.Void,
            Linkage = LinkageKind.Stainless,
            Kind = FunctionKind.StaticConstructor,
            ContainingType = type,
            IsStatic = true,
            Body = declaration.Body,
            Span = declaration.Span,
            Scope = scope,
        };

        type.StaticConstructor = symbol;
        _staticConstructors.Add(symbol);
        scope.Module.Functions.Add(symbol);
    }

    private static void CollectStaticDependencies(StaticSymbol owner, BoundExpression? expression)
    {
        var walker = new StaticReferenceWalker();
        walker.Visit(expression);

        foreach (var referenced in walker.Found)
            if (referenced != owner && !owner.DependsOn.Contains(referenced))
                owner.DependsOn.Add(referenced);
    }

    /// <summary>
    /// Orders the statics so that nothing runs before what it reads. A cycle is
    /// reported here rather than left to produce a zero at run time.
    /// </summary>
    private List<StaticSymbol> SortStatics()
    {
        var ordered = new List<StaticSymbol>();
        var done = new HashSet<StaticSymbol>();
        var onStack = new HashSet<StaticSymbol>();

        void Visit(StaticSymbol symbol)
        {
            if (done.Contains(symbol)) return;

            if (!onStack.Add(symbol))
            {
                diagnostics.Error("SL0378", symbol.Span,
                    $"the initializer of '{symbol.QualifiedName}' depends on itself, " +
                    "directly or through another static; there is no order that would " +
                    "give it a value before it is read");
                return;
            }

            foreach (var dependency in symbol.DependsOn) Visit(dependency);

            onStack.Remove(symbol);
            if (done.Add(symbol)) ordered.Add(symbol);
        }

        foreach (var symbol in _staticSyntax.Keys) Visit(symbol);
        return ordered;
    }
}
