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

/// Hashes, message authentication codes, key derivation and block ciphers.
///
/// ```csharp
/// var digest = Sha256.HashData(Encoding.CreateUtf8().GetBytes("hello"));
/// Console.WriteLine(Convert.ToHexString(digest));
///
/// var cipher = try Aes.FromKey(key);
/// var sealed = try cipher.EncryptCbc(plaintext, iv, PaddingMode.Pkcs7);
/// ```
///
/// **The shape is `System.Security.Cryptography`'s**, so a program being
/// ported finds the names where it left them: `Sha256`, `Hmac`, `Aes`,
/// `AesGcm`, `Rfc2898DeriveBytes.Pbkdf2`, `RandomNumberGenerator.Fill`,
/// `CryptographicOperations.FixedTimeEquals`. Three things about it differ,
/// and each is a rule this language already has rather than a choice made
/// here:
///
/// - **The casing is the house rule's**, not .NET's. `SHA256` is `Sha256` and
///   `HMACSHA256` is `HmacSha256`, because an acronym longer than two letters
///   is `PascalCase` here (style §1.3). Nothing else about a name moves.
/// - **What can fail returns a `Result`.** .NET throws
///   `CryptographicException` for a wrong key length, a bad padding and a
///   failed authentication tag; there is no unwinding here, so each of those
///   is a `CryptoError` the caller cannot read past (§2.6). That is the
///   difference that matters most: an authentication failure *must* be
///   checked, and a `Result` is what makes it impossible not to.
/// - **`Create()` is `new`.** `SHA256.Create()` exists because .NET's is an
///   abstract class over a CryptoAPI implementation chosen at run time. There
///   is one implementation here, so `new Sha256()` is the whole of it.
///
/// **This is a software implementation and makes no constant-time claim
/// beyond the obvious.** `FixedTimeEquals` is constant time and is the one
/// comparison a caller should use on a secret. The AES here is a byte-oriented
/// reference implementation with a table-driven S-box, which is the shape that
/// is known to leak through the data cache on a machine an attacker shares. It
/// is right for a file, a protocol and a password store, and it is not the
/// thing to put under a remote attacker who can time it. AES-NI and a
/// bitsliced fallback are what would answer that, and neither is written --
/// TODO.md carries the note.
///
/// **What is not here yet is public-key.** RSA, ECDsa, ECDiffieHellman and
/// X.509 all rest on arbitrary-precision integer arithmetic, which this
/// standard library does not have; see TODO.md for the shape that would take.
/// So this module is the symmetric half, and it is complete: every hash, MAC,
/// key derivation and cipher .NET ships that does not need a bignum.
module Standard.Security.Cryptography;

import Standard.Text;
import Standard.Bits;

extern "C"
{
    void sl_fail(byte* message);
    bool sl_random_bytes(byte* buffer, nuint length);
}

// ----------------------------------------------------- reading and writing

/// Four bytes of `block` as a big-endian word, which is how every SHA
/// reads its input.
uint ReadBigWord(byte[] block, nuint at)
{
    return ((uint)block[at] << 24) | ((uint)block[at + 1u] << 16) |
           ((uint)block[at + 2u] << 8) | (uint)block[at + 3u];
}

/// Four bytes as a little-endian word, which is how MD5 reads its input.
uint ReadLittleWord(byte[] block, nuint at)
{
    return ((uint)block[at + 3u] << 24) | ((uint)block[at + 2u] << 16) |
           ((uint)block[at + 1u] << 8) | (uint)block[at];
}

/// Eight bytes as a big-endian doubleword, for SHA-384 and SHA-512.
ulong ReadBigDoubleWord(byte[] block, nuint at)
{
    ulong high = (ulong)ReadBigWord(block, at);
    ulong low = (ulong)ReadBigWord(block, at + 4u);
    return (high << 32) | low;
}

/// A word into four big-endian bytes of `into`.
void WriteBigWord(byte[] into, nuint at, uint value)
{
    into[at] = (byte)((value >> 24) & 0xFFu);
    into[at + 1u] = (byte)((value >> 16) & 0xFFu);
    into[at + 2u] = (byte)((value >> 8) & 0xFFu);
    into[at + 3u] = (byte)(value & 0xFFu);
}

/// A word into four little-endian bytes of `into`.
void WriteLittleWord(byte[] into, nuint at, uint value)
{
    into[at] = (byte)(value & 0xFFu);
    into[at + 1u] = (byte)((value >> 8) & 0xFFu);
    into[at + 2u] = (byte)((value >> 16) & 0xFFu);
    into[at + 3u] = (byte)((value >> 24) & 0xFFu);
}

/// A doubleword into eight big-endian bytes of `into`.
void WriteBigDoubleWord(byte[] into, nuint at, ulong value)
{
    WriteBigWord(into, at, (uint)((value >> 32) & 0xFFFFFFFFu));
    WriteBigWord(into, at + 4u, (uint)(value & 0xFFFFFFFFu));
}
