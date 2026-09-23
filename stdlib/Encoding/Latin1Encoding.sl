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

/// ISO-8859-1, where byte n is code point n for every n. Nothing can fail in
/// either direction below U+0100, and nothing above it can be written.
public class Latin1Encoding : SingleByteEncoding
{
    /// `"iso-8859-1"`.
    public override String Name => "iso-8859-1";

    /// Byte n is code point n, for every n. Never U+FFFD, which is what makes
    /// this encoding able to carry any byte sequence at all.
    public override char32 ToScalar(byte value) => (char32)(uint)value;

    /// The scalar itself below U+0100, and -1 at or above it.
    public override int FromScalar(char32 scalar)
    {
        uint value = (uint)scalar;
        return value < 256 ? (int)value : -1;
    }
}
