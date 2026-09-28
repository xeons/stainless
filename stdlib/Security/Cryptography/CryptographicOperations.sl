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

module Standard.Security.Cryptography;

import Standard.Text;
import Standard.Bits;

// ================================================================ discipline

/// The two operations on a secret that are easy to write wrongly.
public static class CryptographicOperations
{
    /// Whether two byte strings are equal, in time that does not depend on
    /// where they first differ.
    ///
    /// **Use this for every comparison of a MAC, a tag, a token or a password
    /// hash.** An ordinary loop returns as soon as it finds a difference, and
    /// an attacker who can time it recovers the expected value one byte at a
    /// time -- a few thousand requests for a MAC that would take for ever to
    /// guess.
    ///
    /// Unequal lengths answer false immediately, which leaks the length and
    /// nothing else; .NET does the same, and a length is not the secret.
    public static bool FixedTimeEquals(ReadOnlySpan<byte> left, ReadOnlySpan<byte> right)
    {
        if (left.Length != right.Length)
            return false;

        // Opaque, so the optimiser cannot learn that the answer is settled at
        // the first difference and stop there.
        uint difference = 0u;
        for (nuint i = 0u; i < left.Length; i++)
            difference = OpaqueCopy(difference | ((uint)left[i] ^ (uint)right[i]));

        return difference == 0u;
    }

    /// Overwrites `buffer` with zeros, in a way the optimiser may not remove
    /// however little is read afterwards.
    ///
    /// A key that is overwritten is not in the next core dump. It may still be
    /// in a register, a copy made along the way, or memory the allocator has
    /// moved; this clears the one buffer it is given and nothing else.
    public static void ZeroMemory(byte[] buffer)
    {
        if (buffer.Length > 0u)
            sl_zero_memory(&buffer[0u], buffer.Length);
    }
}
