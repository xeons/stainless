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

namespace Stainless.Binding;

/// <summary>
/// Checks a program that bound without error against what the emitter assumes
/// of it, and throws an <see cref="InternalCompilerError"/> at the first node
/// that breaks a rule.
///
/// The emitter trusts the tree. A node it has no case for, a local it has no
/// slot for, or a write to something that is not storage would each be a crash
/// at best and quietly wrong code at worst, a long way from the binder that
/// made them. This names the node instead.
///
/// On in a Debug build of the compiler, which is what every test runs, and off
/// in Release. <c>STAINLESS_VERIFY_BOUND</c> set to <c>0</c>, or to anything
/// else, overrides either.
/// </summary>
public static class BoundTreeVerifier
{
    public static bool IsEnabled { get; } =
        Environment.GetEnvironmentVariable("STAINLESS_VERIFY_BOUND") is { Length: > 0 } value
            ? value != "0"
#if DEBUG
            : true;
#else
            : false;
#endif

    public static void Verify(BoundProgram program)
    {
        foreach (var function in program.Functions)
            new FunctionVerifier(function.Symbol).Visit(function.Body);

        foreach (var shared in program.Statics)
            if (shared.Initializer is { } initializer)
                new FunctionVerifier(null).Visit(initializer);
    }

    /// <summary>
    /// Whether a type is one binding settles or refuses, and so has no
    /// representation to emit.
    /// </summary>
    private static bool IsUnsettled(TypeSymbol type) =>
        type is ErrorTypeSymbol or LambdaType or ArrayDraftType or TupleDraftType
            or VariantDraftType or FunctionGroupType or DefaultLiteralType or NewDraftType;

    private sealed class FunctionVerifier(FunctionSymbol? function) : BoundTreeWalker
    {
        private readonly HashSet<LocalSymbol> _declared = [];

        /// <summary>
        /// Inside a <c>for parallel</c>, what its body may name from outside:
        /// only what it captured, because each chunk is a function of its own.
        /// </summary>
        private HashSet<object>? _captured;

        public override void Visit(BoundStatement? statement)
        {
            switch (statement)
            {
                case null:
                    return;

                case BoundLocalDeclaration declaration:
                    Declare(declaration.Local, declaration.Span);
                    break;

                case BoundSwitch chosen:
                    foreach (var section in chosen.Sections)
                    {
                        if (section.Binding is { } binding)
                            Declare(binding, section.Span);

                        foreach (var label in section.Labels)
                        {
                            if (!IsConstant(label))
                                throw Fault("a switch label that is not a constant", label.Span);
                            if (!label.Type.Equals(chosen.Value.Type))
                                throw Fault(
                                    $"a label of '{label.Type.Name}' in a switch over " +
                                    $"'{chosen.Value.Type.Name}'", label.Span);
                        }
                    }
                    break;

                case BoundParallelFor loop:
                {
                    Visit(loop.Start);
                    Visit(loop.Limit);
                    Visit(loop.Stride);

                    var outer = _captured;
                    var outerDeclared = new HashSet<LocalSymbol>(_declared);
                    _captured = [.. loop.Captures];
                    _declared.Clear();
                    Declare(loop.Variable, loop.Span);

                    Visit(loop.Body);

                    _captured = outer;
                    _declared.Clear();
                    _declared.UnionWith(outerDeclared);
                    return;
                }
            }

            base.Visit(statement);
        }

        public override void Visit(BoundExpression? expression)
        {
            if (expression is null)
                return;

            if (expression.Type is null)
                throw Fault($"{expression.GetType().Name} has no type", expression.Span);

            switch (expression)
            {
                case BoundErrorExpression:
                    throw Fault("an error node in a program that reported no error", expression.Span);

                case BoundLambda or BoundFunctionGroup or BoundArrayDraft or BoundSpread
                    or BoundOutDraft or BoundTupleDraft or BoundVariantDraft or BoundNewDraft:
                    throw Fault($"{expression.GetType().Name} was never settled", expression.Span);

                case BoundNullLiteral:
                    break;

                case BoundLocalAccess read:
                    if (!_declared.Contains(read.Local) && _captured?.Contains(read.Local) != true)
                        throw Fault($"'{read.Local.Name}' is read where nothing declared it", read.Span);
                    break;

                case BoundParameterAccess read:
                    Owned(read.Parameter, read.Span);
                    break;

                case BoundThis self:
                    Owned(self.Parameter, self.Span);
                    break;

                case BoundLet held:
                    Declare(held.Local, held.Span);
                    break;

                case BoundTry attempt:
                    Declare(attempt.Slot, attempt.Span);
                    break;

                case BoundAssignment assignment:
                    if (assignment.DeclaresLocal is { } declared)
                        Declare(declared, assignment.Span);
                    if (!HasAddress(assignment.Target))
                        throw Fault(
                            $"an assignment to {assignment.Target.GetType().Name}, which is not storage",
                            assignment.Span);
                    break;

                case BoundIncrement stepped:
                    if (!HasAddress(stepped.Target))
                        throw Fault(
                            $"a step of {stepped.Target.GetType().Name}, which is not storage",
                            stepped.Span);
                    break;

                case BoundAddressOf { DeclaresLocal: { } introduced } address:
                    Declare(introduced, address.Span);
                    break;

                case BoundFieldAccess { Receiver: null, Field.ContainingType: StructTypeSymbol } field:
                    throw Fault("a struct field read with no struct to read it from", field.Span);

                case BoundConditional chosen:
                    if (!SameType(chosen.WhenTrue.Type, chosen.Type) ||
                        !SameType(chosen.WhenFalse.Type, chosen.Type))
                        throw Fault(
                            $"a conditional of '{chosen.Type.Name}' with arms of " +
                            $"'{chosen.WhenTrue.Type.Name}' and '{chosen.WhenFalse.Type.Name}'",
                            chosen.Span);
                    break;
            }

            if (IsUnsettled(expression.Type))
                throw Fault($"{expression.GetType().Name} of type '{expression.Type.Name}'", expression.Span);

            Representable(expression.Type, expression.Span);
            base.Visit(expression);
        }

        private void Declare(LocalSymbol local, SourceSpan span)
        {
            if (IsUnsettled(local.Type))
                throw Fault($"'{local.Name}' is declared as '{local.Type.Name}'", span);

            Representable(local.Type, span);
            _declared.Add(local);
        }

        private void Owned(ParameterSymbol parameter, SourceSpan span)
        {
            if (_captured is not null)
            {
                if (!_captured.Contains(parameter))
                    throw Fault($"'{parameter.Name}' is read by a 'for parallel' that did not capture it", span);
                return;
            }

            if (function is not null && !function.Parameters.Contains(parameter))
                throw Fault($"'{parameter.Name}' is not a parameter of '{function.Name}'", span);
        }

        /// <summary>An inline array is copied as bytes, so what it holds MUST NOT be counted.</summary>
        private static void Representable(TypeSymbol type, SourceSpan span)
        {
            if (type is FixedArrayTypeSymbol inline && inline.Element.CarriesReferences())
                throw Fault($"an inline array of '{inline.Element.Name}', which holds a counted reference", span);
        }

        /// <summary>
        /// Whether the emitter can write through this in place. Anything else
        /// it copies into a temporary first, and a write to that is lost.
        ///
        /// Not <see cref="BoundExpression.IsLValue"/>, which is what the
        /// language lets a program write: the binder's own lowerings write
        /// through names nothing else may, such as the one an object
        /// initializer holds its object in.
        /// </summary>
        private static bool HasAddress(BoundExpression place) => place switch
        {
            BoundStaticAccess or BoundLocalAccess or BoundParameterAccess or BoundThis
                or BoundDereference => true,
            BoundFieldAccess field => field.Field.ContainingType is not StructTypeSymbol ||
                                      field.Receiver is not null && HasAddress(field.Receiver),
            BoundIndex element => element.Target.Type is not FixedArrayTypeSymbol || HasAddress(element.Target),
            _ => false,
        };

        private static bool IsConstant(BoundExpression label) => label switch
        {
            BoundLiteral or BoundConstantAccess or BoundStringLiteral or BoundNullLiteral => true,
            BoundConversion conversion => IsConstant(conversion.Operand),
            _ => false,
        };

        private static bool SameType(TypeSymbol arm, TypeSymbol whole) =>
            arm.Equals(whole) || arm is NullType;

        private static InternalCompilerError Fault(string problem, SourceSpan span) =>
            new("the bound tree breaks a rule the emitter relies on: " + problem, span);
    }
}
