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

namespace Stainless.Binding;

/// <summary>
/// Whether a list of patterns covers every value, and whether one of them can
/// be reached past the ones before it.
///
/// <para>
/// Each pattern is described twice, as a <see cref="Space"/> of values: what
/// it certainly matches and what it could match. A guard, a range or anything
/// else this does not follow is nothing in the first and everything in the
/// second, so neither answer is ever wrong -- at worst an arm that could be
/// reported unreachable is not, and a switch that is exhaustive needs a
/// <c>_</c> it did not strictly need.
/// </para>
/// <para>
/// The question itself is Maranget's: is some value matched by this one and
/// by none of those? A value is a constructor applied to members -- a case of
/// a variant with its fields, <c>true</c>, a member of an enum, null, or "an
/// object" with whatever properties the patterns read -- and a type whose
/// constructors can all be listed is covered once each of them is.
/// </para>
/// </summary>
public sealed partial class Binder
{
    /// <summary>A set of values, as coverage sees it.</summary>
    private abstract record Space
    {
        public static readonly Space Any = new AnySpace();
        public static readonly Space None = new NoSpace();

        public static Space Union(Space left, Space right) =>
            left is AnySpace || right is AnySpace ? Any
            : left is NoSpace ? right
            : right is NoSpace ? left
            : new OrSpace(left, right);

        /// <summary>
        /// Both at once, approximated from below when <paramref name="under"/>
        /// and from above otherwise.
        /// </summary>
        public static Space Intersection(Space left, Space right, bool under)
        {
            if (left is NoSpace || right is NoSpace)
                return None;
            if (left is AnySpace)
                return right;
            if (right is AnySpace)
                return left;

            if (left is ConstructorSpace first && right is ConstructorSpace second &&
                Equals(first.Key, second.Key))
            {
                var members = new List<SpaceMember>();

                foreach (var member in first.Members)
                {
                    var other = second.Members.FirstOrDefault(m => Equals(m.Key, member.Key));
                    members.Add(other is null
                        ? member
                        : member with { Space = Intersection(member.Space, other.Space, under) });
                }

                members.AddRange(second.Members.Where(m => !first.Members.Any(f => Equals(f.Key, m.Key))));

                return under && members.Any(m => m.Space is NoSpace)
                    ? None
                    : new ConstructorSpace(first.Key, members);
            }

            return under ? None : left;
        }
    }

    private sealed record AnySpace : Space;

    private sealed record NoSpace : Space;

    private sealed record OrSpace(Space Left, Space Right) : Space;

    /// <summary>One constructor, and what its members must be; a member not listed may be anything.</summary>
    private sealed record ConstructorSpace(object Key, IReadOnlyList<SpaceMember> Members) : Space;

    private sealed record SpaceMember(object Key, TypeSymbol Type, Space Space);

    /// <summary>The null an optional may hold.</summary>
    private sealed record NullKey
    {
        public static readonly NullKey Instance = new();
    }

    /// <summary>A value of the type the column already has, whatever its members are.</summary>
    private sealed record InstanceKey
    {
        public static readonly InstanceKey Instance = new();
    }

    /// <summary>An object of a class narrower than the column's type.</summary>
    private sealed record TypeKey(NamedTypeSymbol Type);

    /// <summary>A constant: an integer's, a bool's or an enum's bits, or a string.</summary>
    private sealed record ValueKey(object Value);

    /// <summary>
    /// A list pattern: <paramref name="Prefix"/> elements from the front and,
    /// where it is <paramref name="Open"/> with a '..', <paramref name="Suffix"/>
    /// from the back. A closed one has exactly <paramref name="Prefix"/>.
    /// </summary>
    private sealed record ListKey(int Prefix, int Suffix, bool Open, TypeSymbol Element);

    /// <summary>Where an element of a list pattern stands.</summary>
    private sealed record ListPosition(bool FromBack, int Index)
    {
        /// <summary>The whole sequence, under the non-null of an optional one.</summary>
        public static readonly ListPosition Whole = new(false, -1);

        public static ListPosition FromStart(int index) => new(false, index);

        /// <summary>Counted from one: the last element is <c>FromEnd(1)</c>.</summary>
        public static ListPosition FromEnd(int index) => new(true, index);
    }

    /// <summary>
    /// Every constructor a type has, where they can be listed. An enum's
    /// members are its constructors only when <paramref name="closedEnums"/>:
    /// a value need not be one of them.
    /// </summary>
    private List<object>? Signature(TypeSymbol type, bool closedEnums)
    {
        switch (type)
        {
            case VariantTypeSymbol variant:
                return [.. variant.Cases];

            case EnumTypeSymbol enumType:
                return closedEnums && !IsFlags(enumType)
                    ? enumType.Members.Select(m => (object)new ValueKey(m.Value)).Distinct().ToList()
                    : null;

            case OptionalTypeSymbol:
                return [NullKey.Instance, InstanceKey.Instance];

            case PrimitiveTypeSymbol primitive:
                return primitive.IsBool()
                    ? [new ValueKey(1UL), new ValueKey(0UL)]
                    : null;

            case PointerTypeSymbol or WeakTypeSymbol:
                return null;

            default:
                return type.IsError() ? null : [InstanceKey.Instance];
        }
    }

    /// <summary>
    /// Whether some value of <paramref name="type"/> in <paramref name="candidate"/>
    /// is matched by none of <paramref name="rows"/>.
    /// </summary>
    private bool IsReachable(
        IReadOnlyList<Space> rows, Space candidate, TypeSymbol type, bool closedEnums = false) =>
        IsUseful(rows.Select(r => new[] { r }).ToList(), [candidate], [type], closedEnums);

    private bool IsUseful(
        IReadOnlyList<Space[]> rows, Space[] candidate, TypeSymbol[] types, bool closedEnums)
    {
        if (candidate.Length == 0)
            return rows.Count == 0;

        var expanded = new List<Space[]>();
        foreach (var row in rows)
            foreach (var head in Alternatives(row[0]))
                if (head is not NoSpace)
                    expanded.Add([head, .. row[1..]]);

        if (candidate[0] is not OrSpace &&
            expanded.Select(r => r[0]).Append(candidate[0]).Any(IsListSpace))
            return IsUsefulAsList(expanded, candidate, types, closedEnums);

        switch (candidate[0])
        {
            case OrSpace:
                return Alternatives(candidate[0])
                    .Any(head => IsUseful(expanded, [head, .. candidate[1..]], types, closedEnums));

            case NoSpace:
                return false;

            case ConstructorSpace constructor:
                return IsUsefulAs(constructor.Key, expanded, candidate, types, closedEnums);
        }

        var present = expanded
            .Select(r => r[0])
            .OfType<ConstructorSpace>()
            .Select(c => c.Key)
            .ToHashSet();

        if (Signature(types[0], closedEnums) is { } signature && signature.All(present.Contains))
            return signature.Any(key => IsUsefulAs(key, expanded, candidate, types, closedEnums));

        // Some constructor no row names, so only the rows that match anything
        // can match it.
        var rest = expanded.Where(r => r[0] is AnySpace).Select(r => r[1..]).ToList();
        return IsUseful(rest, candidate[1..], types[1..], closedEnums);
    }

    /// <summary>The same question, about the values built by one constructor.</summary>
    private bool IsUsefulAs(
        object key, List<Space[]> rows, Space[] candidate, TypeSymbol[] types, bool closedEnums)
    {
        var members = new List<(object Key, TypeSymbol Type)>();

        void Collect(Space space)
        {
            if (space is not ConstructorSpace constructor || !Includes(constructor.Key, key))
                return;

            foreach (var member in constructor.Members)
                if (!members.Any(m => Equals(m.Key, member.Key)))
                    members.Add((member.Key, member.Type));
        }

        foreach (var row in rows)
            Collect(row[0]);
        Collect(candidate[0]);

        Space[]? Specialize(Space[] row)
        {
            IEnumerable<Space> head;

            if (row[0] is AnySpace)
                head = members.Select(_ => Space.Any);
            else if (row[0] is ConstructorSpace constructor && Includes(constructor.Key, key))
                head = members.Select(m =>
                    constructor.Members.FirstOrDefault(c => Equals(c.Key, m.Key))?.Space ?? Space.Any);
            else
                return null;

            return [.. head, .. row[1..]];
        }

        var specialized = rows.Select(Specialize).OfType<Space[]>().ToList();
        var asked = Specialize(candidate)!;
        var columns = members.Select(m => m.Type).Concat(types[1..]).ToArray();

        return IsUseful(specialized, asked, columns, closedEnums);
    }

    private static bool IsListSpace(Space space) => space is ConstructorSpace { Key: ListKey };

    /// <summary>
    /// The same question for a column of sequences, whose constructors are
    /// their lengths.
    ///
    /// There are infinitely many, but past the longest closed pattern and the
    /// widest '..' pattern every length is matched by the same rows, so the
    /// lengths up to there and "that long or longer" are enough to ask about.
    /// Past there, an element is known only by where it stands from the front
    /// or from the back.
    /// </summary>
    private bool IsUsefulAsList(
        List<Space[]> rows, Space[] candidate, TypeSymbol[] types, bool closedEnums)
    {
        // A pattern that asks nothing of the elements is any length; one that
        // asks something no list pattern says is left out, as it might not match.
        Space? AsList(Space head) => head switch
        {
            AnySpace => Space.Any,
            ConstructorSpace { Key: ListKey } list => list,
            ConstructorSpace { Key: InstanceKey } whole when whole.Members.All(m => m.Space is AnySpace) =>
                Space.Any,
            _ => null,
        };

        var listed = rows
            .Select(r => AsList(r[0]) is { } head ? (Space[])[head, .. r[1..]] : null)
            .OfType<Space[]>()
            .ToList();

        var asked = AsList(candidate[0]) ?? Space.Any;
        var keys = listed.Select(r => r[0]).Append(asked)
            .OfType<ConstructorSpace>()
            .Select(c => (ListKey)c.Key)
            .ToList();

        var element = keys.Select(k => k.Element).FirstOrDefault() ?? ErrorTypeSymbol.Instance;
        int longest = keys.Where(k => !k.Open).Select(k => k.Prefix).DefaultIfEmpty(-1).Max();
        int front = keys.Where(k => k.Open).Select(k => k.Prefix).DefaultIfEmpty(0).Max();
        int back = keys.Where(k => k.Open).Select(k => k.Suffix).DefaultIfEmpty(0).Max();
        int beyond = Math.Max(longest + 1, front + back);

        var lengths = types[0] is FixedArrayTypeSymbol inline
            ? [(Open: false, Length: inline.Length)]
            : Enumerable.Range(0, beyond).Select(n => (Open: false, Length: n))
                .Append((Open: true, Length: beyond))
                .ToList();

        foreach (var (open, length) in lengths)
        {
            // The columns: every element of a closed length, or the front and
            // the back of an open one.
            var positions = open
                ? Enumerable.Range(0, front).Select(ListPosition.FromStart)
                    .Concat(Enumerable.Range(1, back).Reverse().Select(ListPosition.FromEnd))
                    .ToList()
                : Enumerable.Range(0, length).Select(ListPosition.FromStart).ToList();

            Space[]? Specialize(Space[] row)
            {
                if (row[0] is AnySpace)
                    return [.. positions.Select(_ => Space.Any), .. row[1..]];

                var list = (ConstructorSpace)row[0];
                var key = (ListKey)list.Key;

                bool fits = open
                    ? key.Open
                    : key.Open ? key.Prefix + key.Suffix <= length : key.Prefix == length;
                if (!fits)
                    return null;

                Space At(ListPosition position)
                {
                    // Read from the back, an element of a closed length is
                    // also one from the front.
                    var asWritten = !open && key.Open && position.Index >= length - key.Suffix
                        ? ListPosition.FromEnd(length - position.Index)
                        : position;

                    return list.Members.FirstOrDefault(m => Equals(m.Key, asWritten))?.Space ?? Space.Any;
                }

                return [.. positions.Select(At), .. row[1..]];
            }

            var question = Specialize([asked, .. candidate[1..]]);
            if (question is null)
                continue;

            var specialized = listed.Select(Specialize).OfType<Space[]>().ToList();
            var columns = positions.Select(_ => element).Concat(types[1..]).ToArray();

            if (IsUseful(specialized, question, columns, closedEnums))
                return true;
        }

        return false;
    }

    private static IEnumerable<Space> Alternatives(Space space) =>
        space is OrSpace either
            ? Alternatives(either.Left).Concat(Alternatives(either.Right))
            : [space];

    /// <summary>Whether every value <paramref name="key"/> builds is one <paramref name="wider"/> builds.</summary>
    private static bool Includes(object wider, object key) =>
        Equals(wider, key) ||
        wider is InstanceKey && key is TypeKey ||
        wider is TypeKey { Type: ClassTypeSymbol outer } &&
        key is TypeKey { Type: ClassTypeSymbol inner } && inner.DerivesFrom(outer);

    /// <summary>
    /// What <c>not</c> leaves: every other constructor, where the one negated
    /// is exactly a constructor and the rest can be listed; otherwise the
    /// widest or narrowest answer that is still true.
    /// </summary>
    private Space Complement(Space inner, TypeSymbol type, bool under)
    {
        if (inner is AnySpace)
            return Space.None;
        if (inner is NoSpace)
            return Space.Any;

        if (inner is ConstructorSpace { Members: var members } constructor &&
            members.All(m => m.Space is AnySpace) &&
            Signature(type, closedEnums: under) is { } signature &&
            signature.Contains(constructor.Key))
            return signature
                .Where(key => !Equals(key, constructor.Key))
                .Select(key => (Space)new ConstructorSpace(key, []))
                .Aggregate(Space.None, Space.Union);

        return under ? Space.None : Space.Any;
    }

    /// <summary>The cases of a variant some value of which no row matches.</summary>
    private IEnumerable<VariantCaseSymbol> UncoveredCases(
        IReadOnlyList<Space> rows, VariantTypeSymbol variant) =>
        variant.Cases.Where(c => IsReachable(rows, new ConstructorSpace(c, []), variant));

    /// <summary>Why a switch expression is not exhaustive, naming what it left out where that can be named.</summary>
    private string Uncovered(IReadOnlyList<Space> rows, TypeSymbol type)
    {
        const string Tail =
            ", and an expression has to produce a value whatever it is given; add ";

        switch (type)
        {
            case VariantTypeSymbol variant:
                return "this switch does not cover " +
                       Listed(UncoveredCases(rows, variant).Select(c => "'" + c.Name + "'")) +
                       Tail + "the case, or a '_ => ...' arm";

            case EnumTypeSymbol enumType when !IsFlags(enumType):
            {
                var missing = enumType.Members
                    .Where(m => IsReachable(rows, new ConstructorSpace(new ValueKey(m.Value), []),
                        enumType, closedEnums: true))
                    .Select(m => $"'{enumType.Name}.{m.Name}'");

                return "this switch does not cover " + Listed(missing) + Tail +
                       "the member, or a '_ => ...' arm";
            }

            case PrimitiveTypeSymbol primitive when primitive.IsBool():
            {
                var missing = new[] { (1UL, "true"), (0UL, "false") }
                    .Where(b => IsReachable(rows, new ConstructorSpace(new ValueKey(b.Item1), []), type))
                    .Select(b => $"'{b.Item2}'");

                return "this switch does not cover " + Listed(missing) + Tail +
                       "an arm for it, or a '_ => ...' arm";
            }

            default:
                return "this switch has no '_ => ...' arm and its arms do not cover every value, " +
                       "and an expression has to produce a value whatever it is given -- there " +
                       "is no exception here to throw at a value that matched nothing";
        }
    }
}
