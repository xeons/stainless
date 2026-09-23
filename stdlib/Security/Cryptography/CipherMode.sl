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

// ============================================================ block ciphers

/// How the blocks of a message are chained together.
///
/// .NET's `CipherMode`, minus the two nobody should pick: `Ofb` and `Cts` are
/// not implemented by .NET's own AES either, and a mode that exists only to be
/// rejected is worse than a name that is not there.
public enum CipherMode
{
    /// Cipher block chaining: each block is XORed with the one before it, and
    /// the first with the IV. Needs a unique, unpredictable IV per message,
    /// and provides no authentication at all.
    Cbc,

    /// Electronic codebook: each block alone. **Equal plaintext blocks give
    /// equal ciphertext blocks**, which is why the penguin picture is famous.
    /// Right for exactly one thing -- enciphering a single block that is
    /// already a key.
    Ecb,

    /// Cipher feedback, as a full-block stream. Needs a unique IV and, like
    /// CBC, authenticates nothing.
    Cfb,

    /// Counter mode: the cipher makes a keystream, and the message is XORed
    /// with it. Not in .NET's enum, and here because it is what AES-GCM is
    /// built on and what most modern protocols specify. **Reusing a counter
    /// value with the same key destroys the message pair completely.**
    Ctr,
}
