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
/// Module-level storage, and the order its initializers must run in.
/// </summary>
public sealed partial class Binder
{
    // ============================================================ statics

    /// <summary>
    /// <c>extern "C" int errno;</c> and <c>export "C" int slDepth = 0;</c>:
    /// a variable that is the same storage on both sides of the C boundary.
    ///
    /// This is the data half of what <c>extern "C"</c> already did for
    /// functions, and it is needed for the same reason. A C library's surface
    /// is not only its entry points: <c>errno</c>, <c>environ</c>, <c>optarg</c>
    /// and <c>stdin</c> are variables, and a language that speaks the platform
    /// C ABI but cannot name one of them has to write a C shim whose whole
    /// content is a getter.
    ///
    /// It becomes a <see cref="StaticSymbol"/> because that is what it is --
    /// one global, read and written through the same path as any other, with
    /// storage the linker resolves instead of storage this program defines.
    /// </summary>
    private void DeclareForeignVariable(FileScope scope, FieldDeclSyntax declaration)
    {
        var module = scope.Module;

        if (module.Statics.ContainsKey(declaration.Name) ||
            module.Constants.ContainsKey(declaration.Name))
        {
            diagnostics.Error("SL0201", declaration.Span,
                $"'{declaration.Name}' is already declared in module '{module.Name}'");
            return;
        }

        // A C++ variable's name is mangled by rules of its own -- neither
        // Itanium nor Microsoft spells a global the way it spells a function --
        // and none of that is written. Refusing is honest; guessing would
        // produce a link error nobody could read.
        if (declaration.Linkage.IsCpp())
        {
            diagnostics.Error("SL0701", declaration.Span,
                $"'{declaration.Name}' is a variable, and a C++ variable's name is mangled by " +
                "rules this compiler does not implement; declare it 'extern \"C\"', or reach it " +
                "through a C++ function that returns its address");
            return;
        }

        bool imported = declaration.Linkage.IsImport();

        // An imported variable is a declaration, so a value here would be
        // describing storage this program does not own. An exported one is a
        // definition and wants one, for the same reason any other static does.
        if (imported && declaration.Initializer is not null)
        {
            diagnostics.Error("SL0702", declaration.Span,
                $"'{declaration.Name}' is declared 'extern \"C\"', so it is defined elsewhere " +
                "and cannot be given a value here");
            return;
        }

        var type = ResolveType(declaration.Type, scope);

        var symbol = new StaticSymbol(declaration.Name, type, module.Name)
        {
            IsPublic = declaration.Modifiers.HasFlag(Modifiers.Public),
            LinkName = declaration.Name,
            IsImported = imported,
            Span = declaration.Span,
        };

        module.Statics[declaration.Name] = symbol;
        _foreignVariables.Add(symbol);

        // An exported one is defined here, so its value is bound and ordered
        // with every other static's. An imported one has nothing to bind.
        if (!imported && declaration.Initializer is not null)
            _staticSyntax[symbol] = (
                new StaticDeclSyntax(
                    declaration.Span, declaration.Modifiers, declaration.Type,
                    declaration.Name, declaration.Initializer, false, []),
                scope,
                new Dictionary<string, TypeSymbol>(_substitution, StringComparer.Ordinal));
    }

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
             containingType.Constants.Any(c => c.Name == declaration.Name) ||
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

                BindStatic(symbol, declaration, scope);

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
    /// One static's value: what its initializer says, or what <c>[Embed]</c>
    /// says instead.
    ///
    /// <para>
    /// The two are alternatives rather than a pair, which is the whole of why
    /// <c>[Embed]</c> is written where it is. An embedded object is made by the
    /// linker and not by code, so there is nothing for an initializer to
    /// evaluate; writing one beside the attribute would be writing two answers
    /// to the same question, and only one of them could be kept.
    /// </para>
    ///
    /// <para>
    /// The attributes are bound here rather than in pass 6, because the set of
    /// statics is not closed until monomorphization is — the same reason this
    /// pass drains a table instead of walking one.
    /// </para>
    /// </summary>
    private void BindStatic(StaticSymbol symbol, StaticDeclSyntax declaration, FileScope scope)
    {
        AttributeSyntax? embed = null;

        BindAttributes(
            declaration.Attributes, symbol.Attributes, scope, symbol.QualifiedName,
            written =>
            {
                // A second one would be a second file for one static, and there
                // is one static.
                if (embed is not null)
                    diagnostics.Error("SL0729", written.Span,
                        $"'{symbol.Name}' already has an '[Embed]'; a static holds one object, " +
                        "so it carries one file");
                else
                    embed = written;
            });

        if (embed is not null)
        {
            bool isBytes = symbol.Type is
                ArrayTypeSymbol { Element: PrimitiveTypeSymbol { Kind: PrimitiveKind.Byte } };

            if (declaration.Value is not null)
                diagnostics.Error("SL0731", declaration.Value.Span,
                    $"'{symbol.Name}' has an '[Embed]', so the linker makes what it holds and " +
                    "there is nothing for an initializer to run; drop the '=', or drop the " +
                    "attribute and read the file with 'Standard.File'");
            else if (!isBytes)
                diagnostics.Error("SL0730", declaration.Span,
                    $"'{symbol.Name}' is '{symbol.Type.Name}', and an embedded file is its bytes: " +
                    "declare it 'byte[]'");
            else
                symbol.Initializer = BindEmbed(embed);

            return;
        }

        if (declaration.Value is null)
        {
            diagnostics.Error("SL0376", declaration.Span,
                $"'{symbol.Name}' is a static, so it needs a value: the initializers run in " +
                "dependency order before 'Main', and there is no later moment at which one " +
                "could be given a first value");
            return;
        }

        symbol.Initializer = BindConversion(
            BindExpression(declaration.Value), symbol.Type, declaration.Value.Span);
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

        // Storage that crosses to C is emitted whether or not it had an
        // initializer to sort: an imported one has none by definition, and the
        // emitter still has to declare the global. Nothing without an
        // initializer can depend on anything, so the front is as good a place
        // as any.
        var sorted = new HashSet<StaticSymbol>(_staticOrder);
        _staticOrder.InsertRange(
            0, _foreignVariables.Where(variable => !sorted.Contains(variable)));
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
