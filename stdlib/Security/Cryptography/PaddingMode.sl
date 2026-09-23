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

/// What is added to make the plaintext a whole number of blocks.
public enum PaddingMode
{
    /// Nothing. The input must already be a multiple of the block size, and
    /// `CryptoError.BlockLength` says so when it is not.
    None,

    /// PKCS#7: N bytes of the value N, always at least one block-worth of
    /// information added. The default everywhere, and what .NET uses unless
    /// told otherwise.
    Pkcs7,

    /// Zeros to the block boundary. **Not removable**: a plaintext that ended
    /// in a zero byte is indistinguishable from its padding, so decryption
    /// leaves it in place.
    Zeros,

    /// ANSI X9.23: zeros, and the last byte is the count.
    AnsiX923,
}
