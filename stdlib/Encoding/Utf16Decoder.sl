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

/// UTF-16, where a unit is two bytes and a high surrogate wants a second unit.
class Utf16Decoder : TailDecoder
{
    bool _bigEndian;

    public Utf16Decoder(IEncoding encoding, bool big)
    {
        base(encoding);
        _bigEndian = big;
    }

    protected override nuint CountIncompleteTail(byte[] data, nuint length)
    {
        nuint odd = length % 2u;
        nuint whole = length - odd;

        if (whole >= 2u)
        {
            nuint at = whole - 2u;
            uint unit = _bigEndian
                ? ((uint)data[at] << 8) | (uint)data[at + 1u]
                : ((uint)data[at + 1u] << 8) | (uint)data[at];

            // A high surrogate is half a character until its low one arrives.
            if (unit >= 0xD800u && unit <= 0xDBFFu)
                return odd + 2u;
        }

        return odd;
    }
}
