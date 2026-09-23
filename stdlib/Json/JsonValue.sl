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

module Standard.Json;

import Standard.Collections;
import Standard.Reflection;
import Standard.Convert;
import Standard.Math;

// ------------------------------------------------------------------- values

/// A JSON document, or any part of one.
///
/// Exactly the six things the grammar has. A variant rather than a class with
/// a kind field, so reading the wrong one is a compile error rather than a
/// null: `case Text t:` is the only way to reach `t.Value`.
public variant JsonValue
{
    /// The literal `null`. Also what `JsonObject.GetValueOrNull` answers for a name the
    /// document does not mention, since a reader with a default cannot tell
    /// the two apart and neither should have to.
    Null;

    /// `true` or `false`.
    Bool(bool Value);

    /// A number. JSON has only the one numeric type and it is a double, so an
    /// integer past 2^53 has already lost precision by the time it is here.
    /// A parsed one is always finite; `ToJsonText` says what becomes of one that
    /// is not.
    Number(double Value);

    /// A string, decoded: the escapes are gone and the text is what they meant.
    Text(String Value);

    /// An array, in document order.
    Array(List<JsonValue> Items);

    /// An object, in the order its members were written.
    Object(JsonObject Members);
}
