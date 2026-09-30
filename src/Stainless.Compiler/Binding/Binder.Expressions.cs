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

    private BoundExpression BindExpression(ExpressionSyntax syntax)
    {
        if (++_bindDepth > Source.Recursion.MaxDepth)
        {
            _bindDepth--;

            // Asked of the bag rather than remembered: a trial bind reports
            // into a muted bag, or one that is rewound, and the real bind
            // after it MUST still say why the expression is an error.
            if (!diagnostics.Items.Any(d => d.Code == "SL0108"))
            {
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
        FieldKeywordSyntax storage => BindFieldKeyword(storage),
        BaseSyntax baseExpression => BindBaseValue(baseExpression),
        IsPatternSyntax matched => BindIsPattern(matched),
        AsCastSyntax asCast => BindAsCast(asCast),
        SwitchExpressionSyntax chosen => BindSwitchExpression(chosen),
        UnarySyntax unary => BindUnary(unary),
        IncrementSyntax increment => BindIncrement(increment),
        NameofSyntax nameOf => BindNameof(nameOf),
        CheckedSyntax guarded => BindChecked(guarded),
        DefaultSyntax zeroed => BindDefault(zeroed),
        NullForgivingSyntax forgiven => BindNullForgiving(forgiven),
        TupleSyntax tuple => BindTuple(tuple),
        DeclarationExpressionSyntax declaration => RefuseDeclarationExpression(declaration),
        BinarySyntax binary => BindBinary(binary),
        AssignmentSyntax assignment => BindAssignment(assignment),
        CallSyntax call => BindCall(call),
        MemberAccessSyntax member => BindMemberAccess(member),
        SliceSyntax slice => BindSlice(slice),
        IndexSyntax index => BindIndex(index),
        IndexFromEndSyntax fromEnd => BindIndexFromEnd(fromEnd),
        RangeSyntax range => BindRange(range),
        NewSyntax newExpression => BindNew(newExpression),
        WithSyntax changed => BindWith(changed),
        NewArraySyntax newArray => BindNewArray(newArray),
        ConditionalSyntax conditional => BindConditional(conditional),
        LambdaSyntax lambda => new BoundLambda(lambda.Span, LambdaType.Instance, lambda),
        InterpolatedStringSyntax interpolated => BindInterpolatedString(interpolated),
        TrySyntax attempt => BindTry(attempt),
        SpawnExpressionSyntax spawn => BindMisplacedSpawn(spawn),
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
            var written = part.Format is { } format
                ? AsFormattedText(value, format, part.FormatSpan ?? part.Value!.Span, part.Value!.Span)
                : AsText(value, part.Value!.Span);

            if (part.Alignment is { } alignment)
                written = AsAlignedText(written, BindExpression(alignment), alignment.Span);

            parts.Add(written);
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
        if (AsFormattable(value, "", span) is { } written) return written;

        if (value.Type is EnumTypeSymbol enumType)
            return EnumText(value, enumType, span);

        // A code unit is not a character, and the cast that says which is
        // meant is the same one SL0527 asks for everywhere else.
        if (value.Type is PrimitiveTypeSymbol
            { Kind: PrimitiveKind.Char or PrimitiveKind.Char16 } unit)
        {
            diagnostics.Error("SL0557", span,
                $"'{unit.Name}' is one code unit, not a character, so what it should write " +
                "is not decided: '(char32)' writes the character its value names, and " +
                "'(long)' writes the number",
                unit);
            return new BoundErrorExpression(span);
        }

        var conversion = TextConversionFor(value.Type);
        if (conversion is null)
        {
            diagnostics.Error("SL0557", span,
                $"'{value.Type.Name}' has no text to write here. An interpolation takes a " +
                "String or a number, a bool or a char; anything else needs a conversion " +
                "written out, because there is no 'ToString' every type owes",
                value.Type);
            return new BoundErrorExpression(span);
        }

        // The argument is converted first: FromInteger takes a long, and a byte
        // reaching it has to widen exactly as it would at any other call.
        var argument = BindConversion(value, conversion.Parameters[0].Type, span);
        return new BoundCall(span, conversion, receiver: null, [argument]);
    }

    /// <summary>
    /// <c>{value:format}</c>: a number in a standard numeric format, or a class
    /// that implements <c>IFormattable</c> handed the format to read.
    ///
    /// A number's format is checked here, because it is text in the source and
    /// its type is known: a letter the type does not take would otherwise
    /// stop the program the first time the line ran. A class's format means
    /// what the class says and is passed through unread.
    /// </summary>
    private BoundExpression AsFormattedText(
        BoundExpression value, string format, SourceSpan formatSpan, SourceSpan span)
    {
        if (value.Type.IsError()) return value;
        if (AsFormattable(value, format, span) is { } written) return written;

        bool isInteger = value.Type is PrimitiveTypeSymbol
        {
            IsInteger: true, IsCodeUnit: false, Kind: not PrimitiveKind.Bool,
        };
        bool isFloat = value.Type is PrimitiveTypeSymbol { IsFloat: true };

        if (!isInteger && !isFloat)
        {
            // What has text but no format is told so; anything else gets the
            // reason it has no text at all.
            var plain = AsText(value, span);
            if (plain is BoundErrorExpression) return plain;

            diagnostics.Error("SL0753", formatSpan,
                $"'{value.Type.Name}' is written as it is and takes no format; a format " +
                "is for a number, or for a class that implements 'IFormattable'",
                value.Type);
            return new BoundErrorExpression(span);
        }

        if (StandardFormatProblem(format, isInteger) is { } problem)
        {
            diagnostics.Error("SL0753", formatSpan, problem);
            return new BoundErrorExpression(span);
        }

        var formatText = new BoundStringLiteral(formatSpan, _builtins.String, format);
        if (isFloat)
        {
            var asDouble = BindConversion(value, PrimitiveTypeSymbol.Double, span);
            return new BoundCall(span, _builtins.TextFormatDouble, receiver: null, [asDouble, formatText]);
        }

        var integer = (PrimitiveTypeSymbol)value.Type;

        // Hexadecimal and binary write a signed value's two's complement at
        // its own width, as C# does, so -1 as an int is FFFFFFFF rather than
        // sixteen Fs. Reinterpreting it as the unsigned type of that width
        // before widening is what keeps the width.
        if (integer.IsSigned && format[0] is 'X' or 'x' or 'B' or 'b')
        {
            var unsigned = UnsignedOfWidth(integer);
            value = new BoundConversion(span, unsigned, value,
                ClassifyConversion(integer, unsigned, explicitCast: true)!.Value);
            integer = unsigned;
        }

        var (function, wide) = integer.IsSigned
            ? (_builtins.TextFormatLong, PrimitiveTypeSymbol.Long)
            : (_builtins.TextFormatULong, PrimitiveTypeSymbol.ULong);

        return new BoundCall(span, function, receiver: null,
            [BindConversion(value, wide, span), formatText]);
    }

    /// <summary>The unsigned integer type as wide as <paramref name="signed"/>.</summary>
    private static PrimitiveTypeSymbol UnsignedOfWidth(PrimitiveTypeSymbol signed) => signed.Kind switch
    {
        PrimitiveKind.SByte => PrimitiveTypeSymbol.Byte,
        PrimitiveKind.Short => PrimitiveTypeSymbol.UShort,
        PrimitiveKind.Int => PrimitiveTypeSymbol.UInt,
        PrimitiveKind.NInt => PrimitiveTypeSymbol.NUInt,
        _ => PrimitiveTypeSymbol.ULong,
    };

    /// <summary>
    /// Why <paramref name="format"/> is not a standard numeric format for an
    /// integer or a floating-point number, or null when it is one. The forms
    /// are those <c>Text.FormatInteger</c> and <c>Text.FormatDouble</c> take:
    /// a letter, then up to three digits of precision.
    /// </summary>
    private static string? StandardFormatProblem(string format, bool isInteger)
    {
        const string IntegerLetters = "DdXxBbFfNnEeGg";
        const string FloatLetters = "FfNnEeGg";

        string letters = isInteger ? IntegerLetters : FloatLetters;
        string what = isInteger ? "an integer" : "a floating-point number";
        string offered = isInteger
            ? "'D', 'X', 'B', 'F', 'N', 'E' and 'G'"
            : "'F', 'N', 'E' and 'G'";

        if (format.Length == 0)
            return "this format is empty; write a letter after the ':', or leave the ':' out";

        if (!letters.Contains(format[0]))
            return $"'{format}' is not a format for {what}; the standard ones are {offered}, " +
                   "each with an optional precision, as in 'X8' or 'F2'. A custom pattern " +
                   "such as '0.00' is not supported";

        string precision = format[1..];
        if (precision.Length > 3 || !precision.All(char.IsAsciiDigit))
            return $"'{format}' is not a format for {what}: after the letter comes a precision " +
                   "of up to three digits, and nothing else";

        return null;
    }

    /// <summary>
    /// A value's own text through <c>IFormattable.ToText</c>, or null when its
    /// type does not implement it. A class's call goes through the interface,
    /// so a derived class's override is the one that writes.
    /// </summary>
    private BoundExpression? AsFormattable(BoundExpression value, string format, SourceSpan span)
    {
        var formattable = _builtins.Formattable;
        var toText = formattable.FindMethod("ToText")!;

        // A struct is never a reference to the interface, so its own method is
        // called, on the value where it is.
        if (value.Type is StructTypeSymbol structType && structType.AllInterfaces().Contains(formattable) &&
            structType.FindImplementation(toText) is { } own)
            return new BoundCall(span, own,
                new BoundAddressOf(span, structType.MakePointerType(), value),
                [new BoundStringLiteral(span, _builtins.String, format)]);

        if (value.Type is not (ClassTypeSymbol or InterfaceTypeSymbol))
            return null;

        if (!IsImplicitlyConvertible(value, formattable)) return null;

        var receiver = BindConversion(value, formattable, span);
        return new BoundCall(span, toText, receiver,
            [new BoundStringLiteral(span, _builtins.String, format)]);
    }

    /// <summary>
    /// <c>{value,width}</c>: the text padded to a width, on the left when it is
    /// positive and on the right when it is negative. The width MUST be a
    /// constant, as in C#, so that it is part of the string's shape rather
    /// than something computed on the way.
    /// </summary>
    private BoundExpression AsAlignedText(BoundExpression text, BoundExpression alignment, SourceSpan span)
    {
        if (text.Type.IsError() || alignment.Type.IsError()) return text;

        if (IntegerLiteral(alignment) is not { } written || written.Magnitude > int.MaxValue)
        {
            diagnostics.Error("SL0754", span,
                "an interpolation's alignment is a constant integer, as in '{value,8}' or " +
                "'{value,-8}'; pad to a width known only when the program runs with " +
                "'Text.AlignText'");
            return text;
        }

        long width = written.Negative ? -(long)written.Magnitude : (long)written.Magnitude;
        if (width == 0) return text;

        var literal = new BoundLiteral(span, PrimitiveTypeSymbol.Int, unchecked((ulong)width));
        return new BoundCall(span, _builtins.TextAlignText, receiver: null, [text, literal]);
    }

    private readonly Dictionary<EnumTypeSymbol, FunctionSymbol> _enumTexts = [];

    /// <summary>
    /// An enum value as its member's name: what <c>$"{value}"</c> and
    /// <c>value.ToText()</c> both write, and what .NET's <c>Enum.ToString</c>
    /// writes. A value one member has is that member's name, the first
    /// declared where two share it. A <c>[Flags]</c> value is the members
    /// that cover it, largest first, written smallest first and joined by
    /// <c>", "</c>. Anything else is the number.
    ///
    /// The call is to a function the emitter writes, one per enum formatted.
    /// </summary>
    private BoundExpression EnumText(
        BoundExpression value, EnumTypeSymbol enumType, SourceSpan span)
    {
        if (!_enumTexts.TryGetValue(enumType, out var function))
        {
            function = new FunctionSymbol
            {
                Name = "ToText",
                ModuleName = enumType.ModuleName,
                ReturnType = _builtins.String,
                Linkage = LinkageKind.Stainless,
                Span = enumType.Span ?? span,
                TextOfEnum = enumType,
            };
            function.Parameters.Add(new ParameterSymbol("value", enumType, 0));
            _enumTexts[enumType] = function;
        }

        return new BoundCall(span, function, receiver: null, [value]);
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
        } => _builtins.TextFromULong,

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
    /// <summary>
    /// A <c>spawn</c> that is not a statement of its own. The parser folds the
    /// two shapes that are — <c>spawn f(x);</c> and <c>result = spawn f(x);</c>
    /// — into a <see cref="SpawnSyntax"/>, so anything reaching here is a
    /// <c>spawn</c> whose value someone expected to be able to use, and there
    /// is no value: the call has not run yet, and will not have until the join.
    /// </summary>
    private BoundExpression BindMisplacedSpawn(SpawnExpressionSyntax syntax)
    {
        diagnostics.Error("SL0390", syntax.Span,
            "'spawn' has no value to give this expression -- the call has not run yet, and " +
            "will not have until the 'parallel' block closes. Write it as a statement of its " +
            "own, 'spawn f(x);', or store it in something that outlives the block, " +
            "'result = spawn f(x);'");
        return new BoundErrorExpression(syntax.Span);
    }

    private BoundExpression BindTry(TrySyntax syntax)
    {
        var operand = BindExpression(syntax.Operand);
        if (operand.Type.IsError()) return operand;

        if (operand.Type is not VariantTypeSymbol source || !IsResult(source))
        {
            diagnostics.Error("SL0569", syntax.Operand.Span,
                $"'try' takes a 'Result', and this is '{operand.Type.Name}'; there is nothing " +
                "here that could have failed",
                operand.Type);
            return new BoundErrorExpression(syntax.Span);
        }

        // The failure has to go somewhere, and the only place is the caller.
        if (_context.Function?.ReturnType is not VariantTypeSymbol target || !IsResult(target))
        {
            diagnostics.Error("SL0570", syntax.Span,
                _context.Function is null
                    ? "'try' passes a failure to the caller, so it belongs in a function"
                    : $"'{_context.Function.Name}' returns '{_context.Function.ReturnType.Name}', " +
                      "so a failure has nowhere to go. A function containing 'try' returns a " +
                      "'Result'; use 'GetValueOrDefault' for a caller that has a sensible default",
                _context.Function.ReturnType);
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
                $"this fails with '{carried.Name}' and '{_context.Function.Name}' fails with " +
                $"'{wanted.Name}'. 'try' passes a failure on unchanged, so convert it first: " +
                "check it and return the failure you mean",
                carried, wanted);
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
    ///
    /// <para><c>u</c> and <c>l</c> raise that floor. The magnitude rule alone
    /// makes <c>20u</c> an <c>int</c>, because twenty fits one -- so the suffix
    /// the lexer accepts and checks meant nothing at all, and
    /// <c>nuint n = 20u * 4u;</c> was refused for multiplying two
    /// <c>int</c>s. A suffix exists to say what the digits cannot; this is
    /// where it gets to.</para>
    /// </summary>
    private static PrimitiveTypeSymbol LiteralType(object? value, string text)
    {
        if (value is not ulong number) return PrimitiveTypeSymbol.Int;

        bool unsigned = false;
        bool wide = false;

        // Only the trailing letters are a suffix. A hex literal's digits run to
        // 'f', and `0xDul` ends in one of each -- so this walks back from the
        // end rather than searching the text.
        for (int i = text.Length - 1; i >= 0; i--)
        {
            char c = char.ToLowerInvariant(text[i]);
            if (c == 'u') { unsigned = true; continue; }
            if (c == 'l') { wide = true; continue; }
            break;
        }

        // The suffix names a floor and the magnitude names another; the answer
        // is whichever is higher. `4294967296u` is a `ulong` because it has to
        // be, not a `uint` because that is what the letter asked for.
        if (unsigned && wide) return PrimitiveTypeSymbol.ULong;
        if (unsigned)
            return number <= uint.MaxValue ? PrimitiveTypeSymbol.UInt : PrimitiveTypeSymbol.ULong;
        if (wide)
            return number <= long.MaxValue ? PrimitiveTypeSymbol.Long : PrimitiveTypeSymbol.ULong;

        return number switch
        {
            <= int.MaxValue => PrimitiveTypeSymbol.Int,
            <= uint.MaxValue => PrimitiveTypeSymbol.UInt,
            <= long.MaxValue => PrimitiveTypeSymbol.Long,
            _ => PrimitiveTypeSymbol.ULong,
        };
    }

    /// <summary>
    /// <c>point with { Y = 5 }</c>: a copy of the record, made by its
    /// <c>$Clone</c>, with the named properties written through their setters.
    /// </summary>
    /// <remarks>
    /// <para>
    /// The copy is dispatched, as C#'s is, so a derived record reached through
    /// its base comes back whole rather than as the base, and a value its base
    /// computed from a parameter is copied rather than computed again.
    /// </para>
    /// </remarks>
    private BoundExpression BindWith(WithSyntax syntax)
    {
        var target = BindExpression(syntax.Target);
        if (target.Type.IsError()) return new BoundErrorExpression(syntax.Span);

        if (target.Type is not ClassTypeSymbol { RecordParameters.Count: > 0 } record ||
            RecordClone(record) is not { } clone)
        {
            diagnostics.Error("SL0735", syntax.Span,
                $"'with' makes a copy of a record with some of it changed, and " +
                $"'{target.Type.Name}' is not a record; give it positional parameters, or " +
                "write out the construction this would have made",
                target.Type);
            return new BoundErrorExpression(syntax.Span);
        }

        // A positional parameter is a property with an init setter, and any
        // other property with a setter, init or not, may be named too.
        var given = new HashSet<string>(StringComparer.Ordinal);
        var written = new List<BoundWithAssignment>();

        foreach (var assignment in syntax.Assignments)
        {
            var property = record.FindProperty(assignment.Name);

            if (property is not { Setter: not null, IsIndexer: false })
            {
                diagnostics.Error("SL0736", assignment.Span,
                    $"'{record.Name}' has no parameter or settable property named " +
                    $"'{assignment.Name}', so there is nothing for this to change; it takes " +
                    $"{Listed(record.RecordParameters)}",
                    record);
                continue;
            }

            bool positional =
                record.RecordParameters.Contains(assignment.Name, StringComparer.Ordinal);
            if (!positional && property.Setter is { } setter &&
                !CanReach(setter.IsPublic, setter.IsProtected, property.ContainingType))
            {
                diagnostics.Error("SL0249", assignment.Span,
                    NotVisible(property.ContainingType, property.Name, setter.IsProtected));
                continue;
            }

            var value = BindExpression(assignment.Value);
            if (!given.Add(assignment.Name))
            {
                diagnostics.Error("SL0737", assignment.Span,
                    $"'{assignment.Name}' is given a value twice here, and the second would " +
                    "silently be the one that counted");
                continue;
            }

            written.Add(new BoundWithAssignment(assignment.Span, property,
                BindConversion(value, property.Type, assignment.Value.Span)));
        }

        if (diagnostics.HasErrors) return new BoundErrorExpression(syntax.Span);

        return new BoundWith(syntax.Span, record, target, clone, written);
    }

    /// <summary>Names in a list, for a diagnostic that offers them.</summary>
    private static string Listed(IReadOnlyList<string> names) =>
        names.Count == 1 ? $"'{names[0]}'" : string.Join(", ", names.Select(n => $"'{n}'"));

    private BoundExpression BindLiteral(LiteralSyntax syntax) => syntax.Kind switch
    {
        TokenKind.IntLiteral => new BoundLiteral(
            syntax.Span, LiteralType(syntax.Value, syntax.Text), syntax.Value),
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
        // `"..."u8` is a view of bytes in read-only storage that exist for the
        // whole program, so its type is a view that refuses a write.
        TokenKind.Utf8StringLiteral => new BoundConversion(
            syntax.Span, SliceOf(PrimitiveTypeSymbol.Byte, readOnly: true),
            new BoundUtf8Literal(syntax.Span, ArrayOf(PrimitiveTypeSymbol.Byte), (string)syntax.Value!),
            ConversionKind.ArrayToSlice),
        TokenKind.NullKeyword => new BoundNullLiteral(syntax.Span, NullType.Instance),
        _ => new BoundErrorExpression(syntax.Span),
    };

    /// <summary>
    /// <c>var xs = flag ? [1, 2] : [3L];</c>: each arm settled from its own
    /// elements, and then the two brought to the type they share.
    /// </summary>
    private BoundExpression SettleArraysFromElements(BoundConditional chosen)
    {
        var whenTrue = SettleArrayFromElements((BoundArrayDraft)chosen.WhenTrue);
        var whenFalse = SettleArrayFromElements((BoundArrayDraft)chosen.WhenFalse);
        if (whenTrue.Type.IsError() || whenFalse.Type.IsError())
            return new BoundErrorExpression(chosen.Span);

        if (CommonArmType(whenTrue, whenFalse) is not { } type)
        {
            diagnostics.Error("SL0349", chosen.Span,
                $"the arms of a conditional have no common type: one is " +
                $"'{whenTrue.Type.Name}', the other '{whenFalse.Type.Name}'",
                whenTrue.Type, whenFalse.Type);
            return new BoundErrorExpression(chosen.Span);
        }

        return new BoundConditional(chosen.Span, type, chosen.Condition,
            BindConversion(whenTrue, type, whenTrue.Span),
            BindConversion(whenFalse, type, whenFalse.Span));
    }

    private BoundExpression BindThis(ThisSyntax syntax)
    {
        // Inside a lambda, `this` is the object the lambda was written in. The
        // generated closure also has a `this`, and letting the keyword mean
        // that one silently rebound the programmer's word to a type they never
        // wrote.
        if (_context.Closures.Count > 0)
            return CaptureThis(_context.Closures.Count - 1, syntax.Span);

        ReportReachingTheObject(syntax.Span);

        var parameter = _context.Function?.Parameters.FirstOrDefault(p => p.IsThis);
        if (parameter is null && TryGiveLocalFunctionThis(_context.Function, syntax.Span))
            return new BoundErrorExpression(syntax.Span);

        if (parameter is null)
        {
            diagnostics.Error("SL0228", syntax.Span,
                _context.Function is { IsStatic: true } enclosing
                    ? $"'{enclosing.Name}' is static, so there is no 'this': it belongs to " +
                      $"'{enclosing.ContainingType!.Name}' rather than to one of them. Take " +
                      "the object as a parameter, or drop the 'static'"
                    : "'this' is only valid inside a method, constructor or destructor");
            return new BoundErrorExpression(syntax.Span);
        }
        return Receiver(syntax.Span, parameter);
    }

    /// <summary>
    /// <c>field</c>: the storage of the property whose accessor this is, read
    /// through <c>this</c> as any field is, so a lambda captures the object.
    /// </summary>
    private BoundExpression BindFieldKeyword(FieldKeywordSyntax syntax)
    {
        var owner = _context.Closures.Count > 0
            ? _context.Closures[0].OuterFunction?.ContainingType
            : _context.Function?.ContainingType;

        var property = owner?.Properties.FirstOrDefault(p => p.Name == syntax.Property);

        if (property?.StaticBacking is { } shared)
            return new BoundStaticAccess(syntax.Span, shared);

        // An interface or an abstract property has no storage, and its body
        // was refused where it was written.
        if (property?.BackingField is not { } storage)
            return new BoundErrorExpression(syntax.Span);

        var receiver = BindThis(new ThisSyntax(syntax.Span));
        if (receiver.Type.IsError()) return receiver;

        return new BoundFieldAccess(syntax.Span, receiver, storage);
    }

    /// <summary>
    /// The receiver expression for a method's implicit instance. A class method
    /// holds the reference directly; a struct method holds a pointer to the value,
    /// so it is dereferenced back into an lvalue here.
    /// </summary>
    /// <summary>
    /// The type whose statics and constants a bare name may mean: the current
    /// function's, or inside a lambda the one the lambda was written in, since
    /// the lambda's own is the class it was made into.
    /// </summary>
    private NamedTypeSymbol? EnclosingType
    {
        get
        {
            var function = _context.Function;
            for (int i = _context.Closures.Count - 1;
                 i >= 0 && function is not null &&
                 ReferenceEquals(function.ContainingType, _context.Closures[i].Type);
                 i--)
                function = _context.Closures[i].OuterFunction;

            return function?.ContainingType;
        }
    }

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
        if (_context.Function?.ContainingType is not ClassTypeSymbol here)
        {
            diagnostics.Error("SL0515", span,
                "'base' is only valid inside a class method, constructor or destructor");
            return null;
        }

        if (here.BaseClass is not { } baseClass)
        {
            diagnostics.Error("SL0515", span,
                $"'{here.Name}' derives from nothing, so it has no 'base'",
                here);
            return null;
        }

        if (BindImplicitThis(span) is not { } self) return null;
        return new BoundConversion(span, baseClass, self, ConversionKind.Upcast);
    }

    /// <summary>
    /// Whether an <c>is</c> or a type pattern can ask <paramref name="subject"/>
    /// whether it is a <paramref name="wanted"/>, where at least one of the two
    /// is COM. Reports under <paramref name="code"/> when it cannot.
    ///
    /// A COM object answers for itself, so the only pairings the compiler can
    /// rule out are the ones with nobody to ask: a Stainless reference has no
    /// QueryInterface, a COM one has no header to walk, and a <c>[NoUnknown]</c>
    /// vtable has something else in slot 0 and no IID to ask it with. That last
    /// is the rule the cast already keeps; without it here the test was emitted
    /// against an IID nothing had defined.
    /// </summary>
    private bool CanAskCom(
        string code, SourceSpan span, NamedTypeSymbol subject, NamedTypeSymbol wanted)
    {
        if (wanted is not ComInterfaceTypeSymbol asked)
        {
            diagnostics.Error(code, span,
                $"'{subject.Name}' is a com interface and '{wanted.Name}' is not; all a COM " +
                "reference can be asked is QueryInterface, and that names com interfaces",
                subject, wanted);
            return false;
        }

        if (subject is not ComInterfaceTypeSymbol && subject is not ClassTypeSymbol { IsCom: true })
        {
            diagnostics.Error(code, span,
                $"'{subject.Name}' is not a COM reference, so there is no QueryInterface to " +
                $"ask it whether it is a '{asked.Name}'",
                subject, asked);
            return false;
        }

        var noUnknown = subject is ComInterfaceTypeSymbol { HasUnknown: false }
            ? subject
            : asked.HasUnknown ? null : asked;

        if (noUnknown is not null)
        {
            diagnostics.Error(code, span,
                $"'{noUnknown.Name}' is '[NoUnknown]', so there is no QueryInterface to ask " +
                $"whether '{subject.Name}' is a '{asked.Name}' and no IID to ask it with",
                noUnknown, subject, asked);
            return false;
        }

        return true;
    }

    /// <summary>
    /// <c>x as C</c>: the same question <c>is</c> asks, answered with a value.
    ///
    /// The result is a <c>C?</c>, which is what makes this worth having beside
    /// <c>is C c</c>: an answer that is a value can be passed on, stored, or
    /// given a fallback with <c>??</c>, where a branch can only be entered.
    ///
    /// It is the test and the reference it proved, with nothing else in it, as a
    /// <see cref="BoundAs"/>.
    ///
    /// A conversion that cannot fail does not get a test at all: <c>derived as
    /// Base</c> is the ordinary widening and emits nothing.
    /// </summary>
    private BoundExpression BindAsCast(AsCastSyntax syntax)
    {
        var value = BindExpression(syntax.Value);
        if (value.Type.IsError()) return new BoundErrorExpression(syntax.Span);

        // `x as C?` asks for what `as` already answers. Caught on the syntax,
        // before it resolves to the very type this would return.
        if (syntax.Tested is NullableTypeSyntax written)
        {
            var span = written.Element.Span;
            diagnostics.Error("SL0612", syntax.Tested.Span,
                "'as' answers with an optional already, so the '?' says it twice; write " +
                $"'as {span.File.Text[span.Start..span.End]}'");
            return new BoundErrorExpression(syntax.Span);
        }

        if (value.Type is VariantTypeSymbol asked)
        {
            diagnostics.Error("SL0612", syntax.Span,
                $"'{asked.Name}' is a variant, and which case it holds is asked with 'is' or " +
                "a 'switch'; 'as' is for an object that may or may not be of some class",
                asked);
            return new BoundErrorExpression(syntax.Span);
        }

        if (value.Type is WeakTypeSymbol)
        {
            diagnostics.Error("SL0612", syntax.Span,
                $"'{value.Type.Name}' may already have died, so what it is cannot be asked " +
                "directly; read it into an optional first, which is the check that makes it " +
                "safe to look at",
                value.Type);
            return new BoundErrorExpression(syntax.Span);
        }

        var tested = ResolveType(syntax.Tested, _context.File!);
        if (tested.IsError()) return new BoundErrorExpression(syntax.Span);

        if (tested is not NamedTypeSymbol { IsReferenceType: true } wanted)
        {
            diagnostics.Error("SL0612", syntax.Tested.Span,
                $"'{tested.Name}' is not a class or an interface, so 'as' has nothing to ask " +
                "and nothing to answer null with: every other type is known exactly where it " +
                "is written",
                tested);
            return new BoundErrorExpression(syntax.Span);
        }

        // A COM object answers for itself, and answers again. `(I)x` is the one
        // spelling of that question, for the reason a binding `is` gives: two
        // QueryInterface calls are two answers, and this would need both.
        if (wanted is ComInterfaceTypeSymbol || value.Type.AsReference() is ComInterfaceTypeSymbol)
        {
            diagnostics.Error("SL0612", syntax.Span,
                $"a QueryInterface for '{wanted.Name}' is a call the object answers, so 'as' " +
                $"would ask it twice; cast it instead, as '({wanted.Name})...', which asks once " +
                "and ends the program if the answer was no",
                wanted);
            return new BoundErrorExpression(syntax.Span);
        }

        if (value.Type.AsReference() is not NamedTypeSymbol subject)
        {
            diagnostics.Error("SL0612", syntax.Span,
                $"'as' asks what an object really is, and '{value.Type.Name}' is not a " +
                "reference to one",
                value.Type);
            return new BoundErrorExpression(syntax.Span);
        }

        var result = wanted.MakeOptionalType();

        // Nothing to ask: every one of these already is one of those, so this
        // is the ordinary widening and the null arm would be unreachable.
        if (ClassifyConversion(value.Type, result, explicitCast: false) is not null)
            return BindConversion(value, result, syntax.Span);

        // And nothing to ask the other way either: no object is ever both.
        if (subject is ClassTypeSymbol subjectClass && wanted is ClassTypeSymbol wantedClass &&
            !wantedClass.DerivesFrom(subjectClass))
        {
            diagnostics.Error("SL0612", syntax.Span,
                $"no object is both a '{subjectClass.Name}' and a '{wantedClass.Name}': " +
                "neither derives from the other, so this would always be null",
                subjectClass, wantedClass);
            return new BoundErrorExpression(syntax.Span);
        }

        if (subject is ClassTypeSymbol sealedSubject && wanted is InterfaceTypeSymbol contract &&
            !CouldImplement(sealedSubject, contract))
        {
            diagnostics.Error("SL0612", syntax.Span,
                $"'{sealedSubject.Name}' is sealed and does not implement '{contract.Name}', " +
                "so this would always be null",
                sealedSubject, contract);
            return new BoundErrorExpression(syntax.Span);
        }

        return new BoundAs(syntax.Span, result, value, wanted);
    }

    private BoundExpression BindName(NameSyntax syntax)
    {
        if (syntax.TypeArguments is not null)
            return RefuseTypeArgumentsOnValue(syntax, syntax.Name.Text);

        var parts = syntax.Name.Parts;

        if (parts.Count == 1)
        {
            string name = parts[0];

            if (LookupLocal(name) is { } local)
                return Narrowed(new BoundLocalAccess(syntax.Span, local), local);

            if (_context.Function?.Parameters.FirstOrDefault(p => p.Name == name && !p.IsThis)
                is { } parameter)
                return Narrowed(new BoundParameterAccess(syntax.Span, parameter), parameter);

            // A variable of the function around a local function: one of the
            // hidden parameters every call passes it.
            if (TryCaptureIntoLocalFunction(name, syntax.Span) is { } captured)
                return captured;

            if (LookupLocalFunction(name) is { } localFunction)
                return LocalFunctionValue(localFunction, syntax.Span);

            // A constant the enclosing type declares, named without the type
            // in front of it -- which is how it reads inside its own methods,
            // and what C# does with the same declaration.
            if (EnclosingType?.FindConstant(name) is { } ownConstant)
                return new BoundConstantAccess(syntax.Span, ownConstant);

            if (EnclosingType?.FindStatic(name) is { } ownStatic)
                return new BoundStaticAccess(syntax.Span, ownStatic);

            if (EnclosingType?.FindProperty(name) is { Getter.IsStatic: true } ownStaticProperty)
                return BindPropertyRead(syntax.Span, receiver: null, ownStaticProperty);

            // An unqualified member name inside a method means `this.member`.
            // A static method has no `this`, and saying so here is worth more
            // than letting the name fall through to "is not defined".
            if (_context.Function is { IsStatic: true } inStatic &&
                (inStatic.ContainingType!.FindProperty(name) is not null ||
                 inStatic.ContainingType.FindField(name) is not null))
            {
                // A local function is given the object when it turns out to
                // need it; this binding is then thrown away.
                if (TryGiveLocalFunctionThis(inStatic, syntax.Span))
                    return new BoundErrorExpression(syntax.Span);

                diagnostics.Error("SL0576", syntax.Span,
                    $"'{name}' belongs to an instance of '{inStatic.ContainingType.Name}', and " +
                    $"'{inStatic.Name}' is static, so there is no instance here. Take one as a " +
                    "parameter, or drop the 'static'",
                    inStatic.ContainingType);
                return new BoundErrorExpression(syntax.Span);
            }

            if (_context.Function?.ContainingType?.FindProperty(name) is { } ownProperty)
            {
                var receiver = BindImplicitThis(syntax.Span);
                if (receiver is not null)
                    return BindPropertyRead(syntax.Span, receiver, ownProperty);
            }

            if (_context.Function?.ContainingType?.FindField(name) is { } field)
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

            if (BindPrimaryParameter(name, syntax.Span) is { } primary)
                return primary;

            if (_currentModule!.Constants.TryGetValue(name, out var constant))
                return new BoundConstantAccess(syntax.Span, constant);

            if (_currentModule.Statics.TryGetValue(name, out var moduleStatic))
                return new BoundStaticAccess(syntax.Span, moduleStatic);

            foreach (var import in _context.File!.ImportedModules)
            {
                if (import.Constants.TryGetValue(name, out var imported) && imported.IsPublic)
                    return new BoundConstantAccess(syntax.Span, imported);

                if (import.Statics.TryGetValue(name, out var importedStatic) && importedStatic.IsPublic)
                    return new BoundStaticAccess(syntax.Span, importedStatic);
            }
        }

        // Not declared here, so a lambda body reaches outward and captures it.
        if (parts.Count == 1 && TryCapture(parts[0], syntax.Span) is { } fromAround)
            return fromAround;

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

        // A name a pattern binds is in scope only where the pattern is known to
        // have matched, so one read anywhere else is the pattern's question.
        if (parts.Count == 1 && _patternVariableNames.Contains(parts[0]))
        {
            diagnostics.Error("SL0585", syntax.Span,
                $"'{parts[0]}' is named by a pattern, and here that pattern may not have " +
                "matched: the name is in scope in the rest of an '&&' after the test, the " +
                "branch the test guards, and after an 'if' whose other branch always leaves");
            return new BoundErrorExpression(syntax.Span);
        }

        diagnostics.Error("SL0229", syntax.Span, $"'{syntax.Name.Text}' is not defined");
        return new BoundErrorExpression(syntax.Span);
    }

    private BoundExpression? BindImplicitThis(SourceSpan span)
    {
        ReportReachingTheObject(span);

        var parameter = _context.Function?.Parameters.FirstOrDefault(p => p.IsThis);
        if (parameter is null && TryGiveLocalFunctionThis(_context.Function, span))
            return new BoundErrorExpression(span);

        return parameter is null ? null : Receiver(span, parameter);
    }

    /// <summary>
    /// Refuses a reach for the object from inside a field initializer, and says
    /// why.
    ///
    /// The object is not built yet. A field initializer runs before the
    /// constructor's body and in the order the fields were declared, so a
    /// member read here would be whatever the allocation left -- zero -- for
    /// every field below it, and the reader would have no way to see which.
    /// C# refuses the same thing for the same reason.
    /// </summary>
    private void ReportReachingTheObject(SourceSpan span)
    {
        if (!_context.InitializingField || _reportedFieldInitializerReach) return;

        _reportedFieldInitializerReach = true;

        diagnostics.Error("SL0617", span,
            "a field initializer cannot read the object it belongs to: it runs before the " +
            "constructor's body, in declaration order, so what it would read is whatever the " +
            "allocation left. A constructor is where one field's value can depend on another");
    }

    /// <summary>
    /// Whether the initializer being bound has already been told. Binding
    /// carries on after the message so that the rest of the expression is
    /// bound normally, and one mistake stays one diagnostic.
    /// </summary>
    private bool _reportedFieldInitializerReach;

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

            if (target is BoundFieldAccess { Field.IsBitField: true })
            {
                diagnostics.Error("SL0443", syntax.Span,
                    "a bit-field is some of the bits of its storage unit and has no address " +
                    "of its own; copy it into a local first");
                return new BoundErrorExpression(syntax.Span);
            }

            // What a pointer is used for is not followed, so taking one is a write.
            NoteWriteTo(target);
            return new BoundAddressOf(syntax.Span, target.Type.MakePointerType(), target);
        }

        if (syntax.Operator == TokenKind.Star)
        {
            var target = BindExpression(syntax.Operand);
            if (target.Type is not PointerTypeSymbol pointer)
            {
                if (!target.Type.IsError())
                    diagnostics.Error("SL0231", syntax.Span,
                        $"cannot dereference '{target.Type.Name}'; only pointers can be dereferenced",
                        target.Type);
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
                $"operator '{syntax.Operator.FixedText()}' cannot be applied to '{operand.Type.Name}'",
                operand.Type);
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

        return new BoundUnary(syntax.Span, operand.Type, op, operand)
            { IsChecked = _context.CheckedArithmetic && op is BoundUnaryOp.Negate };
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
        // The right side runs only when the left was true, or false, so what
        // the left named in that outcome is in scope there.
        var right = syntax.Operator is TokenKind.AmpAmp or TokenKind.PipePipe
            ? BindRightOperand(syntax.Right, left, whenTrue: syntax.Operator == TokenKind.AmpAmp)
            : BindExpression(syntax.Right);

        if (left.Type.IsError() || right.Type.IsError()) return new BoundErrorExpression(syntax.Span);

        // `x == default` is the zero of the other side's type, as in C#.
        if (left.Type is DefaultLiteralType && HasOwnType(right))
            left = SettleDefault(left.Span, right.Type);
        else if (right.Type is DefaultLiteralType && HasOwnType(left))
            right = SettleDefault(right.Span, left.Type);

        if (RefuseUntyped(left) | RefuseUntyped(right))
            return new BoundErrorExpression(syntax.Span);

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
            TokenKind.GreaterGreaterGreater => BoundBinaryOp.UnsignedShiftRight,
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
                string.Join(" and ", candidates.Select(Operands)),
                [left.Type, right.Type, .. candidates.SelectMany(SignatureTypes)]);
            return new BoundErrorExpression(span);
        }

        if (fitting.Count > 1)
        {
            diagnostics.Error("SL0566", span,
                $"operator '{token.FixedText()}' is ambiguous for '{left.Type.Name}' and " +
                $"'{right.Type.Name}': " + string.Join(" and ", fitting.Select(Operands)) +
                " both accept them",
                [left.Type, right.Type, .. fitting.SelectMany(SignatureTypes)]);
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
                $"operator '{token.FixedText()}' is ambiguous for '{operand.Type.Name}'",
                operand.Type);
            return new BoundErrorExpression(span);
        }

        return new BoundCall(span, fitting[0], receiver: null,
            [BindConversion(operand, fitting[0].Parameters[0].Type, span)]);
    }

    /// <summary>
    /// The operators of that name on either operand's type, without repeating
    /// one when both operands are the same type.
    ///
    /// A type that declares none of that name falls back on a
    /// <c>static virtual</c> operator's body in an interface it implements.
    /// An interface's <c>static abstract</c> operator is never a candidate: it
    /// has no body, and is a promise about the types that do.
    /// </summary>
    private static List<FunctionSymbol> OperatorsNamed(string name, TypeSymbol left, TypeSymbol right)
    {
        var found = new List<FunctionSymbol>();

        foreach (var type in new[] { Underlying(left), Underlying(right) })
        {
            if (type is not NamedTypeSymbol named) continue;

            var own = named.Operators
                .Where(o => o.Name == name && !(o.ContainingType is { IsContract: true } && !o.HasBody))
                .ToList();
            if (own.Count == 0)
                own = named.AllInterfaces()
                    .SelectMany(i => i.Operators)
                    .Where(o => o.Name == name && o.IsVirtual && o.HasBody)
                    .ToList();

            foreach (var candidate in own)
                if (!found.Contains(candidate))
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
                    $"'{left.Type.Name}' and '{right.Type.Name}'",
                    left.Type, right.Type);
                return new BoundErrorExpression(span);
            }
            return new BoundBinary(span, PrimitiveTypeSymbol.Bool, left, op, right);
        }

        // A type's own operator, before anything built in. It comes first so
        // that a class declaring `==` gets asked rather than being compared by
        // address behind its back -- which is the whole reason to declare one.
        // Nothing built in is reachable this way: a primitive, a String and an
        // array declare no operators, so the lookup fails at once for them.
        //
        // A comparison with `null` is never the type's to answer: its operator
        // takes two references that are there, and the question is whether
        // one is. It is the address test, as `is null` is in C#.
        bool againstNull = op is BoundBinaryOp.Equal or BoundBinaryOp.NotEqual &&
                           (left.Type is NullType || right.Type is NullType);
        if (!againstNull && FindBinaryOperator(span, token, left, right) is { } overloaded)
            return overloaded;

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
            string advice = other switch
            {
                OptionalTypeSymbol { Element: var held } when _builtins.IsString(held) =>
                    $"'{other.Name}' may be null, so check it against null first and compare " +
                    "the String it holds",
                PrimitiveTypeSymbol { IsInteger: true } =>
                    "convert the number first, with Standard.Text.FromInteger",
                PrimitiveTypeSymbol { IsFloat: true } =>
                    "convert the number first, with Standard.Text.FromDouble",
                _ => $"convert the '{other.Name}' to a String first",
            };
            diagnostics.Error("SL0292", span,
                $"cannot apply '{token.FixedText()}' to 'String' and '{other.Name}'; {advice}",
                other);
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
                    "compare; an enum converts only through an explicit cast",
                    left.Type, right.Type);
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
                        : "an enum supports comparison, not arithmetic"),
                    left.Type);
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

        // Two arrays of one type are equal when they are one array, as in C#,
        // and an optional one is compared with the array it may hold.
        if (op is BoundBinaryOp.Equal or BoundBinaryOp.NotEqual &&
            (left.Type.NonNullForm() ?? left.Type) is ArrayTypeSymbol leftArray &&
            leftArray.Equals(right.Type.NonNullForm() ?? right.Type))
            return new BoundBinary(span, PrimitiveTypeSymbol.Bool, left, op, right);

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

        // A nullable closure against null, or against the closure it may
        // hold: both are two words, and null is two zero ones.
        if (op is BoundBinaryOp.Equal or BoundBinaryOp.NotEqual)
        {
            if (left.Type is ClosureTypeSymbol { IsNullable: true } &&
                right.Type is NullType or ClosureTypeSymbol)
                right = BindConversion(right, left.Type, span);
            else if (right.Type is ClosureTypeSymbol { IsNullable: true } &&
                     left.Type is NullType or ClosureTypeSymbol)
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
                $"operator '{token.FixedText()}' cannot be applied to '{left.Type.Name}' and '{right.Type.Name}'",
                left.Type, right.Type);
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
        if (op is BoundBinaryOp.ShiftLeft or BoundBinaryOp.ShiftRight or BoundBinaryOp.UnsignedShiftRight)
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
                $"operator '{token.FixedText()}' cannot be applied to '{left.Type.Name}' and '{right.Type.Name}'",
                left.Type, right.Type);
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
                    "add an explicit cast to choose one",
                    left.Type, right.Type);
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
        bool watched = _context.CheckedArithmetic && common.IsInteger &&
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
    /// The right side of <c>&amp;&amp;</c> or <c>||</c>, bound under what the
    /// left established, with what it writes recorded against it: a proof the
    /// left made does not outlive an assignment the right makes.
    /// </summary>
    private BoundExpression BindRightOperand(
        Syntax.ExpressionSyntax syntax, BoundExpression left, bool whenTrue)
    {
        var written = new HashSet<object>();
        _writtenWitnesses.Add(written);

        var right = BindWhereAssigned(
            left, whenTrue, () => BindUnderFacts(syntax, left, whenTrue), isExpression: true);

        _writtenWitnesses.RemoveAt(_writtenWitnesses.Count - 1);
        if (written.Count > 0) _writtenIn[right] = written;

        return right;
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

        _context.VariantFacts = entry;
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
        var whenTrue = BindWhereAssigned(
            condition, whenTrue: true, () => BindExpression(syntax.WhenTrue), isExpression: true);

        _context.VariantFacts = new Dictionary<object, Fact>(entry);
        ApplyFacts(disproves);
        var whenFalse = BindWhereAssigned(
            condition, whenTrue: false, () => BindExpression(syntax.WhenFalse), isExpression: true);

        _context.VariantFacts = entry;

        if (whenTrue.Type.IsError() || whenFalse.Type.IsError())
            return new BoundErrorExpression(syntax.Span);

        if (whenTrue.Type.IsVoid() || whenFalse.Type.IsVoid())
        {
            diagnostics.Error("SL0348", syntax.Span,
                "a conditional expression must produce a value, but an arm is 'void'");
            return new BoundErrorExpression(syntax.Span);
        }

        var type = CommonArmType(whenTrue, whenFalse);

        // `flag ? (null, 1) : ("two", 2)` waits for a tuple type to convert
        // both to, as a pair of tuple drafts would.
        if (whenTrue is BoundTupleDraft && whenFalse is BoundTupleCreate or BoundTupleDraft ||
            whenFalse is BoundTupleDraft && whenTrue is BoundTupleCreate)
            return new BoundConditional(
                syntax.Span, TupleDraftType.Instance, condition, whenTrue, whenFalse);

        // `flag ? [1, 2] : null` waits for the optional both arms can be.
        if (whenTrue is BoundArrayDraft && whenFalse is BoundNullLiteral ||
            whenFalse is BoundArrayDraft && whenTrue is BoundNullLiteral)
            return new BoundConditional(
                syntax.Span, ArrayDraftType.Instance, condition, whenTrue, whenFalse);

        if (type is null)
        {
            diagnostics.Error("SL0349", syntax.Span,
                $"the arms of a conditional have no common type: one is " +
                $"'{whenTrue.Type.Name}', the other '{whenFalse.Type.Name}'",
                whenTrue.Type, whenFalse.Type);
            return new BoundErrorExpression(syntax.Span);
        }

        // Both arms wait for where the whole is going, and settle there.
        if (IsTargetTyped(whenTrue) && IsTargetTyped(whenFalse) ||
            whenTrue is BoundArrayDraft && whenFalse is BoundArrayDraft ||
            whenTrue is BoundVariantDraft && whenFalse is BoundVariantDraft)
            return new BoundConditional(syntax.Span, type, condition, whenTrue, whenFalse);

        return new BoundConditional(
            syntax.Span, type,
            condition,
            BindConversion(whenTrue, type, syntax.WhenTrue.Span),
            BindConversion(whenFalse, type, syntax.WhenFalse.Span));
    }

    /// <summary>The type both arms of a conditional reach, or null if they do not.</summary>
    private TypeSymbol? CommonArmType(BoundExpression left, BoundExpression right)
    {
        // `flag ? new() : fallback` is a `new` of the other arm's type. Two
        // such arms wait together for where the whole is going.
        if (IsTargetTyped(left) && HasOwnType(right))
            return right.Type;
        if (IsTargetTyped(right) && HasOwnType(left))
            return left.Type;
        if (IsTargetTyped(left) && IsTargetTyped(right))
            return left.Type is NewDraftType ? left.Type : right.Type;

        if (left.Type.Equals(right.Type)) return left.Type;

        // `flag ? obj : null` is an optional, which is what the null was reaching for.
        if (left is BoundNullLiteral && right.Type.IsReferenceType)
            return right.Type.MakeOptionalType();
        if (right is BoundNullLiteral && left.Type.IsReferenceType)
            return left.Type.MakeOptionalType();

        if (left.Type is PrimitiveTypeSymbol { IsNumeric: true } leftNumber &&
            right.Type is PrimitiveTypeSymbol { IsNumeric: true } rightNumber &&
            TryFindCommonType(leftNumber, rightNumber, out var common))
        {
            // `flag ? count : 138` stays the width `count` has. Widening both
            // to a third type would make a 32-bit `nuint` meet an `int` at
            // `long`, where a 64-bit one adopts the literal.
            if (!common.Equals(left.Type) && !common.Equals(right.Type))
            {
                if (ConstantFits(right, left.Type)) return left.Type;
                if (ConstantFits(left, right.Type)) return right.Type;
            }
            return common;
        }

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
    /// <summary>
    /// <c>(null, 1)</c> given a tuple type to be: each element converted to
    /// the type in its place.
    /// </summary>
    private BoundExpression SettleTupleDraft(BoundTupleDraft draft, TypeSymbol target, SourceSpan span)
    {
        if (target is not TupleTypeSymbol tuple || tuple.Elements.Count != draft.Elements.Count)
        {
            diagnostics.Error("SL0773", span,
                $"a tuple of {draft.Elements.Count} written out cannot become '{target.Name}'; " +
                "and it has an element that takes its type from where it is going, so it has " +
                "no type of its own to be instead",
                target);
            return new BoundErrorExpression(span);
        }

        return ConvertTupleElements(draft.Elements, tuple, span);
    }

    /// <summary>
    /// A tuple written out, as another tuple type of as many elements: each
    /// element converted to the type in its place, as C# converts a tuple
    /// literal. A tuple that is not written out converts only to its own type.
    /// </summary>
    private BoundExpression ConvertTupleElements(
        IReadOnlyList<BoundExpression> written, TupleTypeSymbol tuple, SourceSpan span)
    {
        var elements = new List<BoundExpression>(written.Count);
        for (int i = 0; i < written.Count; i++)
        {
            var element = written[i];
            elements.Add(BindConversion(element, tuple.Elements[i], element.Span));
        }

        return elements.Any(e => e.Type.IsError())
            ? new BoundErrorExpression(span)
            : new BoundTupleCreate(span, tuple, elements);
    }

    private BoundExpression RefuseDeclarationExpression(DeclarationExpressionSyntax syntax)
    {
        diagnostics.Error("SL0771", syntax.Span,
            $"'{syntax.Name}' is declared where nothing is being taken apart; a declaration " +
            "like this is an element of the left side of a deconstruction, as in " +
            "'(int a, var b) = pair;'");
        return new BoundErrorExpression(syntax.Span);
    }

    private BoundExpression BindTuple(TupleSyntax syntax)
    {
        var elements = syntax.Elements.Select(BindExpression).ToList();
        if (elements.Any(e => e.Type.IsError())) return new BoundErrorExpression(syntax.Span);

        foreach (var element in elements)
        {
            if (element.Type.IsVoid())
            {
                diagnostics.Error("SL0607", element.Span,
                    "an element of a tuple has to be a value, and this produces none");
                return new BoundErrorExpression(syntax.Span);
            }

        }

        // A tuple's type is its elements' types, so one element that waits to
        // be told its type leaves the whole tuple waiting too.
        if (!elements.All(HasOwnType))
            return new BoundTupleDraft(syntax.Span, elements);

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
        if (syntax.Type is null)
            return new BoundDefault(syntax.Span, DefaultLiteralType.Instance);

        // allowVoid, so that the refusal below is the one reported: it says
        // what `default` in particular cannot do, where the general rule in
        // ResolveType says only that 'void' is not a type a value has.
        var type = ResolveType(syntax.Type, _context.File!, allowVoid: true);
        if (type.IsError()) return new BoundErrorExpression(syntax.Span);

        if (type.IsVoid())
        {
            diagnostics.Error("SL0603", syntax.Span,
                "'default(void)' names no value; 'void' is the absence of one");
            return new BoundErrorExpression(syntax.Span);
        }

        CheckDefaultHasZero(syntax.Span, type);
        return new BoundDefault(syntax.Span, type);
    }

    /// <summary>
    /// <c>x!</c>: a <c>C?</c> taken as the <c>C</c> it holds, aborting if it is
    /// null, exactly as <c>(C)x</c> does. On anything that cannot be null it is the
    /// operand unchanged, as C# has it, so a generic body may write it for a
    /// parameter that is only sometimes a <c>C?</c>.
    /// </summary>
    private BoundExpression BindNullForgiving(NullForgivingSyntax syntax)
    {
        var operand = BindExpression(syntax.Operand);
        if (operand.Type.IsError())
            return new BoundErrorExpression(syntax.Span);
        if (RefuseUntyped(operand))
            return new BoundErrorExpression(syntax.Span);

        // A weak reference is read strongly first, which is where it is
        // asked whether the object is still alive.
        if (operand.Type is WeakTypeSymbol weak)
            operand = BindConversion(operand, weak.Element.MakeOptionalType(), syntax.Span);

        return operand.Type.NonNullForm() is { } held
            ? new BoundConversion(syntax.Span, held, operand, ConversionKind.AssertPresent)
            : operand;
    }

    /// <summary>
    /// <c>Pick&lt;int&gt;</c> or <c>list.Map&lt;int&gt;</c> somewhere other than
    /// the callee of a call, where there is nothing for the arguments to do.
    /// </summary>
    private BoundExpression RefuseTypeArgumentsOnValue(ExpressionSyntax syntax, string name)
    {
        if (ConstructedTypeNamed(syntax) is { } type)
        {
            diagnostics.Error("SL0761", syntax.Span,
                $"'{type.Name}' is a type, not a value; reach a static member through it, as " +
                $"in '{type.Name}.Create()', or make one with 'new'",
                type);
            return new BoundErrorExpression(syntax.Span);
        }

        diagnostics.Error("SL0761", syntax.Span,
            $"'{name}' is written with type arguments and is not being called; type " +
            "arguments go on a call, as in 'Pick<int>(a, b)', or on a type before its " +
            "member, as in 'Box<int>.Create()'");
        return new BoundErrorExpression(syntax.Span);
    }

    /// <summary>
    /// Refuses <c>a?.b = v</c> and <c>a?[i]++</c>, as C# does: a write that
    /// might not happen is an <c>if</c>, and is clearer written as one.
    /// </summary>
    private bool RefuseConditionalTarget(ExpressionSyntax target)
    {
        if (target is not (MemberAccessSyntax { Conditional: true } or
                           IndexSyntax { Conditional: true } or SliceSyntax { Conditional: true }))
            return false;

        diagnostics.Error("SL0762", target.Span,
            "a '?.' or '?[' reads, and cannot be written through: the write would happen " +
            "only sometimes, which is an 'if'. Write 'if (a != null)' and assign inside it");
        return true;
    }

    /// <summary>A bare <c>default</c>, as the zero of the type it is going to.</summary>
    private BoundExpression SettleDefault(SourceSpan span, TypeSymbol target)
    {
        if (target.IsVoid())
        {
            diagnostics.Error("SL0603", span,
                "'default' names no value here, because what it is going to is 'void'");
            return new BoundErrorExpression(span);
        }

        CheckDefaultHasZero(span, target);
        return new BoundDefault(span, target);
    }

    /// <summary>Whether an expression has a type of its own rather than one it waits for.</summary>
    private static bool HasOwnType(BoundExpression expression) =>
        expression.Type is not (DefaultLiteralType or NewDraftType or NullType or LambdaType
            or ArrayDraftType or VariantDraftType or FunctionGroupType or TupleDraftType
            or ErrorTypeSymbol)
        && !expression.Type.IsVoid();

    /// <summary>
    /// Whether this is a bare <c>default</c>, a <c>new(...)</c>, or a tuple
    /// with an element that waits likewise: none has a type until something
    /// it is going to gives it one.
    /// </summary>
    private static bool IsTargetTyped(BoundExpression expression) =>
        expression.Type is DefaultLiteralType or NewDraftType or TupleDraftType;

    /// <summary>
    /// Reports a <c>default</c> or <c>new(...)</c> that reached a place with no
    /// type to give it, and answers whether it did.
    /// </summary>
    private bool RefuseUntyped(BoundExpression expression)
    {
        switch (expression.Type)
        {
            case DefaultLiteralType:
                diagnostics.Error("SL0757", expression.Span,
                    "a bare 'default' takes its type from where it is going, and nothing " +
                    "here says what that is; write 'default(T)' with the type you mean");
                return true;

            case NewDraftType:
                diagnostics.Error("SL0756", expression.Span,
                    "'new(...)' takes its type from where it is going, and nothing here says " +
                    "what that is; write the type, as in 'new Point(...)'");
                return true;

            case TupleDraftType:
                diagnostics.Error("SL0773", expression.Span,
                    "an element of this tuple takes its type from where it is going, and " +
                    "nothing here says what that is; a tuple's type is its elements' types. " +
                    "Write the type, as in '(String?, int) pair = (null, 1);'");
                return true;

            default:
                return false;
        }
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
        using (BeginTrial())
        {
            found = BindExpression(syntax.Operand) is not BoundErrorExpression;

            if (!found && syntax.Operand is NameSyntax typeName && _context.File is { } scope)
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
        bool previous = _context.CheckedArithmetic;
        _context.CheckedArithmetic = syntax.IsChecked;
        var value = BindExpression(syntax.Operand);
        _context.CheckedArithmetic = previous;
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
        if (RefuseConditionalTarget(syntax.Operand))
            return new BoundErrorExpression(syntax.Span);

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
                syntax.Span, read.Receiver, property, syntax.IsPrefix, syntax.IsIncrement,
                read.Arguments)
                { IsChecked = _context.CheckedArithmetic };
        }

        if (!Writable(target, syntax.Operand.Span, written)) return new BoundErrorExpression(syntax.Span);
        if (!Countable(target.Type, syntax.Span, written)) return new BoundErrorExpression(syntax.Span);

        InvalidateVariantFact(target);
        if (WrittenParameter(target) is { } written2) MarkAssigned(written2);
        NoteMemberWritten(target);

        return new BoundIncrement(syntax.Span, target, syntax.IsPrefix, syntax.IsIncrement)
            { IsChecked = _context.CheckedArithmetic };
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
                : ""),
            type);
        return false;
    }

    /// <summary>
    /// Whether a place may be written: the checks an assignment makes, asked
    /// separately so that <c>++</c> makes exactly the same ones.
    /// </summary>
    private bool Writable(BoundExpression target, SourceSpan span, string written)
    {
        if (RefusedThroughReadOnlySlice(target, span)) return false;

        if (BaseOf(target) is BoundStaticAccess { Static.IsReadonly: true } owner)
        {
            diagnostics.Error("SL0379", span,
                $"'{owner.Static.Name}' is 'static readonly', so it is written once by its " +
                "initializer and never again. Drop the 'readonly' if it is meant to change");
            return false;
        }

        if (BaseOf(target) is BoundParameterAccess { Parameter.CaptureOrigin: not null } copied)
        {
            diagnostics.Error("SL0769", span,
                $"'{copied.Parameter.Name}' belongs to the function around this local function, " +
                "which is given its value at each call and not the variable itself; assigning " +
                "it would change only that copy. Return the new value, or make it a field");
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
            if (TemporaryStruct(target) is { } temporary)
            {
                diagnostics.Error("SL0399", span,
                    $"this writes into a temporary '{temporary.Type.Name}', which would be " +
                    "discarded with the write; put the struct in a variable, change it there, " +
                    "and store it back",
                    temporary.Type);
                return false;
            }

            diagnostics.Error("SL0240", span,
                target is BoundLocalAccess { Local.IsConst: true } constant
                    ? $"'{constant.Local.Name}' is declared 'const' and cannot be assigned"
                    : written == "="
                        ? "the left-hand side of an assignment must be a variable, field or " +
                          "dereference"
                        : $"'{written}' needs a variable, field or dereference to change");
            return false;
        }

        NoteWriteTo(target);
        return true;
    }

    /// <summary>
    /// The struct value a field write would land in when that value is a copy
    /// nothing keeps: what a call, a property or an indexer answered. Null when
    /// the write has storage to land in, or fails for another reason.
    /// </summary>
    private static BoundExpression? TemporaryStruct(BoundExpression target)
    {
        while (true)
        {
            var inner = target switch
            {
                BoundFieldAccess { Receiver: { } receiver, Field.ContainingType: StructTypeSymbol }
                    => receiver,
                BoundIndex { Target.Type: FixedArrayTypeSymbol } element => element.Target,
                _ => null,
            };

            if (inner is null || inner.IsLValue) return null;
            if (inner is not (BoundFieldAccess or BoundIndex)) return inner;

            target = inner;
        }
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
                when _context.Function?.ContainingType?.FindEvent(bare.Name.Last) is { } own:
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
                EventSymbol? found;
                using (var trial = BeginTrial())
                {
                    target = BindExpression(member.Target);
                    found = (target.Type as NamedTypeSymbol)?.FindEvent(member.Member);
                    if (found is null) return null;
                    trial.Accept();
                }

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
            diagnostics.Error("SL0825", span,
                $"'{subscribed.ContainingType.Name}.{subscribed.Name}' is an event, so it takes " +
                $"'+=' and '-=' and nothing else. '{syntax.Operator.FixedText()}' would " +
                "replace the whole list of subscribers, which is not one subscriber's to do",
                subscribed.ContainingType);
            return new BoundErrorExpression(syntax.Span);
        }

        if (receiver is null)
        {
            diagnostics.Error("SL0822", span,
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

        // A lambda subscribed here holds the object it was written in weakly,
        // for the reason `addweak_` exists; see BindLambdaAsMethodPointer.
        // Only a lambda that is the whole handler: one passed to a call that
        // builds the handler is that call's business.
        _subscribingLambda = adding && subscribed.AddWeak is not null && syntax.Value is LambdaSyntax;

        // The handler is converted to the event's closure type, which is what
        // lets `sub.OnFired` be written bare: a method group has no type of its
        // own, and the event is the context that gives it one.
        var handler = BindConversion(BindExpression(syntax.Value), subscribed.Type, syntax.Value.Span);
        _subscribingLambda = false;
        if (handler.Type.IsError()) return new BoundErrorExpression(syntax.Span);

        // **An object never keeps itself alive through its own subscriptions.**
        // A form subscribing to its own button would otherwise be a cycle ARC
        // cannot free: the form holds the button, the button's event holds the
        // closure, and the closure holds the form.
        if (adding && subscribed.AddWeak is { } weak && IsBoundToThis(handler))
            accessor = weak;

        return new BoundCall(syntax.Span, accessor, receiver, [handler]);
    }

    /// <summary>
    /// Set while the handler of a <c>+=</c> is bound, when that handler is a
    /// lambda; read and cleared by the one lambda it describes.
    /// </summary>
    private bool _subscribingLambda;

    /// <summary>
    /// Whether a closure is a method bound to the object doing the binding:
    /// <c>this.OnClick</c>, a bare <c>OnClick</c>, or either inside a lambda,
    /// where <c>this</c> is the one the lambda captured.
    /// </summary>
    private bool IsBoundToThis(BoundExpression handler)
    {
        if (handler is not BoundClosureCreate { Receiver: { } bound }) return false;

        while (bound is BoundConversion { Kind: ConversionKind.Upcast or ConversionKind.Identity } cast)
            bound = cast.Operand;

        return bound switch
        {
            BoundThis self => _context.Closures.Count == 0 && self.Parameter.IsThis
                              && self.Parameter == _context.Function?.Parameters.FirstOrDefault(p => p.IsThis),
            BoundFieldAccess { Field.Name: ThisCaptureName, Receiver: BoundThis } => _context.Closures.Count > 0,
            BoundConversion { Kind: ConversionKind.PointerCast, Operand: BoundLocalAccess local }
                => _context.Closures.Count > 0 && local.Local.Name == WeakSelfName,
            _ => false,
        };
    }

    private BoundExpression BindAssignment(AssignmentSyntax syntax)
    {
        if (syntax is { Operator: TokenKind.Equals, Target: TupleSyntax })
            return BindDeconstructionExpression(syntax);

        if (RefuseConditionalTarget(syntax.Target))
            return new BoundErrorExpression(syntax.Span);
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

        if (!Writable(target, syntax.Target.Span, "=")) return new BoundErrorExpression(syntax.Span);

        // Whatever was proved about this Result was proved about the value it
        // held a moment ago.
        InvalidateVariantFact(target);

        // Writing into a parameter's own storage makes it owned; see
        // ParameterSymbol.IsAssigned.
        if (WrittenParameter(target) is { } written) MarkAssigned(written);

        NoteMemberWritten(target);

        if (syntax.Operator == TokenKind.Equals)
        {
            var stored = BindConversion(value, target.Type, syntax.Value.Span);
            return IsRepeatable(stored) || target is not (BoundFieldAccess or BoundIndex)
                ? new BoundAssignment(syntax.Span, target, stored)
                : new BoundMemberAssignment(syntax.Span, target, stored);
        }

        // A compound assignment reads its place and writes it back. What the
        // place held is named here by a placeholder, and lowering decides
        // what to hold so that it is worked out once.
        var current = new BoundPlaceholder(syntax.Target.Span, target.Type);

        // `a ??= b` asks a question of the place rather than computing on it,
        // and the value is evaluated and stored only when there was nothing.
        if (syntax.Operator == TokenKind.QuestionQuestionEquals)
        {
            // A property's storage starts out null whatever its type says, and
            // `field ??= Make()` is how an accessor fills it on first use.
            bool unfilled = syntax.Target is FieldKeywordSyntax && target.Type.IsReferenceType;

            if (target.Type is not (OptionalTypeSymbol or PointerTypeSymbol) && !unfilled)
            {
                diagnostics.Error("SL0604", syntax.Target.Span,
                    $"'{target.Type.Name}' cannot be nothing, so '??=' has nothing to fill in",
                    target.Type);
                return new BoundErrorExpression(syntax.Span);
            }

            return new BoundCompoundAssignment(syntax.Span, target.Type, target, current, value,
                BindConversion(value, target.Type, syntax.Value.Span), isFallback: true);
        }

        var combined = BindCompoundOperation(syntax, current, value);
        if (combined.Type.IsError()) return new BoundErrorExpression(syntax.Span);

        return new BoundCompoundAssignment(
            syntax.Span, target.Type, target, current, value, combined, isFallback: false);
    }

    /// <summary>
    /// <c>x op y</c> for <c>x op= y</c>, already converted to the type of
    /// <c>x</c>.
    ///
    /// C#'s rule for a built-in operator: when its result does not convert
    /// back implicitly, it is cast back, provided <c>y</c> itself fits
    /// <c>x</c> or the operator is a shift. So <c>b += 10</c> on a byte is
    /// <c>b = (byte)(b + 10)</c>, and <c>b += 300</c> is still refused.
    /// </summary>
    private BoundExpression BindCompoundOperation(
        AssignmentSyntax syntax, BoundExpression place, BoundExpression value)
    {
        var (op, token) = CompoundOperator(syntax.Operator);
        var combined = BindBinaryOperation(syntax.Span, place, op, value, token);
        if (combined.Type.IsError()) return combined;

        var type = place.Type;
        if (combined is BoundBinary &&
            type is PrimitiveTypeSymbol { IsNumeric: true } or PrimitiveTypeSymbol { Kind: PrimitiveKind.Char } &&
            combined.Type is PrimitiveTypeSymbol &&
            !IsImplicitlyConvertible(combined, type) &&
            (op is BoundBinaryOp.ShiftLeft or BoundBinaryOp.ShiftRight
                or BoundBinaryOp.UnsignedShiftRight ||
             IsImplicitlyConvertible(value, type)) &&
            ClassifyConversion(combined.Type, type, explicitCast: true) is { } kind)
            return new BoundConversion(syntax.Span, type, combined, kind)
                { IsChecked = _context.CheckedArithmetic };

        return BindConversion(combined, type, syntax.Value.Span);
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
        TokenKind.GreaterGreaterGreaterEquals =>
            (BoundBinaryOp.UnsignedShiftRight, TokenKind.GreaterGreaterGreater),
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

        if (nonVirtual && getter.IsAbstract)
            return RefuseAbstractBase(property.Name, span);

        if (!CanReach(getter.IsPublic, getter.IsProtected, property.ContainingType))
        {
            diagnostics.Error("SL0249", span,
                NotVisible(property.ContainingType, property.Name, getter.IsProtected));
            return new BoundErrorExpression(span);
        }

        // What a slot holds is read in place, and its layout is the compiler's.
        if (receiver is not null && property is { ContainingType: SlotTypeSymbol slot, Name: "Value" })
            return new BoundSlotValue(span, slot, receiver);

        // A struct accessor takes its receiver by pointer, exactly as a struct
        // method does. A static one has none at all.
        if (receiver is not null && property.ContainingType is StructTypeSymbol structType)
            receiver = new BoundAddressOf(span, structType.MakePointerType(), receiver);

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
            if (WrittenParameter(receiver) is { } mutated) MarkAssigned(mutated);
            InvalidateVariantFact(receiver);
        }

        var value = BindExpression(syntax.Value);
        if (value.Type.IsError() || property.Type.IsError())
            return new BoundErrorExpression(syntax.Span);

        if (!CanWriteProperty(syntax.Target.Span, receiver, property,
                syntax.Operator == TokenKind.Equals, out var storage))
            return new BoundErrorExpression(syntax.Span);

        // A get-only automatic property is still storage, and the type's own
        // constructor is where storage gets filled in.
        if (storage is not null)
            return new BoundAssignment(syntax.Span, storage,
                BindConversion(value, property.Type, syntax.Value.Span));

        NoteMemberWritten(property);

        // For an indexer, the read that got here already bound and converted
        // the indices, so they are carried over rather than bound again.
        // `base.P = x` reaches the setter this class replaced, as the read
        // reached the getter.
        var indices = property.IsIndexer ? read.Arguments : [];
        if (syntax.Operator == TokenKind.Equals)
        {
            return new BoundPropertyAssignment(
                syntax.Span, receiver, property, BindConversion(value, property.Type, syntax.Value.Span))
            {
                Indices = indices,
                IsNonVirtual = read.IsNonVirtual,
                HoldsReceiver = true,
            };
        }

        // `p.X += 1` calls the getter and then the setter, on one receiver and
        // one set of indices, which lowering evaluates once.
        var current = new BoundPlaceholder(read.Span, property.Type) { IsStorage = false };

        if (syntax.Operator == TokenKind.QuestionQuestionEquals)
        {
            if (property.Type is not (OptionalTypeSymbol or PointerTypeSymbol))
            {
                diagnostics.Error("SL0604", syntax.Target.Span,
                    $"'{property.Type.Name}' cannot be nothing, so '??=' has nothing to fill in",
                    property.Type);
                return new BoundErrorExpression(syntax.Span);
            }

            return new BoundCompoundAssignment(syntax.Span, property.Type, read, current, value,
                BindConversion(value, property.Type, syntax.Value.Span), isFallback: true)
            {
                Property = property,
            };
        }

        var combined = BindCompoundOperation(syntax, current, value);
        if (combined.Type.IsError()) return new BoundErrorExpression(syntax.Span);

        return new BoundCompoundAssignment(
            syntax.Span, property.Type, read, current, value, combined, isFallback: false)
        {
            Property = property,
        };
    }

    /// <summary>
    /// Whether this property may be written here, reporting why not.
    ///
    /// A get-only automatic property has no setter and is still written by its
    /// type's own constructor, or a static one by its type's static
    /// constructor; <paramref name="storage"/> is then the place to store into.
    /// </summary>
    private bool CanWriteProperty(
        SourceSpan span, BoundExpression? receiver, PropertySymbol property, bool plain,
        out BoundExpression? storage)
    {
        storage = null;

        if (property.Setter is not { } setter)
        {
            if (property.BackingField is { } field && receiver is not null && plain &&
                _context.Function is { Kind: FunctionKind.Constructor } ctor &&
                ctor.ContainingType == property.ContainingType)
            {
                // A struct's accessor takes its receiver by address, and the
                // backing field is in the struct itself.
                var holder = receiver is BoundAddressOf { Operand: var place } ? place : receiver;
                storage = new BoundFieldAccess(span, holder, field);
                return true;
            }

            if (property.StaticBacking is { } shared && receiver is null && plain &&
                _context.Function is { Kind: FunctionKind.StaticConstructor } initializer &&
                initializer.ContainingType == property.ContainingType)
            {
                storage = new BoundStaticAccess(span, shared);
                return true;
            }

            diagnostics.Error("SL0395", span,
                $"'{property.ContainingType.Name}.{property.Name}' has no setter" +
                (property.ContainingType is InterfaceTypeSymbol
                    ? ", so the contract does not offer one; declare it 'get; set;'"
                    : !property.IsAuto
                        ? "; it is computed, so there is nothing to write"
                        : property.StaticBacking is not null
                        ? "; add 'set;', or assign it in the static constructor of " +
                          $"'{property.ContainingType.Name}'"
                        : "; add 'set;', or assign it in a constructor of " +
                          $"'{property.ContainingType.Name}'"),
                property.ContainingType);
            return false;
        }

        if (!CanReach(setter.IsPublic, setter.IsProtected, property.ContainingType))
        {
            diagnostics.Error("SL0396", span,
                setter.IsProtected
                    ? $"'{property.ContainingType.Name}.{property.Name}' can be read from " +
                      $"anywhere but written only by '{property.ContainingType.Name}' and " +
                      "classes deriving from it"
                    : $"'{property.ContainingType.Name}.{property.Name}' can be read from " +
                      "anywhere but only written inside its own module",
                property.ContainingType);
            return false;
        }

        if (setter.IsInitAccessor && !MayCallInit(receiver, property))
        {
            diagnostics.Error("SL0781", span,
                $"'{property.ContainingType.Name}.{property.Name}' is 'init', so it is written " +
                "while its object is being made and not after: in an object initializer, a " +
                $"'with', or on 'this' in a constructor or 'init' accessor of " +
                $"'{property.ContainingType.Name}' or a class deriving from it",
                property.ContainingType);
            return false;
        }

        if (property.ContainingType is StructTypeSymbol && receiver is not null &&
            RefusedThroughReadOnlySlice(receiver, span))
            return false;

        // A struct's setter writes the receiver's own storage, so writing one
        // through a `static readonly` writes the static. A class's setter writes
        // the object rather than the static, and a readonly static may hold an
        // object whose fields still change.
        if (property.ContainingType is StructTypeSymbol && receiver is not null &&
            BaseOf(receiver) is BoundStaticAccess { Static.IsReadonly: true } owner)
        {
            diagnostics.Error("SL0379", span,
                $"'{owner.Static.Name}' is 'static readonly', so it is written once by its " +
                "initializer -- and setting a field of the struct it holds is writing it");
            return false;
        }

        // A struct's setter writes through a pointer, so a temporary receiver
        // would be written and then thrown away.
        if (property.ContainingType is StructTypeSymbol && receiver is not null &&
            receiver is BoundAddressOf { Operand: var target } && !target.IsLValue)
        {
            diagnostics.Error("SL0399", span,
                $"'{property.ContainingType.Name}.{property.Name}' is being set on a temporary " +
                "struct, so the write would be discarded; assign to a variable first",
                property.ContainingType);
            return false;
        }

        if (property.ContainingType is StructTypeSymbol && receiver is not null)
        {
            if (IsReadOnlyTarget(receiver) is { } why)
            {
                diagnostics.Error("SL0809", span,
                    $"setting '{property.ContainingType.Name}.{property.Name}' writes the struct " +
                    $"it is set on, and {why}",
                    property.ContainingType);
                return false;
            }

            NoteWriteTo(receiver);
        }

        return true;
    }

    /// <summary>
    /// Whether an <c>init</c> setter may be called on this receiver here: on
    /// <c>this</c>, inside a constructor or an <c>init</c> accessor of the
    /// declaring type or one deriving from it. An object initializer and a
    /// <c>with</c> write through the setter without asking.
    /// </summary>
    private bool MayCallInit(BoundExpression? receiver, PropertySymbol property)
    {
        if (_context.Closures.Count > 0) return false;
        if (_context.Function is not { } here) return false;
        if (here.Kind != FunctionKind.Constructor && !here.IsInitAccessor) return false;

        bool related = here.ContainingType == property.ContainingType ||
                       (here.ContainingType is ClassTypeSymbol derived &&
                        property.ContainingType is ClassTypeSymbol declaring &&
                        derived.DerivesFrom(declaring));

        return related && IsThisReceiver(receiver);
    }

    /// <summary>Whether an expression is the function's own <c>this</c>, however reached.</summary>
    private static bool IsThisReceiver(BoundExpression? receiver) => receiver switch
    {
        BoundThis => true,
        BoundConversion { Kind: ConversionKind.Upcast } upcast => IsThisReceiver(upcast.Operand),
        BoundAddressOf address => IsThisReceiver(address.Operand),
        BoundDereference dereference => IsThisReceiver(dereference.Operand),
        _ => false,
    };

    private static bool IsRepeatable(BoundExpression expression) => Places.IsRepeatable(expression);

    /// <summary>
    /// The accessor of an indexer that takes this index, or null.
    ///
    /// Walks the base chain, because an indexer is inherited like any other
    /// member. Overloaded on the index type, so `this[nuint]` and
    /// `this[String]` can both be declared and asking with one does not find
    /// the other.
    /// </summary>
    private FunctionSymbol? FindIndexer(
        NamedTypeSymbol type, IReadOnlyList<BoundExpression> given, bool setting)
    {
        for (NamedTypeSymbol? at = type; at is not null;
             at = (at as ClassTypeSymbol)?.BaseClass)
        {
            foreach (var property in at.Properties.Where(p => p.IsIndexer))
            {
                var accessor = setting ? property.Setter : property.Getter;
                if (accessor is null) continue;

                // Parameter 0 is `this` and the indices follow it. A setter's
                // last parameter is `value` and is not one of them.
                var indices = accessor.Parameters.Where(p => !p.IsThis).ToList();
                if (setting && indices.Count > 0) indices.RemoveAt(indices.Count - 1);

                if (indices.Count != given.Count) continue;

                bool fits = true;
                for (int i = 0; i < given.Count && fits; i++)
                    fits = IsImplicitlyConvertible(given[i], indices[i].Type);

                if (fits) return accessor;
            }
        }

        return null;
    }

    /// <summary>
    /// <c>a[i]</c> or <c>a[i] = v</c>, as the call it lowers to.
    /// </summary>
    private BoundExpression BuildIndexerCall(
        SourceSpan span, FunctionSymbol accessor, BoundExpression target,
        IReadOnlyList<BoundExpression> given, BoundExpression? value)
    {
        var indices = accessor.Parameters.Where(p => !p.IsThis).ToList();

        var arguments = new List<BoundExpression>();
        for (int i = 0; i < given.Count; i++)
            arguments.Add(BindConversion(given[i], indices[i].Type, span));

        if (value is not null)
            arguments.Add(BindConversion(value, indices[^1].Type, span));

        // A struct's method takes its receiver by pointer, as everywhere else.
        var receiver = accessor.ContainingType is StructTypeSymbol
            ? new BoundAddressOf(span, target.Type.MakePointerType(), target)
            : target;

        return new BoundCall(span, accessor, receiver, arguments);
    }

    private BoundExpression BindIndex(IndexSyntax syntax)
    {
        if (syntax.Conditional)
            return BindConditionalElement(syntax, null);

        var target = BindExpression(syntax.Target);
        if (target.Type.IsError())
            return new BoundErrorExpression(syntax.Span);
        if (RefuseUntyped(target))
            return new BoundErrorExpression(syntax.Span);

        return BindIndexOn(target, syntax);
    }

    /// <summary>The element of a target that has already been bound.</summary>
    private BoundExpression BindIndexOn(BoundExpression target, IndexSyntax syntax)
    {
        var given = syntax.Indices.Select(BindExpression).ToList();

        if (target.Type.IsError() || given.Any(i => i.Type.IsError()))
            return new BoundErrorExpression(syntax.Span);

        // A type's own indexer. Reached through the getter it lowers to, which
        // is why nothing here has to know that a property was involved.
        if (target.Type is NamedTypeSymbol named && FindIndexer(named, given, false) is { } getter)
            return BuildIndexerCall(syntax.Span, getter, target, given, null);

        // `a[^1]`, `a[i]` of an Index, and `a[1..^1]` of anything that counts.
        if (given is [var position] && (IsStandardIndex(position.Type) || IsStandardRange(position.Type)))
            return BindPositionIndex(target, position, syntax.Span);

        if (target.Type is not (PointerTypeSymbol or ArrayTypeSymbol or SliceTypeSymbol
                                or FixedArrayTypeSymbol))
        {
            diagnostics.Error("SL0241", syntax.Span,
                target.Type is NamedTypeSymbol subject && subject.Properties.Any(p => p.IsIndexer)
                    ? $"no indexer on '{target.Type.Name}' takes " +
                      $"({string.Join(", ", given.Select(i => i.Type.Name))})"
                    : $"cannot index '{target.Type.Name}'; only arrays, slices and pointers " +
                      "support indexing, and this type declares no 'this[...]'",
                target.Type);
            return new BoundErrorExpression(syntax.Span);
        }

        // Only an indexer takes more than one, because only an indexer decides
        // what a second one would mean.
        if (given.Count > 1)
        {
            diagnostics.Error("SL0241", syntax.Span,
                $"'{target.Type.Name}' is indexed by one index, and there are " +
                $"{given.Count} here; a type takes more than one only by declaring " +
                "'this[...]' with that many",
                target.Type);
            return new BoundErrorExpression(syntax.Span);
        }

        var index = given[0];

        if (index.Type is not PrimitiveTypeSymbol { IsInteger: true })
        {
            diagnostics.Error("SL0242", syntax.Indices[0].Span,
                $"an index must be an integer, but this is '{index.Type.Name}'",
                index.Type);
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
                diagnostics.Error("SL0490", syntax.Indices[0].Span,
                    $"index {constant} is past the end of '{inline.Name}', which has " +
                    $"{Counted(inline.Length, "element")}",
                    inline);
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
        if (syntax.Conditional)
            return BindConditionalElement(syntax, null);

        var target = BindExpression(syntax.Target);
        if (target.Type.IsError()) return new BoundErrorExpression(syntax.Span);
        if (RefuseUntyped(target))
            return new BoundErrorExpression(syntax.Span);

        return BindSliceOn(target, syntax);
    }

    /// <summary>A slice of a target that has already been bound.</summary>
    private BoundExpression BindSliceOn(BoundExpression target, SliceSyntax syntax)
    {
        var start = BindBound(syntax.Start);
        var end = BindBound(syntax.End);

        if (start?.Type.IsError() == true || end?.Type.IsError() == true)
            return new BoundErrorExpression(syntax.Span);

        var (from, fromOrigin) = start is null ? (null, IndexOrigin.Start) : PositionParts(start);
        var (to, toOrigin) = end is null ? (null, IndexOrigin.Start) : PositionParts(end);

        return MakeSlice(syntax.Span, target, from, fromOrigin, to, toOrigin);
    }

    /// <summary>
    /// One end of a slice, or null where the source left it out: an integer as
    /// a <c>nuint</c>, or a <c>Standard.Index</c> as it is.
    /// </summary>
    private BoundExpression? BindBound(ExpressionSyntax? syntax)
    {
        if (syntax is null) return null;

        var bound = BindExpression(syntax);
        if (bound.Type.IsError()) return bound;

        if (IsStandardIndex(bound.Type))
            return bound;

        if (bound.Type is not PrimitiveTypeSymbol { IsInteger: true })
        {
            diagnostics.Error("SL0242", syntax.Span,
                $"a slice bound must be an integer, but this is '{bound.Type.Name}'",
                bound.Type);
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
                "rather than N of them",
                element);
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
                "than a value can be",
                element);
            return ErrorTypeSymbol.Instance;
        }

        return element.MakeFixedArrayType((int)length);
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
