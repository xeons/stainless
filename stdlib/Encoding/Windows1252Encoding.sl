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

module Standard.Encoding;

import Standard.Text;

/// Windows-1252: Latin-1, except that 0x80 to 0x9F carry punctuation rather
/// than C1 controls. Five of those 32 positions are unassigned and read as
/// U+FFFD.
public class Windows1252Encoding : SingleByteEncoding
{
    /// `"windows-1252"`.
    public override String Name => "windows-1252";

    /// Latin-1 outside 0x80 to 0x9F, and the punctuation table inside it.
    /// Five of those 32 positions are unassigned and read as U+FFFD.
    public override char32 ToScalar(byte value)
    {
        if (value < 0x80 || value > 0x9F)
            return (char32)(uint)value;
        return (char32)DecodeCp1252High((nuint)(value - 0x80));
    }

    /// The Latin-1 byte where there is one, else a scan of the 32-entry
    /// punctuation table, else -1. U+FFFD is -1: it marks the table's
    /// unassigned bytes and is written by none of them.
    public override int FromScalar(char32 scalar)
    {
        uint value = (uint)scalar;
        if (value < 0x80 || (value >= 0xA0 && value < 0x100))
            return (int)value;
        if (value == 0xFFFD)
            return -1;

        for (nuint i = 0; i < 32; i++)
        {
            if (DecodeCp1252High(i) == value)
                return (int)(0x80 + i);
        }
        return -1;
    }
}
