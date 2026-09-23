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

import Standard.Limits;

/// UTF-16 text, which exists for the platforms that ask for it.
///
/// Not the string type to write a program in -- that is `String`, and this is
/// what a Windows `W` entry point or a Java-shaped protocol wants on the wire.
/// Convert at the boundary and stay in `String` everywhere else.
///
/// Positions are units, not characters and not bytes: a scalar outside the
/// basic plane is two units, so `UnitCount` is not a character count and
/// `GetUnitAt` can land on half a surrogate pair. `GetCodePointAt` joins the pair.
public class Utf16String
{

    /// Whether there are any units at all.
    public bool IsEmpty => this.UnitCount() == 0;

    /// The unit at `index`. A unit, not a character: one half of a surrogate
    /// pair is a unit and is not a character.
    public char16 GetUnitAt(nuint index)
    {
        return this.ToPointer()[index];
    }

    /// The scalar beginning at `index`, joining a surrogate pair.
    ///
    /// An unpaired surrogate gives U+FFFD, which is what transcoding it would
    /// have produced -- a lone half cannot be encoded in UTF-8 at all.
    ///
    /// @see Utf16String.SkipCodePoint
    /// @seealso String.GetCodePointAt
    public char32 GetCodePointAt(nuint index)
    {
        nuint count = this.UnitCount();
        if (index >= count)
            return (char32)0xFFFD;

        var units = this.ToPointer();
        uint first = (uint)units[index];

        if (first < 0xD800 || first > 0xDFFF)
            return (char32)first;
        if (first > 0xDBFF || index + 1 >= count)
            return (char32)0xFFFD;

        uint second = (uint)units[index + 1];
        if (second < 0xDC00 || second > 0xDFFF)
            return (char32)0xFFFD;

        return (char32)(0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00));
    }

    /// The index of the character after the one at `index`.
    ///
    /// @see Utf16String.GetCodePointAt
    public nuint SkipCodePoint(nuint index)
    {
        nuint count = this.UnitCount();
        if (index >= count)
            return count;

        var units = this.ToPointer();
        uint first = (uint)units[index];
        if (first < 0xD800 || first > 0xDBFF || index + 1 >= count)
            return index + 1;

        uint second = (uint)units[index + 1];
        if (second < 0xDC00 || second > 0xDFFF)
            return index + 1;
        return index + 2;
    }

    /// True when the two hold the same units.
    public bool Equals(Utf16String other)
    {
        nuint count = this.UnitCount();
        if (count != other.UnitCount())
            return false;

        var mine = this.ToPointer();
        var theirs = other.ToPointer();

        for (nuint i = 0; i < count; i++)
        {
            if (mine[i] != theirs[i])
                return false;
        }
        return true;
    }

    /// The units as raw bytes, little-endian, which is what a Windows API and
    /// a UTF-16LE file both expect.
    ///
    /// @see Text.FromUtf16
    public byte[] ToBytes()
    {
        nuint count = this.UnitCount();
        var bytes = new byte[count * 2];
        var units = this.ToPointer();

        for (nuint i = 0; i < count; i++)
        {
            uint unit = (uint)units[i];
            bytes[i * 2] = (byte)(unit & 0xFF);
            bytes[i * 2 + 1] = (byte)(unit >> 8);
        }
        return bytes;
    }
}
