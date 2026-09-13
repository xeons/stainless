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
/// Expressions that are not a call and not a member access: literals,
/// names, operators, assignment, indexing and slicing.
/// </summary>
public sealed partial class Binder
{
    // ------------------------------------------------------------ expressions

    /// <summary>
    /// How deep the walk over one expression or statement currently is. See
    /// <see cref="Source.Recursion"/>: the parser bounds what it builds, and
    /// this bounds what a tree from anywhere else -- a lowering, a generic
    /// instantiated into a new shape -- can ask the binder to walk.
    /// </summary>
    private int _bindDepth;

    private bool _boundTooDeep;

    private BoundExpression BindExpression(ExpressionSyntax syntax)
    {
        if (++_bindDepth > Source.Recursion.MaxDepth)
        {
            _bindDepth--;

            if (!_boundTooDeep)
            {
                _boundTooDeep = true;
                diagnostics.Error("SL0108", syntax.Span,
                    $"this is nested more than {Source.Recursion.MaxDepth} levels deep, which " +
                    "is past what can be compiled; the usual cause is generated source, and " +
                    "the fix is to give the inner part a name of its own");
            }

            return new BoundErrorExpression(syntax.Span);
        }

        try { return BindExpressionCore(syntax); }
        finally { _bindDepth--; }
    }

    private BoundExpression BindExpressionCore(ExpressionSyntax syntax) => syntax switch
    {
        LiteralSyntax literal => BindLiteral(literal),
        NameSyntax name => BindName(name),
        ThisSyntax thisExpression => BindThis(thisExpression),
        BaseSyntax baseExpression => BindBaseValue(baseExpression),
        TypeTestSyntax typeTest => BindTypeTest(typeTest),
        UnarySyntax unary => BindUnary(unary),
        IncrementSyntax increment => BindIncrement(increment),
        NameofSyntax nameOf => BindNameof(nameOf),
        CheckedSyntax guarded => BindChecked(guarded),
        DefaultSyntax zeroed => BindDefault(zeroed),
        TupleSyntax tuple => BindTuple(tuple),
        BinarySyntax binary => BindBinary(binary),
        AssignmentSyntax assignment => BindAssignment(assignment),
        CallSyntax call => BindCall(call),
        MemberAccessSyntax member => BindMemberAccess(member),
        SliceSyntax slice => BindSlice(slice),
        IndexSyntax index => BindIndex(index),
        NewSyntax newExpression => BindNew(newExpression),
        NewArraySyntax newArray => BindNewArray(newArray),
        ConditionalSyntax conditional => BindConditional(conditional),
        LambdaSyntax lambda => new BoundLambda(lambda.Span, LambdaType.Instance, lambda),
        InterpolatedStringSyntax interpolated => BindInterpolatedString(interpolated),
        TrySyntax attempt => BindTry(attempt),
        ArrayLiteralSyntax array => BindArrayLiteral(array),
        CastSyntax cast => BindCast(cast),
        SizeofSyntax sizeofExpression => BindSizeof(sizeofExpression),
        AlignofSyntax alignofExpression => BindAlignof(alignofExpression),
        OffsetofSyntax offsetofExpression => BindOffsetof(offsetofExpression),
        TypeofSyntax typeofExpression => BindTypeof(typeofExpression),
        IidofSyntax iidofExpression => BindIidof(iidofExpression),
        _ => new BoundErrorExpression(syntax.Span),
    };

    /// <summary>
    /// <c>$"a {b} c"</c>: the literal pieces as they are, and every hole
    /// converted to a String.
    ///
    /// The conversion is the whole of the design question, and the answer here
    /// is the narrow one: a String goes through, a primitive uses the
    /// <c>Text.From*</c> that already exists for it, and anything else is an
    /// error naming what to write. Stainless has no universal <c>ToString</c>,
    /// and inventing one to make this work would be a much larger decision
    /// than a formatting syntax -- every class would owe one, and a default
    /// that printed a type name would be worse than nothing.
    /// </summary>
    private BoundExpression BindInterpolatedString(InterpolatedStringSyntax syntax)
    {
        var parts = new List<BoundExpression>();
        bool literalOnly = true;

        foreach (var part in syntax.Parts)
        {
            if (part.Literal is { } text)
            {
                if (text.Length > 0)
                    parts.Add(new BoundStringLiteral(syntax.Span, _builtins.String, text));
                continue;
            }

            literalOnly = false;

            var value = BindExpression(part.Value!);
            parts.Add(AsText(value, part.Value!.Span));
        }

        // Nothing was interpolated, so this is a string literal with an
        // awkward spelling and should cost what one costs.
        if (literalOnly)
            return new BoundStringLiteral(
                syntax.Span, _builtins.String,
                string.Concat(syntax.Parts.Select(p => p.Literal ?? "")));

        return new BoundInterpolatedString(syntax.Span, _builtins.String, parts);
    }

    /// <summary>One interpolated value as a String, or an error saying why not.</summary>
    private BoundExpression AsText(BoundExpression value, SourceSpan span)
    {
        if (value.Type.IsError()) return value;
        if (_builtins.IsString(value.Type)) return value;

        // An enum is a distinct type and does not become its integer on its own
        // (SL0410), and writing the number would rarely be what was wanted
        // anyway -- the member's name would be, and nothing records those yet.
        if (value.Type is EnumTypeSymbol enumType)
        {
            diagnostics.Error("SL0557", span,
                $"'{enumType.Name}' is an enum, and an interpolation would have to write its " +
                "number rather than its name -- nothing records a member's name yet. Cast it, " +
                "as in '(long)value', or write the name you meant");
            return new BoundErrorExpression(span);
        }

        // A code unit is not a character, and the cast that says which is
        // meant is the same one SL0527 asks for everywhere else.
        if (value.Type is PrimitiveTypeSymbol
            { Kind: PrimitiveKind.Char or PrimitiveKind.Char16 } unit)
        {
            diagnostics.Error("SL0557", span,
                $"'{unit.Name}' is one code unit, not a character, so what it should write " +
                "is not decided: '(char32)' writes the character its value names, and " +
                "'(long)' writes the number");
            return new BoundErrorExpression(span);
        }

        var conversion = TextConversionFor(value.Type);
        if (conversion is null)
        {
            diagnostics.Error("SL0557", span,
                $"'{value.Type.Name}' has no text to write here. An interpolation takes a " +
                "String or a number, a bool or a char; anything else needs a conversion " +
                "written out, because there is no 'ToString' every type owes");
            return new BoundErrorExpression(span);
        }

        // The argument is converted first: FromInteger takes a long, and a byte
        // reaching it has to widen exactly as it would at any other call.
        var argument = BindConversion(value, conversion.Parameters[0].Type, span);
        return new BoundCall(span, conversion, receiver: null, [argument]);
    }

    /// <summary>
    /// Which <c>Text.From*</c> writes this type.
    ///
    /// A char goes through the unsigned side deliberately: it is a code point,
    /// and printing one as a negative number would be nobody's intent.
    /// </summary>
    private FunctionSymbol? TextConversionFor(TypeSymbol type) => type switch
    {
        PrimitiveTypeSymbol { Kind: PrimitiveKind.Bool } => _builtins.TextFromBool,

        PrimitiveTypeSymbol { Kind: PrimitiveKind.Float or PrimitiveKind.Double } =>
            _builtins.TextFromDouble,

        PrimitiveTypeSymbol
        {
            Kind: PrimitiveKind.SByte or PrimitiveKind.Short or PrimitiveKind.Int
                or PrimitiveKind.Long or PrimitiveKind.NInt
        } => _builtins.TextFromLong,

        // Only char32 is a character. `char` is one UTF-8 code unit and
        // `char16` one UTF-16 unit, and a unit is not a character -- which is
        // the distinction SL0527 exists to keep, so this does not quietly
        // cross it either. See AsText for what those two are told.
        PrimitiveTypeSymbol { Kind: PrimitiveKind.Char32 } => _builtins.TextFromChar,

        PrimitiveTypeSymbol
        {
            Kind: PrimitiveKind.Byte or PrimitiveKind.UShort or PrimitiveKind.UInt
                or PrimitiveKind.ULong or PrimitiveKind.NUInt
        } => _builtins.TextFromNUInt,

        _ => null,
    };

    /// <summary>
    /// <c>try e</c>: the value, or a return carrying the failure onward.
    ///
    /// It exists because the shape it replaces is three lines of ceremony
    /// around one idea, and the ceremony is why the library reached for a bare
    /// error enum in half its functions rather than the <c>Result</c> it had.
    ///
    ///     var text = ReadAllText(path);
    ///     if (!text.Ok) { return Fail(text.Error); }
    ///     return Ok(SplitLines(text.Value));
    ///
    ///     return Ok(SplitLines(try ReadAllText(path)));
    ///
    /// The failure path is built as a real <c>return</c> of a real
    /// <c>Fail(...)</c>, so it counts references, releases scopes and returns a
    /// struct exactly as a written one does. Nothing about it is a special
    /// case downstream.
    /// </summary>
    private BoundExpression BindTry(TrySyntax syntax)
    {
        var operand = BindExpression(syntax.Operand);
        if (operand.Type.IsError()) return operand;

        if (operand.Type is not VariantTypeSymbol source || !IsResult(source))
        {
            diagnostics.Error("SL0569", syntax.Operand.Span,
                $"'try' takes a 'Result', and this is '{operand.Type.Name}'; there is nothing " +
                "here that could have failed");
            return new BoundErrorExpression(syntax.Span);
        }

        // The failure has to go somewhere, and the only place is the caller.
        if (_currentFunction?.ReturnType is not VariantTypeSymbol target || !IsResult(target))
        {
            diagnostics.Error("SL0570", syntax.Span,
                _currentFunction is null
                    ? "'try' passes a failure to the caller, so it belongs in a function"
                    : $"'{_currentFunction.Name}' returns '{_currentFunction.ReturnType.Name}', " +
                      "so a failure has nowhere to go. A function containing 'try' returns a " +
                      "'Result'; use 'ValueOr' for a caller that has a sensible default");
            return new BoundErrorExpression(syntax.Span);
        }

        var sourceOk = source.FindCase("Ok")!;
        var sourceFail = source.FindCase("Fail")!;
        var targetFail = target.FindCase("Fail")!;

        var carried = sourceFail.Fields[0].Type;
        var wanted = targetFail.Fields[0].Type;

        // Exactly matching, at first. A conversion between two error types is a
        // decision about what a failure means on the way past, and inventing
        // one here would make it silently.
        if (!carried.Equals(wanted))
        {
            diagnostics.Error("SL0571", syntax.Span,
                $"this fails with '{carried.Name}' and '{_currentFunction.Name}' fails with " +
                $"'{wanted.Name}'. 'try' passes a failure on unchanged, so convert it first: " +
                "check it and return the failure you mean");
            return new BoundErrorExpression(syntax.Span);
        }

        // One slot, read by both paths, so the operand is evaluated once.
        var slot = new LocalSymbol($"try.{_tryCount++}", source, isConst: true);
        var held = new BoundLocalAccess(syntax.Span, slot);

        var test = new BoundVariantTest(syntax.Span, PrimitiveTypeSymbol.Bool, held, sourceOk);

        var failure = new BoundReturn(syntax.Span,
            new BoundVariantConstruction(syntax.Span, target, targetFail, [
                new BoundVariantPayload(syntax.Span, held, sourceFail, sourceFail.Fields[0]),
            ]));

        var success = new BoundVariantPayload(syntax.Span, held, sourceOk, sourceOk.Fields[0]);

        return new BoundTry(syntax.Span, success.Type, slot, operand, test, failure, success);
    }

    private int _tryCount;

    /// <summary>
    /// Whether a variant is <c>Result&lt;T, E&gt;</c> -- the one the standard
    /// library declares, not merely something shaped like it.
    /// </summary>
    private bool IsResult(VariantTypeSymbol variant) =>
        // The template's name, not the instantiation's: SimpleName is the
        // display name and reads `Result<long, MathError>`.
        variant.Template is { Name: "Result" } &&
        variant.FindCase("Ok") is { Fields.Count: 1 } &&
        variant.FindCase("Fail") is { Fields.Count: 1 };

    /// <summary>
    /// What an integer literal is before anything asks it to be something
    /// else: the narrowest of <c>int</c>, <c>uint</c>, <c>long</c> and
    /// <c>ulong</c> that holds it, as in C#.
    ///
    /// Everything used to start out an <c>int</c>, which is right for almost
    /// every literal ever written and wrong in two ways for the rest. A value
    /// past <c>int</c> assigned to something at least as wide fell through to
    /// an ordinary widening and was cut to 32 bits on the way out, so
    /// <c>long l = 9223372036854775808;</c> compiled and held zero. And a
    /// bit pattern such as <c>0xFFFF0000</c> met an <c>int</c> operand as an
    /// <c>int</c>, where C# makes it a <c>uint</c> and widens the operation to
    /// <c>long</c> -- which is the difference between an answer and a
    /// coincidence.
    ///
    /// A literal small enough to be an <c>int</c> is still an <c>int</c>, so
    /// nothing about the common case moves.
    /// </summary>
    private static PrimitiveTypeSymbol LiteralType(object? value) => value switch
    {
        ulong number when number <= int.MaxValue => PrimitiveTypeSymbol.Int,
        ulong number when number <= uint.MaxValue => PrimitiveTypeSymbol.UInt,
        ulong number when number <= long.MaxValue => PrimitiveTypeSymbol.Long,
        ulong => PrimitiveTypeSymbol.ULong,
        _ => PrimitiveTypeSymbol.Int,
    };

    private BoundExpression BindLiteral(LiteralSyntax syntax) => syntax.Kind switch
    {
        TokenKind.IntLiteral => new BoundLiteral(
            syntax.Span, LiteralType(syntax.Value), syntax.Value),
        // `1.5f` lexed to a float and `1.5` to a double; the value says which.
        TokenKind.FloatLiteral => new BoundLiteral(syntax.Span,
            syntax.Value is float ? PrimitiveTypeSymbol.Float : PrimitiveTypeSymbol.Double,
            syntax.Value),
        // A character literal is one Unicode scalar. It starts out as the
        // narrowest code unit type that can hold it whole, and CharacterFits
        // lets it become a wider one where the context asks for it.
        TokenKind.CharLiteral => new BoundLiteral(
            syntax.Span,
            syntax.Value is int scalar && scalar >= 0x80
                ? PrimitiveTypeSymbol.Char32
                : PrimitiveTypeSymbol.Char,
            syntax.Value),
        TokenKind.TrueKeyword or TokenKind.FalseKeyword =>
            new BoundLiteral(syntax.Span, PrimitiveTypeSymbol.Bool, syntax.Value),
        TokenKind.StringLiteral => new BoundStringLiteral(
            syntax.Span, _builtins.String, (string)syntax.Value!),
        TokenKind.NullKeyword => new BoundNullLiteral(syntax.Span, NullType.Instance),
        _ => new BoundErrorExpression(syntax.Span),
    };

    /// <summary>
    /// Binds the elements and leaves the type open, unless nothing is going to
    /// close it -- in which case the elements themselves decide.
    /// </summary>
    private BoundExpression BindArrayLiteral(ArrayLiteralSyntax syntax)
    {
        var elements = syntax.Elements.Select(BindExpression).ToList();
        if (elements.Any(e => e.Type.IsError())) return new BoundErrorExpression(syntax.Span);

        return new BoundArrayDraft(syntax.Span, ArrayDraftType.Instance, elements);
    }

    /// <summary>
    /// Settles an array literal against the type it is going into.
    ///
    /// <c>T[]</c> allocates; <c>T[N]</c> must match in length, because an
    /// inline array is its elements and there is nowhere to put a different
    /// number of them; <c>T[:]</c> settles as the <c>T[]</c> it is a view of,
    /// and the ordinary array-to-slice conversion does the rest.
    /// </summary>
    private BoundExpression BindArraySettle(
        BoundArrayDraft draft, TypeSymbol target, SourceSpan span)
    {
        if (target is SliceTypeSymbol slice)
            return BindConversion(
                BindArraySettle(draft, ArrayOf(slice.Element), span), slice, span);

        TypeSymbol? element = target switch
        {
            ArrayTypeSymbol array => array.Element,
            FixedArrayTypeSymbol inline => inline.Element,
            _ => null,
        };

        if (element is null)
        {
            diagnostics.Error("SL0546", span,
                $"'{target.Name}' is not an array, so an array literal cannot become one");
            return new BoundErrorExpression(span);
        }

        if (target is FixedArrayTypeSymbol wanted && wanted.Length != draft.Elements.Count)
        {
            diagnostics.Error("SL0547", span,
                $"'{wanted.Name}' holds exactly {wanted.Length} " +
                $"element{(wanted.Length == 1 ? "" : "s")}, and this literal has " +
                $"{draft.Elements.Count}; an inline array is its elements, so there is " +
                "nowhere to keep a different number of them");
            return new BoundErrorExpression(span);
        }

        var converted = draft.Elements
            .Select(e => BindConversion(e, element, e.Span))
            .ToList();

        return new BoundArrayLiteral(span, target, element, converted);
    }

    /// <summary>
    /// The type an array literal takes when nothing else says: the one type
    /// every element reaches, which is the same question a ternary's two arms
    /// ask.
    /// </summary>
    private BoundExpression SettleArrayFromElements(BoundArrayDraft draft)
    {
        if (draft.Elements.Count == 0)
        {
            diagnostics.Error("SL0548", draft.Span,
                "an empty array literal has no element type and nothing here says what it " +
                "should be; write 'new T[0]', or give the variable a type");
            return new BoundErrorExpression(draft.Span);
        }

        var element = draft.Elements[0].Type;
        for (int i = 1; i < draft.Elements.Count; i++)
        {
            var next = draft.Elements[i];

            // Already reaches what the ones before agreed on.
            if (IsImplicitlyConvertible(next, element)) continue;

            // Or is wider than they are, and they reach it: [1, 2L] is a long[]
            // for the same reason `flag ? 1 : 2L` is a long.
            if (draft.Elements.Take(i).All(e => IsImplicitlyConvertible(e, next.Type)))
            {
                element = next.Type;
                continue;
            }

            diagnostics.Error("SL0549", next.Span,
                $"this element is '{next.Type.Name}' and the ones before it are " +
                $"'{element.Name}'; an array holds one type, so either make them agree " +
                "or give the array a type of its own");
            return new BoundErrorExpression(draft.Span);
        }

        return BindArraySettle(draft, ArrayOf(element), draft.Span);
    }

    private BoundExpression BindThis(ThisSyntax syntax)
    {
        // Inside a lambda, `this` is the object the lambda was written in. The
        // generated closure also has a `this`, and letting the keyword mean
        // that one silently rebound the programmer's word to a type they never
        // wrote.
        if (_closures.Count > 0) return CaptureThis(_closures.Count - 1, syntax.Span);

        var parameter = _currentFunction?.Parameters.FirstOrDefault(p => p.IsThis);
        if (parameter is null)
        {
            diagnostics.Error("SL0228", syntax.Span,
                _currentFunction is { IsStatic: true } enclosing
                    ? $"'{enclosing.Name}' is static, so there is no 'this': it belongs to " +
                      $"'{enclosing.ContainingType!.Name}' rather than to one of them. Take " +
                      "the object as a parameter, or drop the 'static'"
                    : "'this' is only valid inside a method, constructor or destructor");
            return new BoundErrorExpression(syntax.Span);
        }
        return Receiver(syntax.Span, parameter);
    }

    /// <summary>
    /// The receiver expression for a method's implicit instance. A class method
    /// holds the reference directly; a struct method holds a pointer to the value,
    /// so it is dereferenced back into an lvalue here.
    /// </summary>
    private static BoundExpression Receiver(SourceSpan span, ParameterSymbol parameter)
    {
        var self = new BoundThis(span, parameter.Type, parameter);
        return parameter.Type is PointerTypeSymbol { Element: NamedTypeSymbol } pointer
            ? new BoundDereference(span, pointer.Element, self)
            : self;
    }

    /// <summary>
    /// <c>base</c> written where a value belongs. It never is one: it is this
    /// object seen as its base class, which only means anything when a member is
    /// being looked up on it.
    /// </summary>
    private BoundExpression BindBaseValue(BaseSyntax syntax)
    {
        diagnostics.Error("SL0515", syntax.Span,
            "'base' is not a value; it says where to look a member up, so it is only useful " +
            "as 'base.Member' or, at the head of a constructor, as 'base(...)'");
        return new BoundErrorExpression(syntax.Span);
    }

    /// <summary>
    /// <c>base</c> as the receiver of a member access: this object, typed as the
    /// class it derives from.
    ///
    /// The conversion emits nothing -- the base subobject starts where the
    /// object does -- so what it changes is only where the name is looked up,
    /// and that the call it feeds is not dispatched. Both are the point: an
    /// override reaching its base through the vtable would find itself.
    /// </summary>
    private BoundExpression? BindBaseReceiver(SourceSpan span)
    {
        if (_currentFunction?.ContainingType is not ClassTypeSymbol here)
        {
            diagnostics.Error("SL0515", span,
                "'base' is only valid inside a class method, constructor or destructor");
            return null;
        }

        if (here.BaseClass is not { } baseClass)
        {
            diagnostics.Error("SL0515", span,
                $"'{here.Name}' derives from nothing, so it has no 'base'");
            return null;
        }

        if (BindImplicitThis(span) is not { } self) return null;
        return new BoundConversion(span, baseClass, self, ConversionKind.Upcast);
    }

    /// <summary>
    /// <c>value is Type</c>: whether the object really is one of those.
    ///
    /// A test that could never be true is a mistake rather than a constant
    /// false, and one that must be true is a redundancy worth saying so about.
    /// </summary>
    private BoundExpression BindTypeTest(TypeTestSyntax syntax)
    {
        // Whatever is being tested is bound outside the pattern scope: the one
        // binding this `is` may make is its own, and an `is` nested in the
        // value has no branch of its own to be true in.
        var enclosing = _patterns;
        _patterns = null;
        var value = BindExpression(syntax.Value);
        _patterns = enclosing;

        // A case is not a type and would not resolve as one, so a variant is
        // asked before the right side is resolved. A case wins over a class of
        // the same name, because the value says which question was meant.
        if (value.Type is VariantTypeSymbol variant &&
            syntax.Tested is NamedTypeSyntax { Name.Parts: [var only], TypeArguments.Count: 0 } &&
            variant.FindCase(only) is { } namedCase)
            return BindVariantCaseTest(syntax, value, namedCase);

        // Nothing else a variant could be asked: it is a value type, so it is
        // never an object of some class, and the only question left is which
        // of its cases it holds.
        if (value.Type is VariantTypeSymbol whole &&
            syntax.Tested is NamedTypeSyntax { Name.Parts: [var missing], TypeArguments.Count: 0 })
        {
            diagnostics.Error("SL0518", syntax.Span,
                $"'{whole.Name}' is a variant and has no case named '{missing}'; " +
                "what 'is' asks a variant is which case it holds, and those are " +
                Listed(whole.Cases.Select(c => c.Name)));
            return new BoundErrorExpression(syntax.Span);
        }

        var tested = ResolveType(syntax.Tested, _currentScope!);
        if (value.Type.IsError() || tested.IsError()) return new BoundErrorExpression(syntax.Span);

        if (tested is not NamedTypeSymbol { IsReferenceType: true } wanted)
        {
            diagnostics.Error("SL0518", syntax.Span,
                $"'{tested.Name}' is not a class or an interface, so 'is' has nothing to ask: " +
                "every other type is known exactly where it is written");
            return new BoundErrorExpression(syntax.Span);
        }

        if (value.Type is WeakTypeSymbol)
        {
            diagnostics.Error("SL0518", syntax.Span,
                $"'{value.Type.Name}' may already have died, so what it is cannot be asked " +
                "directly; read it into a '" + wanted.Name + "?' first, which is the check " +
                "that makes it safe to look at");
            return new BoundErrorExpression(syntax.Span);
        }

        if (value.Type.AsReference() is not NamedTypeSymbol subject)
        {
            diagnostics.Error("SL0518", syntax.Span,
                $"'is' asks what an object really is, and '{value.Type.Name}' is not a reference " +
                "to one");
            return new BoundErrorExpression(syntax.Span);
        }

        // A COM object answers for itself, so the only pairing the compiler
        // can rule out is one where neither side is COM at all: a Stainless
        // reference has no QueryInterface to ask, and a COM one has no header
        // to walk.
        if (wanted is ComInterfaceTypeSymbol || subject is ComInterfaceTypeSymbol)
        {
            if (wanted is not ComInterfaceTypeSymbol asked)
            {
                diagnostics.Error("SL0518", syntax.Span,
                    $"'{subject.Name}' is a com interface and '{wanted.Name}' is not; all a COM " +
                    "reference can be asked is QueryInterface, and that names com interfaces");
                return new BoundErrorExpression(syntax.Span);
            }

            if (subject is not ComInterfaceTypeSymbol && subject is not ClassTypeSymbol { IsCom: true })
            {
                diagnostics.Error("SL0518", syntax.Span,
                    $"'{subject.Name}' is not a COM reference, so there is no QueryInterface to " +
                    $"ask it whether it is a '{asked.Name}'");
                return new BoundErrorExpression(syntax.Span);
            }

            if (syntax.Binding is not null)
            {
                diagnostics.Error("SL0587", syntax.BindingSpan,
                    $"a QueryInterface for '{asked.Name}' is a call the object answers, and " +
                    "answers again, so a name here would not be what the test asked about; " +
                    $"cast it instead, as 'var {syntax.Binding} = ({asked.Name})...'");
                return new BoundErrorExpression(syntax.Span);
            }

            // Deliberately no "always true" warning for the upward case. A
            // class's base chain is the compiler's; an object's answer is its
            // own, and even IUnknown -> IUnknown is a call it may refuse.
            return new BoundTypeTest(syntax.Span, PrimitiveTypeSymbol.Bool, value, asked);
        }

        // Two classes in different families: no object is ever both.
        if (subject is ClassTypeSymbol subjectClass && wanted is ClassTypeSymbol wantedClass)
        {
            if (!subjectClass.DerivesFrom(wantedClass) && !wantedClass.DerivesFrom(subjectClass))
            {
                diagnostics.Error("SL0518", syntax.Span,
                    $"no object is both a '{subjectClass.Name}' and a '{wantedClass.Name}': " +
                    "neither derives from the other");
                return new BoundErrorExpression(syntax.Span);
            }

            // Upwards, the answer is settled by the type -- except through an
            // optional, where it still says 'and not null'.
            if (subjectClass.DerivesFrom(wantedClass) && value.Type is not OptionalTypeSymbol)
                diagnostics.Warning("SL0520", syntax.Span,
                    $"every '{subjectClass.Name}' is a '{wantedClass.Name}', so this is always true");
        }

        if (syntax.Binding is not null) return BindClassTestBinding(syntax, value, wanted);

        return new BoundTypeTest(syntax.Span, PrimitiveTypeSymbol.Bool, value, wanted);
    }

    /// <summary>
    /// <c>v is Circle c</c> over a variant: the test is the tag test, and the
    /// name is that case's payload.
    ///
    /// This is the whole reason the binding form exists. The bare
    /// <c>if (v.Circle) { v.Radius }</c> narrowing needs a local or a
    /// parameter to be about (SL0285), because a field or a call result could
    /// be a different value by the time it is read. A binding says so
    /// explicitly: the value is taken once, and what came out of it has a name
    /// of its own.
    /// </summary>
    private BoundExpression BindVariantCaseTest(
        TypeTestSyntax syntax, BoundExpression value, VariantCaseSymbol tested)
    {
        if (syntax.Binding is null)
            return new BoundVariantTest(syntax.Span, PrimitiveTypeSymbol.Bool, value, tested);

        if (tested.Payload is null)
        {
            diagnostics.Error("SL0586", syntax.BindingSpan,
                $"case '{tested.Name}' carries nothing, so there is nothing for " +
                $"'{syntax.Binding}' to be; the test on its own is the whole question");
            return new BoundErrorExpression(syntax.Span);
        }

        if (PatternSubject(syntax, value) is not { } subject)
            return new BoundErrorExpression(syntax.Span);

        _patterns!.Bindings.Add((syntax.Binding, tested.Payload, syntax.BindingSpan,
            new BoundVariantPayload(syntax.BindingSpan, subject, tested, null)));

        return new BoundVariantTest(syntax.Span, PrimitiveTypeSymbol.Bool, subject, tested);
    }

    /// <summary>
    /// <c>x is Circle c</c> over a class: the test, and the downcast it proved.
    ///
    /// The cast checks the base chain a second time, which the test has just
    /// walked. That is a few loads against a rule with no exception to it --
    /// a <c>Downcast</c> is checked, always -- and the alternative is a second
    /// kind of downcast whose safety lives somewhere else in the compiler.
    /// </summary>
    private BoundExpression BindClassTestBinding(
        TypeTestSyntax syntax, BoundExpression value, NamedTypeSymbol wanted)
    {
        if (wanted is not ClassTypeSymbol)
        {
            diagnostics.Error("SL0587", syntax.BindingSpan,
                $"'{wanted.Name}' is an interface, and a reference does not convert down to " +
                $"one, so there is nothing for '{syntax.Binding}' to be; test without a name " +
                "and reach the object through the interface it already has");
            return new BoundErrorExpression(syntax.Span);
        }

        if (PatternSubject(syntax, value) is not { } subject)
            return new BoundErrorExpression(syntax.Span);

        if (ClassifyConversion(subject.Type, wanted, explicitCast: true) is not { } kind)
        {
            diagnostics.Error("SL0587", syntax.BindingSpan,
                $"'{subject.Type.Name}' does not convert to '{wanted.Name}', so the test can " +
                $"be asked but its answer cannot be named");
            return new BoundErrorExpression(syntax.Span);
        }

        _patterns!.Bindings.Add((syntax.Binding!, wanted, syntax.BindingSpan,
            new BoundConversion(syntax.BindingSpan, wanted, subject, kind)));

        return new BoundTypeTest(syntax.Span, PrimitiveTypeSymbol.Bool, subject, wanted);
    }

    /// <summary>
    /// The value a test and its binding both read, evaluated once.
    ///
    /// A local or a parameter is already that. Anything else -- the field and
    /// the call result this form exists for -- is spilled into a name of the
    /// compiler's own, declared around the <c>if</c>.
    /// </summary>
    private BoundExpression? PatternSubject(TypeTestSyntax syntax, BoundExpression value)
    {
        if (_patterns is null)
        {
            diagnostics.Error("SL0585", syntax.BindingSpan,
                $"'{syntax.Binding}' is in scope only where this test succeeded, and there is " +
                "such a place only when the test is the whole condition of an 'if': write " +
                "'if (node.Payload is Number n)', and put anything else the branch needs " +
                "inside it");
            return null;
        }

        if (NarrowableSubject(value) is not null) return value;

        var held = DeclareLocal(
            SyntheticName("is"), value.Type, isConst: true, syntax.Value.Span);
        _patterns.Spills.Add(new BoundLocalDeclaration(syntax.Value.Span, held, value));

        return new BoundLocalAccess(syntax.Value.Span, held);
    }

    private BoundExpression BindName(NameSyntax syntax)
    {
        var parts = syntax.Name.Parts;

        if (parts.Count == 1)
        {
            string name = parts[0];

            if (LookupLocal(name) is { } local)
                return Narrowed(new BoundLocalAccess(syntax.Span, local), local);

            if (_currentFunction?.Parameters.FirstOrDefault(p => p.Name == name && !p.IsThis) is { } parameter)
                return Narrowed(new BoundParameterAccess(syntax.Span, parameter), parameter);

            if (_currentFunction?.ContainingType?.FindStatic(name) is { } ownStatic)
                return new BoundStaticAccess(syntax.Span, ownStatic);

            if (_currentFunction?.ContainingType?.FindProperty(name) is
                    { Getter.IsStatic: true } ownStaticProperty)
                return BindPropertyRead(syntax.Span, receiver: null, ownStaticProperty);

            // An unqualified member name inside a method means `this.member`.
            // A static method has no `this`, and saying so here is worth more
            // than letting the name fall through to "is not defined".
            if (_currentFunction is { IsStatic: true } inStatic &&
                (inStatic.ContainingType!.FindProperty(name) is not null ||
                 inStatic.ContainingType.FindField(name) is not null))
            {
                diagnostics.Error("SL0576", syntax.Span,
                    $"'{name}' belongs to an instance of '{inStatic.ContainingType.Name}', and " +
                    $"'{inStatic.Name}' is static, so there is no instance here. Take one as a " +
                    "parameter, or drop the 'static'");
                return new BoundErrorExpression(syntax.Span);
            }

            if (_currentFunction?.ContainingType?.FindProperty(name) is { } ownProperty)
            {
                var receiver = BindImplicitThis(syntax.Span);
                if (receiver is not null)
                    return BindPropertyRead(syntax.Span, receiver, ownProperty);
            }

            if (_currentFunction?.ContainingType?.FindField(name) is { } field)
            {
                if (!CanReach(field.IsPublic, field.IsProtected, field.ContainingType))
                {
                    diagnostics.Error("SL0249", syntax.Span,
                        NotVisible(field.ContainingType, name, field.IsProtected));
                    return new BoundErrorExpression(syntax.Span);
                }

                var receiver = BindImplicitThis(syntax.Span);
                if (receiver is not null) return new BoundFieldAccess(syntax.Span, receiver, field);
            }

            if (_currentModule!.Constants.TryGetValue(name, out var constant))
                return new BoundConstantAccess(syntax.Span, constant);

            if (_currentModule.Statics.TryGetValue(name, out var moduleStatic))
                return new BoundStaticAccess(syntax.Span, moduleStatic);

            foreach (var import in _currentScope!.Imports.Values.Distinct())
            {
                if (import.Constants.TryGetValue(name, out var imported) && imported.IsPublic)
                    return new BoundConstantAccess(syntax.Span, imported);

                if (import.Statics.TryGetValue(name, out var importedStatic) && importedStatic.IsPublic)
                    return new BoundStaticAccess(syntax.Span, importedStatic);
            }
        }

        // Not declared here, so a lambda body reaches outward and captures it.
        if (parts.Count == 1 && TryCapture(parts[0], syntax.Span) is { } captured)
            return captured;

        // A bare function name is a value only once it is known which delegate
        // it is becoming, so it stays a group until a conversion resolves it.
        var functions = ResolveFunctionCandidates(syntax.Name);
        if (functions.Count > 0)
            return new BoundFunctionGroup(
                syntax.Span, FunctionGroupType.Instance, syntax.Name.Text, functions);

        // A case that carries nothing is written without parentheses, so it
        // reaches here rather than through a call. Last, like every other bare
        // case name: a local, a parameter, a field and a function all win first.
        if (parts.Count == 1 && CouldBeVariantCase(parts[0]))
            return new BoundVariantDraft(syntax.Span, parts[0], []);

        diagnostics.Error("SL0229", syntax.Span, $"'{syntax.Name.Text}' is not defined");
        return new BoundErrorExpression(syntax.Span);
    }

    private BoundExpression? BindImplicitThis(SourceSpan span)
    {
        var parameter = _currentFunction?.Parameters.FirstOrDefault(p => p.IsThis);
        return parameter is null ? null : Receiver(span, parameter);
    }

    private BoundExpression BindUnary(UnarySyntax syntax)
    {
        // `&x` and `*p` are addressing, not arithmetic, so handle them first.
        if (syntax.Operator == TokenKind.Amp)
        {
            // The address of a storage slot, whose type is the slot's rather
            // than what a check proved is in it at this moment.
            var target = Widened(BindExpression(syntax.Operand));
            if (!target.IsLValue && !target.Type.IsError())
            {
                diagnostics.Error("SL0230", syntax.Span, "cannot take the address of a temporary value");
                return new BoundErrorExpression(syntax.Span);
            }
            return new BoundAddressOf(syntax.Span, new PointerTypeSymbol(target.Type), target);
        }

        if (syntax.Operator == TokenKind.Star)
        {
            var target = BindExpression(syntax.Operand);
            if (target.Type is not PointerTypeSymbol pointer)
            {
                if (!target.Type.IsError())
                    diagnostics.Error("SL0231", syntax.Span,
                        $"cannot dereference '{target.Type.Name}'; only pointers can be dereferenced");
                return new BoundErrorExpression(syntax.Span);
            }
            return new BoundDereference(syntax.Span, pointer.Element, target);
        }

        var operand = BindExpression(syntax.Operand);
        if (operand.Type.IsError()) return new BoundErrorExpression(syntax.Span);

        // A type's own, before anything built in -- the same order as binary.
        if (FindUnaryOperator(syntax.Span, syntax.Operator, operand) is { } overloaded)
            return overloaded;

        if (syntax.Operator == TokenKind.Plus)
            return operand;

        var (op, valid) = syntax.Operator switch
        {
            TokenKind.Minus => (BoundUnaryOp.Negate,
                operand.Type is PrimitiveTypeSymbol { IsNumeric: true }),
            TokenKind.Bang => (BoundUnaryOp.LogicalNot, operand.Type.IsBool()),
            TokenKind.Tilde => (BoundUnaryOp.BitwiseNot,
                operand.Type is PrimitiveTypeSymbol { IsInteger: true } || IsFlags(operand.Type)),
            _ => (BoundUnaryOp.Negate, false),
        };

        if (!valid)
        {
            diagnostics.Error("SL0232", syntax.Span,
                $"operator '{syntax.Operator.FixedText()}' cannot be applied to '{operand.Type.Name}'");
            return new BoundErrorExpression(syntax.Span);
        }

        // A negated literal is wide enough for what it will hold.
        //
        // Every integer literal starts out an `int` and adopts a wider type at
        // the point it is used, where the value can be seen (ConstantFits). A
        // minus is in between: `-9000000000000000000` is a unary operation on a
        // literal, so the operation's type is the literal's, and by the time the
        // assignment could widen it the value has already been truncated to 32
        // bits -- silently, `int` to `long` being an implicit widening that has
        // nothing to complain about. So the width is chosen here instead, from
        // what the *negated* value needs: `-2147483648` is still an `int`, as in
        // C#, and everything past it is a `long`.
        if (op is BoundUnaryOp.Negate &&
            operand is BoundLiteral { Value: ulong magnitude } written &&
            written.Type is PrimitiveTypeSymbol { IsInteger: true, IsSigned: true } &&
            magnitude > 2147483648UL)
        {
            operand = new BoundLiteral(
                written.Span,
                magnitude <= 9223372036854775808UL
                    ? PrimitiveTypeSymbol.Long
                    : PrimitiveTypeSymbol.ULong,
                magnitude);
        }

        // Small integers promote to int before arithmetic, as in C#.
        if (op is BoundUnaryOp.Negate or BoundUnaryOp.BitwiseNot)
            operand = PromoteToInt(operand);

        return new BoundUnary(syntax.Span, operand.Type, op, operand);
    }

    private BoundExpression BindBinary(BinarySyntax syntax)
    {
        // `a ?? b` is not a binary operation: only one side is evaluated, and
        // the left is read twice. It is bound where `?.` is, the two folding
        // into one question when they meet.
        if (syntax.Operator == TokenKind.QuestionQuestion) return BindNullFallback(syntax);

        var left = BindExpression(syntax.Left);

        // `a && b` evaluates b only when a was true, so b is bound knowing it.
        // `a || b` evaluates b only when a was false, and knows that instead.
        // Without this, `x != null && x.Next != null` -- the shape every walk
        // over a linked structure is written in -- could not be said at all.
        var right = syntax.Operator is TokenKind.AmpAmp or TokenKind.PipePipe
            ? BindUnderFacts(syntax.Right, left, whenTrue: syntax.Operator == TokenKind.AmpAmp)
            : BindExpression(syntax.Right);

        if (left.Type.IsError() || right.Type.IsError()) return new BoundErrorExpression(syntax.Span);

        var op = syntax.Operator switch
        {
            TokenKind.Plus => BoundBinaryOp.Add,
            TokenKind.Minus => BoundBinaryOp.Subtract,
            TokenKind.Star => BoundBinaryOp.Multiply,
            TokenKind.Slash => BoundBinaryOp.Divide,
            TokenKind.Percent => BoundBinaryOp.Remainder,
            TokenKind.Amp => BoundBinaryOp.BitAnd,
            TokenKind.Pipe => BoundBinaryOp.BitOr,
            TokenKind.Caret => BoundBinaryOp.BitXor,
            TokenKind.LessLess => BoundBinaryOp.ShiftLeft,
            TokenKind.GreaterGreater => BoundBinaryOp.ShiftRight,
            TokenKind.EqualsEquals => BoundBinaryOp.Equal,
            TokenKind.BangEquals => BoundBinaryOp.NotEqual,
            TokenKind.Less => BoundBinaryOp.Less,
            TokenKind.LessEquals => BoundBinaryOp.LessEqual,
            TokenKind.Greater => BoundBinaryOp.Greater,
            TokenKind.GreaterEquals => BoundBinaryOp.GreaterEqual,
            TokenKind.AmpAmp => BoundBinaryOp.LogicalAnd,
            _ => BoundBinaryOp.LogicalOr,
        };

        return BindBinaryOperation(syntax.Span, left, op, right, syntax.Operator);
    }

    /// <summary>
    /// The operator a type declared for this, or null if neither operand's
    /// type declared one.
    ///
    /// Both operands are asked, which is what lets `2 * money` work: the
    /// declaration lives on Money and is found through the right-hand side.
    /// </summary>
    private BoundExpression? FindBinaryOperator(
        SourceSpan span, TokenKind token, BoundExpression left, BoundExpression right)
    {
        if (OperatorNames.For(token) is not { } name) return null;

        var candidates = OperatorsNamed(name, left.Type, right.Type)
            .Where(o => o.Parameters.Count == 2)
            .ToList();

        if (candidates.Count == 0) return null;

        var fitting = candidates
            .Where(o => IsImplicitlyConvertible(left, o.Parameters[0].Type) &&
                        IsImplicitlyConvertible(right, o.Parameters[1].Type))
            .ToList();

        if (fitting.Count == 0)
        {
            // Declared, and not for these types. Saying which is more use than
            // "cannot be applied", which is what the caller would say next.
            diagnostics.Error("SL0565", span,
                $"no operator '{token.FixedText()}' takes '{left.Type.Name}' and " +
                $"'{right.Type.Name}'; the ones declared take " +
                string.Join(" and ", candidates.Select(Operands)));
            return new BoundErrorExpression(span);
        }

        if (fitting.Count > 1)
        {
            diagnostics.Error("SL0566", span,
                $"operator '{token.FixedText()}' is ambiguous for '{left.Type.Name}' and " +
                $"'{right.Type.Name}': " + string.Join(" and ", fitting.Select(Operands)) +
                " both accept them");
            return new BoundErrorExpression(span);
        }

        var chosen = fitting[0];
        return new BoundCall(span, chosen, receiver: null, [
            BindConversion(left, chosen.Parameters[0].Type, span),
            BindConversion(right, chosen.Parameters[1].Type, span),
        ]);
    }

    /// <summary>The same, for `-x` and `!x` and `~x`.</summary>
    private BoundExpression? FindUnaryOperator(
        SourceSpan span, TokenKind token, BoundExpression operand)
    {
        if (OperatorNames.For(token) is not { } name) return null;

        var fitting = OperatorsNamed(name, operand.Type, operand.Type)
            .Where(o => o.Parameters.Count == 1 &&
                        IsImplicitlyConvertible(operand, o.Parameters[0].Type))
            .ToList();

        if (fitting.Count == 0) return null;

        if (fitting.Count > 1)
        {
            diagnostics.Error("SL0566", span,
                $"operator '{token.FixedText()}' is ambiguous for '{operand.Type.Name}'");
            return new BoundErrorExpression(span);
        }

        return new BoundCall(span, fitting[0], receiver: null,
            [BindConversion(operand, fitting[0].Parameters[0].Type, span)]);
    }

    /// <summary>
    /// The operators of that name on either operand's type, without repeating
    /// one when both operands are the same type.
    /// </summary>
    private static List<FunctionSymbol> OperatorsNamed(string name, TypeSymbol left, TypeSymbol right)
    {
        var found = new List<FunctionSymbol>();

        foreach (var type in new[] { Underlying(left), Underlying(right) })
        {
            if (type is not NamedTypeSymbol named) continue;

            foreach (var candidate in named.Operators)
                if (candidate.Name == name && !found.Contains(candidate))
                    found.Add(candidate);
        }

        return found;
    }

    /// <summary>
    /// The type whose operators to look at. A `C?` looks at C's, so that a
    /// narrowed reference and an unnarrowed one behave alike.
    /// </summary>
    private static TypeSymbol Underlying(TypeSymbol type) =>
        type is OptionalTypeSymbol optional ? optional.Element : type;

    /// <summary>An operator's operand types, for a diagnostic.</summary>
    private static string Operands(FunctionSymbol op) =>
        "'" + string.Join(", ", op.Parameters.Select(p => p.Type.Name)) + "'";

    private BoundExpression BindBinaryOperation(
        SourceSpan span, BoundExpression left, BoundBinaryOp op, BoundExpression right, TokenKind token)
    {
        // Logical operators: bool only, and they short-circuit.
        if (op is BoundBinaryOp.LogicalAnd or BoundBinaryOp.LogicalOr)
        {
            if (!left.Type.IsBool() || !right.Type.IsBool())
            {
                diagnostics.Error("SL0233", span,
                    $"operator '{token.FixedText()}' requires 'bool' operands, but got " +
                    $"'{left.Type.Name}' and '{right.Type.Name}'");
                return new BoundErrorExpression(span);
            }
            return new BoundBinary(span, PrimitiveTypeSymbol.Bool, left, op, right);
        }

        // A type's own operator, before anything built in. It comes first so
        // that a class declaring `==` gets asked rather than being compared by
        // address behind its back -- which is the whole reason to declare one.
        // Nothing built in is reachable this way: a primitive, a String and an
        // array declare no operators, so the lookup fails at once for them.
        if (FindBinaryOperator(span, token, left, right) is { } overloaded) return overloaded;

        // Pointer arithmetic: p + i, p - i.
        if (left.Type is PointerTypeSymbol && op is BoundBinaryOp.Add or BoundBinaryOp.Subtract &&
            right.Type is PrimitiveTypeSymbol { IsInteger: true })
        {
            return new BoundBinary(span, left.Type, left, op, PromoteToInt(right));
        }

        // Strings compare by value and concatenate with '+'. Both lower to a
        // runtime call, so neither is a special case anywhere downstream.
        if (_builtins.IsString(left.Type) && _builtins.IsString(right.Type))
        {
            if (op == BoundBinaryOp.Add)
                return new BoundCall(span, _builtins.StringConcat, receiver: null, [left, right]);

            if (op is BoundBinaryOp.Equal or BoundBinaryOp.NotEqual)
            {
                var comparison = new BoundCall(
                    span, _builtins.StringEquals, receiver: null, [left, right]);

                return op == BoundBinaryOp.Equal
                    ? comparison
                    : new BoundUnary(span, PrimitiveTypeSymbol.Bool, BoundUnaryOp.LogicalNot, comparison);
            }

            diagnostics.Error("SL0291", span,
                $"operator '{token.FixedText()}' cannot be applied to strings");
            return new BoundErrorExpression(span);
        }

        if (_builtins.IsString(left.Type) != _builtins.IsString(right.Type))
        {
            var other = _builtins.IsString(left.Type) ? right.Type : left.Type;
            diagnostics.Error("SL0292", span,
                $"cannot apply '{token.FixedText()}' to 'String' and '{other.Name}'; " +
                "convert it first, for example with Standard.Text.FromInteger");
            return new BoundErrorExpression(span);
        }

        // Enums compare with each other and with nothing else. Comparison is
        // allowed as well as equality, because an ordered enum -- a severity, a
        // log level -- is the common case and `level >= Level.Warning` is what
        // people write. Arithmetic is not: adding two colours means nothing.
        if (left.Type is EnumTypeSymbol || right.Type is EnumTypeSymbol)
        {
            bool comparison = op is BoundBinaryOp.Equal or BoundBinaryOp.NotEqual
                or BoundBinaryOp.Less or BoundBinaryOp.LessEqual
                or BoundBinaryOp.Greater or BoundBinaryOp.GreaterEqual;

            bool bitwise = op is BoundBinaryOp.BitAnd or BoundBinaryOp.BitOr or BoundBinaryOp.BitXor;

            if (!left.Type.Equals(right.Type))
            {
                diagnostics.Error("SL0353", span,
                    $"'{left.Type.Name}' and '{right.Type.Name}' are different types and do not " +
                    "compare; an enum converts only through an explicit cast");
                return new BoundErrorExpression(span);
            }

            // A set of bits combines; a choice among alternatives does not. The
            // attribute is what says which one this enum is.
            if (bitwise && IsFlags(left.Type))
                return new BoundBinary(span, left.Type, left, op, right);

            if (!comparison)
            {
                diagnostics.Error("SL0354", span,
                    $"operator '{token.FixedText()}' cannot be applied to '{left.Type.Name}'; " +
                    (bitwise
                        ? $"'{left.Type.Name}' is a choice among alternatives, not a set of bits. " +
                          "Mark it '[Flags]' if its members are meant to combine"
                        : "an enum supports comparison, not arithmetic"));
                return new BoundErrorExpression(span);
            }

            return new BoundBinary(span, PrimitiveTypeSymbol.Bool, left, op, right);
        }

        // Reference and pointer equality.
        if (op is BoundBinaryOp.Equal or BoundBinaryOp.NotEqual &&
            IsReferenceLike(left.Type) && IsReferenceLike(right.Type))
        {
            var (comparableLeft, comparableRight) = UnifyReferences(left, right, span);
            return new BoundBinary(span, PrimitiveTypeSymbol.Bool, comparableLeft, op, comparableRight);
        }

        // `first == one.Add`: one side is a method group or a lambda, which has
        // no type of its own, and the other is what settles it. Comparison is
        // the one place a closure has a context on the far side of the
        // operator rather than in front of it.
        if (op is BoundBinaryOp.Equal or BoundBinaryOp.NotEqual)
        {
            if (left.Type is ClosureTypeSymbol && right is BoundFunctionGroup or BoundLambda)
                right = BindConversion(right, left.Type, span);
            else if (right.Type is ClosureTypeSymbol && left is BoundFunctionGroup or BoundLambda)
                left = BindConversion(left, right.Type, span);
        }

        // Two closures: the same method on the same object. What makes one
        // removable from a list of them, and the reason a method pointer is a
        // value rather than an object.
        if (op is BoundBinaryOp.Equal or BoundBinaryOp.NotEqual &&
            left.Type is ClosureTypeSymbol closure && left.Type.Equals(right.Type))
            return new BoundClosureEqual(
                span, closure, left, right, op == BoundBinaryOp.NotEqual);

        if (left.Type is not PrimitiveTypeSymbol leftPrimitive ||
            right.Type is not PrimitiveTypeSymbol rightPrimitive)
        {
            diagnostics.Error("SL0234", span,
                $"operator '{token.FixedText()}' cannot be applied to '{left.Type.Name}' and '{right.Type.Name}'");
            return new BoundErrorExpression(span);
        }

        // A divisor that is zero at compile time is always a mistake, and there
        // is no reason to make the program run before saying so. A divisor that
        // is only zero sometimes is guarded in the emitted code instead.
        if (op is BoundBinaryOp.Divide or BoundBinaryOp.Remainder &&
            leftPrimitive.IsInteger && rightPrimitive.IsInteger &&
            FoldSwitchLabel(right) is 0)
        {
            diagnostics.Error("SL0415", span,
                op == BoundBinaryOp.Divide
                    ? "division by zero"
                    : "the remainder of a division by zero");

            // Carry on with a value of the type this would have had, so the
            // expression around it reports nothing further: one mistake should
            // produce one message. It is wrapped rather than left a bare
            // literal, because a literal would take part in overload resolution
            // as a literal does and could be ambiguous where the division was not.
            var recovered = PromoteToInt(left).Type;
            return new BoundConversion(span, recovered,
                new BoundLiteral(span, recovered, 0UL), ConversionKind.Identity);
        }

        // Shifts keep the left type; only the left operand promotes.
        if (op is BoundBinaryOp.ShiftLeft or BoundBinaryOp.ShiftRight)
        {
            if (!leftPrimitive.IsInteger || !rightPrimitive.IsInteger)
            {
                diagnostics.Error("SL0235", span, "shift operators require integer operands");
                return new BoundErrorExpression(span);
            }
            // The result is the left operand's type, and the count is brought to
            // that same type. LLVM requires both operands of a shift to match,
            // so a count of a different width produced invalid IR; narrowing it
            // loses nothing, because the emitter reduces it modulo the width.
            var shifted = PromoteToInt(left);
            var count = PromoteToInt(right);

            if (!count.Type.Equals(shifted.Type))
                count = new BoundConversion(span, shifted.Type, count,
                    count.Type.Size < shifted.Type.Size
                        ? ConversionKind.IntegerWiden
                        : ConversionKind.IntegerNarrow);

            return new BoundBinary(span, shifted.Type, shifted, op, count);
        }

        bool isComparison = op is BoundBinaryOp.Equal or BoundBinaryOp.NotEqual
            or BoundBinaryOp.Less or BoundBinaryOp.LessEqual
            or BoundBinaryOp.Greater or BoundBinaryOp.GreaterEqual;

        if (leftPrimitive.Kind == PrimitiveKind.Bool && rightPrimitive.Kind == PrimitiveKind.Bool)
        {
            if (op is BoundBinaryOp.Equal or BoundBinaryOp.NotEqual
                or BoundBinaryOp.BitAnd or BoundBinaryOp.BitOr or BoundBinaryOp.BitXor)
                return new BoundBinary(span, isComparison ? PrimitiveTypeSymbol.Bool : PrimitiveTypeSymbol.Bool,
                    left, op, right);

            diagnostics.Error("SL0236", span,
                $"operator '{token.FixedText()}' cannot be applied to 'bool' operands");
            return new BoundErrorExpression(span);
        }

        if (!leftPrimitive.IsNumeric || !rightPrimitive.IsNumeric)
        {
            diagnostics.Error("SL0234", span,
                $"operator '{token.FixedText()}' cannot be applied to '{left.Type.Name}' and '{right.Type.Name}'");
            return new BoundErrorExpression(span);
        }

        // Same width and opposite signedness is the one pairing width cannot
        // settle, and `TryFindCommonType` widens it to `long`. That is right for
        // two variables and wrong for a variable and a literal: `count - 1` is
        // `nuint` where `count` is one, and the 1 is an `int` only because that
        // is what an unsuffixed literal is.
        //
        // It never came up while `nuint` was eight bytes -- it was simply the
        // wider side, and won. On a target where a pointer is four it is the
        // same width as `int`, and widening to `long` would make the standard
        // library stop compiling for itself. A literal is a number rather than
        // a type, so what is asked here is whether the number fits.
        PrimitiveTypeSymbol? common = null;

        if (leftPrimitive.IsInteger && rightPrimitive.IsInteger &&
            leftPrimitive.Size == rightPrimitive.Size &&
            leftPrimitive.IsSigned != rightPrimitive.IsSigned)
        {
            if (IntegerLiteral(right) is not null && ConstantFits(right, leftPrimitive))
                common = leftPrimitive;
            else if (IntegerLiteral(left) is not null && ConstantFits(left, rightPrimitive))
                common = rightPrimitive;
        }

        if (common is null)
        {
            if (!TryFindCommonType(leftPrimitive, rightPrimitive, out var found))
            {
                diagnostics.Error("SL0238", span,
                    $"'{left.Type.Name}' and '{right.Type.Name}' have no common type; " +
                    "add an explicit cast to choose one");
                return new BoundErrorExpression(span);
            }
            common = found;
        }

        // Bitwise operators need integers, not floats.
        if (op is BoundBinaryOp.BitAnd or BoundBinaryOp.BitOr or BoundBinaryOp.BitXor or BoundBinaryOp.Remainder
            && common.IsFloat && op != BoundBinaryOp.Remainder)
        {
            diagnostics.Error("SL0239", span,
                $"operator '{token.FixedText()}' requires integer operands");
            return new BoundErrorExpression(span);
        }

        left = BindConversion(left, common, span);
        right = BindConversion(right, common, span);

        // Only the three that can overflow, and only on integers: a float
        // saturates to infinity rather than wrapping, and there is nothing for
        // `checked` to catch.
        bool watched = _checkedArithmetic && common.IsInteger &&
            op is BoundBinaryOp.Add or BoundBinaryOp.Subtract or BoundBinaryOp.Multiply;

        return new BoundBinary(span, isComparison ? PrimitiveTypeSymbol.Bool : common, left, op, right)
            { IsChecked = watched };
    }

    private static bool IsReferenceLike(TypeSymbol type) =>
        type is PointerTypeSymbol or ClassTypeSymbol or InterfaceTypeSymbol
            or OptionalTypeSymbol or WeakTypeSymbol or NullType or DelegateTypeSymbol;

    private (BoundExpression, BoundExpression) UnifyReferences(
        BoundExpression left, BoundExpression right, SourceSpan span)
    {
        if (left.Type is NullType) left = new BoundNullLiteral(span, right.Type);
        if (right.Type is NullType) right = new BoundNullLiteral(span, left.Type);
        return (left, right);
    }

    /// <summary>Integer promotion: anything narrower than <c>int</c> widens to <c>int</c>.</summary>
    private BoundExpression PromoteToInt(BoundExpression expression)
    {
        if (expression.Type is PrimitiveTypeSymbol { IsInteger: true, Size: < 4 })
            return new BoundConversion(
                expression.Span, PrimitiveTypeSymbol.Int, expression, ConversionKind.IntegerWiden);
        return expression;
    }

    private static bool TryFindCommonType(
        PrimitiveTypeSymbol left, PrimitiveTypeSymbol right, out PrimitiveTypeSymbol common)
    {
        common = PrimitiveTypeSymbol.Int;

        if (left.IsFloat || right.IsFloat)
        {
            common = left.Kind == PrimitiveKind.Double || right.Kind == PrimitiveKind.Double
                ? PrimitiveTypeSymbol.Double
                : PrimitiveTypeSymbol.Float;
            return true;
        }

        // Promote to at least int, then to whichever side is wider.
        var wider = left.Size >= right.Size ? left : right;
        if (wider.Size < 4) { common = PrimitiveTypeSymbol.Int; return true; }

        if (left.Size == right.Size && left.IsSigned != right.IsSigned)
        {
            // Same width, different signedness: only widening to a bigger signed type is safe.
            if (left.Size >= 8) return false;
            common = PrimitiveTypeSymbol.Long;
            return true;
        }

        common = wider;
        return true;
    }

    /// <summary>
    /// Binds an expression under what the other side of a short-circuit
    /// operator established, then puts the facts back.
    /// </summary>
    private BoundExpression BindUnderFacts(
        Syntax.ExpressionSyntax syntax, BoundExpression from, bool whenTrue)
    {
        var (proves, disproves) = ConditionFacts(from);
        var entry = SnapshotFacts();

        ApplyFacts(whenTrue ? proves : disproves);
        var bound = BindExpression(syntax);

        _variantFacts = entry;
        return bound;
    }

    /// <summary>
    /// <c>a ? b : c</c>. The arms must meet at one type: the same type, a common
    /// numeric type, or one that the other converts to implicitly.
    /// </summary>
    private BoundExpression BindConditional(ConditionalSyntax syntax)
    {
        var condition = BindCondition(syntax.Condition);

        // Each arm runs only when the condition chose it, so each is bound
        // knowing what that choice proved. `r.Ok ? r.Value : Describe(r.Error)`
        // is the shape this exists for.
        var (proves, disproves) = ConditionFacts(condition);
        var entry = SnapshotFacts();

        ApplyFacts(proves);
        var whenTrue = BindExpression(syntax.WhenTrue);

        _variantFacts = new Dictionary<object, Fact>(entry);
        ApplyFacts(disproves);
        var whenFalse = BindExpression(syntax.WhenFalse);

        _variantFacts = entry;

        if (whenTrue.Type.IsError() || whenFalse.Type.IsError())
            return new BoundErrorExpression(syntax.Span);

        if (whenTrue.Type.IsVoid() || whenFalse.Type.IsVoid())
        {
            diagnostics.Error("SL0348", syntax.Span,
                "a conditional expression must produce a value, but an arm is 'void'");
            return new BoundErrorExpression(syntax.Span);
        }

        var type = CommonArmType(whenTrue, whenFalse);
        if (type is null)
        {
            diagnostics.Error("SL0349", syntax.Span,
                $"the arms of a conditional have no common type: one is " +
                $"'{whenTrue.Type.Name}', the other '{whenFalse.Type.Name}'");
            return new BoundErrorExpression(syntax.Span);
        }

        return new BoundConditional(
            syntax.Span, type,
            condition,
            BindConversion(whenTrue, type, syntax.WhenTrue.Span),
            BindConversion(whenFalse, type, syntax.WhenFalse.Span));
    }

    /// <summary>The type both arms of a conditional reach, or null if they do not.</summary>
    private TypeSymbol? CommonArmType(BoundExpression left, BoundExpression right)
    {
        if (left.Type.Equals(right.Type)) return left.Type;

        // `flag ? obj : null` is an optional, which is what the null was reaching for.
        if (left is BoundNullLiteral && right.Type.IsReferenceType) return new OptionalTypeSymbol(right.Type);
        if (right is BoundNullLiteral && left.Type.IsReferenceType) return new OptionalTypeSymbol(left.Type);

        if (left.Type is PrimitiveTypeSymbol { IsNumeric: true } leftNumber &&
            right.Type is PrimitiveTypeSymbol { IsNumeric: true } rightNumber &&
            TryFindCommonType(leftNumber, rightNumber, out var common))
            return common;

        // Otherwise one arm must already be assignable to the other, which is
        // what covers C -> C?, C -> I and an integer literal adopting a width.
        if (IsImplicitlyConvertible(right, left.Type)) return left.Type;
        if (IsImplicitlyConvertible(left, right.Type)) return right.Type;

        return null;
    }

    /// <summary>
    /// <c>(a, b)</c>.
    ///
    /// The type is whatever the elements are, so nothing has to be written
    /// down and nothing is inferred from where it is going: a tuple is
    /// structural, and two of the same element types are one type.
    /// </summary>
    private BoundExpression BindTuple(TupleSyntax syntax)
    {
        var elements = syntax.Elements.Select(BindExpression).ToList();
        if (elements.Any(e => e.Type.IsError())) return new BoundErrorExpression(syntax.Span);

        foreach (var element in elements)
        {
            if (!element.Type.IsVoid()) continue;

            diagnostics.Error("SL0607", element.Span,
                "an element of a tuple has to be a value, and this produces none");
            return new BoundErrorExpression(syntax.Span);
        }

        var type = TupleOf(elements.Select(e => e.Type).ToList());
        return new BoundTupleCreate(syntax.Span, type, elements);
    }

    /// <summary>
    /// <c>default(T)</c>.
    ///
    /// Allowed for every type, including a class, and that is not a new hole in
    /// the null discipline: a fresh array is zeroed, so <c>new C[1][0]</c>
    /// already handed back a null typed as a <c>C</c>, and the library kept
    /// exactly such an array to blank a vacated slot with. This is that,
    /// spelled. `void` is the one refusal: there is no value of it to zero.
    /// </summary>
    private BoundExpression BindDefault(DefaultSyntax syntax)
    {
        // allowVoid, so that the refusal below is the one reported: it says
        // what `default` in particular cannot do, where the general rule in
        // ResolveType says only that 'void' is not a type a value has.
        var type = ResolveType(syntax.Type, _currentScope!, allowVoid: true);
        if (type.IsError()) return new BoundErrorExpression(syntax.Span);

        if (type.IsVoid())
        {
            diagnostics.Error("SL0603", syntax.Span,
                "'default(void)' names no value; 'void' is the absence of one");
            return new BoundErrorExpression(syntax.Span);
        }

        return new BoundDefault(syntax.Span, type);
    }

    /// <summary>
    /// <c>nameof(x)</c>: the last name in what was written, as a String.
    ///
    /// The operand is bound and thrown away, which is the whole value of the
    /// thing — a name that is checked to be a name of something. Reflection is
    /// reached by string, so this is what stops a form file, a serializer or a
    /// property lookup naming a member that was renamed underneath it.
    /// </summary>
    private BoundExpression BindNameof(NameofSyntax syntax)
    {
        string? written = LastNameIn(syntax.Operand);

        if (written is null)
        {
            diagnostics.Error("SL0592", syntax.Operand.Span,
                "'nameof' takes something with a name — a variable, a parameter, a field, a " +
                "property, a method or a type — and answers with the last name written in it");
            return new BoundErrorExpression(syntax.Span);
        }

        // Bound only to be checked, and nothing it produces is kept: this
        // answers with text, and the text was in the source. What the binding
        // buys is that the name is a name of something, which is the whole
        // reason to write `nameof(Caption)` rather than `"Caption"`.
        //
        // Muted, because the operand may equally well be a *type*, and a type
        // name is not an expression. Trying both and complaining once is what
        // keeps `nameof(Button)` and `nameof(button)` from needing different
        // spellings.
        bool found;
        using (diagnostics.Muted())
        {
            found = BindExpression(syntax.Operand) is not BoundErrorExpression;

            if (!found && syntax.Operand is NameSyntax typeName && _currentScope is { } scope)
                found = ResolveNamedType(
                    new NamedTypeSyntax(typeName.Span, typeName.Name, []), scope)
                    is not ErrorTypeSymbol;
        }

        if (!found)
        {
            diagnostics.Error("SL0596", syntax.Operand.Span,
                $"there is nothing named '{written}' here, so 'nameof' has nothing to check " +
                "the spelling of");
            return new BoundErrorExpression(syntax.Span);
        }

        return new BoundStringLiteral(syntax.Span, _builtins.String, written);
    }

    /// <summary>The rightmost identifier in a name, member access or call.</summary>
    private static string? LastNameIn(ExpressionSyntax syntax) => syntax switch
    {
        NameSyntax name => name.Name.Parts[^1],
        MemberAccessSyntax member => member.Member,
        CallSyntax call => LastNameIn(call.Callee),
        _ => null,
    };

    /// <summary>
    /// <c>checked(e)</c> and <c>unchecked(e)</c>.
    ///
    /// Nothing is produced for the word itself: it sets how the arithmetic
    /// inside is bound, and the operations it applies to carry the answer.
    /// </summary>
    private BoundExpression BindChecked(CheckedSyntax syntax)
    {
        bool previous = _checkedArithmetic;
        _checkedArithmetic = syntax.IsChecked;
        var value = BindExpression(syntax.Operand);
        _checkedArithmetic = previous;
        return value;
    }

    /// <summary>
    /// <c>++x</c>, <c>x++</c>, <c>--x</c> and <c>x--</c>.
    ///
    /// It is not lowered to <c>x = x + 1</c>, for two reasons that both matter:
    /// the postfix form's value is the one from before the write, and the place
    /// has to be worked out exactly once, so that <c>a[Next()]++</c> calls
    /// <c>Next</c> one time.
    /// </summary>
    private BoundExpression BindIncrement(IncrementSyntax syntax)
    {
        string written = syntax.IsIncrement ? "++" : "--";
        var target = Widened(BindExpression(syntax.Operand));

        if (target.Type.IsError()) return new BoundErrorExpression(syntax.Span);

        // A property is a getter and a setter rather than a place, so it needs
        // the other node. The read has already bound the receiver exactly once,
        // which is what that node needs.
        if (target is BoundCall { Function.Accessor: { } property } read)
        {
            if (property.Setter is null)
            {
                diagnostics.Error("SL0593", syntax.Span,
                    $"'{property.Name}' has no setter, so '{written}' has nothing to write back");
                return new BoundErrorExpression(syntax.Span);
            }

            if (!Countable(property.Type, syntax.Span, written))
                return new BoundErrorExpression(syntax.Span);

            InvalidateVariantFact(target);
            NoteMemberWritten(property);
            return new BoundPropertyIncrement(
                syntax.Span, read.Receiver, property, syntax.IsPrefix, syntax.IsIncrement)
                { IsChecked = _checkedArithmetic };
        }

        if (!Writable(target, syntax.Operand.Span, written)) return new BoundErrorExpression(syntax.Span);
        if (!Countable(target.Type, syntax.Span, written)) return new BoundErrorExpression(syntax.Span);

        InvalidateVariantFact(target);
        if (WrittenParameter(target) is { } written2) written2.IsAssigned = true;
        NoteMemberWritten(target);

        return new BoundIncrement(syntax.Span, target, syntax.IsPrefix, syntax.IsIncrement)
            { IsChecked = _checkedArithmetic };
    }

    /// <summary>Whether one may be added to a value of this type.</summary>
    private bool Countable(TypeSymbol type, SourceSpan span, string written)
    {
        // A pointer counts in elements, as C's does. Everything else has to be
        // a number: `++` on a class would be an assignment to a new object,
        // which is a different thing wearing the same spelling.
        if (type is PointerTypeSymbol or PrimitiveTypeSymbol { IsNumeric: true }) return true;

        diagnostics.Error("SL0594", span,
            $"'{written}' adds one to a number or steps a pointer, and this is " +
            $"'{type.Name}'" +
            (type is EnumTypeSymbol
                ? "; an enum is a choice rather than a count, so step the integer behind it"
                : ""));
        return false;
    }

    /// <summary>
    /// Whether a place may be written: the checks an assignment makes, asked
    /// separately so that <c>++</c> makes exactly the same ones.
    /// </summary>
    private bool Writable(BoundExpression target, SourceSpan span, string written)
    {
        if (BaseOf(target) is BoundStaticAccess { Static.IsReadonly: true } owner)
        {
            diagnostics.Error("SL0379", span,
                $"'{owner.Static.Name}' is 'static readonly', so it is written once by its " +
                "initializer and never again. Drop the 'readonly' if it is meant to change");
            return false;
        }

        if (BaseOf(target) is BoundParameterAccess { Parameter.Mode: ParameterMode.In } borrowed)
        {
            diagnostics.Error("SL0448", span,
                $"'{borrowed.Parameter.Name}' is an 'in' parameter, which is the caller's " +
                "storage and promises not to be written; take it as 'ref' if it should be, or " +
                "copy it into a local first");
            return false;
        }

        if (!target.IsLValue)
        {
            diagnostics.Error("SL0240", span,
                target is BoundLocalAccess { Local.IsConst: true } constant
                    ? $"'{constant.Local.Name}' is declared 'const' and cannot be assigned"
                    : $"'{written}' needs a variable, field or dereference to change");
            return false;
        }

        return true;
    }

    /// <summary>
    /// Every name declared as an event, anywhere in the program.
    ///
    /// A cheap "could this possibly be one" for <see cref="BindSubscription"/>,
    /// which has to ask before it binds the receiver: binding it is what turns
    /// `Registry.Label = x` -- a static reached through its type -- into a
    /// complaint about an undefined name.
    /// </summary>
    private readonly HashSet<string> _eventNames = new(StringComparer.Ordinal);

    /// <summary>
    /// <c>publisher.Fired += handler</c> and its opposite.
    ///
    /// Intercepted before the target is bound as a read, because reading an
    /// event is not a thing that can be done: from outside the declaring type
    /// these two operators are all there is, and there is no value called
    /// <c>publisher.Fired</c> for them to be an arithmetic on. That is the
    /// difference between an event and a public field of closure type, and the
    /// whole reason the word exists.
    ///
    /// Returns null when the target is not an event, which is every other
    /// <c>+=</c> in the language.
    /// </summary>
    private BoundExpression? BindSubscription(AssignmentSyntax syntax)
    {
        BoundExpression? receiver;
        EventSymbol? subscribed;
        var span = syntax.Target.Span;

        switch (syntax.Target)
        {
            // `Fired += h` inside the declaring type.
            case NameSyntax { Name.Parts.Count: 1 } bare
                when _currentFunction?.ContainingType?.FindEvent(bare.Name.Last) is { } own:
                subscribed = own;
                receiver = BindImplicitThis(span);
                break;

            case MemberAccessSyntax member:
            {
                // Nothing anywhere declares an event of this name, so this is
                // one of the ordinary compound assignments. Asked before the
                // receiver is bound, because binding it is what reports
                // `Registry.Label = ...` -- a static on a type -- as an
                // undefined name.
                if (!_eventNames.Contains(member.Member)) return null;

                // Bound quietly: a receiver that does not bind is not this
                // code's business to complain about. Its type comes back as an
                // error, no event is found, and the ordinary path binds it
                // again and says whatever there is to say.
                BoundExpression target;
                using (diagnostics.Muted()) target = BindExpression(member.Target);

                if (target.Type is not NamedTypeSymbol named) return null;
                if (named.FindEvent(member.Member) is not { } found) return null;

                subscribed = found;
                receiver = target;
                break;
            }

            default:
                return null;
        }

        // Every other assignment operator, `=` above all. Replacing the list
        // wholesale is what a public field of closure type would have allowed
        // and an event does not: one subscriber cannot be allowed to throw away
        // everybody else's.
        if (syntax.Operator is not (TokenKind.PlusEquals or TokenKind.MinusEquals))
        {
            diagnostics.Error("SL0556", span,
                $"'{subscribed.ContainingType.Name}.{subscribed.Name}' is an event, so it takes " +
                $"'+=' and '-=' and nothing else. '{syntax.Operator.FixedText()}' would " +
                "replace the whole list of subscribers, which is not one subscriber's to do");
            return new BoundErrorExpression(syntax.Span);
        }

        if (receiver is null)
        {
            diagnostics.Error("SL0553", span,
                $"'{subscribed.Name}' is an event and belongs to an instance, so it cannot be " +
                "reached from a static method");
            return new BoundErrorExpression(syntax.Span);
        }

        if (!CanReach(subscribed.IsPublic, subscribed.IsProtected, subscribed.ContainingType))
        {
            diagnostics.Error("SL0249", span,
                NotVisible(subscribed.ContainingType, subscribed.Name, subscribed.IsProtected));
            return new BoundErrorExpression(syntax.Span);
        }

        bool adding = syntax.Operator == TokenKind.PlusEquals;
        var accessor = adding ? subscribed.Add : subscribed.Remove;
        if (accessor is null) return new BoundErrorExpression(syntax.Span);

        // The handler is converted to the event's closure type, which is what
        // lets `sub.OnFired` be written bare: a method group has no type of its
        // own, and the event is the context that gives it one.
        var handler = BindConversion(BindExpression(syntax.Value), subscribed.Type, syntax.Value.Span);
        if (handler.Type.IsError()) return new BoundErrorExpression(syntax.Span);

        return new BoundCall(syntax.Span, accessor, receiver, [handler]);
    }

    private BoundExpression BindAssignment(AssignmentSyntax syntax)
    {
        if (BindSubscription(syntax) is { } subscription) return subscription;

        // A narrowed optional is still an optional when it is written to: the
        // check established what it held, not what it may be given next.
        var target = Widened(BindExpression(syntax.Target));

        // The target was bound as a read, which is what proves it is a property
        // and, usefully, has already bound the receiver exactly once.
        if (target is BoundCall { Function.Accessor: { } property } read)
            return BindPropertyAssignment(syntax, read, property);

        var value = BindExpression(syntax.Value);

        if (target.Type.IsError() || value.Type.IsError())
            return new BoundErrorExpression(syntax.Span);

        if (BaseOf(target) is BoundStaticAccess { Static.IsReadonly: true } owner)
        {
            diagnostics.Error("SL0379", syntax.Target.Span,
                $"'{owner.Static.Name}' is 'static readonly', so it is written once by its " +
                "initializer and never again. Drop the 'readonly' if it is meant to change");
            return new BoundErrorExpression(syntax.Span);
        }

        // An `in` parameter is the caller's storage, and the promise not to
        // write it is the only thing separating it from a `ref`. Reaching a
        // field of one is the same write one level down, so the base is what is
        // asked rather than the target itself.
        if (BaseOf(target) is BoundParameterAccess { Parameter.Mode: ParameterMode.In } borrowed)
        {
            diagnostics.Error("SL0448", syntax.Target.Span,
                $"'{borrowed.Parameter.Name}' is an 'in' parameter, which is the caller's " +
                "storage and promises not to be written; take it as 'ref' if it should be, or " +
                "copy it into a local first");
            return new BoundErrorExpression(syntax.Span);
        }

        if (!target.IsLValue)
        {
            diagnostics.Error("SL0240", syntax.Target.Span,
                target is BoundLocalAccess { Local.IsConst: true } constant
                    ? $"'{constant.Local.Name}' is declared 'const' and cannot be assigned"
                    : "the left-hand side of an assignment must be a variable, field or dereference");
            return new BoundErrorExpression(syntax.Span);
        }

        // `a ??= b` is not one of those: the operation is a question about
        // the target rather than an arithmetic on it, and the value is stored
        // only when the answer is that there is nothing there.
        if (syntax.Operator == TokenKind.QuestionQuestionEquals)
        {
            if (target.Type is not (OptionalTypeSymbol or PointerTypeSymbol))
            {
                diagnostics.Error("SL0604", syntax.Target.Span,
                    $"'{target.Type.Name}' cannot be nothing, so '??=' has nothing to fill in");
                return new BoundErrorExpression(syntax.Span);
            }

            var absent = new BoundBinary(
                syntax.Span, PrimitiveTypeSymbol.Bool,
                target, BoundBinaryOp.Equal,
                new BoundNullLiteral(syntax.Span, target.Type));

            InvalidateVariantFact(target);
            if (WrittenParameter(target) is { } filled) filled.IsAssigned = true;
            NoteMemberWritten(target);

            return new BoundConditional(syntax.Span, target.Type, absent,
                new BoundAssignment(syntax.Span, target,
                    BindConversion(value, target.Type, syntax.Value.Span)),
                target);
        }

        // Compound assignment desugars to `target = target op value`.
        if (syntax.Operator != TokenKind.Equals)
        {
            var (op, token) = CompoundOperator(syntax.Operator);
            value = BindBinaryOperation(syntax.Span, target, op, value, token);
            if (value.Type.IsError()) return new BoundErrorExpression(syntax.Span);
        }

        // Whatever was proved about this Result was proved about the value it
        // held a moment ago.
        InvalidateVariantFact(target);

        // Writing into a parameter's own storage makes it owned; see
        // ParameterSymbol.IsAssigned.
        if (WrittenParameter(target) is { } written) written.IsAssigned = true;

        NoteMemberWritten(target);
        return new BoundAssignment(syntax.Span, target, BindConversion(value, target.Type, syntax.Value.Span));
    }

    /// <summary>The operation behind a compound assignment, and the token to blame.</summary>
    private static (BoundBinaryOp Op, TokenKind Token) CompoundOperator(TokenKind kind) => kind switch
    {
        TokenKind.PlusEquals => (BoundBinaryOp.Add, TokenKind.Plus),
        TokenKind.MinusEquals => (BoundBinaryOp.Subtract, TokenKind.Minus),
        TokenKind.StarEquals => (BoundBinaryOp.Multiply, TokenKind.Star),
        TokenKind.SlashEquals => (BoundBinaryOp.Divide, TokenKind.Slash),
        TokenKind.PercentEquals => (BoundBinaryOp.Remainder, TokenKind.Percent),
        TokenKind.AmpEquals => (BoundBinaryOp.BitAnd, TokenKind.Amp),
        TokenKind.PipeEquals => (BoundBinaryOp.BitOr, TokenKind.Pipe),
        TokenKind.CaretEquals => (BoundBinaryOp.BitXor, TokenKind.Caret),
        TokenKind.LessLessEquals => (BoundBinaryOp.ShiftLeft, TokenKind.LessLess),
        _ => (BoundBinaryOp.ShiftRight, TokenKind.GreaterGreater),
    };

    /// <summary>
    /// Reads a property: a call to its getter, and nothing more. Everything
    /// downstream — ARC, interface dispatch, the calling convention — then sees
    /// an ordinary call and needs to know nothing about properties.
    /// </summary>
    /// <summary>
    /// <c>base.P</c> is the implementation this class replaced, exactly as
    /// <c>base.M()</c> is -- so the getter is called directly rather than
    /// through the vtable.
    ///
    /// Without it, an override written the obvious way calls itself:
    ///
    ///     public override bool Flag { get =&gt; base.Flag; }
    ///
    /// dispatches back to this same getter, for ever, and the program hangs
    /// with nothing to say. A method has always been non-virtual through
    /// <c>base</c>; a property accessor is a method and had been missed.
    /// </summary>
    private BoundExpression BindPropertyRead(
        SourceSpan span, BoundExpression? receiver, PropertySymbol property,
        bool nonVirtual = false)
    {
        if (property.Getter is not { } getter) return new BoundErrorExpression(span);

        if (!CanReach(getter.IsPublic, getter.IsProtected, property.ContainingType))
        {
            diagnostics.Error("SL0249", span,
                NotVisible(property.ContainingType, property.Name, getter.IsProtected));
            return new BoundErrorExpression(span);
        }

        // A struct accessor takes its receiver by pointer, exactly as a struct
        // method does. A static one has none at all.
        if (receiver is not null && property.ContainingType is StructTypeSymbol structType)
            receiver = new BoundAddressOf(span, new PointerTypeSymbol(structType), receiver);

        return new BoundCall(span, getter, receiver, []) { IsNonVirtual = nonVirtual };
    }

    /// <summary>
    /// Writes a property. The setter is an ordinary method, so this is a call;
    /// the node exists only so the assignment can still yield the value it
    /// stored, which a setter's own <c>void</c> return cannot.
    /// </summary>
    private BoundExpression BindPropertyAssignment(
        AssignmentSyntax syntax, BoundCall read, PropertySymbol property)
    {
        // Null for a static property, which is written by naming the type.
        var receiver = read.Receiver;

        // A struct's setter writes into the receiver's own storage, so this is
        // a write to the parameter exactly as `p.field = x` is.
        if (receiver is not null)
        {
            if (WrittenParameter(receiver) is { } mutated) mutated.IsAssigned = true;
            InvalidateVariantFact(receiver);
        }

        var value = BindExpression(syntax.Value);
        if (value.Type.IsError() || property.Type.IsError())
            return new BoundErrorExpression(syntax.Span);

        if (property.Setter is not { } setter)
        {
            // A get-only automatic property is still storage, and the type's own
            // constructor is where storage gets filled in.
            if (property.BackingField is { } backing && receiver is not null &&
                syntax.Operator == TokenKind.Equals &&
                _currentFunction is { Kind: FunctionKind.Constructor } ctor &&
                ctor.ContainingType == property.ContainingType)
            {
                var storage = new BoundFieldAccess(syntax.Target.Span, receiver, backing);
                return new BoundAssignment(syntax.Span, storage,
                    BindConversion(value, property.Type, syntax.Value.Span));
            }

            diagnostics.Error("SL0395", syntax.Target.Span,
                $"'{property.ContainingType.Name}.{property.Name}' has no setter" +
                (property.ContainingType is InterfaceTypeSymbol
                    ? ", so the contract does not offer one; declare it 'get; set;'"
                    : property.BackingField is null
                        ? "; it is computed, so there is nothing to write"
                        : "; add 'set;', or assign it in a constructor of " +
                          $"'{property.ContainingType.Name}'"));
            return new BoundErrorExpression(syntax.Span);
        }

        if (!CanReach(setter.IsPublic, setter.IsProtected, property.ContainingType))
        {
            diagnostics.Error("SL0396", syntax.Target.Span,
                setter.IsProtected
                    ? $"'{property.ContainingType.Name}.{property.Name}' can be read from " +
                      $"anywhere but written only by '{property.ContainingType.Name}' and " +
                      "classes deriving from it"
                    : $"'{property.ContainingType.Name}.{property.Name}' can be read from " +
                      "anywhere but only written inside its own module");
            return new BoundErrorExpression(syntax.Span);
        }

        // A struct's setter writes the receiver's own storage, so writing one
        // through a `static readonly` writes the static. A class's setter writes
        // the object rather than the static, and a readonly static may hold an
        // object whose fields still change.
        if (property.ContainingType is StructTypeSymbol && receiver is not null &&
            BaseOf(receiver) is BoundStaticAccess { Static.IsReadonly: true } owner)
        {
            diagnostics.Error("SL0379", syntax.Target.Span,
                $"'{owner.Static.Name}' is 'static readonly', so it is written once by its " +
                "initializer -- and setting a field of the struct it holds is writing it");
            return new BoundErrorExpression(syntax.Span);
        }

        // A struct's setter writes through a pointer, so a temporary receiver
        // would be written and then thrown away.
        if (property.ContainingType is StructTypeSymbol && receiver is not null &&
            receiver is BoundAddressOf { Operand: var target } && !IsRepeatable(target))
        {
            diagnostics.Error("SL0399", syntax.Target.Span,
                $"'{property.ContainingType.Name}.{property.Name}' is being set on a temporary " +
                "struct, so the write would be discarded; assign to a variable first");
            return new BoundErrorExpression(syntax.Span);
        }

        if (syntax.Operator != TokenKind.Equals)
        {
            // `p.X += 1` reads through the getter and writes through the setter,
            // so the receiver is evaluated twice. Requiring it to be a plain load
            // is what makes that harmless.
            if (receiver is not null && !IsRepeatable(receiver))
            {
                diagnostics.Error("SL0397", syntax.Target.Span,
                    $"'{property.ContainingType.Name}.{property.Name}' is a property, so this " +
                    "would call the getter and the setter on separately evaluated receivers; " +
                    "put the receiver in a variable first");
                return new BoundErrorExpression(syntax.Span);
            }

            var (op, token) = CompoundOperator(syntax.Operator);
            value = BindBinaryOperation(syntax.Span, read, op, value, token);
            if (value.Type.IsError()) return new BoundErrorExpression(syntax.Span);
        }

        // For an indexer, the read that got here already bound and converted
        // the indices, so they are carried over rather than bound again --
        // binding twice would evaluate them twice.
        // `base.P = x` reaches the setter this class replaced, on the same
        // terms as the getter above: the read that got here already worked out
        // which it was, so the answer is carried across rather than decided
        // twice.
        NoteMemberWritten(property);
        return new BoundPropertyAssignment(syntax.Span, receiver, property,
            BindConversion(value, property.Type, syntax.Value.Span))
        {
            Indices = property.IsIndexer ? read.Arguments : [],
            IsNonVirtual = read.IsNonVirtual,
        };
    }

    /// <summary>
    /// True when evaluating this expression again has no consequences: it reads
    /// storage or computes from constants, rather than doing anything.
    ///
    /// A call is deliberately absent, which is what makes this useful: it is
    /// exactly the question a lowering has to ask before naming its operand
    /// twice.
    /// </summary>
    private static bool IsRepeatable(BoundExpression expression) => expression switch
    {
        BoundLiteral or BoundStringLiteral or BoundNullLiteral or BoundConstantAccess => true,
        BoundLocalAccess or BoundParameterAccess or BoundThis or BoundStaticAccess => true,
        BoundFieldAccess field => field.Receiver is null || IsRepeatable(field.Receiver),
        BoundDereference dereference => IsRepeatable(dereference.Operand),
        BoundAddressOf address => IsRepeatable(address.Operand),
        BoundConversion conversion => IsRepeatable(conversion.Operand),
        BoundUnary unary => IsRepeatable(unary.Operand),
        BoundBinary binary => IsRepeatable(binary.Left) && IsRepeatable(binary.Right),
        _ => false,
    };

    /// <summary>
    /// The accessor of an indexer that takes this index, or null.
    ///
    /// Walks the base chain, because an indexer is inherited like any other
    /// member. Overloaded on the index type, so `this[nuint]` and
    /// `this[String]` can both be declared and asking with one does not find
    /// the other.
    /// </summary>
    private FunctionSymbol? FindIndexer(NamedTypeSymbol type, BoundExpression index, bool setting)
    {
        for (NamedTypeSymbol? at = type; at is not null;
             at = (at as ClassTypeSymbol)?.BaseClass)
        {
            foreach (var property in at.Properties.Where(p => p.IsIndexer))
            {
                var accessor = setting ? property.Setter : property.Getter;
                if (accessor is null) continue;

                // Parameter 0 is `this`; parameter 1 is the index. A setter's
                // last parameter is `value` and is not one of the indices.
                var indices = accessor.Parameters.Where(p => !p.IsThis).ToList();
                if (setting && indices.Count > 0) indices.RemoveAt(indices.Count - 1);

                if (indices.Count == 1 && IsImplicitlyConvertible(index, indices[0].Type))
                    return accessor;
            }
        }

        return null;
    }

    /// <summary>
    /// <c>a[i]</c> or <c>a[i] = v</c>, as the call it lowers to.
    /// </summary>
    private BoundExpression BuildIndexerCall(
        SourceSpan span, FunctionSymbol accessor, BoundExpression target,
        BoundExpression index, BoundExpression? value)
    {
        var indices = accessor.Parameters.Where(p => !p.IsThis).ToList();

        var arguments = new List<BoundExpression>
        {
            BindConversion(index, indices[0].Type, span),
        };

        if (value is not null)
            arguments.Add(BindConversion(value, indices[^1].Type, span));

        // A struct's method takes its receiver by pointer, as everywhere else.
        var receiver = accessor.ContainingType is StructTypeSymbol
            ? new BoundAddressOf(span, new PointerTypeSymbol(target.Type), target)
            : target;

        return new BoundCall(span, accessor, receiver, arguments);
    }

    private BoundExpression BindIndex(IndexSyntax syntax)
    {
        var target = BindExpression(syntax.Target);
        var index = BindExpression(syntax.Index);

        if (target.Type.IsError() || index.Type.IsError())
            return new BoundErrorExpression(syntax.Span);

        // A type's own indexer. Reached through the getter it lowers to, which
        // is why nothing here has to know that a property was involved.
        if (target.Type is NamedTypeSymbol named && FindIndexer(named, index, false) is { } getter)
            return BuildIndexerCall(syntax.Span, getter, target, index, null);

        if (target.Type is not (PointerTypeSymbol or ArrayTypeSymbol or SliceTypeSymbol
                                or FixedArrayTypeSymbol))
        {
            diagnostics.Error("SL0241", syntax.Span,
                target.Type is NamedTypeSymbol subject && subject.Properties.Any(p => p.IsIndexer)
                    ? $"no indexer on '{target.Type.Name}' takes '{index.Type.Name}'"
                    : $"cannot index '{target.Type.Name}'; only arrays, slices and pointers " +
                      "support indexing, and this type declares no 'this[...]'");
            return new BoundErrorExpression(syntax.Span);
        }

        if (index.Type is not PrimitiveTypeSymbol { IsInteger: true })
        {
            diagnostics.Error("SL0242", syntax.Index.Span,
                $"an index must be an integer, but this is '{index.Type.Name}'");
            return new BoundErrorExpression(syntax.Span);
        }

        // Any integer indexes an array, as in C#. A negative one sign-extends to
        // a very large unsigned value, so the single unsigned bounds compare in
        // the emitter catches it without a second check.
        // An inline array's length is part of its type, so a constant index can
        // be answered now rather than at run time. That is strictly better than
        // what `T[]` can do, and it is the whole reason the length is in the
        // type: the check is free and the failure is a compile error.
        if (target.Type is FixedArrayTypeSymbol inline)
        {
            if (FoldSwitchLabel(index) is { } constant &&
                constant <= long.MaxValue && (long)constant >= inline.Length)
            {
                diagnostics.Error("SL0490", syntax.Index.Span,
                    $"index {constant} is past the end of '{inline.Name}', which has " +
                    $"{Counted(inline.Length, "element")}");
                return new BoundErrorExpression(syntax.Span);
            }

            return new BoundIndex(syntax.Span, inline.Element, target, PromoteToInt(index));
        }

        if (target.Type is ArrayTypeSymbol array)
            return new BoundIndex(syntax.Span, array.Element, target, PromoteToInt(index));

        if (target.Type is SliceTypeSymbol slice)
            return new BoundIndex(syntax.Span, slice.Element, target, PromoteToInt(index));

        var pointer = (PointerTypeSymbol)target.Type;
        return new BoundIndex(syntax.Span, pointer.Element, target, PromoteToInt(index));
    }

    /// <summary>
    /// <c>a[from:to]</c> over an array or another slice.
    ///
    /// Slicing a slice narrows it rather than nesting: the result names the same
    /// array, further in. So there is one indirection however many times a slice
    /// has been cut, and the array underneath is kept alive by whichever slices
    /// still name it.
    /// </summary>
    private BoundExpression BindSlice(SliceSyntax syntax)
    {
        var target = BindExpression(syntax.Target);
        if (target.Type.IsError()) return new BoundErrorExpression(syntax.Span);

        var element = target.Type switch
        {
            ArrayTypeSymbol array => array.Element,
            SliceTypeSymbol slice => slice.Element,
            _ => null,
        };

        if (element is null)
        {
            diagnostics.Error("SL0452", syntax.Span,
                $"cannot slice '{target.Type.Name}'; slicing takes part of an array or of " +
                "another slice");
            return new BoundErrorExpression(syntax.Span);
        }

        var start = BindBound(syntax.Start);
        var end = BindBound(syntax.End);

        if (start?.Type.IsError() == true || end?.Type.IsError() == true)
            return new BoundErrorExpression(syntax.Span);

        return new BoundSlice(syntax.Span, SliceOf(element), target, start, end);
    }

    /// <summary>One end of a slice, or null where the source left it out.</summary>
    private BoundExpression? BindBound(ExpressionSyntax? syntax)
    {
        if (syntax is null) return null;

        var bound = BindExpression(syntax);
        if (bound.Type.IsError()) return bound;

        if (bound.Type is not PrimitiveTypeSymbol { IsInteger: true })
        {
            diagnostics.Error("SL0242", syntax.Span,
                $"a slice bound must be an integer, but this is '{bound.Type.Name}'");
            return new BoundErrorExpression(syntax.Span);
        }

        return BindConversion(bound, PrimitiveTypeSymbol.NUInt, syntax.Span);
    }

    /// <summary>
    /// <c>T[N]</c>. The length has to be known now, because it is part of the
    /// type and the type decides a layout -- so it is a literal or a constant
    /// and nothing else.
    /// </summary>
    private TypeSymbol ResolveFixedArray(FixedArrayTypeSyntax syntax, FileScope scope)
    {
        var element = ResolveType(syntax.Element, scope, allowVoid: true);
        if (element.IsError()) return element;

        if (element.IsVoid())
        {
            diagnostics.Error("SL0310", syntax.Span, "there is no array of 'void'");
            return ErrorTypeSymbol.Instance;
        }

        // A counted reference in an inline array would have to be retained
        // element by element on every copy of whatever holds it. That is the
        // same question a union cannot answer, and the answer here is the same
        // one for now: plain data.
        if (element.CarriesReferences())
        {
            diagnostics.Error("SL0486", syntax.Span,
                $"an inline array cannot hold '{element.Name}', because it holds a " +
                "counted reference and every copy of the array would have to retain " +
                $"each element. Use '{element.Name}[]', which is one counted object " +
                "rather than N of them");
            return ErrorTypeSymbol.Instance;
        }

        if (ConstantLength(syntax.Length, scope) is not { } length)
        {
            diagnostics.Error("SL0487", syntax.Length.Span,
                "the length of an inline array must be a constant, because it is " +
                "part of the type: an integer literal, or a 'const' holding one");
            return ErrorTypeSymbol.Instance;
        }

        if (length <= 0)
        {
            diagnostics.Error("SL0488", syntax.Length.Span,
                $"an inline array needs at least one element, and this asks for {length}");
            return ErrorTypeSymbol.Instance;
        }

        // The product has to stay addressable. This is far past any real struct
        // and exists so that a typo produces a diagnostic rather than a
        // nonsensical size.
        long bytes = (long)element.Size * length;
        if (bytes > int.MaxValue)
        {
            diagnostics.Error("SL0489", syntax.Length.Span,
                $"'{element.Name}[{length}]' would be {bytes} bytes, which is more " +
                "than a value can be");
            return ErrorTypeSymbol.Instance;
        }

        return new FixedArrayTypeSymbol(element, (int)length);
    }

    /// <summary>
    /// The value of an inline array's length: an integer literal, or a name that
    /// reaches a constant holding one.
    /// </summary>
    private long? ConstantLength(ExpressionSyntax syntax, FileScope scope)
    {
        switch (syntax)
        {
            case LiteralSyntax { Kind: TokenKind.IntLiteral, Value: ulong number }:
                return number > long.MaxValue ? null : (long)number;

            case NameSyntax name when name.Name.Parts.Count == 1:
                return LookUpConstant(scope.Module, name.Name.Parts[0], scope);

            case MemberAccessSyntax { Target: NameSyntax target } member
                when target.Name.Parts.Count == 1 &&
                     scope.Imports.TryGetValue(target.Name.Parts[0], out var imported):
                return LookUpConstant(imported, member.Member, scope, requirePublic: true);

            default:
                return null;
        }
    }

    private long? LookUpConstant(
        ModuleSymbol module, string name, FileScope scope, bool requirePublic = false)
    {
        if (!module.Constants.TryGetValue(name, out var constant))
        {
            foreach (var imported in scope.Imports.Values)
                if (imported.Constants.TryGetValue(name, out var candidate) && candidate.IsPublic)
                {
                    constant = candidate;
                    break;
                }

            if (constant is null) return null;
        }
        else if (requirePublic && !constant.IsPublic)
        {
            return null;
        }

        return constant.Value is ulong number && number <= long.MaxValue ? (long)number : null;
    }
}
