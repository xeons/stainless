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

module Standard.Reflection;

// ---------------------------------------------------------------- attributes

/// One attribute as written on a declaration, with the constants it was given.
public struct Attribute
{
    /// The runtime's record for this attribute. Owned by the metadata, which
    /// lives as long as the program, so it never has to be freed.
    public byte* Handle;

    /// The attribute's name, without the brackets.
    public String Name => Text.FromNullTerminated(sl_attribute_name(Handle));

    /// How many constants were written in the brackets.
    public nuint ValueCount => sl_attribute_value_count(Handle);

    /// Which kind the value at `index` is -- one of the `Kind` constants --
    /// so a reader knows whether to call `GetText` or `GetNumber`.
    public int GetValueKind(nuint index) => (int)sl_attribute_value_kind(Handle, index);

    /// The value as text. Only meaningful when GetValueKind is KindString.
    public String GetText(nuint index)
    {
        return Text.FromNullTerminated(sl_attribute_value_text(Handle, index));
    }

    /// The value as a whole number. Meaningful for the integer kinds and for
    /// `KindBool`, where one is true; zero for anything else, including a
    /// string, rather than a reinterpretation of its pointer.
    public long GetNumber(nuint index) => sl_attribute_value_number(Handle, index);
}
