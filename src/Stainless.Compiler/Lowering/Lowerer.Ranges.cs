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

namespace Stainless.Lowering;

/// <summary>Ranges and positions taken apart as they run: each part evaluated once, and named after.</summary>
public sealed partial class Lowerer
{
    /// <summary>What each <see cref="BoundNamedValue"/> lowered so far is read as after.</summary>
    private readonly Dictionary<BoundPlaceholder, BoundExpression> _named = new(ReferenceEqualityComparer.Instance);

    /// <summary>
    /// <c>let x = target in let n = x.Count in let r = range in let from = ... in x.Slice(from, to - from)</c>,
    /// with what reading again is free left where it is.
    /// </summary>
    private BoundExpression LowerRangeSlice(BoundRangeSlice sliced)
    {
        var held = new List<HeldValue>();
        var names = new List<(BoundPlaceholder Name, BoundExpression Value)>();

        // What is sliced is held where it is read again, or where what is
        // held after it would otherwise run first.
        if (sliced.Target is { } target)
            names.Add((sliced.Receiver!,
                Places.IsRepeatable(target) ||
                sliced.Length is null && (sliced.Range is null || Places.IsRepeatable(sliced.Range))
                    ? target
                    : Holds.HoldValue(target, held, everything: true)));

        if (sliced.Length is { } length)
            names.Add((sliced.Counted!, Holds.HoldValue(Substituted(length, names), held, everything: true)));

        if (sliced.Range is { } range)
            names.Add((sliced.Whole!,
                Places.IsRepeatable(range) ? range : Holds.HoldValue(range, held, everything: true)));

        if (sliced.Start is { } start)
            names.Add((sliced.From!, Holds.HoldValue(Substituted(start, names), held, everything: true)));

        return Rewrite(Places.WithHeld(sliced.Span, held, Substituted(sliced.Access, names)));
    }

    /// <summary><c>let x = value in x</c> where the value first stands, and <c>x</c> wherever it is named after.</summary>
    private BoundExpression LowerNamedValue(BoundNamedValue named)
    {
        var value = named.Value;
        var local = Synthetic("once", value.Type);
        bool made = value is BoundCall or BoundNew or BoundIndirectCall or BoundClosureCall;
        var reading = new BoundLocalAccess(value.Span, local);

        _named[named.Name] = reading;
        return new BoundLet(value.Span, local, Rewrite(value), reading) { IsOwned = value.Type.NeedsArc() && !made };
    }
}
