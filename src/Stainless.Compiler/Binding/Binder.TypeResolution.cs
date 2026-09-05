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
        if (_arrays.TryGetValue(element, out var existing)) return existing;
        var array = new ArrayTypeSymbol(element);
        _arrays[element] = array;
        return array;
    }

    /// <summary>
    /// <c>T[:]</c>, built once per element type.
    ///
    /// The three fields are hidden storage: a slice is reached through indexing
    /// and Length, and naming the array it came from would let a caller keep the
    /// whole of it alive on purpose and by accident alike.
    /// </summary>
    private SliceTypeSymbol SliceOf(TypeSymbol element)
    {
        if (_slices.TryGetValue(element, out var existing)) return existing;

        var slice = new SliceTypeSymbol
        {
            Element = element,
            SimpleName = element.Name + "[:]",
            ModuleName = Builtins.StandardModuleName,
        };

        slice.Fields.Add(new FieldSymbol(
            SliceTypeSymbol.ArrayFieldName, ArrayOf(element), slice, 0) { IsBackingField = true });
        slice.Fields.Add(new FieldSymbol(
            SliceTypeSymbol.OffsetFieldName, PrimitiveTypeSymbol.NUInt, slice, 1)
            { IsBackingField = true });
        slice.Fields.Add(new FieldSymbol(
            SliceTypeSymbol.LengthFieldName, PrimitiveTypeSymbol.NUInt, slice, 2)
            { IsBackingField = true });

        _slices[element] = slice;
        _structs.Add(slice);
        ComputeLayout(slice, []);
        return slice;
    }

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
    private TypeSymbol ResolveType(TypeSyntax syntax, FileScope scope)
    {
        var resolved = ResolveTypeCore(syntax, scope);

        if (resolved is StructTypeSymbol { IsOpaque: true } opaque)
        {
            diagnostics.Error("SL0524", syntax.Span,
                $"'{opaque.Name}' is declared without a body, so its size is not known here " +
                $"and there is no value of it to have; write '{opaque.Name}*', which is what an " +
                "incomplete type is for");
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
        switch (syntax)
        {
            case SliceTypeSyntax sliceSyntax:
            {
                var element = ResolveType(sliceSyntax.Element, scope);
                if (element.IsError()) return element;

                if (element.IsVoid())
                {
                    diagnostics.Error("SL0451", sliceSyntax.Span,
                        "there is no slice of 'void'");
                    return ErrorTypeSymbol.Instance;
                }

                return SliceOf(element);
            }

            case ArrayTypeSyntax array:
            {
                var element = ResolveType(array.Element, scope);
                if (element.IsError()) return element;
                if (element.IsVoid())
                {
                    diagnostics.Error("SL0310", syntax.Span, "there is no array of 'void'");
                    return ErrorTypeSymbol.Instance;
                }
                return ArrayOf(element);
            }

            case FixedArrayTypeSyntax fixedArray:
                return ResolveFixedArray(fixedArray, scope);

            case PrimitiveTypeSyntax primitive:
                return PrimitiveFor(primitive.Keyword);

            case PointerTypeSyntax pointer:
            {
                // The one place an incomplete type may appear. C says the same,
                // and for the same reason: a pointer has a size whatever it
                // points at.
                var element = ResolveTypeCore(pointer.Element, scope);
                if (element.IsError()) return element;
                if (element is NamedTypeSymbol { IsReferenceType: true })
                {
                    diagnostics.Error("SL0270", syntax.Span,
                        $"'{element.Name}' is a reference type, so '{element.Name}*' is not " +
                        "allowed; it is already a managed pointer");
                    return ErrorTypeSymbol.Instance;
                }
                return new PointerTypeSymbol(element);
            }

            case NullableTypeSyntax nullable:
            {
                var element = ResolveType(nullable.Element, scope);
                if (element.IsError()) return element;
                if (element is not NamedTypeSymbol { IsReferenceType: true } referenceType)
                {
                    diagnostics.Error("SL0271", syntax.Span,
                        $"'{element.Name}?' is not valid; only class and interface references can " +
                        $"be optional (a '{element.Name}' is a value and is never null)");
                    return ErrorTypeSymbol.Instance;
                }
                return new OptionalTypeSymbol(referenceType);
            }

            case WeakTypeSyntax weak:
            {
                var element = ResolveType(weak.Element, scope);
                if (element.IsError()) return element;

                var referenced = element.AsReference();
                if (referenced is null)
                {
                    diagnostics.Error("SL0272", syntax.Span,
                        $"'weak' requires a class or interface reference, but '{element.Name}' is not one");
                    return ErrorTypeSymbol.Instance;
                }
                return new WeakTypeSymbol(referenced);
            }

            case NamedTypeSyntax named:
            {
                var resolved = ResolveNamedType(named, scope);
                if (resolved is AttributeTypeSymbol)
                {
                    diagnostics.Error("SL0345", syntax.Span,
                        $"'{resolved.Name}' is an attribute and cannot be used as a type; " +
                        $"write it as '[{resolved.Name}]' on a declaration instead");
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
            _substitution.TryGetValue(parts[0], out var substituted))
            return substituted;

        if (syntax.TypeArguments.Count > 0)
            return ResolveConstructedType(syntax, scope);

        if (parts.Count == 1)
        {
            if (module.Types.TryGetValue(parts[0], out var local)) return local;
            if (module.Aliases.TryGetValue(parts[0], out var ownAlias)) return ResolveAlias(ownAlias);

            // Naming a generic without arguments is a common slip; say so plainly.
            if (module.GenericTypes.TryGetValue(parts[0], out var template))
            {
                diagnostics.Error("SL0325", syntax.Span,
                    $"'{template.Name}' is generic and needs type arguments, " +
                    $"as in '{template.Name}<{string.Join(", ", template.Parameters)}>'");
                return ErrorTypeSymbol.Instance;
            }

            var visible = scope.Imports.Values.Distinct()
                .Where(imported => imported.Types.TryGetValue(parts[0], out var t) && t.IsPublic)
                .Select(imported => imported.Types[parts[0]])
                .Distinct()
                .ToList();

            // An imported alias is a name like any other, and is looked for only
            // when no imported type answered -- a type is the more direct thing.
            if (visible.Count == 0)
            {
                var aliases = scope.Imports.Values.Distinct()
                    .Where(i => i.Aliases.TryGetValue(parts[0], out var a) && a.IsPublic)
                    .Select(i => i.Aliases[parts[0]])
                    .Distinct()
                    .ToList();

                if (aliases.Count == 1) return ResolveAlias(aliases[0]);
                if (aliases.Count > 1)
                {
                    diagnostics.Error("SL0273", syntax.Span,
                        $"'{parts[0]}' is ambiguous between " +
                        string.Join(" and ", aliases.Select(a => $"'{a.QualifiedName}'")) +
                        "; qualify it with its module name");
                    return ErrorTypeSymbol.Instance;
                }
            }

            if (visible.Count == 1) return visible[0];
            if (visible.Count > 1)
            {
                diagnostics.Error("SL0273", syntax.Span,
                    $"'{parts[0]}' is ambiguous between " +
                    string.Join(" and ", visible.Select(t => $"'{t.QualifiedName}'")) +
                    "; qualify it with its module name");
                return ErrorTypeSymbol.Instance;
            }
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
                        diagnostics.Error("SL0274", syntax.Span,
                            $"'{type.QualifiedName}' is not public");
                        return ErrorTypeSymbol.Instance;
                    }
                    return type;
                }

                if (target.Aliases.TryGetValue(parts[^1], out var qualifiedAlias))
                {
                    if (target != module && !qualifiedAlias.IsPublic)
                    {
                        diagnostics.Error("SL0274", syntax.Span,
                            $"'{qualifiedAlias.QualifiedName}' is not public");
                        return ErrorTypeSymbol.Instance;
                    }
                    return ResolveAlias(qualifiedAlias);
                }

                diagnostics.Error("SL0275", syntax.Span,
                    $"module '{target.Name}' does not declare a type named '{parts[^1]}'");
                return ErrorTypeSymbol.Instance;
            }
        }

        diagnostics.Error("SL0276", syntax.Span,
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

        var template = FindGenericType(syntax.Name, scope);
        if (template is null)
        {
            diagnostics.Error("SL0326", syntax.Span,
                $"no generic type named '{syntax.Name.Text}' is in scope");
            return ErrorTypeSymbol.Instance;
        }

        return Instantiate(template, arguments, syntax.Span);
    }

    private GenericTypeTemplate? FindGenericType(QualifiedName name, FileScope scope)
    {
        var module = scope.Module;
        if (name.Parts.Count == 1)
        {
            if (module.GenericTypes.TryGetValue(name.Parts[0], out var local)) return local;

            return scope.Imports.Values.Distinct()
                .Select(m => m.GenericTypes.TryGetValue(name.Parts[0], out var t) && t.IsPublic ? t : null)
                .FirstOrDefault(t => t is not null);
        }

        string moduleName = string.Join('.', name.Parts.Take(name.Parts.Count - 1));
        if (scope.Imports.TryGetValue(moduleName, out var target) ||
            _modules.TryGetValue(moduleName, out target))
        {
            if (target.GenericTypes.TryGetValue(name.Last, out var found) &&
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

            return _currentScope!.Imports.Values.Distinct()
                .SelectMany(m => m.GenericFunctions)
                .Where(f => f.Name == name.Parts[0] && f.IsPublic)
                .ToList();
        }

        string moduleName = string.Join('.', name.Parts.Take(name.Parts.Count - 1));
        if (_currentScope!.Imports.TryGetValue(moduleName, out var target) ||
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
        var viable = candidates
            .Where(c => c.Declaration.Parameters.Count == arguments.Count)
            .ToList();

        if (viable.Count == 0) viable = [candidates[0]];

        // Every candidate of the right arity is tried, and one that infers but
        // then would not accept the arguments is not a candidate. Two templates
        // may take one argument and differ in its shape -- `Sort(T[:])` and
        // `Sort(IList<T>)` do -- and picking the first would make the second
        // unreachable.
        var fitting = new List<(GenericFunctionTemplate Template, List<TypeSymbol> Arguments)>();
        Dictionary<string, TypeSymbol>? firstFailure = null;
        GenericFunctionTemplate? failed = null;

        // A candidate whose parameters were all worked out and which still would
        // not take the arguments. It is the better thing to report: the reader
        // has an argument that does not fit, not a type nobody could name.
        (GenericFunctionTemplate Template, Dictionary<string, TypeSymbol> Inferred)? nearMiss = null;

        foreach (var candidate in viable)
        {
            var names = candidate.Parameters.ToHashSet(StringComparer.Ordinal);
            var inferred = new Dictionary<string, TypeSymbol>(StringComparer.Ordinal);

            // An enclosing type's parameters are already fixed, so they are
            // given rather than inferred; only the method's own are worked out.
            foreach (var (name, type) in candidate.OuterSubstitution) inferred.TryAdd(name, type);

            int shared = Math.Min(arguments.Count, candidate.Declaration.Parameters.Count);
            for (int i = 0; i < shared; i++)
                Infer(candidate.Declaration.Parameters[i].Type, arguments[i].Type,
                    names, inferred, candidate.Scope);

            // A lambda has no type of its own, so the loop above learned nothing
            // from one. Anything still unknown may yet be readable off a lambda's
            // result, once the arguments that are values have said what its
            // parameters are.
            if (candidate.Parameters.Any(p => !inferred.ContainsKey(p)))
                InferFromLambdaResults(candidate, arguments, names, inferred);

            if (candidate.Parameters.Any(p => !inferred.ContainsKey(p)))
            {
                firstFailure ??= inferred;
                failed ??= candidate;
                continue;
            }

            if (Accepts(candidate, inferred, arguments))
                fitting.Add((candidate, candidate.Parameters.Select(p => inferred[p]).ToList()));
            else
                nearMiss ??= (candidate, inferred);
        }

        if (fitting.Count == 1)
            return InstantiateFunction(fitting[0].Template, fitting[0].Arguments, syntax.Span);

        if (fitting.Count > 1)
        {
            diagnostics.Error("SL0453", syntax.Span,
                $"'{candidates[0].Name}' is ambiguous here: " +
                string.Join(" and ", fitting.Select(f =>
                    $"'{f.Template.Name}<{string.Join(", ", f.Arguments.Select(a => a.Name))}>'")) +
                " both accept these arguments");
            return null;
        }

        // Everything was worked out and an argument still did not fit: say which.
        if (nearMiss is { } near)
        {
            Accepts(near.Template, near.Inferred, arguments, report: near.Template.Name);
            return null;
        }

        var template = failed ?? viable[0];
        var reported = firstFailure ?? new Dictionary<string, TypeSymbol>(StringComparer.Ordinal);
        var missing = template.Parameters.Where(p => !reported.ContainsKey(p)).ToList();

        diagnostics.Error("SL0327", syntax.Span,
            $"cannot infer {string.Join(" and ", missing.Select(m => "'" + m + "'"))} " +
            $"for '{template.Name}' from these arguments; " +
            "Stainless infers type arguments only from the values passed");
        return null;
    }

    /// <summary>
    /// Works out the type parameters that appear only in a lambda's result.
    ///
    /// The order matters, and is why this is a second pass rather than part of
    /// the first. Given <c>Map&lt;T, R&gt;(T[:] items, IFunc&lt;T, R&gt; f)</c> and
    /// <c>Map(numbers, n =&gt; n * 2)</c>: T comes from <c>numbers</c>, which
    /// makes the lambda's target <c>IFunc&lt;int, R&gt;</c>, which gives the lambda
    /// its parameter type, which lets its body be bound, which is what says
    /// what R is. No step in that chain can be taken earlier.
    ///
    /// It loops, because one lambda's result may settle another's parameter,
    /// and stops as soon as a pass learns nothing -- so a call that genuinely
    /// cannot be inferred reaches SL0327 rather than spinning.
    /// </summary>
    private void InferFromLambdaResults(
        GenericFunctionTemplate candidate,
        List<BoundExpression> arguments,
        HashSet<string> names,
        Dictionary<string, TypeSymbol> inferred)
    {
        int shared = Math.Min(arguments.Count, candidate.Declaration.Parameters.Count);

        bool learned = true;
        while (learned && candidate.Parameters.Any(p => !inferred.ContainsKey(p)))
        {
            learned = false;

            for (int i = 0; i < shared; i++)
            {
                if (arguments[i] is not BoundLambda lambda) continue;

                // Read off the interface's *declaration* rather than a resolved
                // symbol. `IFunc<int, R>` will not resolve at all while R is
                // unknown -- a constructed type with one unresolved argument is
                // an error type entire -- and it is exactly that position this
                // is trying to fill.
                if (candidate.Declaration.Parameters[i].Type
                    is not NamedTypeSyntax { TypeArguments.Count: > 0 } written) continue;

                if (FindGenericType(written.Name, candidate.Scope) is not { } template) continue;
                if (template.Declaration.Kind != TypeDeclKind.Interface) continue;
                if (template.Parameters.Count != written.TypeArguments.Count) continue;

                var methods = template.Declaration.Members.OfType<FunctionDeclSyntax>().ToList();
                if (methods.Count != 1) continue;

                var method = methods[0];
                if (method.Parameters.Count != lambda.Syntax.Parameters.Count) continue;

                // The interface writes its method in terms of its own parameter
                // names; the use site says what each of those is. `IFunc<A, B>`
                // declaring `B Apply(A)`, used as `IFunc<T, R>`, makes the
                // lambda take a T and produce an R.
                var atUseSite = new Dictionary<string, TypeSyntax>(StringComparer.Ordinal);
                for (int p = 0; p < template.Parameters.Count; p++)
                    atUseSite[template.Parameters[p]] = written.TypeArguments[p];

                var result = AsWritten(method.ReturnType, atUseSite);

                // Only worth binding a body to learn something not already known.
                if (result is not NamedTypeSyntax { Name.Parts.Count: 1, TypeArguments.Count: 0 } wanted
                    || !names.Contains(wanted.Name.Parts[0])
                    || inferred.ContainsKey(wanted.Name.Parts[0])) continue;

                // Every parameter has to be settled before the body can bind.
                var parameterTypes = ResolveAll(
                    method.Parameters.Select(p => AsWritten(p.Type, atUseSite)),
                    candidate.Scope, inferred);
                if (parameterTypes is null) continue;

                if (ProbeLambdaResult(lambda.Syntax, parameterTypes) is not { } produced) continue;

                inferred[wanted.Name.Parts[0]] = produced;
                learned = true;
            }
        }
    }

    /// <summary>
    /// An interface's method signature restated in the caller's names: the
    /// <c>A</c> and <c>B</c> of <c>IFunc&lt;A, B&gt;</c> become whatever was
    /// written at <c>IFunc&lt;T, R&gt;</c>.
    ///
    /// Bare names only. A functional interface whose method mentions its
    /// parameter inside another type -- <c>List&lt;B&gt; Apply(A)</c> -- is left
    /// alone rather than half-translated, and falls through to SL0327 saying
    /// so, which is the honest outcome until something needs otherwise.
    /// </summary>
    private static TypeSyntax AsWritten(TypeSyntax declared, Dictionary<string, TypeSyntax> atUseSite) =>
        declared is NamedTypeSyntax { Name.Parts.Count: 1, TypeArguments.Count: 0 } name &&
        atUseSite.TryGetValue(name.Name.Parts[0], out var written)
            ? written
            : declared;

    /// <summary>
    /// Every type resolved under what has been inferred so far, or null if any
    /// of them still depends on something unknown.
    /// </summary>
    private List<TypeSymbol>? ResolveAll(
        IEnumerable<TypeSyntax> types, FileScope scope, Dictionary<string, TypeSymbol> inferred)
    {
        var previous = _substitution;
        _substitution = inferred;

        try
        {
            var resolved = new List<TypeSymbol>();
            using (diagnostics.Muted())
            {
                foreach (var type in types)
                {
                    var one = ResolveType(type, scope);
                    if (one.IsError()) return null;
                    resolved.Add(one);
                }
            }
            return resolved;
        }
        finally
        {
            _substitution = previous;
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
    private bool Accepts(
        GenericFunctionTemplate template,
        Dictionary<string, TypeSymbol> inferred,
        List<BoundExpression> arguments,
        string? report = null)
    {
        var previous = _substitution;
        _substitution = inferred;

        try
        {
            for (int i = 0; i < arguments.Count; i++)
            {
                var wanted = ResolveType(template.Declaration.Parameters[i].Type, template.Scope);
                if (wanted.IsError()) return false;
                if (IsImplicitlyConvertible(arguments[i], wanted)) continue;

                if (report is not null) ReportArgumentMismatch(report, i, arguments[i], wanted);
                return false;
            }

            return true;
        }
        finally
        {
            _substitution = previous;
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
        var candidates = type.GenericMethods.Where(m => m.Name == member.Member).ToList();
        if (candidates.Count == 0) return null;

        if (!candidates[0].IsPublic && type.ModuleName != _currentModule!.Name)
        {
            diagnostics.Error("SL0257", member.Span, $"'{type.Name}.{member.Member}' is not public");
            return new BoundErrorExpression(syntax.Span);
        }

        var function = InferAndInstantiate(candidates, syntax, arguments);
        if (function is null) return new BoundErrorExpression(syntax.Span);

        // A struct method takes its receiver by pointer, as everywhere else.
        var self = type is StructTypeSymbol
            ? new BoundAddressOf(member.Span, new PointerTypeSymbol(type), receiver)
            : receiver;

        return BuildCall(syntax, function, self, arguments);
    }

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
        TokenKind.ByteKeyword => PrimitiveTypeSymbol.Byte,
        TokenKind.UShortKeyword => PrimitiveTypeSymbol.UShort,
        TokenKind.UIntKeyword => PrimitiveTypeSymbol.UInt,
        TokenKind.ULongKeyword => PrimitiveTypeSymbol.ULong,
        TokenKind.NUIntKeyword => PrimitiveTypeSymbol.NUInt,
        TokenKind.FloatKeyword => PrimitiveTypeSymbol.Float,
        _ => PrimitiveTypeSymbol.Double,
    };
}
