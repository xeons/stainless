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

module Standard.Net.Http;

import Standard.Text;

/// `value` in lower-case hexadecimal, with no leading zeros.
internal String FormatHttpHexadecimal(ulong value)
{
    if (value == 0u)
        return "0";
    var digits = new StringBuilder();
    int shift = 60;
    bool started = false;
    while (shift >= 0)
    {
        int digit = (int)((value >> shift) & 0xFu);
        if (digit != 0 || started)
        {
            started = true;
            digits.Append("0123456789abcdef".Substring((nuint)digit, 1u));
        }
        shift -= 4;
    }
    return digits.ToText();
}
