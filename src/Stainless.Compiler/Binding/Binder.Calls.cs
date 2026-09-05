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
/// Calls, and the overload resolution behind them.
///
/// Argument conversion, variadic promotion, and the diagnostics that
/// say why no candidate matched -- which is most of the file, because a
/// failed call is where a type error usually surfaces.
/// </summary>
public sealed partial class Binder
{
    private BoundExpression BindCall(CallSyntax syntax)
    {
        var arguments = syntax.Arguments.Select(BindArgument).ToList();

        // `base(...)` is the base constructor and `this(...)` another of this
        // class's own; neither is a member of anything.
        if (syntax.Callee is BaseSyntax) return BindBaseConstruction(syntax, arguments);
        if (syntax.Callee is ThisSyntax) return BindThisConstruction(syntax, arguments);

        // A bare `Ok(x)` builds a variant rather than calling anything. It has
        // to be decided here, before the name is looked up, because a draft has
        // no type yet and overload resolution has nothing to resolve against.
        // What keeps that unambiguous is SL0414: a module-level function may not
        // be named after a case of a variant this file can see. A method still
        // may, and is reached through its receiver.
        if (syntax.Callee is NameSyntax { Name.Parts: [var bare] } &&
            LookupLocal(bare) is null && CouldBeVariantCase(bare))
            return BindVariantDraft(syntax, bare, arguments);


        // `Shape.Circle(2.0)` names the variant as well as the case, so it
        // needs nothing from the surrounding expression to settle it.
        if (syntax.Callee is MemberAccessSyntax { } named &&
            ResolveVariantPrefix(named.Target) is { } prefix)
        {
            if (prefix.FindCase(named.Member) is not { } prefixCase)
            {
                diagnostics.Error("SL0435", named.Span,
                    $"variant '{prefix.Name}' has no case named '{named.Member}'; it has " +
                    Listed(prefix.Cases.Select(c => c.Name)));
                return new BoundErrorExpression(syntax.Span);
            }

            return BindVariantConstruction(prefix, prefixCase, arguments, syntax.Span);
        }

        // `receiver.Method(args)`, unless the receiver is really a module path.
        if (syntax.Callee is MemberAccessSyntax member)
        {
            if (ResolveModulePrefix(member.Target) is not { } module)
                return BindMethodCall(syntax, member, arguments);

            bool sameModule = module == _currentModule;
            var visible = module.FindFunctions(member.Member)
                .Where(f => sameModule || f.IsPublic)
                .ToList();

            if (visible.Any(f => AcceptsArguments(f, arguments)))
                return BindFunctionCall(syntax, visible, member.Member, arguments);

            var qualified = new QualifiedName(member.Span,
                [.. FlattenName(member.Target)!, member.Member]);
            if (TryBindGenericCall(syntax, qualified, arguments) is { } generic) return generic;

            return BindFunctionCall(syntax, visible, member.Member, arguments);
        }

        // A local, parameter or field holding a delegate is called indirectly,
        // and shadows any function of the same name -- the value is nearer.
        if (BindDelegateTarget(syntax.Callee) is { } indirect)
            return BuildIndirectCall(syntax, indirect, arguments);

        if (syntax.Callee is NameSyntax callee)
        {
            var candidates = ResolveFunctionCandidates(callee.Name);

            // An instantiation of a generic is an ordinary function with an
            // ordinary name, so it turns up here beside everything else. It must
            // not shadow the template it came from: `Sort(list)` instantiating
            // `Sort<Money>` cannot be what a later `Sort(numbers[2:5])` resolves
            // to. So the templates are tried whenever nothing already built fits.
            if (candidates.Any(c => AcceptsArguments(c, arguments)))
                return BindFunctionCall(syntax, candidates, callee.Name.Text, arguments);

            if (TryBindGenericCall(syntax, callee.Name, arguments) is { } generic) return generic;

            if (candidates.Count > 0)
                return BindFunctionCall(syntax, candidates, callee.Name.Text, arguments);

            // A method of the enclosing type, called without a receiver.
            if (callee.Name.Parts.Count == 1 &&
                _currentFunction?.ContainingType?.FindMethods(callee.Name.Text).ToList() is
                    { Count: > 0 } own)
            {
                var receiver = BindImplicitThis(callee.Span);
                if (receiver is not null)
                {
                    var method = ResolveOverload(own, arguments, callee.Span, callee.Name.Text);
                    if (method is null) return new BoundErrorExpression(syntax.Span);

                    // Inherited, so it may belong to a base in another module.
                    var owner = method.ContainingType ?? _currentFunction!.ContainingType!;
                    if (!CanReach(method.IsPublic, method.IsProtected, owner))
                    {
                        diagnostics.Error("SL0257", callee.Span,
                            NotVisible(owner, callee.Name.Text, method.IsProtected));
                        return new BoundErrorExpression(syntax.Span);
                    }

                    return BuildCall(syntax, method, receiver, arguments);
                }
            }

            if (callee.Name.Parts.Count == 1 && _currentFunction?.ContainingType is { } enclosing)
            {
                var generics = enclosing.GenericMethods.Where(m => m.Name == callee.Name.Text).ToList();
                if (generics.Count > 0)
                {
                    var instantiated = InferAndInstantiate(generics, syntax, arguments);
                    if (instantiated is null) return new BoundErrorExpression(syntax.Span);

                    var receiver = BindImplicitThis(callee.Span);
                    if (receiver is not null)
                        return BuildCall(syntax, instantiated, receiver, arguments);
                }
            }

            // Inside a lambda, a bare name may be a method of the object the
            // lambda was written in. That object is captured, and the call then
            // goes through the capture like any other member.
            if (callee.Name.Parts.Count == 1 && _closures.Count > 0 &&
                MethodsOfEnclosingThis(callee.Name.Text) is { Count: > 0 } outerMethods)
            {
                var outerMethod =
                    ResolveOverload(outerMethods, arguments, callee.Span, callee.Name.Text);
                if (outerMethod is null) return new BoundErrorExpression(syntax.Span);

                var captured = CaptureThis(_closures.Count - 1, callee.Span);
                if (captured.Type.IsError()) return new BoundErrorExpression(syntax.Span);
                return BuildCall(syntax, outerMethod, captured, arguments);
            }

            diagnostics.Error("SL0252", callee.Span, $"no function named '{callee.Name.Text}' is in scope");
            return new BoundErrorExpression(syntax.Span);
        }

        diagnostics.Error("SL0253", syntax.Span, "this expression is not callable");
        return new BoundErrorExpression(syntax.Span);
    }

    /// <summary>
    /// One argument, which may be written <c>ref x</c>.
    ///
    /// A <c>ref</c> argument is bound to the address of what it names, so what
    /// reaches the callee is a pointer and nothing in the emitter has to learn a
    /// new way to pass one. What it costs is a check that there is an address to
    /// take: a local, a parameter, a field, an array element or a dereference
    /// has one, and a call result or a literal does not.
    /// </summary>
    private BoundExpression BindArgument(ExpressionSyntax syntax)
    {
        if (syntax is not RefArgumentSyntax reference) return BindExpression(syntax);

        var target = BindExpression(reference.Value);
        if (target.Type.IsError()) return target;

        if (!IsAddressable(target))
        {
            diagnostics.Error("SL0443", reference.Span,
                "'ref' passes the storage this names rather than a copy of it, and this " +
                "expression has no storage to pass; put it in a local first");
            return new BoundErrorExpression(reference.Span);
        }

        if (IsReadOnlyTarget(target) is { } why)
        {
            diagnostics.Error("SL0444", reference.Span,
                $"'ref' lets the callee write to this, and {why}");
            return new BoundErrorExpression(reference.Span);
        }

        return new BoundAddressOf(
            reference.Span, new PointerTypeSymbol(target.Type), target)
        {
            FromRefKeyword = true,
        };
    }

    /// <summary>True for an expression that names storage rather than a value.</summary>
    private static bool IsAddressable(BoundExpression expression) => expression switch
    {
        // A bit-field is some of the bits of a byte, and there is no pointer to
        // that. It is why C refuses `&s.flags` too.
        BoundFieldAccess { Field.IsBitField: true } => false,

        BoundLocalAccess or BoundParameterAccess or BoundThis
            or BoundFieldAccess or BoundIndex or BoundDereference or BoundStaticAccess => true,
        _ => false,
    };

    /// <summary>Why this storage may not be written, or null when it may.</summary>
    private static string? IsReadOnlyTarget(BoundExpression expression) => expression switch
    {
        BoundLocalAccess { Local.IsConst: true } local =>
            $"'{local.Local.Name}' is a 'const'",
        BoundParameterAccess { Parameter.Mode: ParameterMode.In } parameter =>
            $"'{parameter.Parameter.Name}' is an 'in' parameter, which promises not to be written",
        BoundStaticAccess held =>
            $"'{held.Static.Name}' is a 'static readonly'",
        _ => null,
    };

    /// <summary>
    /// Binds a bare callee that names a value of delegate type, or returns null
    /// when it does not name one. Nothing is bound unless it really resolves to
    /// a delegate, so an ordinary call is never disturbed by this.
    /// </summary>
    private BoundExpression? BindDelegateTarget(ExpressionSyntax callee)
    {
        switch (callee)
        {
            case NameSyntax { Name.Parts.Count: 1 } name:
            {
                string text = name.Name.Parts[0];

                if (LookupLocal(text) is { Type: DelegateTypeSymbol } local)
                    return new BoundLocalAccess(name.Span, local);

                if (_currentFunction?.Parameters.FirstOrDefault(
                        p => p.Name == text && !p.IsThis) is { Type: DelegateTypeSymbol } parameter)
                    return new BoundParameterAccess(name.Span, parameter);

                if (_currentFunction?.ContainingType?.FindProperty(text)
                        is { Type: DelegateTypeSymbol } property)
                {
                    var receiver = BindImplicitThis(name.Span);
                    if (receiver is not null)
                        return BindPropertyRead(name.Span, receiver, property);
                }

                if (_currentFunction?.ContainingType?.FindField(text) is { Type: DelegateTypeSymbol } field)
                {
                    var receiver = BindImplicitThis(name.Span);
                    if (receiver is not null) return new BoundFieldAccess(name.Span, receiver, field);
                }

                return null;
            }

            // `receiver.field(...)` is handled by BindMethodCall instead, which
            // has already bound the receiver and so cannot bind it twice.
            default:
                return null;
        }
    }

    private BoundExpression BuildIndirectCall(
        CallSyntax syntax, BoundExpression target, List<BoundExpression> arguments)
    {
        var delegateType = (DelegateTypeSymbol)target.Type;

        if (arguments.Count != delegateType.Signature.Count)
        {
            diagnostics.Error("SL0363", syntax.Span,
                $"delegate '{delegateType.Name}' is '{delegateType.SignatureText}' and takes " +
                $"{delegateType.Signature.Count} argument{(delegateType.Signature.Count == 1 ? "" : "s")}, " +
                $"but {Given(arguments.Count)}");
            return new BoundErrorExpression(syntax.Span);
        }

        var converted = new List<BoundExpression>(arguments.Count);
        for (int i = 0; i < arguments.Count; i++)
        {
            var parameter = delegateType.Signature[i];
            var span = syntax.Arguments[i].Span;

            if (!ArgumentFits(arguments[i], parameter))
            {
                ReportArgumentMode(delegateType.Name, i, arguments[i], parameter);
                return new BoundErrorExpression(syntax.Span);
            }

            converted.Add(ConvertArgument(arguments[i], parameter, span));
        }

        return new BoundIndirectCall(syntax.Span, delegateType, target, converted);
    }

    private BoundExpression BindMethodCall(
        CallSyntax syntax, MemberAccessSyntax member, List<BoundExpression> arguments)
    {
        var receiver = member.Target is BaseSyntax
            ? BindBaseReceiver(member.Target.Span)
            : BindExpression(member.Target);

        if (receiver is null || receiver.Type.IsError()) return new BoundErrorExpression(syntax.Span);

        if (ReachThroughPointer(member, receiver) is not { } reachedThrough)
            return new BoundErrorExpression(syntax.Span);
        receiver = reachedThrough;

        if (receiver.Type is OptionalTypeSymbol or WeakTypeSymbol)
        {
            diagnostics.Error("SL0254", member.Span,
                $"'{receiver.Type.Name}' may be null; check it against null before calling '{member.Member}'");
            return new BoundErrorExpression(syntax.Span);
        }

        // An enum has no methods, so `HasFlag` is the language spelling the test
        // out rather than a member being called: it becomes `(value & f) == f`,
        // which is the same thing written by hand and costs the same.
        if (receiver.Type is EnumTypeSymbol flagsEnum && member.Member == "HasFlag")
            return BindHasFlag(syntax, member, receiver, flagsEnum, arguments);

        if (TryBindIntrinsicMember(syntax, member, receiver, arguments) is { } intrinsic)
            return intrinsic;

        if (receiver.Type is not NamedTypeSymbol namedType)
        {
            diagnostics.Error("SL0255", member.Span,
                $"'{receiver.Type.Name}' has no method named '{member.Member}'");
            return new BoundErrorExpression(syntax.Span);
        }

        // A field holding a delegate is called through, not dispatched to. It is
        // checked before methods so that the field's own name is what is called;
        // a method of the same name would be a different thing entirely.
        if (namedType.FindProperty(member.Member) is { Type: DelegateTypeSymbol } callableProperty)
        {
            var read = BindPropertyRead(member.Span, receiver, callableProperty);
            return read.Type.IsError()
                ? new BoundErrorExpression(syntax.Span)
                : BuildIndirectCall(syntax, read, arguments);
        }

        if (namedType.FindField(member.Member) is { Type: DelegateTypeSymbol } callable)
        {
            if (!CanReach(callable.IsPublic, callable.IsProtected, callable.ContainingType))
            {
                diagnostics.Error("SL0249", member.Span,
                    NotVisible(callable.ContainingType, member.Member, callable.IsProtected));
                return new BoundErrorExpression(syntax.Span);
            }

            return BuildIndirectCall(
                syntax, new BoundFieldAccess(member.Span, receiver, callable), arguments);
        }

        var overloads = namedType.FindMethods(member.Member).ToList();

        if (overloads.Count == 0)
        {
            if (TryBindGenericMethodCall(syntax, member, namedType, receiver, arguments) is { } generic)
                return generic;

            diagnostics.Error("SL0255", member.Span,
                $"'{namedType.Name}' has no method named '{member.Member}'");
            return new BoundErrorExpression(syntax.Span);
        }

        // Which overload is decided by the arguments, the same way a call to a
        // module-level function is.
        var method = overloads.Count == 1
            ? overloads[0]
            : ResolveOverload(overloads, arguments, member.Span, $"{namedType.Name}.{member.Member}");

        if (method is null) return new BoundErrorExpression(syntax.Span);

        // The accessors are real methods, but they are the lowering rather than
        // the language: naming one directly is naming an implementation detail.
        if (method.Accessor is { } accessed)
        {
            diagnostics.Error("SL0398", member.Span,
                $"'{member.Member}' is the {(method.ReturnType.IsVoid() ? "setter" : "getter")} of " +
                $"property '{namedType.Name}.{accessed.Name}'; use the property itself");
            return new BoundErrorExpression(syntax.Span);
        }

        if (!CanReach(method.IsPublic, method.IsProtected, method.ContainingType ?? namedType))
        {
            diagnostics.Error("SL0257", member.Span,
                NotVisible(method.ContainingType ?? namedType, member.Member, method.IsProtected));
            return new BoundErrorExpression(syntax.Span);
        }

        // A struct method takes its receiver by pointer. A temporary is fine: the
        // emitter puts it in a slot first, and anything the method writes back is
        // discarded, exactly as it is in C#.
        if (namedType is StructTypeSymbol)
            receiver = new BoundAddressOf(member.Span, new PointerTypeSymbol(namedType), receiver);

        return BuildCall(syntax, method, receiver, arguments,
            nonVirtual: member.Target is BaseSyntax);
    }

    /// <summary>
    /// Lowers <c>value.HasFlag(f)</c> to <c>(value &amp; f) == f</c>.
    ///
    /// The flag is named twice by the lowering, so it has to be something that
    /// can be read twice. In practice it is always a member of the enum.
    /// </summary>
    private BoundExpression BindHasFlag(
        CallSyntax syntax, MemberAccessSyntax member, BoundExpression receiver,
        EnumTypeSymbol enumType, List<BoundExpression> arguments)
    {
        if (!IsFlags(enumType))
        {
            diagnostics.Error("SL0408", member.Span,
                $"'{enumType.Name}' is a choice among alternatives, so it holds one value " +
                "rather than a set of them; mark it '[Flags]' if its members are meant to combine");
            return new BoundErrorExpression(syntax.Span);
        }

        if (arguments.Count != 1)
        {
            diagnostics.Error("SL0409", syntax.Span,
                $"'HasFlag' takes one '{enumType.Name}', but {Given(arguments.Count)}");
            return new BoundErrorExpression(syntax.Span);
        }

        var flag = arguments[0];
        if (!flag.Type.Equals(enumType))
        {
            if (!flag.Type.IsError())
                diagnostics.Error("SL0409", syntax.Arguments[0].Span,
                    $"'HasFlag' takes one '{enumType.Name}', but this is '{flag.Type.Name}'");
            return new BoundErrorExpression(syntax.Span);
        }

        if (!IsRepeatable(flag))
        {
            diagnostics.Error("SL0410", syntax.Arguments[0].Span,
                "the flag is tested against itself, so it is read twice; " +
                "put this in a variable first");
            return new BoundErrorExpression(syntax.Span);
        }

        var masked = new BoundBinary(syntax.Span, enumType, receiver, BoundBinaryOp.BitAnd, flag);
        return new BoundBinary(
            syntax.Span, PrimitiveTypeSymbol.Bool, masked, BoundBinaryOp.Equal, flag);
    }

    /// <summary>
    /// Binds <c>CompareTo</c>, <c>EqualTo</c> and <c>HashCode</c> on a type that
    /// implements them without saying so, or returns null when this is an
    /// ordinary call.
    ///
    /// Each lowers to something that already exists: equality to the <c>==</c>
    /// the binder knows for that type, and the other two to a runtime call. A
    /// declared member always wins, because this runs only after lookup on a
    /// named type has failed.
    /// </summary>
    private BoundExpression? TryBindIntrinsicMember(
        CallSyntax syntax, MemberAccessSyntax member, BoundExpression receiver,
        List<BoundExpression> arguments)
    {
        var type = receiver.Type;
        if (!HasIntrinsicMembers(type)) return null;
        if (type is NamedTypeSymbol named && named.FindMethod(member.Member) is not null) return null;

        int wanted = member.Member == "HashCode" ? 0 : 1;
        if (member.Member is not ("CompareTo" or "EqualTo" or "HashCode")) return null;

        if (arguments.Count != wanted)
        {
            diagnostics.Error("SL0412", syntax.Span,
                $"'{type.Name}.{member.Member}' takes {wanted} " +
                $"argument{(wanted == 1 ? "" : "s")}, but {Given(arguments.Count)}");
            return new BoundErrorExpression(syntax.Span);
        }

        if (member.Member == "HashCode")
            return new BoundCall(syntax.Span, HashFor(type), null, [Widen(receiver, HashFor(type))]);

        var other = BindConversion(arguments[0], type, syntax.Arguments[0].Span);
        if (other.Type.IsError()) return new BoundErrorExpression(syntax.Span);

        // Equality is the operator, which already knows how to compare a String
        // and how to compare an enum.
        if (member.Member == "EqualTo")
            return BindBinaryOperation(
                syntax.Span, receiver, BoundBinaryOp.Equal, other, TokenKind.EqualsEquals);

        var compare = CompareFor(type);
        return new BoundCall(
            syntax.Span, compare, null, [Widen(receiver, compare), Widen(other, compare)]);
    }

    /// <summary>The runtime comparison that orders values of this type.</summary>
    private FunctionSymbol CompareFor(TypeSymbol type) => type switch
    {
        _ when _builtins.IsString(type) => _builtins.CompareText,
        PrimitiveTypeSymbol { IsFloat: true } => _builtins.CompareDouble,
        PrimitiveTypeSymbol { IsSigned: true } => _builtins.CompareLong,
        EnumTypeSymbol { UnderlyingType.IsSigned: true } => _builtins.CompareLong,
        _ => _builtins.CompareULong,
    };

    private FunctionSymbol HashFor(TypeSymbol type) => type switch
    {
        _ when _builtins.IsString(type) => _builtins.HashText,
        PrimitiveTypeSymbol { IsFloat: true } => _builtins.HashDouble,
        _ => _builtins.HashInteger,
    };

    /// <summary>
    /// Widens a value to the parameter the runtime call takes. Written directly
    /// rather than through <see cref="BindConversion"/> because an enum does not
    /// convert implicitly to its integer, and here the compiler is the one
    /// asking rather than the programmer.
    /// </summary>
    private BoundExpression Widen(BoundExpression value, FunctionSymbol target)
    {
        var wanted = target.Parameters[0].Type;
        if (value.Type.Equals(wanted)) return value;
        if (_builtins.IsString(value.Type)) return value;

        var kind = value.Type switch
        {
            PrimitiveTypeSymbol { Kind: PrimitiveKind.Bool } => ConversionKind.BoolToInteger,
            PrimitiveTypeSymbol { IsFloat: true } => ConversionKind.FloatResize,
            _ => ConversionKind.IntegerWiden,
        };

        return new BoundConversion(value.Span, wanted, value, kind);
    }

    private List<FunctionSymbol> ResolveFunctionCandidates(QualifiedName name)
    {
        if (name.Parts.Count == 1)
        {
            var local = _currentModule!.FindFunctions(name.Parts[0]).ToList();
            if (local.Count > 0) return local;

            return _currentScope!.Imports.Values.Distinct()
                .SelectMany(m => m.FindFunctions(name.Parts[0]))
                .Where(f => f.IsPublic)
                .ToList();
        }

        // Qualified: everything before the last part names a module.
        string moduleName = string.Join('.', name.Parts.Take(name.Parts.Count - 1));
        if (_currentScope!.Imports.TryGetValue(moduleName, out var module) ||
            _modules.TryGetValue(moduleName, out module))
        {
            bool sameModule = module == _currentModule;
            return module.FindFunctions(name.Last).Where(f => sameModule || f.IsPublic).ToList();
        }

        return [];
    }

    private BoundExpression BindFunctionCall(
        CallSyntax syntax, List<FunctionSymbol> candidates, string name, List<BoundExpression> arguments)
    {
        if (candidates.Count == 0)
        {
            diagnostics.Error("SL0252", syntax.Span, $"no function named '{name}' is in scope");
            return new BoundErrorExpression(syntax.Span);
        }

        var function = ResolveOverload(candidates, arguments, syntax.Span, name);
        if (function is null) return new BoundErrorExpression(syntax.Span);

        return BuildCall(syntax, function, receiver: null, arguments);
    }

    private BoundExpression BuildCall(
        CallSyntax syntax, FunctionSymbol function, BoundExpression? receiver,
        List<BoundExpression> arguments, bool nonVirtual = false)
    {
        int expected = function.Parameters.Count(p => !p.IsThis);
        bool countOk = function.IsVariadic ? arguments.Count >= expected : arguments.Count == expected;

        if (!countOk)
        {
            diagnostics.Error("SL0260", syntax.Span,
                $"'{function.Name}' takes {expected}{(function.IsVariadic ? " or more" : "")} " +
                $"argument{(expected == 1 ? "" : "s")}, but {Given(arguments.Count)}");
            return new BoundErrorExpression(syntax.Span);
        }

        var converted = ConvertArguments(function, arguments, syntax.Arguments);
        return new BoundCall(syntax.Span, function, receiver, converted)
            { IsNonVirtual = nonVirtual };
    }

    private List<BoundExpression> ConvertArguments(
        FunctionSymbol function, List<BoundExpression> arguments, IReadOnlyList<ExpressionSyntax> syntax)
    {
        var parameters = function.Parameters.Where(p => !p.IsThis).ToList();
        var result = new List<BoundExpression>(arguments.Count);

        for (int i = 0; i < arguments.Count; i++)
        {
            var span = i < syntax.Count ? syntax[i].Span : arguments[i].Span;

            if (i >= parameters.Count)
            {
                result.Add(PromoteVariadic(arguments[i]));   // C varargs promotions
                continue;
            }

            result.Add(ConvertArgument(arguments[i], parameters[i], span));
        }

        return result;
    }

    /// <summary>
    /// One argument, converted for the parameter it is going to.
    ///
    /// A <c>ref</c> argument is already the address the callee wants and is
    /// deliberately not converted: the callee writes back through it, and a
    /// conversion would leave the result nowhere to go. An <c>in</c> argument is
    /// converted like a value one and then has its address taken here, because
    /// nothing at the call site said to; a value with no storage of its own gets
    /// a temporary, which lives as long as the frame does.
    /// </summary>
    private BoundExpression ConvertArgument(
        BoundExpression argument, ParameterSymbol parameter, SourceSpan span)
    {
        if (parameter.Mode == ParameterMode.Ref) return argument;

        var value = BindConversion(argument, parameter.Type, span);

        return parameter.Mode == ParameterMode.In && !value.Type.IsError()
            ? new BoundAddressOf(span, new PointerTypeSymbol(parameter.Type), value)
            : value;
    }

    /// <summary>C's default argument promotions: float widens to double, small ints to int.</summary>
    private BoundExpression PromoteVariadic(BoundExpression argument)
    {
        // A C variadic function has no declared parameter type to convert
        // against, so the String-to-bytes decision has to be made here instead.
        if (argument is BoundStringLiteral)
            return new BoundConversion(argument.Span, new PointerTypeSymbol(PrimitiveTypeSymbol.Byte),
                argument, ConversionKind.StringLiteralToPointer);

        if (_builtins.IsString(argument.Type))
        {
            diagnostics.Error("SL0294", argument.Span,
                "pass ToPointer() when giving a String to a C variadic function such as printf; " +
                "the String itself is an object, not a byte pointer");
            return new BoundErrorExpression(argument.Span);
        }

        if (argument.Type is PrimitiveTypeSymbol { Kind: PrimitiveKind.Float })
            return new BoundConversion(
                argument.Span, PrimitiveTypeSymbol.Double, argument, ConversionKind.FloatResize);

        if (argument.Type is PrimitiveTypeSymbol { IsInteger: true, Size: < 4 } or
            PrimitiveTypeSymbol { Kind: PrimitiveKind.Bool })
            return new BoundConversion(
                argument.Span, PrimitiveTypeSymbol.Int, argument, ConversionKind.IntegerWiden);

        return argument;
    }

    /// <summary>
    /// Explains why one argument does not fit, preferring the specific advice
    /// over the generic type mismatch when there is some.
    /// </summary>
    private void ReportArgumentMismatch(
        string name, int index, BoundExpression argument, TypeSymbol target)
    {
        if (_builtins.IsString(argument.Type) && IsBytePointer(target))
        {
            diagnostics.Error("SL0293", argument.Span,
                $"argument {index + 1} of '{name}' expects 'byte*'; a String does not convert to " +
                "one on its own. Call ToPointer() to hand its bytes to C, and keep the String " +
                "alive for as long as C holds the pointer");
            return;
        }

        // "an array literal was given" says nothing a reader did not already
        // know. Settling it against the parameter reports what is actually
        // wrong -- an element that does not fit, or a length that does not.
        if (argument is BoundArrayDraft draft)
        {
            BindArraySettle(draft, target, argument.Span);
            return;
        }

        diagnostics.Error("SL0262", argument.Span,
            $"argument {index + 1} of '{name}' expects '{target.Name}', " +
            $"but '{argument.Type.Name}' was given");
    }

    /// <summary>
    /// Whether <paramref name="argument"/> can be passed where
    /// <paramref name="target"/> is expected. This is expression-aware, not just
    /// type-aware: a string literal converts to <c>byte*</c> and a String
    /// variable does not, and overload resolution has to agree with
    /// <see cref="BindConversion"/> about that.
    /// </summary>
    private bool IsImplicitlyConvertible(BoundExpression argument, TypeSymbol target)
    {
        // A bare function name fits a delegate when one of its overloads has
        // that exact signature. The delegate is the only context a bare name
        // has, which is also how the overload gets chosen.
        if (argument is BoundFunctionGroup group)
            return target is DelegateTypeSymbol wanted && group.Candidates.Any(wanted.Accepts);

        if (argument is BoundLambda lambda)
            return target switch
            {
                DelegateTypeSymbol signature => signature.Signature.Count == lambda.Syntax.Parameters.Count,
                InterfaceTypeSymbol functional => SingleMethodOf(functional) is { } only &&
                    only.Parameters.Count(p => !p.IsThis) == lambda.Syntax.Parameters.Count,
                _ => false,
            };

        if (argument is BoundArrayDraft draft2)
            return target switch
            {
                ArrayTypeSymbol wanted =>
                    draft2.Elements.All(e => IsImplicitlyConvertible(e, wanted.Element)),
                FixedArrayTypeSymbol inline =>
                    inline.Length == draft2.Elements.Count &&
                    draft2.Elements.All(e => IsImplicitlyConvertible(e, inline.Element)),
                SliceTypeSymbol slice =>
                    draft2.Elements.All(e => IsImplicitlyConvertible(e, slice.Element)),
                _ => false,
            };

        // A bare case name fits a variant with that case, on the same terms a
        // lambda fits an interface: the parameter is the only thing that says
        // which variant was meant, and the arity is what can be checked before
        // the arguments are converted against the fields.
        if (argument is BoundVariantDraft draft)
            return target is VariantTypeSymbol variant &&
                   variant.FindCase(draft.Case) is { } named &&
                   named.Fields.Count == draft.Arguments.Count;

        if (IsBytePointer(target))
        {
            if (argument is BoundStringLiteral) return true;
            if (_builtins.IsString(argument.Type)) return false;
        }

        if (ConstantFits(argument, target)) return true;
        if (CharacterFits(argument, target)) return true;

        return ClassifyConversion(argument.Type, target, explicitCast: false) is not null;
    }

    /// <summary>
    /// Whether an argument may be given to a parameter, mode and all.
    ///
    /// A <c>ref</c> parameter takes only an argument that said <c>ref</c>, and
    /// takes it at exactly its own type: the callee writes back through it, so
    /// a conversion on the way in would be a write to something the caller never
    /// named. An <c>in</c> parameter converts like a value one, because what it
    /// receives may be a temporary and a temporary may be converted.
    /// </summary>
    private bool ArgumentFits(BoundExpression argument, ParameterSymbol parameter)
    {
        // Already reported. Saying the mode is wrong as well would bury the
        // diagnostic that actually explains what happened.
        if (argument.Type.IsError()) return true;

        bool given = argument is BoundAddressOf { FromRefKeyword: true };

        if (parameter.Mode == ParameterMode.Ref)
            return given &&
                   ((BoundAddressOf)argument).Operand.Type.Equals(parameter.Type);

        return !given && IsImplicitlyConvertible(argument, parameter.Type);
    }

    /// <summary>
    /// Reports why an argument did not fit: the mode first, because a type
    /// mismatch reported against a 'ref' that should not be there reads as a
    /// puzzle rather than a mistake.
    /// </summary>
    private void ReportArgumentMode(
        string name, int index, BoundExpression argument, ParameterSymbol parameter)
    {
        bool given = argument is BoundAddressOf { FromRefKeyword: true };

        if (parameter.Mode == ParameterMode.Ref && !given)
        {
            diagnostics.Error("SL0445", argument.Span,
                $"argument {index + 1} of '{name}' is 'ref {parameter.Type.Name} " +
                $"{parameter.Name}', so the call must say so too: write " +
                "'ref' before it");
            return;
        }

        if (parameter.Mode != ParameterMode.Ref && given)
        {
            diagnostics.Error("SL0446", argument.Span,
                $"argument {index + 1} of '{name}' is " +
                (parameter.Mode == ParameterMode.In
                    ? $"'in {parameter.Type.Name} {parameter.Name}', which the callee promises " +
                      "not to write, so it is not passed with 'ref'"
                    : $"'{parameter.Type.Name} {parameter.Name}', which is passed by value; " +
                      "drop the 'ref'"));
            return;
        }

        var actual = argument is BoundAddressOf { FromRefKeyword: true, Operand: { } inner }
            ? inner
            : argument;

        if (parameter.Mode == ParameterMode.Ref)
        {
            diagnostics.Error("SL0447", argument.Span,
                $"argument {index + 1} of '{name}' is 'ref {parameter.Type.Name}', and this is " +
                $"'{actual.Type.Name}'. A 'ref' argument is not converted, because the callee " +
                "writes back through it and there would be nowhere for the result to go");
            return;
        }

        ReportArgumentMismatch(name, index, argument, parameter.Type);
    }

    /// <summary>Whether one candidate could take these arguments.</summary>
    private bool AcceptsArguments(FunctionSymbol candidate, List<BoundExpression> arguments)
    {
        int expected = candidate.Parameters.Count(p => !p.IsThis);
        if (candidate.IsVariadic ? arguments.Count < expected : arguments.Count != expected)
            return false;

        var parameters = candidate.Parameters.Where(p => !p.IsThis).ToList();
        for (int i = 0; i < parameters.Count; i++)
            if (!ArgumentFits(arguments[i], parameters[i]))
                return false;

        return true;
    }

    private FunctionSymbol? ResolveOverload(
        IReadOnlyList<FunctionSymbol> candidates, List<BoundExpression> arguments, SourceSpan span, string name)
    {
        var viable = candidates.Where(c => AcceptsArguments(c, arguments)).ToList();

        switch (viable.Count)
        {
            case 1:
                return viable[0];

            case 0:
                if (candidates.Count == 1)
                {
                    // One candidate: report the real mismatch rather than "no overload".
                    var only = candidates[0];
                    var parameters = only.Parameters.Where(p => !p.IsThis).ToList();
                    int expected = parameters.Count;

                    if (only.IsVariadic ? arguments.Count < expected : arguments.Count != expected)
                        diagnostics.Error("SL0260", span,
                            $"'{name}' takes {expected}{(only.IsVariadic ? " or more" : "")} " +
                            $"argument{(expected == 1 ? "" : "s")}, but {Given(arguments.Count)}");
                    else
                        for (int i = 0; i < parameters.Count; i++)
                            if (!ArgumentFits(arguments[i], parameters[i]))
                                ReportArgumentMode(name, i, arguments[i], parameters[i]);
                    return null;
                }

                diagnostics.Error("SL0263", span,
                    $"no overload of '{name}' accepts these {arguments.Count} argument(s)");
                return null;

            default:
                // Prefer an exact match before declaring ambiguity.
                var exact = viable.Where(candidate =>
                {
                    var parameters = candidate.Parameters.Where(p => !p.IsThis).ToList();
                    return parameters.Count == arguments.Count &&
                           parameters.Zip(arguments).All(pair => pair.First.Type.Equals(pair.Second.Type));
                }).ToList();

                if (exact.Count == 1) return exact[0];

                diagnostics.Error("SL0264", span, $"the call to '{name}' is ambiguous");
                return null;
        }
    }
}
