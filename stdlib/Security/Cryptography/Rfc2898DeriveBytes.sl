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

// ===================================================== key derivation

/// PBKDF2, which .NET calls `Rfc2898DeriveBytes`.
///
/// Turns a password into key material by making the derivation deliberately
/// slow: `iterations` passes of HMAC, so that guessing costs the attacker what
/// it cost you. The number is the whole security argument, and it has to rise
/// over the years -- OWASP's 2023 figure is 600,000 for HMAC-SHA-256, and a
/// count from an old program is a count that has stopped meaning anything.
///
/// **This is the weakest of the modern password hashes and the only one
/// here.** PBKDF2 costs an attacker with a GPU very much less than it costs a
/// server, because it needs no memory. scrypt and Argon2 exist to close that
/// gap and neither is written; TODO.md carries them. Use PBKDF2 where a format
/// specifies it, and understand what it does not buy.
public static class Rfc2898DeriveBytes
{
    /// `length` bytes derived from `password` and `salt`.
    ///
    /// `hash` is the HMAC's inner hash -- `new Sha256()` is the usual answer.
    /// The salt should be at least sixteen random bytes and is not secret; its
    /// job is to make one attack per password rather than one per database.
    ///
    /// @param password    the secret to stretch
    /// @param salt        at least sixteen random bytes, stored beside the result
    /// @param iterations  how many HMAC passes; the whole security argument
    /// @param hash        the HMAC's inner hash, `new Sha256()` for the usual answer
    /// @param length      how many bytes to derive
    /// @failure CryptoError.Parameter  `iterations` or `length` is zero
    public static Result<byte[], CryptoError> Pbkdf2(byte[:] password, byte[:] salt,
                                                     nuint iterations, IHashAlgorithm hash,
                                                     nuint length)
    {
        if (iterations == 0u || length == 0u)
            return Fail(CryptoError.Parameter);

        var mac = new Hmac(hash, password);
        nuint macSize = mac.HashSizeInBytes;

        byte[] derived = new byte[length];
        byte[] counter = new byte[4u];
        nuint filled = 0u;
        uint index = 1u;

        while (filled < length)
        {
            counter[0u] = (byte)((index >> 24) & 0xFFu);
            counter[1u] = (byte)((index >> 16) & 0xFFu);
            counter[2u] = (byte)((index >> 8) & 0xFFu);
            counter[3u] = (byte)(index & 0xFFu);

            mac.Reset();
            mac.AppendData(salt);
            mac.AppendData(counter);
            byte[] block = mac.GetHashAndReset();

            byte[] running = new byte[macSize];
            for (nuint i = 0u; i < macSize; i++)
                running[i] = block[i];

            for (nuint round = 1u; round < iterations; round++)
            {
                block = mac.ComputeHash(block);
                for (nuint i = 0u; i < macSize; i++)
                    running[i] = (byte)(running[i] ^ block[i]);
            }

            nuint take = length - filled;
            if (take > macSize)
                take = macSize;

            for (nuint i = 0u; i < take; i++)
                derived[filled + i] = running[i];

            CryptographicOperations.ZeroMemory(running);
            filled += take;
            index++;
        }

        return Ok(derived);
    }
}
