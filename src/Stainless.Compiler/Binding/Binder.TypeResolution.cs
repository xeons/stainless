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
/// Syntax to type symbol, and the caches that keep one symbol per type.
///
/// One <c>T[]</c> symbol per element type means one TypeInfo and one
/// destroy hook, however many places mention the array.
/// </summary>
public sealed partial class Binder
{
    // ------------------------------------------------------------ type resolution

    /// <summary>
    /// Returns the single symbol for <c>T[]</c>, creating it on first use. One
    /// symbol per element type means one TypeInfo and one destroy hook, however
    /// many places mention the array.
    /// </summary>
    private ArrayTypeSymbol ArrayOf(TypeSymbol element)
    {
        var array = element.MakeArrayType();
        if (!_arrays.ContainsKey(element)) Remember(_arrays, element, array);
        return array;
    }

    /// <summary>
    /// <c>(int, String)</c>, made the first time it is asked for.
    ///
    /// Interned by its element types, the way a slice is by its element: a
    /// tuple is structural, so one written in two modules is one type. What
    /// comes back is an ordinary struct whose fields are <c>Item1</c> upwards,
    /// which is what makes layout, both ABI classifiers and the reference walk
    /// apply to it with nothing written for tuples.
    /// </summary>
    private TupleTypeSymbol TupleOf(IReadOnlyList<TypeSymbol> elements)
    {
        var key = new TypeList(elements.ToList());
        if (_tuples.TryGetValue(key, out var existing)) return existing;

        var tuple = new TupleTypeSymbol
        {
            Elements = elements.ToList(),
            SimpleName = MadeTypeName(Builtins.StandardModuleName,
                "(" + string.Join(", ", elements.Select(e => e.Name)) + ")",
                () => "(" + string.Join(", ", elements.Select(TypeIdentity)) + ")"),
            ModuleName = Builtins.StandardModuleName,
        };

        for (int i = 0; i < elements.Count; i++)
            tuple.Fields.Add(new FieldSymbol(
                TupleTypeSymbol.FieldName(i), elements[i], tuple, i) { IsPublic = true });

        Remember(_tuples, key, tuple);
        _structs.Add(tuple);
        LayOutIfLate(tuple);
        return tuple;
    }

    /// <summary>
    /// <c>Span&lt;T&gt;</c> or <c>ReadOnlySpan&lt;T&gt;</c>, built once per
    /// element type.
    ///
    /// The members are the standard library's: <c>Standard.Span&lt;T&gt;</c> is
    /// an ordinary generic struct, and this is its instantiation, made as a
    /// slice so that indexing, cutting and the conversions still know it. A
    /// referenced library names slices before any template can be read, so one
    /// made that early is filled when pass 4 begins.
    /// </summary>
    private SliceTypeSymbol SliceOf(TypeSymbol element, bool readOnly)
    {
        if (_slices.TryGetValue((element, readOnly), out var existing)) return existing;

        string spelling = readOnly ? "ReadOnlySpan" : "Span";
        var slice = new SliceTypeSymbol
        {
            Element = element,
            IsReadOnly = readOnly,
            SimpleName = MadeTypeName(Builtins.StandardModuleName,
                $"{spelling}<{element.Name}>", () => $"{spelling}<{TypeIdentity(element)}>"),
            ModuleName = Builtins.StandardModuleName,
            IsPublic = true,
            TypeArguments = [element],
        };

        Remember(_slices, (element, readOnly), slice);

        if (_slicesAwaitingTemplate is null)
            CompleteSlice(slice);
        else
            _slicesAwaitingTemplate.Add(slice);

        return slice;
    }

    /// <summary>Slices made before their templates could be read. Null once they can.</summary>
    private List<SliceTypeSymbol>? _slicesAwaitingTemplate = [];

    /// <summary>Fills every slice made so far, and every later one as it is made.</summary>
    private void CompleteSlicesAwaitingTemplate()
    {
        var waiting = _slicesAwaitingTemplate!;
        _slicesAwaitingTemplate = null;
        foreach (var slice in waiting)
            CompleteSlice(slice);
    }

    /// <summary>
    /// Gives a slice its members from the standard library's declaration, or
    /// only its three fields when there is no standard library to ask.
    /// </summary>
    private void CompleteSlice(SliceTypeSymbol slice)
    {
        if (SliceTemplate(slice.IsReadOnly) is { } template)
        {
            Instantiate(template, [slice.Element], template.Declaration.Span, filling: slice);
            return;
        }

        slice.Fields.Add(new FieldSymbol(
            "_array", ArrayOf(slice.Element).MakeOptionalType(), slice, SliceTypeSymbol.ArrayField));
        slice.Fields.Add(new FieldSymbol(
            "_offset", PrimitiveTypeSymbol.NUInt, slice, SliceTypeSymbol.OffsetField));
        slice.Fields.Add(new FieldSymbol(
            "_length", PrimitiveTypeSymbol.NUInt, slice, SliceTypeSymbol.LengthField));

        _structs.Add(slice);
        LayOutIfLate(slice);
    }

    /// <summary>The standard library's <c>Span&lt;T&gt;</c> or <c>ReadOnlySpan&lt;T&gt;</c>.</summary>
    private GenericTypeTemplate? SliceTemplate(bool readOnly) =>
        _modules.GetValueOrDefault(Builtins.StandardModuleName)?
            .FindGenericType(readOnly ? "ReadOnlySpan" : "Span", 1);

    private bool IsSliceTemplate(GenericTypeTemplate template) =>
        ReferenceEquals(template, SliceTemplate(readOnly: false)) ||
        ReferenceEquals(template, SliceTemplate(readOnly: true));

    /// <summary>
    /// Resolves a written type, and insists it is one a value can be made of.
    ///
    /// An opaque type is the single exception, and only directly under a
    /// pointer: <c>HWND__*</c> is a pointer to something whose layout is
    /// declared elsewhere, which is the whole of what such a type is for. Doing
    /// the check here rather than at each use is what makes it complete --
    /// a field, a local, a parameter, a return type, an array element, a
    /// <c>sizeof</c> and a generic argument all arrive through this one door.
    /// </summary>
    private TypeSymbol ResolveType(TypeSyntax syntax, FileScope scope, bool allowVoid = false)
    {
        var resolved = ResolveTypeCore(syntax, scope);

        // `void` is the absence of a value, so the only place it can be
        // written is where no value is produced: a return type. Anywhere else
        // -- a local, a field, a parameter, a type argument -- it named
        // storage for nothing, and reached the emitter as `alloca void` or a
        // struct with a `void` member, which is IR that does not exist. A
        // pointer never reaches this: `void*` is resolved as a pointer, which
        // has a size whatever it points at, and means what C's does.
        if (resolved.IsVoid() && !allowVoid)
        {
            diagnostics.Report(Codes.VoidUsedAsValueType, syntax.Span,
                "'void' is the absence of a value, so it can only be what a function returns; " +
                "there is no variable, field, parameter or type argument of it");
            return ErrorTypeSymbol.Instance;
        }

        if (resolved is StructTypeSymbol { IsOpaque: true } opaque)
        {
            diagnostics.Report(Codes.IncompleteTypeUsedByValue, syntax.Span,
                $"'{opaque.Name}' is declared without a body, so its size is not known here " +
                $"and there is no value of it to have; write '{opaque.Name}*', which is what an " +
                "incomplete type is for",
                opaque);
            return ErrorTypeSymbol.Instance;
        }

        return resolved;
    }

    /// <summary>
    /// The resolution itself, without the completeness check. Only the pointer
    /// case calls it directly, which is exactly the exception it is making.
    /// </summary>
    private TypeSymbol ResolveTypeCore(TypeSyntax syntax, FileScope scope)
    {
        if (syntax is TupleTypeSyntax written)
        {
            var elements = written.Elements.Select(e => ResolveType(e, scope)).ToList();
            if (elements.Any(e => e.IsError())) return ErrorTypeSymbol.Instance;
            if (elements.Count < 2) return ErrorTypeSymbol.Instance;
            return TupleOf(elements);
        }

        switch (syntax)
        {
            case SliceTypeSyntax sliceSyntax:
            {
                // allowVoid, so that the specific message below is the one
                // reported rather than the general rule in ResolveType.
                var element = ResolveType(sliceSyntax.Element, scope, allowVoid: true);
                if (element.IsError()) return element;

                if (element.IsVoid())
                {
                    diagnostics.Report(Codes.SpanOfVoid, sliceSyntax.Span,
                        $"there is no '{(sliceSyntax.IsReadOnly ? "ReadOnlySpan" : "Span")}<void>'");
                    return ErrorTypeSymbol.Instance;
                }

                return SliceOf(element, sliceSyntax.IsReadOnly);
            }

            case ArrayTypeSyntax array:
            {
                var element = ResolveType(array.Element, scope, allowVoid: true);
                if (element.IsError()) return element;
                if (element.IsVoid())
                {
                    diagnostics.Report(Codes.VoidArrayElement, syntax.Span,
                        "there is no array of 'void'");
                    return ErrorTypeSymbol.Instance;
                }
                return ArrayOf(element);
            }

            case FixedArrayTypeSyntax fixedArray:
                return ResolveFixedArray(fixedArray, scope);

            case PrimitiveTypeSyntax primitive:
            {
                // compiler-rt divides 128-bit integers for a 64-bit target
                // alone, and clang has no __int128 on a 32-bit one: a program
                // that divided would fail to link with nothing to say why. The
                // standard library may name the type everywhere, since what
                // nothing reaches is never emitted.
                if (primitive.Keyword is TokenKind.Int128Keyword or TokenKind.UInt128Keyword &&
                    TargetPlatform.Current.PointerWidth < 8 && !_reportedNarrowInt128 &&
                    !IsStandardLibrary(scope.Module))
                {
                    _reportedNarrowInt128 = true;
                    diagnostics.Report(Codes.Int128OnThirtyTwoBitTarget, primitive.Span,
                        $"'{primitive.Keyword.FixedText()}' needs a 64-bit target, and " +
                        $"'{TargetPlatform.Current.Name}' is 32-bit: clang has no __int128 there, and " +
                        "nothing divides one");
                }

                return PrimitiveFor(primitive.Keyword);
            }

            case PointerTypeSyntax pointer:
            {
                // The one place an incomplete type may appear. C says the same,
                // and for the same reason: a pointer has a size whatever it
                // points at.
                var element = ResolveTypeCore(pointer.Element, scope);
                if (element.IsError()) return element;
                if (element is NamedTypeSymbol { IsReferenceType: true })
                {
                    diagnostics.Report(Codes.PointerToReferenceType, syntax.Span,
                        $"'{element.Name}' is a reference type, so '{element.Name}*' is not " +
                        "allowed; it is already a managed pointer",
                        element);
                    return ErrorTypeSymbol.Instance;
                }
                return element.MakePointerType();
            }

            case NullableTypeSyntax nullable:
            {
                var element = ResolveType(nullable.Element, scope);
                if (element.IsError()) return element;

                // A closure's null is its function word, so `Notify?` is the
                // closure's own two words with a zero allowed in them.
                if (element is ClosureTypeSymbol closure)
                    return closure.MakeNullable();

                if (element is not (NamedTypeSymbol { IsReferenceType: true } or ArrayTypeSymbol))
                {
                    diagnostics.Report(Codes.OptionalOfValueType, syntax.Span,
                        $"'{element.Name}?' is not valid; only class, interface and array " +
                        $"references can be optional (a '{element.Name}' is a value and is never " +
                        "null)",
                        element);
                    return ErrorTypeSymbol.Instance;
                }
                return element.MakeOptionalType();
            }

            case WeakTypeSyntax weak:
            {
                var element = ResolveType(weak.Element, scope);
                if (element.IsError()) return element;

                var referenced = element.AsReference();
                if (referenced is null)
                {
                    diagnostics.Report(Codes.WeakOfNonReference, syntax.Span,
                        $"'weak' requires a class or interface reference, but '{element.Name}' is not one",
                        element);
                    return ErrorTypeSymbol.Instance;
                }

                return referenced.MakeWeakType();
            }

            case NamedTypeSyntax named:
            {
                var resolved = ResolveNamedType(named, scope);
                if (resolved is AttributeTypeSymbol)
                {
                    diagnostics.Report(Codes.AttributeUsedAsType, syntax.Span,
                        $"'{resolved.Name}' is an attribute and cannot be used as a type; " +
                        $"write it as '[{resolved.Name}]' on a declaration instead",
                        resolved);
                    return ErrorTypeSymbol.Instance;
                }
                return resolved;
            }

            default:
                return ErrorTypeSymbol.Instance;
        }
    }

    private TypeSymbol ResolveNamedType(NamedTypeSyntax syntax, FileScope scope)
    {
        var module = scope.Module;
        var parts = syntax.Name.Parts;

        // A bare name may be a type parameter of the instantiation being bound.
        if (parts.Count == 1 && syntax.TypeArguments.Count == 0 &&
            _context.Substitution.TryGetValue(parts[0], out var substituted))
            return substituted;

        if (syntax.TypeArguments.Count > 0)
            return ResolveConstructedType(syntax, scope);

        // A type declared inside another is named for where it was written, so
        // `Outer.Inner` is one name and not a module and a type. It is looked
        // for before the module path, because a module cannot be called
        // `Outer` while a type in this file is.
        if (parts.Count > 1 && module.Types.TryGetValue(syntax.Name.Text, out var nestedHere))
            return nestedHere;

        if (parts.Count > 1)
        {
            foreach (var imported in scope.ImportedModules)
                if (imported.Types.TryGetValue(syntax.Name.Text, out var nestedThere) &&
                    nestedThere.IsPublic)
                    return nestedThere;
        }

        if (parts.Count == 1)
        {
            if (module.Types.TryGetValue(parts[0], out var local)) return local;

            // Inside `Outer`, a bare `Inner` is `Outer.Inner`. That is what
            // makes nesting worth having: the short name works where it
            // belongs, and the long one everywhere else.
            if (Enclosing() is { } within &&
                module.Types.TryGetValue(within + "." + parts[0], out var sibling))
                return sibling;
            if (module.Aliases.TryGetValue(parts[0], out var ownAlias)) return ResolveAlias(ownAlias);

            // Naming a generic without arguments is a common slip; say so plainly.
            if (module.FindGenericType(parts[0], null) is { } template)
            {
                diagnostics.Report(Codes.GenericTypeMissingArguments, syntax.Span,
                    $"'{template.Name}' is generic and needs type arguments, " +
                    $"as in '{template.Name}<{string.Join(", ", template.Parameters)}>'");
                return ErrorTypeSymbol.Instance;
            }

            var visible = scope.ImportedModules
                .Where(imported => imported.Types.TryGetValue(parts[0], out var t) && t.IsPublic)
                .Select(imported => imported.Types[parts[0]])
                .Distinct()
                .ToList();

            // An imported alias is a name like any other, and is looked for only
            // when no imported type answered -- a type is the more direct thing.
            if (visible.Count == 0)
            {
                var aliases = scope.ImportedModules
                    .Where(i => i.Aliases.TryGetValue(parts[0], out var a) && a.IsPublic)
                    .Select(i => i.Aliases[parts[0]])
                    .Distinct()
                    .ToList();

                if (aliases.Count == 1) return ResolveAlias(aliases[0]);
                if (aliases.Count > 1)
                {
                    diagnostics.Report(Codes.AmbiguousTypeName, syntax.Span,
                        $"'{parts[0]}' is ambiguous between " +
                        string.Join(" and ", aliases.Select(a => $"'{a.QualifiedName}'")) +
                        "; qualify it with its module name");
                    return ErrorTypeSymbol.Instance;
                }
            }

            if (visible.Count == 1) return visible[0];
            if (visible.Count > 1)
            {
                diagnostics.Report(Codes.AmbiguousTypeName, syntax.Span,
                    $"'{parts[0]}' is ambiguous between " +
                    string.Join(" and ", visible.Select(t => $"'{t.QualifiedName}'")) +
                    "; qualify it with its module name");
                return ErrorTypeSymbol.Instance;
            }

            // Built in, and not reserved: a type of the program's own by the
            // same name was found above and is the one meant.
            if (VectorTypeSymbol.Named(parts[0]) is { } vector) return vector;
        }
        else
        {
            string moduleName = string.Join('.', parts.Take(parts.Count - 1));
            if (scope.Imports.TryGetValue(moduleName, out var target) ||
                _modules.TryGetValue(moduleName, out target))
            {
                if (target.Types.TryGetValue(parts[^1], out var type))
                {
                    if (target != module && !type.IsPublic)
                    {
                        diagnostics.Report(Codes.TypeNotAccessible, syntax.Span,
                            $"'{type.QualifiedName}' is not public");
                        return ErrorTypeSymbol.Instance;
                    }
                    return type;
                }

                if (target.Aliases.TryGetValue(parts[^1], out var qualifiedAlias))
                {
                    if (target != module && !qualifiedAlias.IsPublic)
                    {
                        diagnostics.Report(Codes.TypeNotAccessible, syntax.Span,
                            $"'{qualifiedAlias.QualifiedName}' is not public");
                        return ErrorTypeSymbol.Instance;
                    }
                    return ResolveAlias(qualifiedAlias);
                }

                diagnostics.Report(Codes.ModuleTypeNotFound, syntax.Span,
                    $"module '{target.Name}' does not declare a type named '{parts[^1]}'");
                return ErrorTypeSymbol.Instance;
            }
        }

        diagnostics.Report(Codes.TypeNotFound, syntax.Span,
            $"the type '{syntax.Name.Text}' was not found; " +
            "check the spelling, or add an 'import' for the module that declares it");
        return ErrorTypeSymbol.Instance;
    }

    /// <summary>Resolves <c>Box&lt;int&gt;</c> by finding the template and instantiating it.</summary>
    private TypeSymbol ResolveConstructedType(NamedTypeSyntax syntax, FileScope scope)
    {
        var module = scope.Module;
        var arguments = syntax.TypeArguments.Select(a => ResolveType(a, scope)).ToList();
        if (arguments.Any(a => a.IsError())) return ErrorTypeSymbol.Instance;

        // A generic delegate or closure is looked for first, because it is a
        // template of its own kind and would not be found among the types.
        if (FindGenericDelegate(syntax.Name, scope, arguments.Count) is { } signature)
            return InstantiateDelegate(signature, arguments, syntax.Span);

        var template = FindGenericType(syntax.Name, scope, arguments.Count);

        // The right name with the wrong number of arguments is reported as that,
        // by whichever declaration of the name there is.
        if (template is null && FindGenericDelegate(syntax.Name, scope, null) is { } misfit)
            return InstantiateDelegate(misfit, arguments, syntax.Span);
        template ??= FindGenericType(syntax.Name, scope, null);

        if (template is null)
        {
            diagnostics.Report(Codes.GenericTypeNotFound, syntax.Span,
                $"no generic type named '{syntax.Name.Text}' is in scope");
            return ErrorTypeSymbol.Instance;
        }

        // Refused here as well as in Instantiate, so that what the type was
        // wanted for is not reported again against a placeholder.
        if (RefuseRunawayInstantiation(template.Name, arguments, syntax.Span))
            return ErrorTypeSymbol.Instance;

        return Instantiate(template, arguments, syntax.Span);
    }

    /// <summary>The generic delegate or closure of that name in scope, or null.</summary>
    /// <param name="arity">How many type arguments were written, or null to take any.</param>
    private GenericDelegateTemplate? FindGenericDelegate(QualifiedName name, FileScope scope, int? arity)
    {
        var module = scope.Module;

        if (name.Parts.Count == 1)
        {
            if (module.FindGenericDelegate(name.Parts[0], arity) is { } local) return local;

            return scope.ImportedModules
                .Select(m => m.FindGenericDelegate(name.Parts[0], arity) is { IsPublic: true } t ? t : null)
                .FirstOrDefault(t => t is not null);
        }

        string owner = string.Join('.', name.Parts.Take(name.Parts.Count - 1));
        if (scope.Imports.TryGetValue(owner, out var target) ||
            _modules.TryGetValue(owner, out target))
        {
            if (target.FindGenericDelegate(name.Last, arity) is { } found &&
                (target == module || found.IsPublic))
                return found;
        }

        return null;
    }

    /// <summary>
    /// The type whose declaration is being bound, by name, or null.
    ///
    /// Only the name is wanted: what it is for is finding `Outer.Inner` from
    /// inside `Outer`, and that is a lookup in the module's own table.
    /// </summary>
    private string? Enclosing()
    {
        if (_declaringType is { } declaring) return declaring;

        // The *template's* name for an instantiation. `Cache<int>` was written
        // `Cache`, and the type nested in it was hoisted as `Cache.Entry`
        // before any instantiation existed.
        if (_context.Function?.ContainingType is { } containing)
            return containing.Template?.Name ?? containing.SimpleName;

        return null;
    }

    /// <param name="arity">How many type arguments were written, or null to take any.</param>
    private GenericTypeTemplate? FindGenericType(QualifiedName name, FileScope scope, int? arity)
    {
        var module = scope.Module;
        if (name.Parts.Count == 1)
        {
            if (module.FindGenericType(name.Parts[0], arity) is { } local) return local;

            return scope.ImportedModules
                .Select(m => m.FindGenericType(name.Parts[0], arity) is { IsPublic: true } t ? t : null)
                .FirstOrDefault(t => t is not null);
        }

        string moduleName = string.Join('.', name.Parts.Take(name.Parts.Count - 1));
        if (scope.Imports.TryGetValue(moduleName, out var target) ||
            _modules.TryGetValue(moduleName, out target))
        {
            if (target.FindGenericType(name.Last, arity) is { } found &&
                (target == module || found.IsPublic))
                return found;
        }

        return null;
    }

    /// <summary>Finds a generic function template visible from the current module.</summary>
    private List<GenericFunctionTemplate> FindGenericFunctions(QualifiedName name)
    {
        if (name.Parts.Count == 1)
        {
            var local = _currentModule!.GenericFunctions.Where(f => f.Name == name.Parts[0]).ToList();
            if (local.Count > 0) return local;

            return _context.File!.ImportedModules
                .SelectMany(m => m.GenericFunctions)
                .Where(f => f.Name == name.Parts[0] && f.IsPublic)
                .ToList();
        }

        string moduleName = string.Join('.', name.Parts.Take(name.Parts.Count - 1));
        if (_context.File!.Imports.TryGetValue(moduleName, out var target) ||
            _modules.TryGetValue(moduleName, out target))
        {
            bool sameModule = target == _currentModule;
            return target.GenericFunctions
                .Where(f => f.Name == name.Last && (sameModule || f.IsPublic))
                .ToList();
        }

        return [];
    }

    /// <summary>
    /// Binds a call to a generic function by inferring its type arguments from
    /// the arguments actually passed, then instantiating it.
    /// </summary>
    private BoundExpression? TryBindGenericCall(
        CallSyntax syntax, QualifiedName name, List<BoundExpression> arguments)
    {
        var candidates = FindGenericFunctions(name);
        if (candidates.Count == 0) return null;

        var function = InferAndInstantiate(candidates, syntax, arguments);
        return function is null
            ? new BoundErrorExpression(syntax.Span)
            : BuildCall(syntax, function, receiver: null, arguments);
    }

    /// <summary>
    /// Chooses a template, infers its type arguments from the values passed, and
    /// instantiates it. Shared by generic free functions and generic methods,
    /// which differ only in whether a receiver comes along.
    /// </summary>
    private FunctionSymbol? InferAndInstantiate(
        IReadOnlyList<GenericFunctionTemplate> candidates,
        CallSyntax syntax,
        List<BoundExpression> arguments)
    {
        var written = syntax.Callee switch
        {
            NameSyntax name => name.TypeArguments,
            MemberAccessSyntax member => member.TypeArguments,
            _ => null,
        };

        List<TypeSymbol>? given = null;
        if (written is not null)
        {
            given = written.Select(w => ResolveType(w, _context.File!)).ToList();
            if (given.Any(g => g.IsError()))
                return null;

            var arity = candidates.Where(c => c.Parameters.Count == given.Count).ToList();
            if (arity.Count == 0)
            {
                var counts = candidates.Select(c => c.Parameters.Count).Distinct().Order().ToList();
                diagnostics.Report(Codes.CallTypeArgumentCountMismatch, syntax.Callee.Span,
                    $"'{candidates[0].Name}' takes " +
                    string.Join(" or ", counts) +
                    $" type argument{(counts is [1] ? "" : "s")}, and {given.Count} " +
                    $"{(given.Count == 1 ? "was" : "were")} written");
                return null;
            }

            candidates = arity;
        }

        var viable = candidates
            .Where(c => c.Declaration.Parameters.Count == arguments.Count ||
                        IsGathering(c.Declaration.Parameters, arguments))
            .ToList();

        // None has the call's arity, so the closest reports it: the one that
        // takes the most of what was written, whatever order they came in.
        if (viable.Count == 0)
            viable = [candidates.MinBy(c => Math.Abs(c.Declaration.Parameters.Count - arguments.Count))!];

        // Every candidate of the right arity is tried, and one that infers but
        // then would not accept the arguments is not a candidate. Two templates
        // may take one argument and differ in its shape -- `Sort(Span<T>)` and
        // `Sort(IList<T>)` do -- and picking the first would make the second
        // unreachable.
        var fitting = new List<(GenericFunctionTemplate Template, List<TypeSymbol> Arguments,
                                Dictionary<string, TypeSymbol> Inferred)>();
        Dictionary<string, TypeSymbol>? firstFailure = null;
        GenericFunctionTemplate? failed = null;

        // The first candidate that got as far as a lambda's body.
        GenericFunctionTemplate? failedAtLambda = null;

        // A candidate whose parameters were all worked out and which still would
        // not take the arguments. It is the better thing to report: the reader
        // has an argument that does not fit, not a type nobody could name.
        GenericFunctionTemplate? nearMiss = null;

        // Each candidate is a trial, kept only if it fits: one that loses MUST
        // NOT leave behind what its lambdas instantiated. What is reported
        // about a loser is worked out again, outside any trial, because what
        // its trial made is gone.
        foreach (var candidate in viable)
        {
            using var trial = BeginTrial(quiet: false);

            var unanswered = new List<(LambdaSyntax, IReadOnlyList<TypeSymbol>)>();
            var inferred = InferTemplateArguments(candidate, given, arguments, unanswered);

            if (candidate.Parameters.Any(p => !inferred.ContainsKey(p)))
            {
                firstFailure ??= inferred;
                failed ??= candidate;
                if (unanswered.Count > 0) failedAtLambda ??= candidate;
                continue;
            }

            if (Accepts(candidate, inferred, arguments))
            {
                fitting.Add((candidate, candidate.Parameters.Select(p => inferred[p]).ToList(), inferred));
                trial.Accept();
            }
            else
            {
                nearMiss ??= candidate;
            }
        }

        if (fitting.Count == 1)
            return InstantiateFunction(fitting[0].Template, fitting[0].Arguments, syntax.Span);

        // Several fit, and they are ranked as any overloads are: one that every
        // argument converts to at least as well, and one better, is the call.
        // `Trim(Span<T>, T)` and `Trim(ReadOnlySpan<T>, T)` both take a span,
        // and the one that keeps it writable is the better fit.
        if (fitting.Count > 1)
        {
            var parameters = fitting
                .Select(f => ParameterTypesUnder(f.Template, f.Inferred, arguments))
                .ToList();

            for (int i = 0; i < fitting.Count; i++)
            {
                if (Enumerable.Range(0, fitting.Count)
                    .All(j => j == i || IsBetter(parameters[i], parameters[j], arguments)))
                    return InstantiateFunction(fitting[i].Template, fitting[i].Arguments, syntax.Span);
            }
        }

        if (fitting.Count > 1)
        {
            diagnostics.Report(Codes.AmbiguousGenericType, syntax.Span,
                $"'{candidates[0].Name}' is ambiguous here: " +
                string.Join(" and ", fitting.Select(f =>
                    $"'{f.Template.Name}<{string.Join(", ", f.Arguments.Select(a => a.Name))}>'")) +
                " both accept these arguments");
            return null;
        }

        // Everything was worked out and an argument still did not fit: say which.
        if (nearMiss is not null)
        {
            var inferred = InferTemplateArguments(nearMiss, given, arguments, []);
            Accepts(nearMiss, inferred, arguments, report: nearMiss.Name);
            return null;
        }

        // A lambda whose parameters were known and whose body still would not
        // bind is the reason nothing could be inferred, and its own errors say
        // why far better than SL0327 would.
        if (failedAtLambda is not null)
        {
            var failedLambdas = new List<(LambdaSyntax, IReadOnlyList<TypeSymbol>)>();
            InferTemplateArguments(failedAtLambda, given, arguments, failedLambdas);

            int before = diagnostics.ErrorCount;
            foreach (var (lambda, parameters) in failedLambdas)
                ProbeLambdaResult(lambda, parameters, report: true);
            if (diagnostics.ErrorCount > before)
                return null;
        }

        var template = failed ?? viable[0];
        var reported = firstFailure ?? new Dictionary<string, TypeSymbol>(StringComparer.Ordinal);
        var missing = template.Parameters.Where(p => !reported.ContainsKey(p)).ToList();

        diagnostics.Report(Codes.TypeArgumentNotInferred, syntax.Span,
            $"cannot infer {string.Join(" and ", missing.Select(m => "'" + m + "'"))} " +
            $"for '{template.Name}' from these arguments; " +
            "Stainless infers type arguments only from the values passed");
        return null;
    }

    /// <summary>
    /// What a template's type parameters are, as far as the arguments say:
    /// those written at the call, those read off each argument's type, and
    /// those read off what a lambda argument produces. A lambda whose body
    /// could not say is added to <paramref name="unanswered"/>.
    /// </summary>
    private Dictionary<string, TypeSymbol> InferTemplateArguments(
        GenericFunctionTemplate candidate,
        List<TypeSymbol>? given,
        List<BoundExpression> arguments,
        List<(LambdaSyntax, IReadOnlyList<TypeSymbol>)> unanswered)
    {
        var names = candidate.Parameters.ToHashSet(StringComparer.Ordinal);
        var inferred = new Dictionary<string, TypeSymbol>(StringComparer.Ordinal);

        // An enclosing type's parameters are already fixed, so they are
        // given rather than inferred; only the method's own are worked out.
        foreach (var (name, type) in candidate.OuterSubstitution) inferred.TryAdd(name, type);

        // Written at the call, so there is nothing to infer.
        if (given is not null)
            for (int i = 0; i < given.Count; i++)
                inferred[candidate.Parameters[i]] = given[i];

        // An array literal says nothing of its own type, but its elements agree
        // on one, and `ToList([1, 2])` is a list of int for that reason.
        // A `ref` or `out` argument is the variable's address, and the
        // parameter is written as the variable's type.
        for (int i = 0; i < arguments.Count; i++)
            if (WrittenParameterType(candidate.Declaration.Parameters, arguments, i) is { } wanted)
                Infer(wanted,
                    arguments[i] switch
                    {
                        BoundArrayDraft draft when AgreedElementType(draft) is { } element =>
                            ArrayOf(element),
                        BoundAddressOf { FromRefKeyword: true } or
                        BoundAddressOf { FromOutKeyword: true } =>
                            ((BoundAddressOf)arguments[i]).Operand.Type,
                        _ => arguments[i].Type,
                    },
                    names, inferred, candidate.Scope);

        // A lambda has no type of its own, so the loop above learned nothing
        // from one. Anything still unknown may yet be readable off a lambda's
        // result, once the arguments that are values have said what its
        // parameters are.
        if (candidate.Parameters.Any(p => !inferred.ContainsKey(p)))
            InferFromLambdaResults(candidate, arguments, names, inferred, unanswered);

        return inferred;
    }

    /// <summary>
    /// Whether a call gives a template's <c>params</c> parameter its elements
    /// one by one. An array, a slice or an array literal in its place is the
    /// array itself, as it is for a function that is not generic.
    /// </summary>
    private static bool IsGathering(
        IReadOnlyList<ParameterSyntax> declared, List<BoundExpression> arguments)
    {
        if (declared.Count == 0 || !declared[^1].IsParams) return false;
        if (arguments.Count < declared.Count - 1) return false;
        if (arguments.Count != declared.Count) return true;

        return arguments[^1] is not BoundArrayDraft &&
               arguments[^1].Type is not (ArrayTypeSymbol or SliceTypeSymbol);
    }

    /// <summary>
    /// The type written for the parameter argument <paramref name="index"/>
    /// lands on: the element type of a <c>params</c> array being gathered, and
    /// null past the end of a template that has none.
    /// </summary>
    private static TypeSyntax? WrittenParameterType(
        IReadOnlyList<ParameterSyntax> declared, List<BoundExpression> arguments, int index)
    {
        if (IsGathering(declared, arguments) && index >= declared.Count - 1)
            return declared[^1].Type switch
            {
                ArrayTypeSyntax array => array.Element,
                SliceTypeSyntax slice => slice.Element,
                _ => null,
            };

        return index < declared.Count ? declared[index].Type : null;
    }

    /// <summary>
    /// Works out the type parameters that appear only in a lambda's result.
    ///
    /// The order matters, and is why this is a second pass rather than part of
    /// the first. Given <c>Select&lt;T, R&gt;(Span&lt;T&gt; items, IFunc&lt;T, R&gt; f)</c> and
    /// <c>Select(numbers, n =&gt; n * 2)</c>: T comes from <c>numbers</c>, which
    /// makes the lambda's target <c>IFunc&lt;int, R&gt;</c>, which gives the lambda
    /// its parameter type, which lets its body be bound, which is what says
    /// what R is. No step in that chain can be taken earlier.
    ///
    /// It loops, because one lambda's result may settle another's parameter,
    /// and stops as soon as a pass learns nothing -- so a call that genuinely
    /// cannot be inferred reaches SL0327 rather than spinning.
    ///
    /// A function passed by name takes the same route, with its declaration
    /// read in place of a body: see <see cref="NamedFunctionResult"/>.
    /// </summary>
    private void InferFromLambdaResults(
        GenericFunctionTemplate candidate,
        List<BoundExpression> arguments,
        HashSet<string> names,
        Dictionary<string, TypeSymbol> inferred,
        List<(LambdaSyntax, IReadOnlyList<TypeSymbol>)> unanswered)
    {
        int shared = Math.Min(arguments.Count, candidate.Declaration.Parameters.Count);

        bool learned = true;
        while (learned && candidate.Parameters.Any(p => !inferred.ContainsKey(p)))
        {
            learned = false;

            for (int i = 0; i < shared; i++)
            {
                var lambda = arguments[i] as BoundLambda;
                var group = arguments[i] as BoundFunctionGroup;
                if (lambda is null && group is null) continue;

                // Read off the interface's *declaration* rather than a resolved
                // symbol. `IFunc<int, R>` will not resolve at all while R is
                // unknown -- a constructed type with one unresolved argument is
                // an error type entire -- and it is exactly that position this
                // is trying to fill.
                if (candidate.Declaration.Parameters[i].Type
                    is not NamedTypeSyntax { TypeArguments.Count: > 0 } written) continue;

                // Either a generic closure -- `closure R Transform<T, R>(T)` --
                // or a generic interface with one method, which is what the
                // library used before closures could be generic. They differ
                // only in where the signature is written down.
                if (Callable(written.Name, candidate.Scope, written.TypeArguments.Count) is not { } shape)
                    continue;
                if (shape.Names.Count != written.TypeArguments.Count) continue;
                if (lambda is not null && shape.Parameters.Count != lambda.Syntax.Parameters.Count)
                    continue;

                // The declaration writes its signature in terms of its own
                // parameter names; the use site says what each of those is.
                // `Transform<A, B>` declaring `B(A)`, used as `Transform<T, R>`,
                // makes the lambda take a T and produce an R.
                var atUseSite = new Dictionary<string, TypeSyntax>(StringComparer.Ordinal);
                for (int p = 0; p < shape.Names.Count; p++)
                    atUseSite[shape.Names[p]] = written.TypeArguments[p];

                var result = AsWritten(shape.ReturnType, atUseSite);

                // Only worth binding a body to learn something not already
                // known. The result may be the parameter itself -- `R Apply(T)`
                // -- or carry it inside something else, which is what
                // `Optional<R> Apply(T)` does for FlatMap.
                var parametersWritten = shape.Parameters
                    .Select(p => AsWritten(p.Type, atUseSite))
                    .ToList();
                bool parametersUnknown =
                    parametersWritten.Any(p => MentionsUnknown(p, names, inferred));

                // A function's parameters are declared, so a named one can say
                // what they are as well as what it returns; a lambda's cannot.
                if (!MentionsUnknown(result, names, inferred) &&
                    (lambda is not null || !parametersUnknown))
                    continue;

                int known = inferred.Count;
                TypeSymbol? produced;

                if (lambda is not null)
                {
                    // Every parameter has to be settled before the body can bind.
                    var parameterTypes = ResolveAll(parametersWritten, candidate.Scope, inferred);
                    if (parameterTypes is null) continue;

                    produced = ProbeLambdaResult(lambda.Syntax, parameterTypes);
                    if (produced is null && !unanswered.Any(u => u.Item1 == lambda.Syntax))
                        unanswered.Add((lambda.Syntax, parameterTypes));
                }
                else
                {
                    produced = NamedFunctionResult(
                        group!, parametersWritten, parametersUnknown,
                        candidate.Scope, names, inferred);
                }

                if (produced is null) continue;

                // Matched structurally rather than assigned, so `Optional<R>`
                // against an `Optional<nuint>` says R is nuint and a result
                // that turned out to be some other shape says nothing at all.
                Infer(result, produced, names, inferred, candidate.Scope);
                if (inferred.Count > known) learned = true;
            }
        }
    }

    /// <summary>
    /// What a function passed by name returns, for the signature it is being
    /// passed as -- which is what a lambda's body would have said, read off a
    /// declaration instead.
    ///
    /// Which overload is meant is settled by the parameter types already
    /// inferred: <c>Select(names, Upper)</c> knows T is String, and so wants the
    /// <c>Upper</c> that takes one. Where those are not known yet, a name with
    /// exactly one function of the right arity is that function, and its
    /// parameters are what settles them. Anything less certain says nothing,
    /// and the call reaches SL0327 as it would have.
    /// </summary>
    private TypeSymbol? NamedFunctionResult(
        BoundFunctionGroup group,
        IReadOnlyList<TypeSyntax> parametersWritten,
        bool parametersUnknown,
        FileScope scope,
        HashSet<string> names,
        Dictionary<string, TypeSymbol> inferred)
    {
        // Only what the conversion that follows could take: an instance method
        // named without its object is refused there, so it is no answer here.
        var fitting = group.Candidates
            .Where(f => group.Receiver is not null || f.IsStatic || f.ContainingType is null)
            .Where(f => f.Parameters.Count(p => !p.IsThis) == parametersWritten.Count)
            .ToList();

        if (!parametersUnknown)
        {
            if (ResolveAll(parametersWritten, scope, inferred) is not { } wanted) return null;

            fitting = fitting
                .Where(f => f.Parameters.Where(p => !p.IsThis)
                    .Select(p => p.Type).SequenceEqual(wanted))
                .ToList();

            return fitting.Count == 1 ? fitting[0].ReturnType : null;
        }

        if (fitting.Count != 1) return null;

        var only = fitting[0];
        var declared = only.Parameters.Where(p => !p.IsThis).ToList();
        for (int i = 0; i < declared.Count; i++)
            Infer(parametersWritten[i], declared[i].Type, names, inferred, scope);

        return only.ReturnType;
    }

    /// <summary>
    /// The signature behind a generic name that a lambda could become: a
    /// generic closure or delegate, or a generic interface with exactly one
    /// method. Null for anything else.
    ///
    /// Read off the *declaration* rather than a resolved symbol, because
    /// `Transform&lt;int, R&gt;` will not resolve at all while R is unknown --
    /// a constructed type with one unresolved argument is an error type entire
    /// -- and it is exactly that position this is trying to fill.
    /// </summary>
    private CallableShape? Callable(QualifiedName name, FileScope scope, int arity)
    {
        if (FindGenericDelegate(name, scope, arity) is { } signature)
            return new CallableShape(
                signature.Parameters,
                signature.Declaration.ReturnType,
                signature.Declaration.Parameters);

        if (FindGenericType(name, scope, arity) is not { } template) return null;
        if (template.Declaration.Kind != TypeDeclKind.Interface) return null;

        var methods = template.Declaration.Members.OfType<FunctionDeclSyntax>().ToList();
        if (methods.Count != 1) return null;

        return new CallableShape(
            template.Parameters, methods[0].ReturnType, methods[0].Parameters);
    }

    /// <summary>
    /// What a lambda would have to be, written in the declaring template's own
    /// type parameter names.
    /// </summary>
    private sealed record CallableShape(
        IReadOnlyList<string> Names,
        TypeSyntax ReturnType,
        IReadOnlyList<ParameterSyntax> Parameters);

    /// <summary>
    /// An interface's method signature restated in the caller's names: the
    /// <c>A</c> and <c>B</c> of <c>IFunc&lt;A, B&gt;</c> become whatever was
    /// written at <c>IFunc&lt;T, R&gt;</c>.
    ///
    /// All the way down, so a method that mentions its interface's parameter
    /// inside something else -- <c>List&lt;B&gt; Apply(A)</c> -- is restated
    /// rather than left half-translated.
    /// </summary>
    private static TypeSyntax AsWritten(TypeSyntax declared, Dictionary<string, TypeSyntax> atUseSite)
    {
        switch (declared)
        {
            case NamedTypeSyntax { Name.Parts.Count: 1, TypeArguments.Count: 0 } name
                when atUseSite.TryGetValue(name.Name.Parts[0], out var written):
                return written;

            case NamedTypeSyntax { TypeArguments.Count: > 0 } constructed:
            {
                var arguments = constructed.TypeArguments
                    .Select(a => AsWritten(a, atUseSite)).ToList();

                return arguments.SequenceEqual(constructed.TypeArguments)
                    ? constructed
                    : constructed with { TypeArguments = arguments };
            }

            case TupleTypeSyntax tuple:
                return tuple with
                {
                    Elements = tuple.Elements.Select(e => AsWritten(e, atUseSite)).ToList(),
                };

            case ArrayTypeSyntax array:
                return array with { Element = AsWritten(array.Element, atUseSite) };

            case SliceTypeSyntax slice:
                return slice with { Element = AsWritten(slice.Element, atUseSite) };

            case PointerTypeSyntax pointer:
                return pointer with { Element = AsWritten(pointer.Element, atUseSite) };

            case NullableTypeSyntax nullable:
                return nullable with { Element = AsWritten(nullable.Element, atUseSite) };

            default:
                return declared;
        }
    }

    /// <summary>
    /// True when a written type still rests on a parameter nothing has worked
    /// out yet, which is the only reason to go and bind a lambda's body.
    /// </summary>
    private static bool MentionsUnknown(
        TypeSyntax written, IReadOnlySet<string> names, Dictionary<string, TypeSymbol> inferred) =>
        written switch
        {
            NamedTypeSyntax { Name.Parts: [var only], TypeArguments.Count: 0 } =>
                names.Contains(only) && !inferred.ContainsKey(only),

            NamedTypeSyntax constructed =>
                constructed.TypeArguments.Any(a => MentionsUnknown(a, names, inferred)),

            ArrayTypeSyntax array => MentionsUnknown(array.Element, names, inferred),
            SliceTypeSyntax slice => MentionsUnknown(slice.Element, names, inferred),
            PointerTypeSyntax pointer => MentionsUnknown(pointer.Element, names, inferred),
            NullableTypeSyntax nullable => MentionsUnknown(nullable.Element, names, inferred),
            _ => false,
        };

    /// <summary>
    /// Every type resolved under what has been inferred so far, or null if any
    /// of them still depends on something unknown.
    /// </summary>
    private List<TypeSymbol>? ResolveAll(
        IEnumerable<TypeSyntax> types, FileScope scope, Dictionary<string, TypeSymbol> inferred)
    {
        using (Enter(_context with { Substitution = inferred }))
        {
            var resolved = new List<TypeSymbol>();
            foreach (var type in types)
            {
                var one = ResolveTypeQuietly(type, scope);
                if (one.IsError()) return null;
                resolved.Add(one);
            }
            return resolved;
        }
    }

    /// <summary>
    /// Whether a template, with its parameters worked out, would take the
    /// arguments given.
    ///
    /// The parameter types are resolved under the inferred substitution rather
    /// than by instantiating: instantiating queues a body to be bound, and a
    /// candidate that loses should not leave one behind.
    /// </summary>
    /// <summary>What each argument would convert to, were <paramref name="template"/> called with it.</summary>
    private TypeSymbol?[] ParameterTypesUnder(
        GenericFunctionTemplate template,
        Dictionary<string, TypeSymbol> inferred,
        List<BoundExpression> arguments)
    {
        var types = new TypeSymbol?[arguments.Count];

        using (Enter(_context with { Substitution = inferred }))
        {
            for (int i = 0; i < arguments.Count; i++)
            {
                if (WrittenParameterType(template.Declaration.Parameters, arguments, i)
                    is not { } written)
                    break;

                types[i] = ResolveType(written, template.Scope);
            }
        }

        return types;
    }

    private bool Accepts(
        GenericFunctionTemplate template,
        Dictionary<string, TypeSymbol> inferred,
        List<BoundExpression> arguments,
        string? report = null)
    {
        using (Enter(_context with { Substitution = inferred }))
        {
            // Only as far as both lists go. When no template has the arity of
            // the call, the first is tried anyway so that the call can report
            // against something, and an argument past its last parameter is
            // the arity's problem, which the call itself reports as SL0260.
            for (int i = 0; i < arguments.Count; i++)
            {
                if (WrittenParameterType(template.Declaration.Parameters, arguments, i)
                    is not { } written)
                    break;

                var wanted = ResolveType(written, template.Scope);
                if (wanted.IsError()) return false;

                // Past the last declared parameter only a gathered `params`
                // element lands, and that is passed by value.
                var declared = template.Declaration.Parameters;
                var mode = i < declared.Count ? declared[i].Mode : ParameterMode.Value;
                var parameter = new ParameterSymbol(
                    i < declared.Count ? declared[i].Name : declared[^1].Name, wanted, i)
                {
                    Mode = mode,
                };
                if (ArgumentFits(arguments[i], parameter)) continue;

                if (report is not null) ReportArgumentMode(report, i, arguments[i], parameter);
                return false;
            }

            return true;
        }
    }

    /// <summary>
    /// A generic method reached through a receiver. It stays a template until the
    /// arguments say what its type parameters are, so it cannot be found by the
    /// ordinary method lookup.
    /// </summary>
    private BoundExpression? TryBindGenericMethodCall(
        CallSyntax syntax, MemberAccessSyntax member, NamedTypeSymbol type,
        BoundExpression receiver, List<BoundExpression> arguments)
    {
        var candidates = GenericMethodsNamed(type, member.Member);
        if (candidates.Count == 0) return null;

        if (!candidates[0].IsPublic && type.ModuleName != _currentModule!.Name)
        {
            diagnostics.Report(Codes.MethodNotAccessible, member.Span,
                $"'{type.Name}.{member.Member}' is not public",
                type);
            return new BoundErrorExpression(syntax.Span);
        }

        var function = InferAndInstantiate(candidates, syntax, arguments);
        if (function is null) return new BoundErrorExpression(syntax.Span);

        // A struct method takes its receiver by pointer, as everywhere else.
        var self = type is StructTypeSymbol
            ? new BoundAddressOf(member.Span, type.MakePointerType(), receiver)
            : receiver;

        // `base.Visit<int>(...)` is the replaced body, not a dispatch.
        return BuildCall(syntax, function, self, arguments, nonVirtual: member.Target is BaseSyntax);
    }

    /// <summary>True once SL0831 has been said; it is about the target, not each use.</summary>
    private bool _reportedNarrowInt128;

    private static bool IsStandardLibrary(ModuleSymbol module) =>
        module.Name == "Standard" || module.Name.StartsWith("Standard.", StringComparison.Ordinal);

    private static PrimitiveTypeSymbol PrimitiveFor(TokenKind keyword) => keyword switch
    {
        TokenKind.VoidKeyword => PrimitiveTypeSymbol.Void,
        TokenKind.BoolKeyword => PrimitiveTypeSymbol.Bool,
        TokenKind.CharKeyword => PrimitiveTypeSymbol.Char,
        TokenKind.Char16Keyword => PrimitiveTypeSymbol.Char16,
        TokenKind.Char32Keyword => PrimitiveTypeSymbol.Char32,
        TokenKind.SByteKeyword => PrimitiveTypeSymbol.SByte,
        TokenKind.ShortKeyword => PrimitiveTypeSymbol.Short,
        TokenKind.IntKeyword => PrimitiveTypeSymbol.Int,
        TokenKind.LongKeyword => PrimitiveTypeSymbol.Long,
        TokenKind.NIntKeyword => PrimitiveTypeSymbol.NInt,
        TokenKind.Int128Keyword => PrimitiveTypeSymbol.Int128,
        TokenKind.ByteKeyword => PrimitiveTypeSymbol.Byte,
        TokenKind.UShortKeyword => PrimitiveTypeSymbol.UShort,
        TokenKind.UIntKeyword => PrimitiveTypeSymbol.UInt,
        TokenKind.ULongKeyword => PrimitiveTypeSymbol.ULong,
        TokenKind.NUIntKeyword => PrimitiveTypeSymbol.NUInt,
        TokenKind.UInt128Keyword => PrimitiveTypeSymbol.UInt128,
        TokenKind.FloatKeyword => PrimitiveTypeSymbol.Float,
        TokenKind.NDoubleKeyword => PrimitiveTypeSymbol.NDouble,
        _ => PrimitiveTypeSymbol.Double,
    };
}
