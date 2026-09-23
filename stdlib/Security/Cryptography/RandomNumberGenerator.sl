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

// ================================================================== entropy

/// Random bytes fit to be a key, which `Standard.Random` deliberately is not.
///
/// This is the platform's generator -- `BCryptGenRandom` on Windows,
/// `getrandom` on Linux -- reached through the runtime. `Random` is xoshiro256**
/// and its whole future is computable from 256 bits of state, which is what
/// makes a seeded run reproducible and what makes it unfit for a key, a nonce
/// or a token.
public static class RandomNumberGenerator
{
    /// Fills `buffer` with random bytes, and says whether it could.
    ///
    /// The failure is a machine with no entropy source at all, which in
    /// practice means a misconfigured container. It is a `bool` rather than a
    /// `Result` because there is exactly one reason and the name says it.
    public static bool Fill(byte[] buffer)
    {
        if (buffer.Length == 0u)
            return true;
        return sl_random_bytes(&buffer[0u], buffer.Length);
    }

    /// `count` random bytes.
    ///
    /// Aborts if the platform will supply none, which is the same judgement
    /// `new Random()` makes: a key that is not random is worse than a program
    /// that stops, and there is no useful value to return instead.
    public static byte[] GetBytes(nuint count)
    {
        byte[] buffer = new byte[count];
        if (!Fill(buffer))
            sl_fail("RandomNumberGenerator: the platform supplied no entropy".ToPointer());
        return buffer;
    }

    /// A number in `[from, to)`, drawn without the modulo bias that
    /// `GetBytes(4) % range` has.
    ///
    /// Aborts on an empty or backwards range, which names a bug rather than an
    /// outcome -- the same judgement `Random.NextBelow` makes.
    public static int GetInt32(int from, int to)
    {
        if (to <= from)
            sl_fail("RandomNumberGenerator.GetInt32: the range is empty".ToPointer());

        uint span = (uint)(to - from);

        // Reject the tail that would make one residue likelier than the rest.
        // The loop is expected to run about once.
        uint limit = 0xFFFFFFFFu - (0xFFFFFFFFu % span) - 1u;
        byte[] four = new byte[4u];

        while (true)
        {
            if (!Fill(four))
                sl_fail("RandomNumberGenerator: the platform supplied no entropy".ToPointer());

            uint drawn = ((uint)four[0u] << 24) | ((uint)four[1u] << 16) |
                         ((uint)four[2u] << 8) | (uint)four[3u];

            if (drawn <= limit)
                return from + (int)(drawn % span);
        }
    }
}
