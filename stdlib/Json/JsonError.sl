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

// ------------------------------------------------------------------- errors

/// Why a document could not be read.
public enum JsonError
{
    /// Nothing went wrong.
    None,

    /// A character that cannot start what is expected here, or a control
    /// character inside a string that was not escaped.
    Unexpected,

    /// A string with no closing quote.
    UnterminatedText,

    /// A backslash followed by something that is not an escape.
    BadEscape,

    /// Digits that are not a JSON number.
    BadNumber,

    /// Something that started like `true`, `false` or `null` and was not.
    BadLiteral,

    /// A second value after the first. A JSON document is one value.
    TrailingContent,

    /// Nesting past `MaxDepth`.
    TooDeep,

    /// A document that is not the object a type wants. Only reflection-based
    /// reading raises this; parsing to a `JsonValue` takes any value.
    NotAnObject,

    /// A type with no field tables to map onto.
    NotReflected,
}
