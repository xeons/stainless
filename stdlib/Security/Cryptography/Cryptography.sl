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

/// Hashes, message authentication codes, key derivation, block and stream
/// ciphers, key agreement and signatures.
///
/// ```csharp
/// var digest = Sha256.HashData(Encoding.CreateUtf8().GetBytes("hello"));
/// Console.WriteLine(Convert.ToHexString(digest));
///
/// var cipher = try Aes.FromKey(key);
/// var sealed = try cipher.EncryptCbc(plaintext, iv, PaddingMode.Pkcs7);
///
/// var shared = try X25519.DeriveSharedSecret(myPrivateKey, theirPublicKey);
/// var signature = try Ed25519.Sign(signingKey, message);
/// ```
///
/// **The shape is `System.Security.Cryptography`'s**, so a program being
/// ported finds the names where it left them: `Sha256`, `Hmac`, `Aes`,
/// `AesGcm`, `ChaCha20Poly1305`, `Rfc2898DeriveBytes.Pbkdf2`,
/// `RandomNumberGenerator.Fill`, `CryptographicOperations.FixedTimeEquals`.
/// `Blake2b`, `Scrypt` and `Argon2id` are not in .NET and follow the same
/// shape. Three things about it differ, and each is a rule this language
/// already has rather than a choice made here:
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
/// **The ciphers and MACs are constant time in software.** AES is bitsliced
/// and its S-box is a logic circuit, GHASH multiplies with integer multiplies
/// rather than a table, and ChaCha20, Poly1305, the SHA-2 family and BLAKE2b
/// are arithmetic on words. None indexes memory by a key or by data, and none
/// branches on either, so the time and the cache lines touched depend only on
/// lengths. `FixedTimeEquals` is the comparison to use on anything secret.
///
/// Three things that claim does not cover. **It is timing and cache only**:
/// nothing here resists power analysis, electromagnetic emanation or fault
/// injection, which want masking and hardware this library does not have.
/// **It rests on the multiply**: GHASH and Poly1305 assume a multiply whose
/// time does not depend on its operands, which is true of every x64 and ARMv8
/// core and not of some older and embedded ones. **The memory-hard password
/// hashes index memory by the password**, which is what makes them memory
/// hard: all of scrypt's second half, and Argon2id's after its first half.
///
/// Nothing uses AES-NI, which the language cannot spell, so AES runs at a
/// small fraction of what the hardware could give. `ChaCha20Poly1305` is
/// about three times as fast as `AesGcm` here, and is the one to choose
/// where a format leaves the choice open.
///
/// **Public-key is constant time wherever a secret is involved.** `X25519`
/// whole, and `Ed25519` signing and key generation, whose scalar
/// multiplication reads its table by mask; every secret-dependent choice there
/// is a mask passed through `OpaqueCopy`, so the optimiser cannot turn it back
/// into a branch. `Ed25519.Verify` is variable time and touches nothing
/// secret.
///
/// **Public-key is Curve25519 and nothing else.** `X25519` agrees keys and
/// `Ed25519` signs, over the one curve whose arithmetic needs no general
/// bignum. RSA, ECDsa over the NIST curves, and X.509 all rest on
/// arbitrary-precision integer arithmetic, which this standard library does
/// not have; see TODO.md for the shape that would take.
module Standard.Security.Cryptography;

import Standard.Text;
import Standard.Bits;

extern "C"
{
    void sl_fail(byte* message);
    bool sl_random_bytes(byte* buffer, nuint length);
    void sl_zero_memory(byte* buffer, nuint length);
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

/// Eight bytes as a little-endian doubleword, for BLAKE2b and Argon2.
ulong ReadLittleDoubleWord(byte[] block, nuint at)
{
    ulong low = (ulong)ReadLittleWord(block, at);
    ulong high = (ulong)ReadLittleWord(block, at + 4u);
    return (high << 32) | low;
}

/// Eight bytes as a little-endian doubleword, which is how Curve25519 reads
/// a field element.
ulong ReadLittleDoubleWord(ReadOnlySpan<byte> block, nuint at)
{
    ulong value = 0u;
    for (nuint i = 8u; i > 0u; i--)
        value = (value << 8) | (ulong)block[at + i - 1u];
    return value;
}

/// A doubleword into eight little-endian bytes of `into`.
void WriteLittleDoubleWord(byte[] into, nuint at, ulong value)
{
    WriteLittleWord(into, at, (uint)(value & 0xFFFFFFFFu));
    WriteLittleWord(into, at + 4u, (uint)((value >> 32) & 0xFFFFFFFFu));
}
