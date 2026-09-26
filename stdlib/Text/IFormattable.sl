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

module Standard.Text;

/// A value that has text to write into an interpolated string.
///
/// **Opted into, never owed.** There is no `ToString` every type has, and a
/// class that does not implement this is still refused by `$"{value}"`. One
/// that does is written by its own `ToText`, which is handed the hole's format
/// -- `{when:yyyy-MM-dd}` passes `"yyyy-MM-dd"` -- or `""` when the hole has
/// none. What a format means is the type's to decide, and nothing checks it
/// when the program compiles.
///
/// A struct implements no interface, so this is for classes; a struct's text is
/// a method it names, called in the hole.
public interface IFormattable
{
    /// This value as text, in `format`, which is `""` for the type's default.
    String ToText(String format);
}
