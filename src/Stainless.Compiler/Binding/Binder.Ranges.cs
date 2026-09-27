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
/// <c>^n</c> and <c>a..b</c>: positions counted from either end, and runs of
/// them.
///
/// <para>
/// Each is a <c>Standard.Index</c> or a <c>Standard.Range</c> when it is a
/// value. Used at once to index an array, a slice or an inline array, it is
/// taken apart again, so <c>a[^1]</c> is an index that the emitter counts back
/// from the length it already loads for the bounds check, and <c>a[1..^1]</c>
/// is the same slice <c>a[1:^1]</c> is. Nothing is built that is not kept.
/// </para>
///
/// <para>
/// Any other type takes them as C# has it take them: a <c>Count</c> or
/// <c>Length</c> and an indexer taking an integer make <c>x[^1]</c>, and the
/// same count and a <c>Slice(start, length)</c> make <c>x[1..^1]</c>. An
/// indexer declared to take an <c>Index</c> or a <c>Range</c> is asked first.
/// </para>
/// </summary>
public sealed partial class Binder
{
    private StructTypeSymbol StandardIndex => (StructTypeSymbol)_builtins.Standard.Types["Index"];

    private StructTypeSymbol StandardRange => (StructTypeSymbol)_builtins.Standard.Types["Range"];

    private static bool IsStandardIndex(TypeSymbol type) =>
        type is StructTypeSymbol { SimpleName: "Index", ModuleName: Builtins.StandardModuleName };

    private static bool IsStandardRange(TypeSymbol type) =>
        type is StructTypeSymbol { SimpleName: "Range", ModuleName: Builtins.StandardModuleName };

    // ============================================================ as values

    /// <summary><c>^n</c>, as the <c>Standard.Index</c> it is.</summary>
    private BoundExpression BindIndexFromEnd(IndexFromEndSyntax syntax)
    {
        var count = BindExpression(syntax.Operand);
        if (count.Type.IsError())
            return count;

        if (count.Type is not PrimitiveTypeSymbol { IsInteger: true })
        {
            diagnostics.Error("SL0242", syntax.Operand.Span,
                $"'^' counts back from the end by an integer, but this is '{count.Type.Name}'",
                count.Type);
            return new BoundErrorExpression(syntax.Span);
        }

        return MakeIndex(syntax.Span, count, fromEnd: true);
    }

    /// <summary><c>a..b</c>, as the <c>Standard.Range</c> it is.</summary>
    private BoundExpression BindRange(RangeSyntax syntax)
    {
        var start = BindRangeEnd(syntax.Start, syntax.Span, fromEnd: false);
        var end = BindRangeEnd(syntax.End, syntax.Span, fromEnd: true);

        if (start.Type.IsError() || end.Type.IsError())
            return new BoundErrorExpression(syntax.Span);

        var range = StandardRange;
        var constructor = range.Constructors.First(c => c.Parameters.Count(p => !p.IsThis) == 2);
        return new BoundStructNew(syntax.Span, range, constructor, [start, end]);
    }

    /// <summary>
    /// One end of a range as an <c>Index</c>. A missing start is <c>0</c> and
    /// a missing end is <c>^0</c>.
    /// </summary>
    private BoundExpression BindRangeEnd(ExpressionSyntax? syntax, SourceSpan span, bool fromEnd)
    {
        if (syntax is null)
            return MakeIndex(span, new BoundLiteral(span, PrimitiveTypeSymbol.NUInt, 0UL), fromEnd);

        var bound = BindExpression(syntax);
        if (bound.Type.IsError() || IsStandardIndex(bound.Type))
            return bound;

        if (bound.Type is not PrimitiveTypeSymbol { IsInteger: true })
        {
            diagnostics.Error("SL0242", syntax.Span,
                $"a range runs between integers or 'Index' values, but this is '{bound.Type.Name}'",
                bound.Type);
            return new BoundErrorExpression(syntax.Span);
        }

        return MakeIndex(syntax.Span, bound, fromEnd: false);
    }

    /// <summary>
    /// <c>new Index(value, fromEnd)</c>. Any integer is taken, as an index
    /// takes any integer: a negative one becomes a word no length reaches.
    /// </summary>
    private BoundStructNew MakeIndex(SourceSpan span, BoundExpression value, bool fromEnd)
    {
        var index = StandardIndex;
        var constructor = index.Constructors.First(c => c.Parameters.Count(p => !p.IsThis) == 2);
        return new BoundStructNew(span, index, constructor,
            [AsWord(value), new BoundLiteral(span, PrimitiveTypeSymbol.Bool, fromEnd)]);
    }

    /// <summary>An integer as a <c>nuint</c>, folded where it is a constant that fits.</summary>
    private BoundExpression AsWord(BoundExpression value) =>
        IsImplicitlyConvertible(value, PrimitiveTypeSymbol.NUInt)
            ? BindConversion(value, PrimitiveTypeSymbol.NUInt, value.Span)
            : AsInteger(value, PrimitiveTypeSymbol.NUInt);

    /// <summary>
    /// An <c>Index</c> taken apart where it was written out: its count and
    /// which end it is from. One that is only known at run time stays whole,
    /// as <see cref="IndexOrigin.Written"/>.
    /// </summary>
    private static (BoundExpression Value, IndexOrigin Origin) PositionParts(BoundExpression position)
    {
        if (!IsStandardIndex(position.Type))
            return (position, IndexOrigin.Start);

        if (position is BoundStructNew { Arguments: [var value, BoundLiteral { Value: bool fromEnd }] })
            return (value, fromEnd ? IndexOrigin.End : IndexOrigin.Start);

        return (position, IndexOrigin.Written);
    }

    // ============================================================ indexing

    /// <summary><c>target[position]</c>, where the position is an <c>Index</c> or a <c>Range</c>.</summary>
    private BoundExpression BindPositionIndex(BoundExpression target, BoundExpression position, SourceSpan span)
    {
        bool range = IsStandardRange(position.Type);

        switch (target.Type)
        {
            case ArrayTypeSymbol or SliceTypeSymbol when range:
                return SliceByRange(target, position, span);

            case ArrayTypeSymbol or SliceTypeSymbol or FixedArrayTypeSymbol when !range:
                return IndexByPosition(target, position, span);

            case FixedArrayTypeSymbol:
                diagnostics.Error("SL0452", span,
                    $"cannot slice '{target.Type.Name}'; a slice holds the array it is part of, " +
                    "and an inline array is not one that can be held",
                    target.Type);
                return new BoundErrorExpression(span);

            case NamedTypeSymbol named:
                return range
                    ? SliceCountable(named, target, position, span)
                    : IndexCountable(named, target, position, span);

            default:
                diagnostics.Error("SL0777", span,
                    $"'{target.Type.Name}' has no length, so there is no end to count back " +
                    "from; '^' and ranges work on an array, a slice, an inline array, or a " +
                    "type with 'Count' or 'Length'",
                    target.Type);
                return new BoundErrorExpression(span);
        }
    }

    /// <summary>One element of an array, a slice or an inline array, from either end.</summary>
    private BoundExpression IndexByPosition(BoundExpression target, BoundExpression position, SourceSpan span)
    {
        var element = target.Type switch
        {
            ArrayTypeSymbol array => array.Element,
            SliceTypeSymbol slice => slice.Element,
            _ => ((FixedArrayTypeSymbol)target.Type).Element,
        };

        var (value, origin) = PositionParts(position);

        // An inline array's length is in its type, so `^n` of a constant is a
        // constant index, and one outside it is an error now rather than later.
        if (target.Type is FixedArrayTypeSymbol inline && origin == IndexOrigin.End &&
            FoldSwitchLabel(value) is { } back)
        {
            if (back == 0 || back > (ulong)inline.Length)
            {
                diagnostics.Error("SL0490", position.Span,
                    $"^{back} is outside '{inline.Name}', which has " +
                    $"{Counted(inline.Length, "element")}",
                    inline);
                return new BoundErrorExpression(span);
            }

            return new BoundIndex(span, element, target,
                new BoundLiteral(span, PrimitiveTypeSymbol.NUInt, (ulong)inline.Length - back));
        }

        return new BoundIndex(span, element, target,
            origin == IndexOrigin.Written ? value : PromoteToInt(value)) { Origin = origin };
    }

    /// <summary><c>a[r]</c> for a <c>Range</c>: the slice <c>a[from:to]</c> would be.</summary>
    private BoundExpression SliceByRange(BoundExpression target, BoundExpression range, SourceSpan span)
    {
        if (range is BoundStructNew { Arguments: [var start, var end] })
        {
            var (from, fromOrigin) = PositionParts(start);
            var (to, toOrigin) = PositionParts(end);
            return MakeSlice(span, target, from, fromOrigin, to, toOrigin);
        }

        // Read twice, once for each end.
        var whole = Named(range);
        var fields = StandardRange;

        var slice = MakeSlice(span, target,
            new BoundFieldAccess(span, whole, fields.FindField("_start")!), IndexOrigin.Written,
            new BoundFieldAccess(span, whole, fields.FindField("_end")!), IndexOrigin.Written);

        return slice.Type.IsError()
            ? slice
            : new BoundRangeSlice(span, slice.Type, slice) { Range = range, Whole = whole };
    }

    /// <summary>A slice of an array or another slice, each end counted from where it says.</summary>
    private BoundExpression MakeSlice(
        SourceSpan span, BoundExpression target,
        BoundExpression? from, IndexOrigin fromOrigin,
        BoundExpression? to, IndexOrigin toOrigin)
    {
        var element = target.Type switch
        {
            ArrayTypeSymbol array => array.Element,
            SliceTypeSymbol slice => slice.Element,
            _ => null,
        };

        if (element is null)
        {
            diagnostics.Error("SL0452", span,
                $"cannot slice '{target.Type.Name}'; slicing takes part of an array or of " +
                "another slice, or calls a type's own 'Slice(start, length)'",
                target.Type);
            return new BoundErrorExpression(span);
        }

        return new BoundSlice(span, SliceOf(element), target, from, to)
        {
            StartOrigin = fromOrigin,
            EndOrigin = toOrigin,
        };
    }

    // ============================================================ counting types

    /// <summary>
    /// <c>x[^1]</c> on a type with a count and an indexer taking an integer:
    /// <c>x[x.Count - 1]</c>, with <c>x</c> evaluated once.
    /// </summary>
    private BoundExpression IndexCountable(
        NamedTypeSymbol named, BoundExpression target, BoundExpression position, SourceSpan span)
    {
        if (CounterOf(named) is not { } counter)
            return RefuseUncounted(named, span);

        if (IntegerIndexerOf(named) is not { } indexer)
        {
            diagnostics.Error("SL0241", span,
                $"no indexer on '{named.Name}' takes an integer, so there is nothing for an " +
                "'Index' to become",
                named);
            return new BoundErrorExpression(span);
        }

        // Named once as the receiver and again for the count. The receiver is
        // evaluated first, so the count reads what it left behind, and the
        // call stays a call: a write through it reaches the setter.
        BoundExpression receiver = target, again = target;
        if (!IsRepeatable(target))
        {
            var name = new BoundPlaceholder(target.Span, target.Type);
            receiver = new BoundNamedValue(target.Span, target, name);
            again = name;
        }

        var length = AsInteger(BindPropertyRead(span, again, counter), PrimitiveTypeSymbol.NUInt);
        var offset = OffsetIn(position, length, span);
        var indexType = (PrimitiveTypeSymbol)indexer.Parameters.First(p => !p.IsThis).Type;

        return BuildIndexerCall(span, indexer, receiver, [AsInteger(offset, indexType)], null);
    }

    /// <summary>
    /// <c>x[a..b]</c> on a type with a count and a <c>Slice(start, length)</c>:
    /// what that method answers, for the run the range names.
    /// </summary>
    private BoundExpression SliceCountable(
        NamedTypeSymbol named, BoundExpression target, BoundExpression range, SourceSpan span)
    {
        if (CounterOf(named) is not { } counter)
            return RefuseUncounted(named, span);

        if (SliceMethodOf(named) is not { } slice)
        {
            diagnostics.Error("SL0452", span,
                $"cannot slice '{named.Name}'; a range takes part of an array or a slice, or " +
                "calls a type's own 'Slice(start, length)', and it declares none",
                named);
            return new BoundErrorExpression(span);
        }

        // What is sliced, its count, the range and where the run starts are
        // each evaluated once, in that order, and named after.
        var receiver = Named(target);
        var length = AsInteger(BindPropertyRead(span, receiver, counter), PrimitiveTypeSymbol.NUInt);
        var counted = new BoundPlaceholder(span, PrimitiveTypeSymbol.NUInt);

        BoundExpression start, end;
        BoundPlaceholder? whole = null;
        if (range is BoundStructNew { Arguments: [var first, var last] })
        {
            (start, end) = (first, last);
        }
        else
        {
            whole = Named(range);
            start = new BoundFieldAccess(span, whole, StandardRange.FindField("_start")!);
            end = new BoundFieldAccess(span, whole, StandardRange.FindField("_end")!);
        }

        var offset = OffsetIn(start, counted, span);
        var from = new BoundPlaceholder(span, offset.Type);
        var to = OffsetIn(end, counted, span);
        var count = new BoundBinary(span, PrimitiveTypeSymbol.NUInt, to, BoundBinaryOp.Subtract, from);

        var parameters = slice.Parameters.Where(p => !p.IsThis).ToList();
        var call = new BoundCall(span, slice, AsReceiver(receiver, named),
        [
            AsInteger(from, (PrimitiveTypeSymbol)parameters[0].Type),
            AsInteger(count, (PrimitiveTypeSymbol)parameters[1].Type),
        ]);

        return new BoundRangeSlice(span, call.Type, call)
        {
            Target = target,
            Receiver = receiver,
            Length = length,
            Counted = counted,
            Range = whole is null ? null : range,
            Whole = whole,
            Start = offset,
            From = from,
        };
    }

    private BoundErrorExpression RefuseUncounted(NamedTypeSymbol named, SourceSpan span)
    {
        diagnostics.Error("SL0777", span,
            $"'{named.Name}' has no 'Count' or 'Length', so there is no end to count back " +
            "from; '^' and ranges work on an array, a slice, an inline array, or a type " +
            "with one",
            named);
        return new BoundErrorExpression(span);
    }

    /// <summary>Where an <c>Index</c> lands in a sequence of <paramref name="length"/>.</summary>
    private BoundExpression OffsetIn(BoundExpression position, BoundExpression length, SourceSpan span)
    {
        var (value, origin) = PositionParts(position);

        switch (origin)
        {
            case IndexOrigin.Start:
                return value;

            case IndexOrigin.End:
                return new BoundBinary(span, PrimitiveTypeSymbol.NUInt,
                    length, BoundBinaryOp.Subtract, value);

            default:
            {
                var index = StandardIndex;
                var getOffset = index.FindMethod("GetOffset")!;
                return new BoundCall(span, getOffset,
                    new BoundAddressOf(span, index.MakePointerType(), position), [length]);
            }
        }
    }

    /// <summary>
    /// What names a value read more than once, which lowering evaluates once
    /// unless reading it again is free: storage where what stands for it will be.
    /// </summary>
    private static BoundPlaceholder Named(BoundExpression value) =>
        new(value.Span, value.Type) { IsStorage = !IsRepeatable(value) || value.IsLValue };

    /// <summary>A method's receiver: a struct by its address, anything else as it is.</summary>
    private static BoundExpression AsReceiver(BoundExpression receiver, NamedTypeSymbol type) =>
        type is StructTypeSymbol
            ? new BoundAddressOf(receiver.Span, type.MakePointerType(), receiver)
            : receiver;

    /// <summary>What counts a type: an integer <c>Count</c>, or failing that an integer <c>Length</c>.</summary>
    private static PropertySymbol? CounterOf(NamedTypeSymbol type)
    {
        foreach (var name in (string[])["Count", "Length"])
            if (type.FindProperty(name) is { Type: PrimitiveTypeSymbol { IsInteger: true }, Getter: not null } found)
                return found;

        return null;
    }

    /// <summary>The getter of an indexer taking one integer, or null.</summary>
    private static FunctionSymbol? IntegerIndexerOf(NamedTypeSymbol type) =>
        type.Properties
            .Where(p => p.IsIndexer && p.Getter is not null)
            .Select(p => p.Getter!)
            .FirstOrDefault(g => g.Parameters.Where(p => !p.IsThis).ToList() is
                [{ Type: PrimitiveTypeSymbol { IsInteger: true } }]);

    /// <summary>An instance <c>Slice</c> taking a start and a length, both integers, or null.</summary>
    private static FunctionSymbol? SliceMethodOf(NamedTypeSymbol type) =>
        type.FindMethods("Slice").FirstOrDefault(m =>
            !m.IsStatic && !m.ReturnType.IsVoid() &&
            m.Parameters.Where(p => !p.IsThis).ToList() is
                [{ Type: PrimitiveTypeSymbol { IsInteger: true } },
                 { Type: PrimitiveTypeSymbol { IsInteger: true } }]);
}
