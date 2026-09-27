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

using Stainless.Binding;
using Stainless.Source;

namespace Stainless.Lowering;

/// <summary>
/// Collection expressions: every part evaluated and held where a spread is
/// among them, then the storage made and filled.
/// </summary>
public sealed partial class Lowerer
{
    /// <summary>One part of a collection once its values are held: an element, or a spread and what it walks.</summary>
    private readonly record struct CollectionPart(BoundExpression Value, BoundCollectionSpread? Spread);

    private BoundExpression LowerCollection(BoundCollection collection)
    {
        var span = collection.Span;
        var held = new List<HeldValue>();
        bool hold = collection.Parts.Any(p => p is BoundCollectionSpread);
        var parts = new List<CollectionPart>();

        foreach (var part in collection.Parts)
        {
            if (part is not BoundCollectionSpread spread)
            {
                var value = Rewrite(part);
                parts.Add(new CollectionPart(hold ? Holds.HoldValue(value, held, everything: true) : value, null));
                continue;
            }

            var source = Rewrite(spread.Source);
            if (!Places.IsRepeatable(source))
                source = Holds.HoldValue(source, held, everything: true);

            if (spread.Walk is null)
            {
                foreach (var element in spread.Elements)
                    parts.Add(new CollectionPart(Rewrite(Replace(element, spread.Walked, source)), null));
                continue;
            }

            parts.Add(new CollectionPart(source, spread));
        }

        var made = collection.Form switch
        {
            CollectionForm.Literal => new BoundArrayLiteral(span, collection.Type, collection.ElementType,
                parts.Select(p => p.Value).ToList()),
            CollectionForm.Filled => FillCollection(collection, parts),
            _ => AddToCollection(collection, parts),
        };

        return Places.WithHeld(span, held, made);
    }

    /// <summary>
    /// <c>let array = new T[n] in let at = 0 in (array[at] = a, at = at + 1, at = Copy(array, at, b), ..., array)</c>:
    /// the array made once at its size and filled from the front.
    /// </summary>
    private BoundExpression FillCollection(BoundCollection collection, List<CollectionPart> parts)
    {
        var span = collection.Span;
        var arrayType = (ArrayTypeSymbol)collection.Type;

        var made = Synthetic("array", arrayType);
        var at = Synthetic("at", PrimitiveTypeSymbol.NUInt);
        var madeRead = new BoundLocalAccess(span, made);
        var atRead = new BoundLocalAccess(span, at);

        var writes = new List<BoundExpression>();
        foreach (var part in parts)
        {
            if (part.Spread is { } spread)
            {
                writes.Add(new BoundAssignment(span, atRead,
                    new BoundCall(span, spread.Walk!, null, [madeRead, atRead, part.Value])));
                continue;
            }

            writes.Add(new BoundAssignment(part.Value.Span,
                new BoundIndex(part.Value.Span, collection.ElementType, madeRead, atRead), part.Value));
            writes.Add(new BoundAssignment(span, atRead,
                new BoundBinary(span, PrimitiveTypeSymbol.NUInt, atRead, BoundBinaryOp.Add, Word(span, 1))));
        }

        return new BoundLet(span, made, new BoundNewArray(span, arrayType, TotalOf(parts, span)),
            new BoundLet(span, at, Word(span, 0), new BoundSequence(span, writes, madeRead)));
    }

    /// <summary>
    /// <c>let made = new C() in (made.Add(a), AddSpread(made, b), ..., made)</c>, and for an
    /// <c>ArrayBuilder</c> its <c>ToArray()</c> in place of the last.
    /// </summary>
    private BoundExpression AddToCollection(BoundCollection collection, List<CollectionPart> parts)
    {
        var span = collection.Span;
        var builder = collection.Builder!;

        List<BoundExpression> arguments = collection.Form == CollectionForm.Gathered
            ? [Word(span, parts.Count(p => p.Spread is null))]
            : collection.Capacity is { } capacity
                ? [Replace(capacity, collection.Total!, TotalOf(parts, span))]
                : [];
        var creation = new BoundNew(span, builder, collection.Constructor, arguments);

        var made = Synthetic("made", builder, isConst: true);
        var reading = new BoundLocalAccess(span, made);

        var calls = parts
            .Select(part => part.Spread is { } spread
                ? new BoundCall(span, spread.Walk!, null, [reading, part.Value])
                : new BoundCall(part.Value.Span, collection.Add!, reading, [part.Value]))
            .ToList<BoundExpression>();

        BoundExpression finish = collection.Finish is { } toArray
            ? new BoundCall(span, toArray, reading, [])
            : reading;

        return new BoundLet(span, made, creation, new BoundSequence(span, calls, finish));
    }

    /// <summary>How many elements there are: those written, and what each spread says it yields.</summary>
    private static BoundExpression TotalOf(List<CollectionPart> parts, SourceSpan span)
    {
        BoundExpression total = Word(span, parts.Count(p => p.Spread is null));
        foreach (var part in parts)
            if (part.Spread is { } spread)
                total = new BoundBinary(span, PrimitiveTypeSymbol.NUInt,
                    total, BoundBinaryOp.Add, Replace(spread.Count!, spread.Walked, part.Value));

        return total;
    }

    /// <summary>
    /// The array a <c>params</c> parameter is given; for a <c>Span&lt;T&gt;</c>, viewed
    /// as the slice, and checked on the way out of the statement for a
    /// reference anything kept where it lives in the frame.
    /// </summary>
    private BoundExpression LowerParamsArray(BoundParamsArray gathered)
    {
        var literal = new BoundArrayLiteral(gathered.Span, gathered.Array, gathered.Array.Element,
            RewriteAll(gathered.Elements))
        {
            OnStack = gathered.InFrame,
        };

        return gathered.Type is SliceTypeSymbol slice
            ? new BoundConversion(gathered.Span, slice, literal, ConversionKind.ArrayToSlice)
            : literal;
    }

    private static BoundLiteral Word(SourceSpan span, int value) =>
        new(span, PrimitiveTypeSymbol.NUInt, (ulong)value);
}
