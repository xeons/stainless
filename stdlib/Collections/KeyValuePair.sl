// Stainless - an experimental general-purpose language.
// Copyright (C) 2026 Brandon Scott
//
// This file is part of the Stainless runtime library. It is free
// software: you can redistribute it and/or modify it under the terms of
// the GNU General Public License as published by the Free Software
// Foundation, either version 3 of the License, or (at your option) any
// later version.
//
// It is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
// for more details.
//
// As an additional permission under section 7 of that License, compiling
// a program with Stainless does not by itself place that program under
// the GNU General Public License. See LICENSE.RUNTIME.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

module Standard.Collections;

// ------------------------------------------------------------------- pairs

/// One key and one value. What a dictionary yields when it is iterated.
///
/// @typeparam TKey    the key half's type; nothing is asked of it, since a pair
///                    is looked at rather than looked in
/// @typeparam TValue  the value half's type; nothing is asked of it
public class KeyValuePair<TKey, TValue>
{
    /// The key half.
    public TKey Key { get; }

    /// The value half.
    public TValue Value { get; }

    /// Builds a pair. Iteration is what normally makes these -- one per entry
    /// visited, so a `foreach` over a large dictionary allocates one per step.
    public KeyValuePair(TKey key, TValue value)
    {
        Key = key;
        Value = value;
    }
}
