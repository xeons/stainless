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

/// US-ASCII. A byte above 127 is not ASCII, and reads as U+FFFD.
public class AsciiEncoding : SingleByteEncoding
{
    /// `"us-ascii"`.
    public override String Name => "us-ascii";

    /// The byte itself below 128, and U+FFFD at or above it.
    public override char32 ToScalar(byte value)
    {
        return value < 128 ? (char32)(uint)value : (char32)0xFFFD;
    }

    /// The scalar itself below U+0080, and -1 at or above it.
    public override int FromScalar(char32 scalar)
    {
        uint value = (uint)scalar;
        return value < 128 ? (int)value : -1;
    }
}
