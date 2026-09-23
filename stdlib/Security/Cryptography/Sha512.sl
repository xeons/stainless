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

/// SHA-512: the 64-bit member of the family, and faster than SHA-256 on a
/// 64-bit machine for the same reason it is wider.
public sealed class Sha512 : Sha2Wide
{
    public Sha512()
    {
        base();
        InitializeState();
    }

    public override String Name => "SHA-512";

    public override nuint HashSizeInBytes => 64u;

    /// The digest of `data`, with no object to keep.
    public static byte[] HashData(byte[:] data) => new Sha512().ComputeHash(data);

    protected override void InitializeState()
    {
        _state[0u] = 0x6A09E667F3BCC908u;
        _state[1u] = 0xBB67AE8584CAA73Bu;
        _state[2u] = 0x3C6EF372FE94F82Bu;
        _state[3u] = 0xA54FF53A5F1D36F1u;
        _state[4u] = 0x510E527FADE682D1u;
        _state[5u] = 0x9B05688C2B3E6C1Fu;
        _state[6u] = 0x1F83D9ABFB41BD6Bu;
        _state[7u] = 0x5BE0CD19137E2179u;
    }
}
