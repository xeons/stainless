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

module Standard.Net.Security;

/// A set of 16-bit code points, such as extension types or groups, as a
/// bitmap of 8 KiB.
///
/// A message MAY carry thousands of entries, and a list searched for each
/// would make checking them for repeats quadratic.
internal sealed class TlsCodePointSet
{
    private ulong[] _words;

    internal TlsCodePointSet()
    {
        _words = new ulong[1024u];
    }

    /// Whether `value` is in the set. A value over 0xFFFF never is.
    internal bool Contains(uint value)
    {
        if (value > 0xFFFFu)
            return false;
        return (_words[(nuint)(value >> 6)] & ((ulong)1u << (value & 63u))) != 0u;
    }

    /// Adds `value`, and answers whether it was new. A value over 0xFFFF is
    /// never added.
    internal bool Add(uint value)
    {
        if (value > 0xFFFFu || Contains(value))
            return false;
        _words[(nuint)(value >> 6)] |= (ulong)1u << (value & 63u);
        return true;
    }
}
