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
/// What may become what, implicitly and by a cast.
///
/// Also where the target-typed drafts are settled: a lambda, an array
/// literal, a variant case and a bare function name each become
/// something here or become an error.
/// </summary>
public sealed partial class Binder
{
    // ------------------------------------------------------------ conversions

    private BoundExpression BindConversion(BoundExpression expression, TypeSymbol target, SourceSpan span)
    {
        if (expression.Type.IsError() || target.IsError()) return expression;

        // A string literal may be handed straight to C: its bytes are static and
        // NUL-terminated, so there is no lifetime to get wrong. A String held in
        // a variable is a different matter, and must go through ToPointer().
        if (expression is BoundStringLiteral literal && IsBytePointer(target))
            return new BoundConversion(span, target, literal, ConversionKind.StringLiteralToPointer);

        // A function name becomes a delegate by naming the overload that matches.
        if (expression is BoundFunctionGroup group)
            return BindFunctionReference(group, target, span);

        // A lambda has no type until it is told what to be.
        if (expression is BoundLambda lambda)
            return BindLambda(lambda, target, span);

        // Nor has `Ok(x)`, for the same reason and by the same route.
        if (expression is BoundVariantDraft draft)
            return BindVariantSettle(draft, target, span);

        // Nor `[a, b, c]`.
        if (expression is BoundArrayDraft arrayDraft)
            return BindArraySettle(arrayDraft, target, span);

        // A value becomes the `Optional<T>` holding it, the way it becomes a
        // `T?` in Swift and C#. This is what lets an indexer be honest about a
        // lookup that may miss: `map[key]` answers `Optional<V>` and
        // `map[key] = value` still takes a plain one, because a getter and a
        // setter share one type (§7.5) and without this every write would read
        // `map[key] = Some(value)`.
        //
        // Desugared to the construction `Some(value)` already produces, so
        // nothing downstream learns a new shape.
        if (PromotedToOptional(expression, target) is { } some)
            return BindVariantConstruction(
                (VariantTypeSymbol)target, some, [expression], span);

        // **A folded literal is already what it is going to be.**
        //
        // A negative constant is stored as its two's complement and the type
        // says how wide that is: `-1` bound against `int` is a BoundLiteral of
        // type `int` holding 0xFFFF_FFFF_FFFF_FFFF. Converting one to its own
        // type a second time reads that back as a magnitude, finds
        // 18446744073709551615, and reports that it does not fit -- which it
        // does not, and which is not what it says.
        //
        // Nothing needs converting: it arrived as this type. The first caller
        // to find this was a default parameter value, which is bound once
        // against the parameter's type and then written into every call that
        // leaves it out, where the ordinary argument conversion runs over it
        // again -- so `int quality = -1` was an error at every such call and
        // `int quality = 1` was fine.
        if (expression is BoundLiteral or BoundConstantAccess && expression.Type.Equals(target))
            return expression;

        // A literal that fits simply adopts the target type; there is nothing to
        // convert at run time.
        if (ConstantFits(expression, target) || CharacterFits(expression, target))
            return new BoundLiteral(span, target, FoldedConstant(expression, target));

        // A conditional and a switch expression are the values they choose
        // between, so a conversion of one is a conversion of its arms:
        // `nuint n = flag ? 1 : 2` gives each literal the width a lone one
        // would have taken. Only where every arm is a literal -- an arm that is
        // computed needs the cast the author writes, here as anywhere else --
        // and an arm that does not fit then says so where it is written.
        if (target is PrimitiveTypeSymbol { IsNumeric: true } &&
            expression is BoundConditional or BoundLet &&
            ArmsAreLiterals(expression))
            return ConvertArms(expression, target, span);

        // A value written out that does not fit is a mistake, not a conversion.
        //
        // Checked here rather than left to the widening: `int` to `long` has
        // nothing to complain about, so a literal too large for a target at
        // least that wide would reach the emitter and be cut to 32 bits with
        // nothing said.
        if (target is PrimitiveTypeSymbol { IsInteger: true } &&
            IntegerLiteral(expression) is { } tooLarge)
        {
            string written = tooLarge.Negative ? "-" + tooLarge.Magnitude : $"{tooLarge.Magnitude}";
            diagnostics.Error("SL0266", span,
                $"{written} does not fit in '{target.Name}', so it cannot be one; the value is " +
                "outside the range of that type rather than in need of a conversion");
            return new BoundErrorExpression(span);
        }

        if (_builtins.IsString(expression.Type) && IsBytePointer(target))
        {
            diagnostics.Error("SL0293", span,
                "a String does not convert to 'byte*' on its own; call ToPointer() to hand its " +
                "bytes to C, and keep the String alive for as long as C holds the pointer");
            return new BoundErrorExpression(span);
        }

        // A conversion the program declared, which is a call rather than a
        // kind. Asked after everything built in, so nothing anyone writes can
        // change what an existing conversion means.
        if (UserConversion(expression, target, allowExplicit: false, span) is { } converted)
            return converted;

        var kind = ClassifyConversion(expression.Type, target, explicitCast: false);
        if (kind is null)
        {
            // Between two code unit types the generic message says what
            // happened and not why, and the why is the whole rule.
            if (expression.Type is PrimitiveTypeSymbol { IsCodeUnit: true } fromUnit &&
                target is PrimitiveTypeSymbol { IsCodeUnit: true } toUnit)
            {
                diagnostics.Error("SL0527", span, CodeUnitMessage(expression, fromUnit, toUnit));
                return new BoundErrorExpression(span);
            }

            // A double literal handed to a float is the one C# habit the cast
            // hint would send the wrong way: the fix is the suffix, not a cast.
            string hint = expression is BoundLiteral { Value: double } &&
                          target is PrimitiveTypeSymbol { Kind: PrimitiveKind.Float }
                ? $"; write it with an 'f' suffix, " +
                  $"'{expression.Span.File.Text[expression.Span.Start..expression.Span.End]}f', " +
                  "to make it a float"
                : ClassifyConversion(expression.Type, target, explicitCast: true) is not null
                    ? $"; an explicit cast '({target.Name})' would allow it"
                    : "";
            diagnostics.Error("SL0265", span,
                $"cannot convert '{expression.Type.Name}' to '{target.Name}'{hint}");
            return new BoundErrorExpression(span);
        }

        // An identity conversion still has to be recorded when the types differ,
        // as between an enum and its underlying integer: same bits, different type.
        if (kind == ConversionKind.Identity && expression.Type.Equals(target)) return expression;

        // Null adopts the target type rather than being converted at runtime.
        if (expression is BoundNullLiteral) return new BoundNullLiteral(span, target);

        return new BoundConversion(span, target, expression, kind.Value);
    }

    /// <summary>
    /// The call a declared conversion operator would make, or null when there
    /// is no such conversion.
    ///
    /// Both types are asked, because either may declare it: <c>Money</c> owns
    /// both <c>long -&gt; Money</c> and <c>Money -&gt; long</c>, and a program
    /// reading either one looks at <c>Money</c> to find out what it does.
    ///
    /// <b>One conversion, and no chain.</b> The value has to be exactly what
    /// the operator takes -- with the single exception of a literal, which
    /// adopts the source type the way it adopts any other (<c>Money m = 5;</c>
    /// where the operator takes a <c>long</c>). Anything else stays an error
    /// naming the cast that would fix it. C# composes a standard conversion
    /// with a user-defined one and gets rules nobody can hold in their head;
    /// what is here instead is a rule that fits in a sentence.
    /// </summary>
    private BoundExpression? UserConversion(
        BoundExpression expression, TypeSymbol target, bool allowExplicit, SourceSpan span)
    {
        if (expression.Type.IsError() || target.IsError()) return null;
        if (expression.Type.Equals(target)) return null;

        var candidates = FindUserConversions(expression, target, allowExplicit);

        if (candidates.Count == 0) return null;

        if (candidates.Count > 1)
        {
            diagnostics.Error("SL0616", span,
                $"two conversions turn '{expression.Type.Name}' into '{target.Name}', and " +
                "nothing here says which was meant; one of them belongs somewhere else");
            return new BoundErrorExpression(span);
        }

        var chosen = candidates[0];
        var argument = BindConversion(expression, chosen.Parameters[0].Type, span);

        return new BoundCall(span, chosen, receiver: null, [argument]);
    }

    /// <summary>
    /// Every declared conversion that could carry this value to that type.
    ///
    /// More than one is the program's mistake rather than a preference to be
    /// resolved, so nothing here ranks them; the caller reports it.
    /// </summary>
    private List<FunctionSymbol> FindUserConversions(
        BoundExpression expression, TypeSymbol target, bool allowExplicit)
    {
        var candidates = new List<FunctionSymbol>();

        foreach (var type in new[] { expression.Type, target })
        {
            if (type is not NamedTypeSymbol named) continue;

            foreach (var conversion in named.Conversions)
            {
                if (!conversion.ReturnType.Equals(target)) continue;
                if (!allowExplicit && !conversion.IsImplicitConversion) continue;

                var wanted = conversion.Parameters[0].Type;

                if (!expression.Type.Equals(wanted) && !ConstantFits(expression, wanted))
                    continue;

                if (!candidates.Contains(conversion)) candidates.Add(conversion);
            }
        }

        return candidates;
    }

    /// <summary>
    /// Whether a declared conversion could take this value to that type. Asked
    /// by overload resolution, which decides whether a call is possible before
    /// it decides what it means.
    /// </summary>
    private bool HasUserConversion(BoundExpression expression, TypeSymbol target) =>
        FindUserConversions(expression, target, allowExplicit: false).Count > 0;

    /// <summary>
    /// Resolves a bare function name against the delegate it is being stored in.
    /// Overloads are separated by the signature the delegate asks for, which is
    /// the only context a bare name has.
    /// </summary>
    private BoundExpression BindFunctionReference(
        BoundFunctionGroup group, TypeSymbol target, SourceSpan span)
    {
        if (target is ClosureTypeSymbol closure)
            return BindClosureReference(group, closure, span);

        if (target is not DelegateTypeSymbol wanted)
        {
            // A bound method offered as a group and settled by nothing: the
            // message that was here before groups carried a receiver.
            if (group.Receiver is not null)
            {
                diagnostics.Error("SL0250", span,
                    $"'{group.Name}' is a method; call it with '()', or store it in a " +
                    "'closure' type, which is what can hold a method and its object");
                return new BoundErrorExpression(span);
            }

            diagnostics.Error("SL0360", span,
                $"'{group.Name}' is a function; it converts to a delegate type, " +
                $"and '{target.Name}' is not one");
            return new BoundErrorExpression(span);
        }

        if (group.Receiver is not null)
        {
            diagnostics.Error("SL0360", span,
                $"'{group.Name}' is a method, so it carries the object it was reached " +
                $"through, and '{wanted.Name}' is a delegate -- one pointer, with nowhere " +
                "to keep it. Declare the type 'closure' instead of 'delegate'");
            return new BoundErrorExpression(span);
        }

        var matches = group.Candidates.Where(wanted.Accepts).ToList();

        if (matches.Count == 0)
        {
            diagnostics.Error("SL0361", span,
                $"no overload of '{group.Name}' matches delegate '{wanted.Name}', " +
                $"which is '{wanted.SignatureText}'");
            return new BoundErrorExpression(span);
        }

        if (matches.Count > 1)
        {
            diagnostics.Error("SL0362", span,
                $"'{group.Name}' is ambiguous for delegate '{wanted.Name}'");
            return new BoundErrorExpression(span);
        }

        return new BoundFunctionReference(span, wanted, matches[0]);
    }

    /// <summary>
    /// Resolves a function or bound method against the closure it is being
    /// stored in.
    ///
    /// The receiver is not part of the match. A closure's signature says what
    /// the *call* takes, and the object is what the closure carries, so a
    /// method of any type fits a closure of the right shape -- which is the
    /// whole reason a component's handler need not know what it is subscribed
    /// to.
    /// </summary>
    private BoundExpression BindClosureReference(
        BoundFunctionGroup group, ClosureTypeSymbol wanted, SourceSpan span)
    {
        // An instance method is a candidate only with the object it was reached
        // through. No name reaches one without it today -- a bare method name
        // inside its class is not a group -- and this keeps it that way should
        // one start to, rather than handing the method a null receiver.
        var matches = group.Candidates
            .Where(wanted.Accepts)
            .Where(f => group.Receiver is not null || f.IsStatic || f.ContainingType is null)
            .ToList();

        if (matches.Count == 0)
        {
            diagnostics.Error("SL0361", span,
                $"no overload of '{group.Name}' matches closure '{wanted.Name}', " +
                $"which is '{wanted.SignatureText}'");
            return new BoundErrorExpression(span);
        }

        if (matches.Count > 1)
        {
            diagnostics.Error("SL0362", span,
                $"'{group.Name}' is ambiguous for closure '{wanted.Name}'");
            return new BoundErrorExpression(span);
        }

        var chosen = matches[0];

        // A closure calls what it holds with the object first, which is where a
        // method already takes its own. A plain function has no such parameter,
        // so its address cannot go in that slot; a thunk that takes one and
        // ignores it can, with null for the object.
        if (chosen.IsStatic || chosen.ContainingType is null)
            return new BoundClosureCreate(span, wanted, ThunkFor(chosen), receiver: null);

        return new BoundClosureCreate(span, wanted, chosen, group.Receiver);
    }

    /// <summary>
    /// The one thunk per plain function that lets a closure hold it: a function
    /// taking an ignored receiver first, then the function's own parameters,
    /// and passing them straight on.
    ///
    /// <para>
    /// This used to be refused (SL0599), with "wrap it in a lambda" as the way
    /// out -- which is exactly what this writes, except that a lambda is a new
    /// class and a new object at every mention. A thunk shared by every mention
    /// and a null receiver instead cost no allocation, and they keep what
    /// closure equality promises: two mentions of <c>Upper</c> are equal, so
    /// one subscribed with <c>+=</c> can be removed with <c>-=</c>.
    /// </para>
    /// </summary>
    private FunctionSymbol ThunkFor(FunctionSymbol function)
    {
        if (_thunks.TryGetValue(function, out var existing)) return existing;

        var thunk = new FunctionSymbol
        {
            Name = $"Thunk.{_closureCount++}",
            ModuleName = _currentModule!.Name,
            ReturnType = function.ReturnType,
            Linkage = LinkageKind.Stainless,
            IsPublic = false,
            Span = function.Span,
            Scope = _currentScope,
        };

        var ignored = new PointerTypeSymbol(PrimitiveTypeSymbol.Byte);
        thunk.Parameters.Add(new ParameterSymbol("receiver", ignored, 0));

        var forwarded = new List<BoundExpression>();
        foreach (var parameter in function.Parameters.Where(p => !p.IsThis))
        {
            var own = new ParameterSymbol(parameter.Name, parameter.Type, thunk.Parameters.Count)
            {
                Mode = parameter.Mode,
            };
            thunk.Parameters.Add(own);

            BoundExpression access = new BoundParameterAccess(function.Span, own);

            // A parameter passed by address is the caller's storage already, and
            // the address of it is what the function wants in turn.
            forwarded.Add(own.IsByReference
                ? new BoundAddressOf(function.Span, new PointerTypeSymbol(own.Type), access)
                {
                    FromRefKeyword = own.Mode == ParameterMode.Ref,
                    FromOutKeyword = own.Mode == ParameterMode.Out,
                }
                : access);
        }

        var call = new BoundCall(function.Span, function, receiver: null, forwarded);
        BoundStatement statement = function.ReturnType.IsVoid()
            ? new BoundExpressionStatement(function.Span, call)
            : new BoundReturn(function.Span, call);

        _functions.Add(new BoundFunction(thunk, new BoundBlock(function.Span, [statement])));
        _thunks[function] = thunk;
        return thunk;
    }

    private readonly Dictionary<FunctionSymbol, FunctionSymbol> _thunks = [];

    /// <summary>
    /// Whether every value this could produce is written out as a number.
    ///
    /// A conditional produces one of its arms and a switch expression is a
    /// chain of conditionals held in a name, so neither has a value of its own
    /// for a conversion to act on. Asking the arms is what makes
    /// <c>nuint n = flag ? 1 : 2</c> mean what <c>nuint n = 1</c> means.
    /// </summary>
    private static bool ArmsAreLiterals(BoundExpression expression) => expression switch
    {
        BoundConditional choice =>
            ArmsAreLiterals(choice.WhenTrue) && ArmsAreLiterals(choice.WhenFalse),
        BoundLet held => ArmsAreLiterals(held.Body),
        _ => IntegerLiteral(expression) is not null ||
             expression is BoundLiteral { Type: PrimitiveTypeSymbol { IsNumeric: true } },
    };

    /// <summary>
    /// The same expression with each arm converted, which is where an arm that
    /// does not fit reports it.
    /// </summary>
    private BoundExpression ConvertArms(
        BoundExpression expression, TypeSymbol target, SourceSpan span) => expression switch
    {
        BoundConditional choice => new BoundConditional(
            choice.Span, target, choice.Condition,
            ConvertArms(choice.WhenTrue, target, choice.WhenTrue.Span),
            ConvertArms(choice.WhenFalse, target, choice.WhenFalse.Span)),

        BoundLet held => new BoundLet(
            held.Span, held.Local, held.Value, ConvertArms(held.Body, target, span)),

        _ => BindConversion(expression, target, span),
    };

    /// <summary>
    /// Whether an integer literal fits the target type exactly, as in C#, where
    /// <c>byte b = 200;</c> and <c>nuint n = 5;</c> need no cast because the
    /// compiler can see the value. Only a literal qualifies: anything computed
    /// still needs an explicit cast.
    /// </summary>
    private static bool ConstantFits(BoundExpression expression, TypeSymbol target)
    {
        if (IntegerLiteral(expression) is not { } written) return false;

        // A float or a double holds any integer that can be written, rounding
        // if it must, exactly as C# does. It has to be said here rather than
        // left to the ordinary int-to-float conversion, because every integer
        // literal starts out an `int`: `double d = 5000000000;` reached the
        // emitter as an `int` holding a value no `int` holds, and came out
        // 705032704 -- a valid program, quietly given a different number.
        if (target is PrimitiveTypeSymbol { IsFloat: true }) return true;

        if (target is not PrimitiveTypeSymbol { IsInteger: true } integer) return false;

        // A minus over a literal is a unary operation to the parser, and a
        // negative literal to the reader: `sbyte c = -100;` is as plain as
        // `byte b = 200;`. The magnitude is measured against the signed floor,
        // which is one further out than the ceiling: `-128` fits an sbyte.
        if (written.Negative)
        {
            if (written.Magnitude == 0) return true;
            if (!integer.IsSigned) return false;
            ulong floor = integer.Size >= 8 ? 1UL << 63 : 1UL << (integer.Bits - 1);
            return written.Magnitude <= floor;
        }

        ulong maximum = integer.Size >= 8
            ? (integer.IsSigned ? long.MaxValue : ulong.MaxValue)
            : (1UL << (integer.Bits - (integer.IsSigned ? 1 : 0))) - 1;

        return written.Magnitude <= maximum;
    }

    /// <summary>
    /// An integer literal, with or without a minus in front of it, or null
    /// when the expression is neither.
    /// </summary>
    private static (ulong Magnitude, bool Negative)? IntegerLiteral(BoundExpression expression)
    {
        if (NegatedLiteral(expression) is { } magnitude) return (magnitude, true);

        if (InlinedInteger(expression) is not { } inlined) return null;

        // A negative value is held as its two's complement, sign-extended to a
        // word, and the type is what says the top bit is a sign. Read as a
        // magnitude it would be a number every unsigned type holds, so `-1`
        // would fit a `nuint`.
        return inlined.Written.IsSigned && (inlined.Bits & (1UL << 63)) != 0
            ? (unchecked(0UL - inlined.Bits), true)
            : (inlined.Bits, false);
    }

    /// <summary>
    /// The bits of a value written out in the source, with the type it was
    /// written as, or null for anything computed.
    ///
    /// A <c>const</c> answers here as well as a literal, because a constant is
    /// a value inlined at every use: <c>const int Limit = 64;</c> makes
    /// <c>nuint size = Limit;</c> as plain as <c>nuint size = 64;</c>, and C#
    /// reads one the same way. An enum member does not, since its type is the
    /// enum rather than a number.
    /// </summary>
    private static (ulong Bits, PrimitiveTypeSymbol Written)? InlinedInteger(
        BoundExpression expression)
    {
        (object? value, TypeSymbol? type) = expression switch
        {
            BoundLiteral literal => (literal.Value, literal.Type),
            BoundConstantAccess named => (named.Constant.Value, named.Constant.Type),
            _ => ((object?)null, null),
        };

        // A code unit is held as a scalar rather than as a width, and the three
        // encodings are kept apart by SL0527 rather than by whether a number
        // fits. Reading one here would answer that question first and with the
        // wrong code.
        return type is PrimitiveTypeSymbol { IsInteger: true } written && value is ulong bits
            ? (bits, written)
            : null;
    }

    /// <summary>
    /// The <c>Some</c> case an expression would be wrapped in to become
    /// <paramref name="target"/>, or null when no such promotion applies.
    ///
    /// Recognised by shape, as <c>Result</c> is: a variant whose template is
    /// named <c>Optional</c>, with a <c>None</c> carrying nothing and a
    /// <c>Some</c> carrying one field. The compiler knowing a library type is
    /// not new -- <c>try</c> knows <c>Result</c> the same way -- and this is
    /// the price of `Optional&lt;T&gt;` being an ordinary variant rather than
    /// a second spelling of <c>T?</c>.
    ///
    /// Something already of the target type is left alone, so an
    /// <c>Optional&lt;T&gt;</c> assigned to one is not wrapped twice. An
    /// <c>Optional&lt;T&gt;</c> assigned to an
    /// <c>Optional&lt;Optional&lt;T&gt;&gt;</c> is, which is what it means.
    /// </summary>
    private VariantCaseSymbol? PromotedToOptional(BoundExpression expression, TypeSymbol target)
    {
        if (target is not VariantTypeSymbol { Template.Name: "Optional" } optional) return null;
        if (expression.Type.Equals(target) || expression.Type.IsError()) return null;
        if (expression.Type.IsVoid()) return null;

        if (optional.FindCase("None") is not { Fields.Count: 0 }) return null;
        if (optional.FindCase("Some") is not { Fields.Count: 1 } some) return null;

        // Only when the value can actually be stored in the payload. Without
        // this every mismatched assignment to an Optional would report the
        // payload's complaint rather than its own.
        return IsImplicitlyConvertible(expression, some.Fields[0].Type) ? some : null;
    }

    /// <summary>
    /// The magnitude of an integer literal under a single minus, or null when
    /// the expression is not that shape.
    /// </summary>
    private static ulong? NegatedLiteral(BoundExpression expression) =>
        expression is BoundUnary
        {
            Operator: BoundUnaryOp.Negate,
            Operand: BoundLiteral { Value: ulong magnitude } written,
        } && written.Type is PrimitiveTypeSymbol { IsInteger: true }
            ? magnitude
            : null;

    /// <summary>
    /// The value a fitting literal carries into its new type.
    ///
    /// For an integer target that is the literal's own value, or the two's
    /// complement of a negated one, which is the shape the emitter already
    /// narrows to the declared width. For a float target it is the number
    /// itself, held as one, because a <c>double</c> holding a <c>ulong</c>
    /// would reach the emitter as an integer spelled where a float belongs.
    /// </summary>
    private static object? FoldedConstant(BoundExpression expression, TypeSymbol target)
    {
        if (IntegerLiteral(expression) is { } written &&
            target is PrimitiveTypeSymbol { IsFloat: true } number)
        {
            double value = written.Negative ? -(double)written.Magnitude : written.Magnitude;
            return number.Kind == PrimitiveKind.Float ? (float)value : value;
        }

        if (NegatedLiteral(expression) is { } magnitude) return unchecked(0UL - magnitude);

        return InlinedInteger(expression) is { } inlined
            ? inlined.Bits
            : ((BoundLiteral)expression).Value;
    }

    /// <summary>
    /// Whether a character literal may simply adopt <paramref name="target"/>.
    ///
    /// The literal is a scalar, and each code unit type holds a different range
    /// of them in a single unit: <c>char</c> is one UTF-8 byte and so stops at
    /// U+007F, <c>char16</c> is one UTF-16 unit and so stops below the
    /// surrogates' own range, and <c>char32</c> holds every scalar there is.
    /// Any other integer takes it as the number it is, which is what makes
    /// <c>const int Tab = '	';</c> work.
    /// </summary>
    private static bool CharacterFits(BoundExpression expression, TypeSymbol target)
    {
        if (expression is not BoundLiteral { Value: int scalar }) return false;
        if (expression.Type is not PrimitiveTypeSymbol { IsCodeUnit: true }) return false;
        if (target is not PrimitiveTypeSymbol { IsInteger: true } integer) return false;

        return integer.Kind switch
        {
            PrimitiveKind.Char => scalar < 0x80,
            PrimitiveKind.Char16 => scalar < 0x10000,
            PrimitiveKind.Char32 => true,
            _ => integer.Size >= 4 ||
                 scalar <= (1 << (integer.Bits - (integer.IsSigned ? 1 : 0))) - 1,
        };
    }

    /// <summary>
    /// Why one code unit type will not become another.
    ///
    /// A character literal that does not fit gets the specific answer, because
    /// the scalar is known and the count of units it needs is the argument.
    /// Anything else gets the general one.
    /// </summary>
    private static string CodeUnitMessage(
        BoundExpression expression, PrimitiveTypeSymbol from, PrimitiveTypeSymbol to)
    {
        string wider = to.Kind == PrimitiveKind.Char ? "'char16' or 'char32'" : "'char32'";

        if (expression is BoundLiteral { Value: int scalar })
        {
            int units = to.Kind switch
            {
                PrimitiveKind.Char => Utf8Length(scalar),
                PrimitiveKind.Char16 => scalar >= 0x10000 ? 2 : 1,
                _ => 1,
            };
            string unitName = to.Kind == PrimitiveKind.Char ? "bytes of UTF-8" : "UTF-16 units";

            return $"U+{scalar:X4} takes {units} {unitName}, so it is not one '{to.Name}'; " +
                   $"declare it {wider}";
        }

        return $"'{from.Name}' and '{to.Name}' are different encodings, not different widths " +
               $"of one, so one does not become the other on its own; a cast '({to.Name})' " +
               "moves the bits across and re-encodes nothing";
    }

    private static int Utf8Length(int scalar) =>
        scalar < 0x80 ? 1 : scalar < 0x800 ? 2 : scalar < 0x10000 ? 3 : 4;

    /// <summary>True for <c>byte*</c>, the shape C expects for text.</summary>
    private static bool IsBytePointer(TypeSymbol type) =>
        type is PointerTypeSymbol { Element: PrimitiveTypeSymbol { Kind: PrimitiveKind.Byte } };

    /// <summary>
    /// Whether an object behind <paramref name="wanted"/> could be a
    /// <paramref name="candidate"/>.
    ///
    /// True when the class implements the interface itself, and true for any
    /// unsealed class, since something below it may implement what it does not.
    /// False only for a sealed class that does not -- the one case where the
    /// test could never hold, and so the one worth refusing.
    /// </summary>
    private static bool CouldImplement(ClassTypeSymbol candidate, InterfaceTypeSymbol wanted) =>
        candidate.AllInterfaces().Contains(wanted) || !candidate.IsSealed;

    /// <summary>
    /// Returns how to get from <paramref name="from"/> to <paramref name="to"/>,
    /// or null when no such conversion exists.
    /// </summary>
    private ConversionKind? ClassifyConversion(TypeSymbol from, TypeSymbol to, bool explicitCast)
    {
        if (from.Equals(to)) return ConversionKind.Identity;

        // null literal -> any nullable representation. A delegate is a raw
        // function pointer, so a null one is exactly C's null callback.
        if (from is NullType)
            return to is PointerTypeSymbol or OptionalTypeSymbol or WeakTypeSymbol or DelegateTypeSymbol
                ? ConversionKind.NullToReference
                : null;

        // Two closure types of the same signature are the same two words, and
        // one of them may be the type a lambda was given rather than one
        // anybody declared. Nothing is emitted: the layout is identical, and
        // so is the reference walk that counts the receiver.
        if (from is ClosureTypeSymbol fromClosure && to is ClosureTypeSymbol toClosure &&
            fromClosure.ReturnType.Equals(toClosure.ReturnType) &&
            fromClosure.Signature.Count == toClosure.Signature.Count &&
            !fromClosure.Signature.Where(
                (p, i) => !p.Type.Equals(toClosure.Signature[i].Type) ||
                          p.Mode != toClosure.Signature[i].Mode).Any())
            return ConversionKind.Identity;

        // The whole of an array, as a slice of it.
        if (from is ArrayTypeSymbol whole && to is SliceTypeSymbol asSlice)
            return whole.Element.Equals(asSlice.Element) ? ConversionKind.ArrayToSlice : null;

        // A derived class is a base class. With single inheritance the base
        // subobject starts where the object does, so this is the same pointer
        // and emits nothing; the other direction is a check.
        if (from is ClassTypeSymbol fromDerived && to is ClassTypeSymbol toBase)
        {
            if (fromDerived.DerivesFrom(toBase)) return ConversionKind.Upcast;
            return explicitCast && toBase.DerivesFrom(fromDerived)
                ? ConversionKind.Downcast
                : null;
        }

        // A pointer COM wrote through a void**, taken into ARC's care. The
        // other direction is an ordinary pointer cast, and byte* is the
        // language's void*, so it needs no rule of its own.
        if (from is PointerTypeSymbol && to is ComInterfaceTypeSymbol)
            return explicitCast ? ConversionKind.ComAdopt : null;

        if (from is ComInterfaceTypeSymbol && to is PointerTypeSymbol)
            return explicitCast || IsBytePointer(to) ? ConversionKind.PointerCast : null;

        // Between com interfaces the vtable is the prefix rather than the
        // object, so a derived reference already satisfies the base and the
        // other direction is a QueryInterface.
        if (from is ComInterfaceTypeSymbol fromCom && to is ComInterfaceTypeSymbol toCom)
        {
            if (fromCom.DerivesFrom(toCom)) return ConversionKind.ComUpcast;

            // A QueryInterface is a call through slot 0, and a `[NoUnknown]`
            // vtable has something else there. The cast is refused rather than
            // emitted as a call to whatever that turned out to be.
            if (!fromCom.HasUnknown || !toCom.HasUnknown) return null;

            return explicitCast ? ConversionKind.ComQuery : null;
        }

        // A com class, as one of the interfaces it presents. Not free: what the
        // caller gets is the tear-off's address, which is inside the object.
        if (from is ClassTypeSymbol { IsCom: true } presenting &&
            to is ComInterfaceTypeSymbol presented)
            return presenting.ComInterfaces.Contains(presented) ||
                   presented == _builtins.Unknown
                ? ConversionKind.ComTearOff
                : null;

        // A class converts to any interface it implements, and an interface to
        // any it extends. Because a reference is the same pointer either way,
        // this costs nothing at run time.
        if (from is NamedTypeSymbol { IsReferenceType: true } source2 && to is InterfaceTypeSymbol wanted)
            return source2.AllInterfaces().Contains(wanted) ? ConversionKind.ClassToInterface : null;

        // And back down again, which is the same check a class downcast is.
        //
        // An interface reference *is* the object pointer -- the vtable hangs off
        // the object's TypeInfo rather than travelling beside the reference --
        // so asking whether it points at a particular class is the question
        // 'sl_is_instance' already answers, and the pointer that comes back is
        // the one that went in. Nothing new is emitted for this.
        //
        // Refused where it could never hold: a sealed class that does not
        // implement the interface can never be behind one. An unsealed one is
        // allowed, because something deriving from it may implement the
        // interface even when it does not itself.
        if (from is InterfaceTypeSymbol implemented && to is ClassTypeSymbol behind)
            return explicitCast && CouldImplement(behind, implemented)
                ? ConversionKind.Downcast
                : null;

        if (from is ClassTypeSymbol optionalImplementer &&
            to is OptionalTypeSymbol { Element: InterfaceTypeSymbol optionalWanted })
            return optionalImplementer.Interfaces.Contains(optionalWanted)
                ? ConversionKind.ClassToInterface
                : null;

        // C -> C?  and  weak C? -> C? are reference identities at runtime, and
        // so is Derived -> Base?, which is both conversions at once and neither
        // of them any instructions.
        if (from is ClassTypeSymbol fromClass && to is OptionalTypeSymbol toOptional)
            return toOptional.Element is ClassTypeSymbol optionalBase && fromClass.DerivesFrom(optionalBase)
                ? ConversionKind.ReferenceToOptional
                : null;

        // Derived? -> Base?, for the same reason.
        if (from is OptionalTypeSymbol { Element: ClassTypeSymbol optionalDerived } &&
            to is OptionalTypeSymbol { Element: ClassTypeSymbol optionalWantedBase } &&
            optionalDerived.DerivesFrom(optionalWantedBase))
            return ConversionKind.Upcast;

        if (from is InterfaceTypeSymbol fromInterface && to is OptionalTypeSymbol toOptionalInterface)
            return fromInterface.Equals(toOptionalInterface.Element)
                ? ConversionKind.ReferenceToOptional
                : null;

        // I -> I?, and IDerived -> IBase?, both of which are the same pointer.
        if (from is ComInterfaceTypeSymbol fromComReference &&
            to is OptionalTypeSymbol { Element: ComInterfaceTypeSymbol wantedCom } &&
            fromComReference.DerivesFrom(wantedCom))
            return ConversionKind.ReferenceToOptional;

        // A com class straight to an optional interface, which is the two
        // conversions above at once and still one add.
        if (from is ClassTypeSymbol { IsCom: true } presentingOptional &&
            to is OptionalTypeSymbol { Element: ComInterfaceTypeSymbol optionalPresented } &&
            (presentingOptional.ComInterfaces.Contains(optionalPresented) ||
             optionalPresented == _builtins.Unknown))
            return ConversionKind.ComTearOff;

        if (from is WeakTypeSymbol fromWeak && to is OptionalTypeSymbol weakTarget)
            return fromWeak.Element.Equals(weakTarget.Element) ? ConversionKind.ReferenceToOptional : null;

        // C -> weak C?  and  C? -> weak C?. This is the only way to break a
        // reference cycle, since ARC cannot collect one, so it is implicit: the
        // weak slot already says what is meant, and requiring a cast as well
        // would put punctuation between the programmer and the one escape hatch
        // they have.
        if (to is WeakTypeSymbol toWeak)
        {
            var referenced = from is OptionalTypeSymbol weakSource ? weakSource.Element : from;
            return referenced is NamedTypeSymbol { IsReferenceType: true } &&
                   referenced.Equals(toWeak.Element)
                ? ConversionKind.ReferenceToWeak
                : null;
        }

        // C? -> C discards a null check, so it must be explicit.
        if (from is OptionalTypeSymbol fromOptional && to is NamedTypeSymbol { IsReferenceType: true })
        {
            if (!explicitCast) return null;
            if (fromOptional.Element.Equals(to)) return ConversionKind.PointerCast;

            // I? -> C, which loses the null and asks the object what it is, on
            // the same terms as the interface-to-class rule above.
            if (fromOptional.Element is InterfaceTypeSymbol optionalInterface &&
                to is ClassTypeSymbol optionalBehind)
                return CouldImplement(optionalBehind, optionalInterface)
                    ? ConversionKind.Downcast
                    : null;

            // Derived? -> Base loses the null and nothing else; Base? -> Derived
            // loses the null and checks what is left.
            return fromOptional.Element is ClassTypeSymbol optionalSource && to is ClassTypeSymbol castTarget
                ? optionalSource.DerivesFrom(castTarget) ? ConversionKind.PointerCast
                  : castTarget.DerivesFrom(optionalSource) ? ConversionKind.Downcast
                  : null
                : null;
        }

        if (from is PointerTypeSymbol && to is PointerTypeSymbol)
        {
            // Any pointer converts to byte* implicitly, mirroring C's void*.
            bool toBytePointer = to is PointerTypeSymbol { Element: PrimitiveTypeSymbol { Kind: PrimitiveKind.Byte } };
            return explicitCast || toBytePointer ? ConversionKind.PointerCast : null;
        }

        // A pointer and a delegate, explicitly, in either direction.
        //
        // **This is what dynamic loading is made of.** `GetProcAddress` and
        // `dlsym` answer a `void*`, and the only useful thing to do with one is
        // call it -- which needs a delegate, because a delegate is exactly a C
        // function pointer and nothing else (§2.14). Without this the idiom was
        // `*(Fn*)&symbol`: correct, and a line that reads as a mistake and gets
        // copied as one. `Standard.Drawing` resolves thirty symbols this way.
        //
        // Explicit only, and never implicit. Nothing about a `void*` says it
        // points at code, let alone at code of this signature, so the cast is
        // an assertion by the programmer -- the same bargain the reference
        // conversions below already make, and the reason both directions are
        // spelled out rather than inferred.
        if (from is PointerTypeSymbol && to is DelegateTypeSymbol)
            return explicitCast ? ConversionKind.PointerCast : null;

        if (from is DelegateTypeSymbol && to is PointerTypeSymbol)
            return explicitCast ? ConversionKind.PointerCast : null;

        // A reference to a raw pointer, explicitly. Reflection needs it to read an
        // instance by field offset; the result is uncounted, so keep the
        // reference alive for as long as the pointer is used.
        if (from is NamedTypeSymbol { IsReferenceType: true } or ArrayTypeSymbol &&
            to is PointerTypeSymbol)
            return explicitCast ? ConversionKind.PointerCast : null;

        // And back again, which is what lets a C callback recover the object it
        // was given as context. Nothing checks that the pointer really points at
        // one of these, so the cast is an assertion by the programmer -- the same
        // bargain the other direction already makes.
        if (from is PointerTypeSymbol &&
            to is NamedTypeSymbol { IsReferenceType: true } or ArrayTypeSymbol)
            return explicitCast ? ConversionKind.PointerCast : null;

        // An integer that is at least as wide as a pointer, in either
        // direction. **Pointer width, not eight.** This said `Size: 8` and so
        // asked a question about the host rather than about the target: on a
        // 32-bit build `nuint` is four bytes, so the one type whose whole
        // purpose is to hold a pointer was the one refused, while `ulong` --
        // which is wider than the pointer it would be truncated into -- was
        // allowed. That made `(char16*)(nuint)id` a compile error for x86, and
        // `bindings/win32` is written in exactly that idiom: `CursorArrow`,
        // `InvalidHandle` and `TreeRoot` are all a number cast to a handle.
        if (from is PointerTypeSymbol &&
            to is PrimitiveTypeSymbol { IsInteger: true } intTarget &&
            intTarget.Size >= TargetPlatform.Current.PointerWidth)
            return explicitCast ? ConversionKind.PointerToInteger : null;

        if (from is PrimitiveTypeSymbol { IsInteger: true } intSource &&
            intSource.Size >= TargetPlatform.Current.PointerWidth &&
            to is PointerTypeSymbol)
            return explicitCast ? ConversionKind.IntegerToPointer : null;

        // An enum never converts implicitly, in either direction. That is the
        // whole point of declaring one: a Level is not a byte that happens to be
        // small, and a byte is not a Level. An explicit cast is still available,
        // which is what interop and serialization need.
        if (from is EnumTypeSymbol || to is EnumTypeSymbol)
        {
            if (!explicitCast) return null;

            var fromCore = from is EnumTypeSymbol fromEnum ? fromEnum.UnderlyingType : from;
            var toCore = to is EnumTypeSymbol toEnum ? toEnum.UnderlyingType : to;

            if (fromCore is not PrimitiveTypeSymbol { IsInteger: true } ||
                toCore is not PrimitiveTypeSymbol { IsInteger: true })
                return null;

            return ClassifyConversion(fromCore, toCore, explicitCast: true);
        }

        if (from is not PrimitiveTypeSymbol source || to is not PrimitiveTypeSymbol target) return null;
        if (source.Kind == PrimitiveKind.Void || target.Kind == PrimitiveKind.Void) return null;

        if (source.Kind == PrimitiveKind.Bool)
            return target.IsInteger && explicitCast ? ConversionKind.BoolToInteger : null;
        if (target.Kind == PrimitiveKind.Bool) return null;

        if (source.IsFloat && target.IsFloat)
            return target.Size >= source.Size || explicitCast ? ConversionKind.FloatResize : null;

        if (source.IsInteger && target.IsFloat)
            return ConversionKind.IntToFloat;               // implicit, as in C#

        if (source.IsFloat && target.IsInteger)
            return explicitCast ? ConversionKind.FloatToInt : null;

        // char, char16 and char32 are three encodings, not three widths of one
        // type. 'e' is one byte of UTF-8, one UTF-16 unit and one scalar; 'e'
        // with an acute accent is two, one and one; an emoji is four, two and
        // one. So widening one to another re-encodes nothing and produces a
        // unit that means something else, which is a bug a cast should have to
        // spell. Against every other integer they behave as integers.
        if (source.IsCodeUnit && target.IsCodeUnit && source.Kind != target.Kind && !explicitCast)
            return null;

        if (source.IsInteger && target.IsInteger)
        {
            if (target.Size > source.Size && (source.IsSigned == target.IsSigned || !source.IsSigned))
                return ConversionKind.IntegerWiden;
            if (target.Size == source.Size && source.IsSigned == target.IsSigned)
                return ConversionKind.Identity;
            if (!explicitCast) return null;
            return target.Size >= source.Size ? ConversionKind.IntegerWiden : ConversionKind.IntegerNarrow;
        }

        return null;
    }
}
