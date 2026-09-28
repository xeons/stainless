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
/// Collection expressions: <c>[a, b, ..c]</c>, settled against the type they
/// are going into.
///
/// <para>
/// Without a <c>..</c> an array literal is what it has always been: one
/// allocation and a store per element at a constant index. A <c>..</c> of an
/// inline array is written out as its elements, since its length is in its
/// type. Any other <c>..</c> is walked by a generic function in
/// <c>stdlib/Standard/ArrayBuilder.sl</c>, instantiated at the element types
/// involved, because walking is a loop and a loop is a statement.
/// </para>
///
/// <para>
/// Anything more than an array literal is settled as a <see cref="BoundCollection"/>
/// and lowered. With a <c>..</c> present, every element is evaluated first,
/// in the order written, and held; then the storage is made, sized exactly
/// when every <c>..</c> can say its count, and filled.
/// </para>
/// </summary>
public sealed partial class Binder
{
    /// <summary>
    /// Binds the elements and leaves the type open, unless nothing is going to
    /// close it -- in which case the elements themselves decide.
    /// </summary>
    private BoundExpression BindArrayLiteral(ArrayLiteralSyntax syntax)
    {
        var elements = new List<BoundExpression>();
        bool failed = false;

        foreach (var written in syntax.Elements)
        {
            var bound = written is SpreadElementSyntax spread ? BindSpread(spread) : BindExpression(written);
            failed |= bound.Type.IsError();

            if (bound.Type.IsVoid())
            {
                diagnostics.Error("SL0310", bound.Span,
                    "there is no array of 'void'; an element has to be a value, and this produces none");
                failed = true;
            }

            elements.Add(bound);
        }

        if (failed)
            return new BoundErrorExpression(syntax.Span);

        return new BoundArrayDraft(syntax.Span, ArrayDraftType.Instance, elements);
    }

    /// <summary><c>..source</c>: what is spread, and the type of each thing it yields.</summary>
    private BoundExpression BindSpread(SpreadElementSyntax syntax)
    {
        var source = BindExpression(syntax.Operand);
        if (source is BoundArrayDraft inner)
            source = SettleArrayFromElements(inner);

        if (source.Type.IsError())
            return source;
        if (RefuseUntyped(source))
            return new BoundErrorExpression(syntax.Span);

        if (SpreadElementOf(source.Type) is not { } element)
        {
            diagnostics.Error("SL0778", syntax.Operand.Span,
                $"'..' spreads the elements of an array, a slice or anything with a " +
                $"'GetEnumerator()', and '{source.Type.Name}' is none of those",
                source.Type);
            return new BoundErrorExpression(syntax.Span);
        }

        return new BoundSpread(syntax.Span, element, source);
    }

    /// <summary>
    /// What walking a value yields, by the rule <c>foreach</c> keeps: an
    /// array's element, or <c>GetEnumerator().Current</c> found by name.
    /// </summary>
    private static TypeSymbol? SpreadElementOf(TypeSymbol type)
    {
        switch (type)
        {
            case ArrayTypeSymbol array: return array.Element;
            case SliceTypeSymbol slice: return slice.Element;
            case FixedArrayTypeSymbol inline: return inline.Element;
        }

        if (type is not NamedTypeSymbol source ||
            source.FindMethod("GetEnumerator") is not { } getEnumerator ||
            getEnumerator.Parameters.Any(p => !p.IsThis) ||
            getEnumerator.ReturnType is not NamedTypeSymbol enumerator)
            return null;

        var current = enumerator.FindMethod("get_Current") ?? enumerator.FindMethod("Current");
        if (current is null || current.ReturnType.IsVoid() ||
            enumerator.FindMethod("MoveNext") is not { } moveNext || !moveNext.ReturnType.IsBool())
            return null;

        return current.ReturnType;
    }

    /// <summary>Whether one part of a literal fits an element type: a value by its conversion, a spread by what it yields.</summary>
    private bool PartFits(BoundExpression part, TypeSymbol element) =>
        part is BoundSpread spread
            ? spread.Type.Equals(element) || ClassifyConversion(spread.Type, element, explicitCast: false) is not null
            : IsImplicitlyConvertible(part, element);

    /// <summary>
    /// The element type a collection expression would have as <paramref name="target"/>,
    /// or null when it cannot become one.
    /// </summary>
    private TypeSymbol? CollectionElementOf(TypeSymbol target) => target switch
    {
        ArrayTypeSymbol array => array.Element,
        SliceTypeSymbol slice => slice.Element,
        FixedArrayTypeSymbol inline => inline.Element,
        ClassTypeSymbol collection => CollectionShapeOf(collection)?.Add.Parameters.First(p => !p.IsThis).Type,
        InterfaceTypeSymbol wanted when IsListInterface(wanted) => wanted.TypeArguments[0],
        OptionalTypeSymbol { Element: ArrayTypeSymbol or ClassTypeSymbol } optional =>
            CollectionElementOf(optional.Element),
        _ => null,
    };

    /// <summary>
    /// How many elements a literal has once its inline arrays are written
    /// out, or null when a spread has no length until it runs.
    /// </summary>
    private static int? WrittenLength(BoundArrayDraft draft)
    {
        int total = 0;
        foreach (var part in draft.Elements)
        {
            switch (part)
            {
                case BoundSpread { Source.Type: FixedArrayTypeSymbol inline }:
                    total += inline.Length;
                    break;

                case BoundSpread:
                    return null;

                default:
                    total++;
                    break;
            }
        }

        return total;
    }

    /// <summary>Whether an array literal fits a target, for overload resolution.</summary>
    private bool CollectionFits(BoundArrayDraft draft, TypeSymbol target) =>
        CollectionElementOf(target) is { } element &&
        draft.Elements.All(e => PartFits(e, element)) &&
        (target is not FixedArrayTypeSymbol inline || WrittenLength(draft) == inline.Length);

    // ============================================================ settling

    /// <summary>
    /// Settles an array literal against the type it is going into.
    ///
    /// <c>T[]</c> allocates; <c>T[N]</c> must match in length, because an
    /// inline array is its elements and there is nowhere to put a different
    /// number of them; <c>Span&lt;T&gt;</c> settles as the <c>T[]</c> it is a view of,
    /// and the ordinary array-to-slice conversion does the rest. A class with
    /// <c>Add</c> is made and added to, and <c>IEnumerable&lt;T&gt;</c>,
    /// <c>IList&lt;T&gt;</c> and <c>IReadOnlyList&lt;T&gt;</c> are given a
    /// <c>List&lt;T&gt;</c>.
    /// </summary>
    private BoundExpression BindArraySettle(
        BoundArrayDraft draft, TypeSymbol target, SourceSpan span)
    {
        switch (target)
        {
            case SliceTypeSymbol slice:
                return BindConversion(BindArraySettle(draft, ArrayOf(slice.Element), span), slice, span);

            case ArrayTypeSymbol or FixedArrayTypeSymbol:
                return SettleArray(draft, target, span);

            // What an optional may hold, made and then held.
            case OptionalTypeSymbol { Element: ArrayTypeSymbol or ClassTypeSymbol } optional:
                return BindConversion(BindArraySettle(draft, optional.Element, span), target, span);

            case ClassTypeSymbol collection:
                return SettleCollection(draft, collection, span);

            case InterfaceTypeSymbol wanted when IsListInterface(wanted):
            {
                var list = ListTemplateFor(wanted) is { } template
                    ? Instantiate(template, [wanted.TypeArguments[0]], span) as ClassTypeSymbol
                    : null;
                if (list is null)
                    break;

                return BindConversion(SettleCollection(draft, list, span), wanted, span);
            }
        }

        diagnostics.Error("SL0546", span,
            $"'{target.Name}' is not an array, a slice, or a class with 'Add', so an array " +
            "literal cannot become one",
            target);
        return new BoundErrorExpression(span);
    }

    /// <summary>An array or an inline array, from the parts of a literal.</summary>
    private BoundExpression SettleArray(BoundArrayDraft draft, TypeSymbol target, SourceSpan span)
    {
        var element = target is ArrayTypeSymbol array ? array.Element : ((FixedArrayTypeSymbol)target).Element;

        if (target is FixedArrayTypeSymbol wanted)
        {
            if (draft.Elements.FirstOrDefault(p => p is BoundSpread { Source.Type: not FixedArrayTypeSymbol })
                is { } unmeasured)
            {
                diagnostics.Error("SL0779", unmeasured.Span,
                    $"'{wanted.Name}' holds exactly {Counted(wanted.Length, "element")}, and this " +
                    $"'..' has no length until it runs; only an inline array's is known here",
                    wanted);
                return new BoundErrorExpression(span);
            }

            if (WrittenLength(draft) is { } written && written != wanted.Length)
            {
                diagnostics.Error("SL0547", span,
                    $"'{wanted.Name}' holds exactly {wanted.Length} " +
                    $"element{(wanted.Length == 1 ? "" : "s")}, and this literal has " +
                    $"{written}; an inline array is its elements, so there is " +
                    "nowhere to keep a different number of them",
                    wanted);
                return new BoundErrorExpression(span);
            }
        }

        if (ConvertParts(draft, element) is not { } parts)
            return new BoundErrorExpression(span);

        if (!parts.Any(p => p is BoundCollectionSpread))
            return new BoundArrayLiteral(span, target, element, parts);

        // Nothing is spread that did not have its length in its type, so the
        // literal is the one it always was.
        if (!parts.Any(IsWalked))
            return new BoundCollection(span, target, element, CollectionForm.Literal, parts);

        var arrayType = (ArrayTypeSymbol)target;
        if (parts.Any(p => IsWalked(p) && !IsCounted(((BoundCollectionSpread)p).Source.Type)))
            return GatherThroughArrayBuilder(parts, arrayType, span);

        // Every length is known, so the array is made once at its size.
        parts = parts.Select(p => IsWalked(p) ? Counting((BoundCollectionSpread)p, span) : p).ToList();

        var filled = new List<BoundExpression>(parts.Count);
        foreach (var part in parts)
        {
            if (!IsWalked(part))
            {
                filled.Add(part);
                continue;
            }

            var spread = (BoundCollectionSpread)part;
            if (SpreadHelper("CopySpreadElements", [element, spread.Source.Type], span) is not { } copy)
                return new BoundErrorExpression(span);

            filled.Add(Walking(spread, copy));
        }

        return new BoundCollection(span, arrayType, element, CollectionForm.Filled, filled);
    }

    /// <summary>
    /// An array from spreads not all of which can say how long they are:
    /// gathered into an <c>ArrayBuilder</c>, which grows as it goes.
    /// </summary>
    private BoundExpression GatherThroughArrayBuilder(
        List<BoundExpression> parts, ArrayTypeSymbol arrayType, SourceSpan span)
    {
        if (_builtins.Standard.FindGenericType("ArrayBuilder", 1) is not { } template ||
            Instantiate(template, [arrayType.Element], span) is not ClassTypeSymbol builder)
            return new BoundErrorExpression(span);

        var add = builder.FindMethod("Add")!;
        if (AddedParts(parts, builder, add, span) is not { } added)
            return new BoundErrorExpression(span);

        return new BoundCollection(span, arrayType, arrayType.Element, CollectionForm.Gathered, added)
        {
            Builder = builder,
            Constructor = builder.Constructors.First(),
            Add = add,
            Finish = builder.FindMethod("ToArray")!,
        };
    }

    /// <summary>
    /// A class with <c>Add</c>: made, then added to once per element and once
    /// per element of each spread, in order.
    /// </summary>
    private BoundExpression SettleCollection(BoundArrayDraft draft, ClassTypeSymbol collection, SourceSpan span)
    {
        if (CollectionShapeOf(collection) is not { } shape)
        {
            diagnostics.Error("SL0546", span,
                IsDefaultConstructible(collection)
                    ? $"'{collection.Name}' has no 'Add' taking one element, so there is nothing " +
                      "for an array literal's elements to be added with"
                    : $"'{collection.Name}' has no constructor taking nothing, so there is " +
                      "nothing for an array literal to start from",
                collection);
            return new BoundErrorExpression(span);
        }

        var element = shape.Add.Parameters.First(p => !p.IsThis).Type;

        if (ConvertParts(draft, element) is not { } parts)
            return new BoundErrorExpression(span);

        // With room reserved when the count is known, as `new List<T>(n)` would.
        var constructor = shape.Empty;
        BoundPlaceholder? total = null;
        BoundExpression? capacity = null;

        if (shape.Sized is { } sized &&
            parts.All(p => !IsWalked(p) || IsCounted(((BoundCollectionSpread)p).Source.Type)))
        {
            parts = parts.Select(p => IsWalked(p) ? Counting((BoundCollectionSpread)p, span) : p).ToList();

            constructor = sized;
            total = new BoundPlaceholder(span, PrimitiveTypeSymbol.NUInt);
            capacity = AsInteger(total, (PrimitiveTypeSymbol)sized.Parameters.First(p => !p.IsThis).Type);
        }

        // A collection expression has no initializer to name anything in.
        CheckRequiredMembers(collection, constructor, null, span);

        if (AddedParts(parts, collection, shape.Add, span) is not { } added)
            return new BoundErrorExpression(span);

        return new BoundCollection(span, collection, element, CollectionForm.Added, added)
        {
            Builder = collection,
            Constructor = constructor,
            Add = shape.Add,
            Total = total,
            Capacity = capacity,
        };
    }

    /// <summary>
    /// The parts of what is added to, in order: each element as <paramref name="add"/>
    /// takes it, and each spread with the function that adds what it yields.
    /// </summary>
    private List<BoundExpression>? AddedParts(
        List<BoundExpression> parts, ClassTypeSymbol type, FunctionSymbol add, SourceSpan span)
    {
        var element = add.Parameters.First(p => !p.IsThis).Type;
        var added = new List<BoundExpression>(parts.Count);

        foreach (var part in parts)
        {
            if (part is not BoundCollectionSpread spread)
            {
                added.Add(BindConversion(part, element, part.Span));
                continue;
            }

            if (!IsWalked(spread))
            {
                added.Add(new BoundCollectionSpread(spread.Span, spread.Type, spread.Source, spread.Walked)
                {
                    Elements = spread.Elements.Select(e => BindConversion(e, element, e.Span)).ToList(),
                });
                continue;
            }

            if (SpreadHelper("AddSpreadElements", [type, spread.Source.Type], span) is not { } each)
                return null;

            added.Add(Walking(spread, each));
        }

        return added;
    }

    /// <summary>
    /// Every part converted to the element type. An inline array spread is
    /// its elements, read from what it names; any other is walked. Null when
    /// a part does not fit, which is reported.
    /// </summary>
    private List<BoundExpression>? ConvertParts(BoundArrayDraft draft, TypeSymbol element)
    {
        var parts = new List<BoundExpression>();
        bool failed = false;

        foreach (var part in draft.Elements)
        {
            if (part is not BoundSpread spread)
            {
                var converted = BindConversion(part, element, part.Span);
                failed |= converted.Type.IsError();
                parts.Add(converted);
                continue;
            }

            if (!PartFits(spread, element))
            {
                diagnostics.Error("SL0778", spread.Span,
                    $"this '..' yields '{spread.Type.Name}', which does not convert to " +
                    $"'{element.Name}', the element type here",
                    spread.Type, element);
                failed = true;
                continue;
            }

            // Held unless reading it again is free, so the placeholder is
            // storage where what stands for it will be.
            var source = spread.Source;
            var walked = new BoundPlaceholder(source.Span, source.Type)
            {
                IsStorage = source.IsLValue || !IsRepeatable(source),
            };

            if (source.Type is FixedArrayTypeSymbol inline)
            {
                var elements = new List<BoundExpression>(inline.Length);
                for (int i = 0; i < inline.Length; i++)
                    elements.Add(BindConversion(
                        new BoundIndex(spread.Span, inline.Element, walked, Word(spread.Span, i)),
                        element, spread.Span));

                parts.Add(new BoundCollectionSpread(spread.Span, spread.Type, source, walked) { Elements = elements });
                continue;
            }

            parts.Add(new BoundCollectionSpread(spread.Span, spread.Type, source, walked));
        }

        return failed ? null : parts;
    }

    /// <summary>Whether a part is a spread walked at run time, rather than written out.</summary>
    private static bool IsWalked(BoundExpression part) =>
        part is BoundCollectionSpread { Source.Type: not FixedArrayTypeSymbol };

    /// <summary>A spread that says how many it yields.</summary>
    private BoundCollectionSpread Counting(BoundCollectionSpread spread, SourceSpan span) =>
        new(spread.Span, spread.Type, spread.Source, spread.Walked)
        {
            Count = CountOf(spread.Walked, span),
            Walk = spread.Walk,
        };

    /// <summary>A spread with the function that walks it.</summary>
    private static BoundCollectionSpread Walking(BoundCollectionSpread spread, FunctionSymbol walk) =>
        new(spread.Span, spread.Type, spread.Source, spread.Walked)
        {
            Count = spread.Count,
            Walk = walk,
        };

    /// <summary>Whether a spread of this type can say how many it will yield before it is walked.</summary>
    private static bool IsCounted(TypeSymbol type) =>
        type is ArrayTypeSymbol or SliceTypeSymbol or FixedArrayTypeSymbol ||
        type is NamedTypeSymbol named && CounterOf(named) is not null;

    /// <summary>How many a counted spread yields, as a <c>nuint</c>.</summary>
    private BoundExpression CountOf(BoundExpression source, SourceSpan span) => source.Type switch
    {
        ArrayTypeSymbol or SliceTypeSymbol => new BoundArrayLength(span, PrimitiveTypeSymbol.NUInt, source),
        FixedArrayTypeSymbol inline => Word(span, inline.Length),
        _ => AsInteger(
            BindPropertyRead(span, source, CounterOf((NamedTypeSymbol)source.Type)!), PrimitiveTypeSymbol.NUInt),
    };

    private static BoundLiteral Word(SourceSpan span, int value) =>
        new(span, PrimitiveTypeSymbol.NUInt, (ulong)value);

    /// <summary>One of the functions in <c>stdlib/Standard/ArrayBuilder.sl</c>, instantiated.</summary>
    private FunctionSymbol? SpreadHelper(string name, IReadOnlyList<TypeSymbol> arguments, SourceSpan span) =>
        _builtins.Standard.GenericFunctions.FirstOrDefault(t => t.Name == name) is { } template
            ? InstantiateFunction(template, arguments, span)
            : null;

    // ============================================================ collection types

    /// <summary>
    /// What makes a class something a collection expression can become: a
    /// constructor taking nothing, one instance <c>Add</c> taking one element,
    /// and, where it has one, a constructor taking only an integer
    /// <c>capacity</c>.
    /// </summary>
    private sealed record CollectionShape(FunctionSymbol? Empty, FunctionSymbol Add, FunctionSymbol? Sized);

    private CollectionShape? CollectionShapeOf(ClassTypeSymbol type)
    {
        if (!IsDefaultConstructible(type))
            return null;

        var adds = type.FindMethods("Add")
            .Where(m => !m.IsStatic && m.Parameters.Count(p => !p.IsThis) == 1)
            .ToList();

        // Several: the one taking what the type yields when walked, as C#
        // takes its element type from the iteration type.
        var add = adds.Count == 1
            ? adds[0]
            : SpreadElementOf(type) is { } yielded
                ? adds.FirstOrDefault(m => m.Parameters.First(p => !p.IsThis).Type.Equals(yielded))
                : null;

        if (add is null)
            return null;

        var empty = type.Constructors.FirstOrDefault(c => !c.Parameters.Any(p => !p.IsThis));
        var sized = type.Constructors.FirstOrDefault(c => c.IsPublic &&
            c.Parameters.Where(p => !p.IsThis).ToList() is
                [{ Name: "capacity", Type: PrimitiveTypeSymbol { IsInteger: true } }]);

        return new CollectionShape(empty, add, sized);
    }

    /// <summary>
    /// <c>IEnumerable&lt;T&gt;</c>, <c>IList&lt;T&gt;</c> and
    /// <c>IReadOnlyList&lt;T&gt;</c>: the interfaces a <c>List&lt;T&gt;</c>
    /// is, and so the ones a collection expression can be given one for.
    /// </summary>
    private static bool IsListInterface(InterfaceTypeSymbol type) =>
        type.ModuleName == "Standard.Collections" && type.TypeArguments.Count == 1 &&
        type.Template?.Name is "IEnumerable" or "IList" or "IReadOnlyList";

    private static GenericTypeTemplate? ListTemplateFor(InterfaceTypeSymbol type) =>
        type.Template?.Module.FindGenericType("List", 1);

    /// <summary>
    /// The type an array literal takes when nothing else says: the one type
    /// every element reaches, which is the same question a ternary's two arms
    /// ask. A spread offers what it yields.
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

        var (element, disagreeing) = AgreeOnElementType(draft);
        if (disagreeing is null)
            return BindArraySettle(draft, ArrayOf(element), draft.Span);

        diagnostics.Error("SL0549", disagreeing.Span,
            $"this element is '{disagreeing.Type.Name}' and the ones before it are " +
            $"'{element.Name}'; an array holds one type, so either make them agree " +
            "or give the array a type of its own",
            disagreeing.Type, element);
        return new BoundErrorExpression(draft.Span);
    }

    /// <summary>The one type every element of a non-empty array literal reaches, or null.</summary>
    private TypeSymbol? AgreedElementType(BoundArrayDraft draft) =>
        draft.Elements.Count != 0 && AgreeOnElementType(draft) is (var element, null) ? element : null;

    /// <summary>
    /// The type the elements of a non-empty array literal agree on, and the
    /// first that reaches it not, with what the ones before it agreed on.
    /// </summary>
    private (TypeSymbol Element, BoundExpression? Disagreeing) AgreeOnElementType(BoundArrayDraft draft)
    {
        var element = draft.Elements[0].Type;
        for (int i = 1; i < draft.Elements.Count; i++)
        {
            var next = draft.Elements[i];

            // Already reaches what the ones before agreed on.
            if (PartFits(next, element))
                continue;

            // Or is wider than they are, and they reach it: [1, 2L] is a long[]
            // for the same reason `flag ? 1 : 2L` is a long.
            if (draft.Elements.Take(i).All(e => PartFits(e, next.Type)))
            {
                element = next.Type;
                continue;
            }

            return (element, next);
        }

        return (element, null);
    }
}
