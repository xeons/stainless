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

/// SHA-384: SHA-512 from a different start, with half the answer thrown away.
///
/// The truncation is what makes it worth having rather than a curiosity --
/// a SHA-512 digest reveals the whole final state, and a SHA-384 one does
/// not, so length-extension does not apply to it.
public sealed class Sha384 : Sha2Wide
{
    public Sha384()
    {
        base();
        InitializeState();
    }

    public override String Name => "SHA-384";

    public override nuint HashSizeInBytes => 48u;

    /// The digest of `data`, with no object to keep.
    public static byte[] HashData(byte[:] data) => new Sha384().ComputeHash(data);

    protected override void InitializeState()
    {
        _state[0u] = 0xCBBB9D5DC1059ED8u;
        _state[1u] = 0x629A292A367CD507u;
        _state[2u] = 0x9159015A3070DD17u;
        _state[3u] = 0x152FECD8F70E5939u;
        _state[4u] = 0x67332667FFC00B31u;
        _state[5u] = 0x8EB44A8768581511u;
        _state[6u] = 0xDB0C2E0D64F98FA7u;
        _state[7u] = 0x47B5481DBEFA4FA4u;
    }
}
