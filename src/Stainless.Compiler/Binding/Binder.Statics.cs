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
            diagnostics.Report(Codes.DuplicateModuleMember, declaration.Span,
                $"'{declaration.Name}' is already declared in module '{module.Name}'");
            return;
        }

        // A C++ variable's name is mangled by rules of its own -- neither
        // Itanium nor Microsoft spells a global the way it spells a function --
        // and none of that is written. Refusing is honest; guessing would
        // produce a link error nobody could read.
        if (declaration.Linkage.IsCpp())
        {
            diagnostics.Report(Codes.CppVariableNotSupported, declaration.Span,
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
            diagnostics.Report(Codes.ExternVariableInitialized, declaration.Span,
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
                new Dictionary<string, TypeSymbol>(_context.Substitution, StringComparer.Ordinal));
    }

    private void DeclareStatic(
        FileScope scope, StaticDeclSyntax declaration, NamedTypeSymbol? containingType = null)
    {
        var module = scope.Module;

        if (containingType is null &&
            (module.Statics.ContainsKey(declaration.Name) ||
             module.Constants.ContainsKey(declaration.Name)))
        {
            diagnostics.Report(Codes.DuplicateModuleMember, declaration.Span,
                $"'{declaration.Name}' is already declared in module '{module.Name}'");
            return;
        }

        if (containingType is not null &&
            (containingType.FindStatic(declaration.Name) is not null ||
             containingType.Constants.Any(c => c.Name == declaration.Name) ||
             containingType.FindStorage(declaration.Name) is not null ||
             containingType.FindProperty(declaration.Name) is not null))
        {
            diagnostics.Report(Codes.DuplicateMember, declaration.Span,
                $"'{containingType.Name}' already declares a member named '{declaration.Name}'",
                containingType);
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
            new Dictionary<string, TypeSymbol>(_context.Substitution, StringComparer.Ordinal));
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

                using (Enter(_context.ForBody(StaticInitializerContext(symbol)) with
                       {
                           File = scope,
                           Substitution = substitution,
                       }))
                    BindStatic(symbol, declaration, scope);

                // A static outlives every thread, so whatever it holds is
                // reachable from all of them at once. Said, not refused: a
                // program with one thread has no race to have, and the compiler
                // cannot see which kind it is looking at.
                if (!IsSendable(symbol.Type))
                    ReportNotSendable(symbol.Type, declaration.Span,
                        symbol.IsPropertyStorage
                            ? $"static property '{symbol.DisplayName}'"
                            : $"static '{symbol.Name}'");
            }
        }
    }

    /// <summary>
    /// What a static on a type is initialized inside: a static function of that
    /// type, so its initializer names the type's other statics, constants and
    /// static methods without the type in front, as its methods do. Null at
    /// module level, where there is nothing enclosing.
    /// </summary>
    private FunctionSymbol? StaticInitializerContext(StaticSymbol symbol) =>
        symbol.ContainingType is not { } type
            ? null
            : new FunctionSymbol
            {
                Name = symbol.DisplayName,
                ModuleName = symbol.ModuleName,
                ReturnType = symbol.Type,
                Linkage = LinkageKind.Stainless,
                ContainingType = type,
                IsStatic = true,
                Span = symbol.Span,
                Scope = _context.File,
            };

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
                    diagnostics.Report(Codes.AttributeRepeated, written.Span,
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
                diagnostics.Report(Codes.EmbedStaticHasInitializer, declaration.Value.Span,
                    $"'{symbol.Name}' has an '[Embed]', so the linker makes what it holds and " +
                    "there is nothing for an initializer to run; drop the '=', or drop the " +
                    "attribute and read the file with 'Standard.File'");
            else if (!isBytes)
                diagnostics.Report(Codes.EmbedStaticNotByteArray, declaration.Span,
                    $"'{symbol.Name}' is '{symbol.Type.Name}', and an embedded file is its bytes: " +
                    "declare it 'byte[]'",
                    symbol.Type);
            else
                symbol.Initializer = BindEmbed(embed);

            return;
        }

        // Its `default` is the parser's rather than the program's, so it is
        // said once, as the missing value it is.
        if (StaticPropertyStartsWithoutValue(symbol, declaration))
        {
            symbol.Initializer = new BoundDefault(declaration.Span, symbol.Type);
            return;
        }

        if (declaration.Value is null)
        {
            diagnostics.Report(Codes.StaticWithoutInitializer, declaration.Span,
                $"'{symbol.Name}' is a static, so it needs a value: the initializers run in " +
                "dependency order before 'Main', and there is no later moment at which one " +
                "could be given a first value");
            return;
        }

        // A scope for what the initializer declares as it goes, which an
        // `out var` does.
        PushScope();
        symbol.Initializer = BindConversion(
            BindExpression(declaration.Value), symbol.Type, declaration.Value.Span);
        PopScope();
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
        var bodies = new Dictionary<FunctionSymbol, BoundBlock>();
        foreach (var function in _functions)
            bodies.TryAdd(function.Symbol, function.Body);
        var methods = _functions
            .Where(f => f.Symbol.ContainingType is not null)
            .ToLookup(f => f.Symbol.ContainingType!, f => f.Symbol);

        foreach (var (symbol, _) in _staticSyntax)
            CollectStaticDependencies(symbol, symbol.Initializer, bodies, methods);

        _initialization = SortInitialization(bodies, methods);
        _staticOrder = _initialization
            .Select(step => step.Static)
            .OfType<StaticSymbol>()
            .ToList();

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
    /// It runs after its own type's field initializers, which is C#'s order
    /// too, and before anything that reads one of that type's statics: an
    /// initializer elsewhere, or another type's block. A type is set up as a
    /// unit, and the units are sorted as the initializers are.
    /// </summary>
    private void DeclareStaticConstructor(
        FileScope scope, NamedTypeSymbol type, StaticConstructorDeclSyntax declaration)
    {
        if (type.StaticConstructor is not null)
        {
            diagnostics.Report(Codes.DuplicateDestructorOrStaticConstructor, declaration.Span,
                $"'{type.Name}' already declares a 'static {type.SimpleName}()'; there is one " +
                "moment before 'Main' at which a type is set up, so there is one block for it",
                type);
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

    private static void CollectStaticDependencies(
        StaticSymbol owner, BoundExpression? expression,
        IReadOnlyDictionary<FunctionSymbol, BoundBlock> bodies,
        ILookup<NamedTypeSymbol, FunctionSymbol> methods)
    {
        var walker = new StaticReferenceWalker(bodies, methods);
        walker.Visit(expression);

        foreach (var referenced in walker.Found)
            if (!owner.DependsOn.Contains(referenced))
                owner.DependsOn.Add(referenced);

        foreach (var referenced in walker.FoundLater)
            if (referenced != owner && !owner.DependsOn.Contains(referenced))
                owner.DependsOn.Add(referenced);
    }

    /// <summary>
    /// Orders the initializers and static constructors so that nothing runs
    /// before what it reads. A cycle is reported here rather than left to
    /// produce a zero at run time.
    /// </summary>
    private List<StaticInitialization> SortInitialization(
        IReadOnlyDictionary<FunctionSymbol, BoundBlock> bodies,
        ILookup<NamedTypeSymbol, FunctionSymbol> methods)
    {
        var ordered = new List<StaticInitialization>();
        var done = new HashSet<object>();
        var onStack = new HashSet<object>();

        var constructorReads = _functions
            .Where(f => f.Symbol.Kind == FunctionKind.StaticConstructor)
            .ToDictionary(f => f.Symbol, f =>
            {
                var walker = new StaticReferenceWalker(bodies, methods);
                walker.Visit(f.Body);
                return walker.Found;
            });

        // A static in a type with a static constructor is read after that
        // constructor, unless it is read from the same type -- whose own
        // initializers run first.
        IEnumerable<object> Reading(StaticSymbol read, NamedTypeSymbol? from)
        {
            yield return read;
            if (read.ContainingType is { StaticConstructor: { } setup } owner && owner != from)
                yield return setup;
        }

        IEnumerable<object> DependenciesOf(object node)
        {
            if (node is StaticSymbol symbol)
            {
                foreach (var dependency in symbol.DependsOn)
                foreach (var needed in Reading(dependency, symbol.ContainingType))
                    yield return needed;
                yield break;
            }

            var constructor = (FunctionSymbol)node;
            var type = constructor.ContainingType!;

            foreach (var own in type.Statics) yield return own;

            foreach (var read in constructorReads.GetValueOrDefault(constructor) ?? [])
                if (read.ContainingType != type)
                    foreach (var needed in Reading(read, type))
                        yield return needed;
        }

        void Visit(object node)
        {
            if (done.Contains(node)) return;

            if (!onStack.Add(node))
            {
                if (node is StaticSymbol symbol)
                    diagnostics.Report(Codes.StaticInitializationCycle, symbol.Span,
                        $"the initializer of '{symbol.QualifiedName.TrimEnd('$')}' depends on " +
                        "itself, directly or through another static; there is no order that would " +
                        "give it a value before it is read");
                else if (node is FunctionSymbol constructor)
                    diagnostics.Report(Codes.StaticInitializationCycle, constructor.Span,
                        $"the static constructor of '{constructor.ContainingType!.Name}' reads a " +
                        "static that, directly or through another, needs this type set up first; " +
                        "there is no order that would run both",
                        constructor.ContainingType);
                return;
            }

            foreach (var dependency in DependenciesOf(node)) Visit(dependency);

            onStack.Remove(node);
            if (!done.Add(node)) return;

            ordered.Add(node is StaticSymbol initialized
                ? new StaticInitialization(initialized, null)
                : new StaticInitialization(null, (FunctionSymbol)node));
        }

        foreach (var symbol in _staticSyntax.Keys) Visit(symbol);
        foreach (var constructor in _staticConstructors) Visit(constructor);
        return ordered;
    }
}
