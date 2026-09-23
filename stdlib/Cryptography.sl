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
/// Console.WriteLine(Convert.ToHex(digest));
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

// ============================================================ what can fail

/// Why an operation did not happen.
///
/// One enum for the module, as `IOError` is for `Standard.IO`: a caller
/// switching on the failure of a decrypt wants the same vocabulary as one
/// checking a key length.
public enum CryptoError
{
    /// The key is not a length this algorithm takes. AES takes 16, 24 or 32
    /// bytes; an HMAC key may be any length at all, so this never comes from
    /// one.
    KeyLength,

    /// The initialization vector is not one block long.
    IvLength,

    /// The nonce is not a length this mode takes. AES-GCM takes any non-empty
    /// nonce and wants twelve bytes.
    NonceLength,

    /// The authentication tag is not a length this mode produces.
    TagLength,

    /// The input is not a whole number of blocks, and the padding mode in
    /// force does not add any.
    BlockLength,

    /// The padding on a decrypted block does not describe itself. Usually the
    /// wrong key, and deliberately says no more than that.
    Padding,

    /// The tag did not match. **The plaintext is not returned**, because a
    /// plaintext that failed authentication is attacker-controlled and
    /// handling it at all is the mistake AEAD exists to prevent.
    AuthenticationFailed,

    /// An iteration count of zero, or an output length of zero, where neither
    /// is meaningful.
    Parameter,

    /// The platform would not supply entropy.
    NoEntropy,
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

// ================================================================== hashing

/// A hash function, one block at a time.
///
/// This is .NET's `IncrementalHash` rather than its `HashAlgorithm`: append
/// what there is, and ask for the digest when there is no more. `ComputeHash`
/// on the base class is the one-shot for the common case, and the static
/// `HashData` on each algorithm is the same thing without an object.
///
/// Implement it to add an algorithm; `Hmac` takes any implementation, so a
/// hash written outside this module gets a MAC for free.
///
/// @see Hmac
public interface IHashAlgorithm
{
    /// What the algorithm is called, as a standard names it -- `SHA-256`,
    /// `HMAC-SHA-256`. This is the spelling that goes in a protocol field,
    /// so it keeps the hyphens and the capitals.
    String Name { get; }

    /// How many bytes the digest is.
    nuint HashSizeInBytes { get; }

    /// How many bytes the compression function eats at a time. HMAC needs it,
    /// which is why it is on the interface rather than inside.
    nuint BlockSizeInBytes { get; }

    /// Adds bytes to what is being hashed.
    void AppendData(byte[:] data);

    /// The digest of everything appended since the last reset, and a reset.
    /// Calling it twice in a row gives the digest of the empty input the
    /// second time, which is what the reset means.
    byte[] GetHashAndReset();

    /// Throws away what has been appended and starts again.
    void Reset();
}

/// The buffering and the padding, which every Merkle-Damgard hash shares.
///
/// MD5, SHA-1, SHA-256, SHA-384 and SHA-512 differ in three things -- the
/// compression function, the state, and whether the length that terminates the
/// message is written big-endian -- and agree about everything else: fill a
/// block, compress it, and finish by appending a one bit, zeros, and the
/// length in bits. That is what is here, so a new algorithm of this family is
/// `CompressBlock`, `ComputeDigest` and `InitializeState` and nothing else.
public abstract class HashAlgorithm : IHashAlgorithm
{
    /// The block being filled. `BlockSizeInBytes` long, and never full on
    /// return from `AppendData` -- a block that fills is compressed at once, which
    /// is what lets `FinishHash` assume there is room for the one bit.
    protected byte[] _block;

    /// How much of `_block` is filled.
    protected nuint _used;

    /// How many bytes have been appended in total, which becomes the length
    /// field.
    protected ulong _byteCount;

    nuint _lengthBytes;
    bool _bigEndianLength;

    /// `lengthBytes` is the width of the length field: eight for the 32-bit
    /// family, sixteen for SHA-512, whose upper eight bytes are always zero
    /// here because no input reaches 2^64 bytes.
    protected HashAlgorithm(nuint blockSize, nuint lengthBytes, bool bigEndianLength)
    {
        _block = new byte[blockSize];
        _used = 0u;
        _byteCount = 0u;
        _lengthBytes = lengthBytes;
        _bigEndianLength = bigEndianLength;
    }

    public abstract String Name { get; }

    public abstract nuint HashSizeInBytes { get; }

    public nuint BlockSizeInBytes => _block.Length;

    public void AppendData(byte[:] data)
    {
        nuint at = 0u;
        while (at < data.Length)
        {
            nuint room = _block.Length - _used;
            nuint take = data.Length - at;
            if (take > room)
                take = room;

            for (nuint i = 0u; i < take; i++)
                _block[_used + i] = data[at + i];

            _used += take;
            at += take;
            _byteCount += (ulong)take;

            if (_used == _block.Length)
            {
                CompressBlock(_block);
                _used = 0u;
            }
        }
    }

    public byte[] GetHashAndReset()
    {
        byte[] digest = FinishHash();
        Reset();
        return digest;
    }

    public void Reset()
    {
        for (nuint i = 0u; i < _block.Length; i++)
            _block[i] = 0;

        _used = 0u;
        _byteCount = 0u;
        InitializeState();
    }

    /// The digest of `data` on its own. Resets first, so an object that has
    /// been appended to is still safe to ask.
    public byte[] ComputeHash(byte[:] data)
    {
        Reset();
        AppendData(data);
        return GetHashAndReset();
    }

    /// One block into the state.
    protected abstract void CompressBlock(byte[] block);

    /// The state as bytes, once the last block has been compressed.
    protected abstract byte[] ComputeDigest();

    /// The state as a fresh hash has it.
    protected abstract void InitializeState();

    /// The one bit, the zeros and the length, then the digest.
    byte[] FinishHash()
    {
        ulong bits = _byteCount * 8u;

        _block[_used] = 0x80;
        _used++;

        // The length has to fit in this block. If it does not, fill this one
        // with zeros, compress it, and put the length in the next.
        if (_used > _block.Length - _lengthBytes)
        {
            while (_used < _block.Length)
            {
                _block[_used] = 0;
                _used++;
            }

            CompressBlock(_block);
            _used = 0u;
        }

        while (_used < _block.Length - _lengthBytes)
        {
            _block[_used] = 0;
            _used++;
        }

        nuint field = _block.Length - _lengthBytes;
        for (nuint i = 0u; i < _lengthBytes; i++)
            _block[field + i] = 0;

        // Eight bytes of it either way; a sixteen-byte field's top half stays
        // zero, since `_byteCount` is a ulong and cannot fill it.
        for (nuint i = 0u; i < 8u; i++)
        {
            byte octet = (byte)((bits >> (uint)(8u * i)) & 0xFFu);
            if (_bigEndianLength)
                _block[_block.Length - 1u - i] = octet;
            else
                _block[field + i] = octet;
        }

        CompressBlock(_block);
        return ComputeDigest();
    }
}

// -------------------------------------------------------------------- MD5

/// MD5, which is **broken** and is here because formats still carry it.
///
/// Collisions are cheap and have been since 2004: two inputs with the same
/// digest can be produced on a laptop in seconds. That makes it unusable for a
/// signature, a certificate or anything else where an adversary chooses the
/// input. It remains what an old protocol field, a package manifest and a
/// legacy database column contain, and refusing to implement it does not make
/// those go away.
///
/// Use `Sha256` for anything new.
///
/// @see Sha256
public sealed class Md5 : HashAlgorithm
{
    uint _a;
    uint _b;
    uint _c;
    uint _d;
    uint[] _sines;
    uint[] _shifts;

    public Md5()
    {
        base(64u, 8u, false);

        // floor(abs(sin(i + 1)) * 2^32), written out rather than computed:
        // the table is the specification, and a rounding that differed by one
        // in the last place would be a hash that is silently not MD5.
        _sines = [
            0xD76AA478u, 0xE8C7B756u, 0x242070DBu, 0xC1BDCEEEu,
            0xF57C0FAFu, 0x4787C62Au, 0xA8304613u, 0xFD469501u,
            0x698098D8u, 0x8B44F7AFu, 0xFFFF5BB1u, 0x895CD7BEu,
            0x6B901122u, 0xFD987193u, 0xA679438Eu, 0x49B40821u,
            0xF61E2562u, 0xC040B340u, 0x265E5A51u, 0xE9B6C7AAu,
            0xD62F105Du, 0x02441453u, 0xD8A1E681u, 0xE7D3FBC8u,
            0x21E1CDE6u, 0xC33707D6u, 0xF4D50D87u, 0x455A14EDu,
            0xA9E3E905u, 0xFCEFA3F8u, 0x676F02D9u, 0x8D2A4C8Au,
            0xFFFA3942u, 0x8771F681u, 0x6D9D6122u, 0xFDE5380Cu,
            0xA4BEEA44u, 0x4BDECFA9u, 0xF6BB4B60u, 0xBEBFBC70u,
            0x289B7EC6u, 0xEAA127FAu, 0xD4EF3085u, 0x04881D05u,
            0xD9D4D039u, 0xE6DB99E5u, 0x1FA27CF8u, 0xC4AC5665u,
            0xF4292244u, 0x432AFF97u, 0xAB9423A7u, 0xFC93A039u,
            0x655B59C3u, 0x8F0CCC92u, 0xFFEFF47Du, 0x85845DD1u,
            0x6FA87E4Fu, 0xFE2CE6E0u, 0xA3014314u, 0x4E0811A1u,
            0xF7537E82u, 0xBD3AF235u, 0x2AD7D2BBu, 0xEB86D391u,
        ];

        _shifts = [
            7u, 12u, 17u, 22u, 7u, 12u, 17u, 22u,
            7u, 12u, 17u, 22u, 7u, 12u, 17u, 22u,
            5u, 9u, 14u, 20u, 5u, 9u, 14u, 20u,
            5u, 9u, 14u, 20u, 5u, 9u, 14u, 20u,
            4u, 11u, 16u, 23u, 4u, 11u, 16u, 23u,
            4u, 11u, 16u, 23u, 4u, 11u, 16u, 23u,
            6u, 10u, 15u, 21u, 6u, 10u, 15u, 21u,
            6u, 10u, 15u, 21u, 6u, 10u, 15u, 21u,
        ];

        InitializeState();
    }

    public override String Name => "MD5";

    public override nuint HashSizeInBytes => 16u;

    /// The digest of `data`, with no object to keep.
    public static byte[] HashData(byte[:] data) => new Md5().ComputeHash(data);

    protected override void InitializeState()
    {
        _a = 0x67452301u;
        _b = 0xEFCDAB89u;
        _c = 0x98BADCFEu;
        _d = 0x10325476u;
    }

    protected override void CompressBlock(byte[] block)
    {
        uint[] words = new uint[16u];
        for (nuint i = 0u; i < 16u; i++)
            words[i] = ReadLittleWord(block, i * 4u);

        uint a = _a;
        uint b = _b;
        uint c = _c;
        uint d = _d;

        for (nuint step = 0u; step < 64u; step++)
        {
            uint mixed = 0u;
            nuint word = 0u;

            if (step < 16u)
            {
                mixed = (b & c) | (~b & d);
                word = step;
            }
            else if (step < 32u)
            {
                mixed = (d & b) | (~d & c);
                word = (5u * step + 1u) % 16u;
            }
            else if (step < 48u)
            {
                mixed = b ^ c ^ d;
                word = (3u * step + 5u) % 16u;
            }
            else
            {
                mixed = c ^ (b | ~d);
                word = (7u * step) % 16u;
            }

            uint rotated = a + mixed + _sines[step] + words[word];
            a = d;
            d = c;
            c = b;
            b = b + RotateLeft(rotated, (int)_shifts[step]);
        }

        _a += a;
        _b += b;
        _c += c;
        _d += d;
    }

    protected override byte[] ComputeDigest()
    {
        byte[] digest = new byte[16u];
        WriteLittleWord(digest, 0u, _a);
        WriteLittleWord(digest, 4u, _b);
        WriteLittleWord(digest, 8u, _c);
        WriteLittleWord(digest, 12u, _d);
        return digest;
    }
}

// ------------------------------------------------------------------ SHA-1

/// SHA-1, which is **broken for collisions** and still required by some
/// protocols.
///
/// SHAttered produced two PDFs with the same digest in 2017 and the cost has
/// only fallen since. It is not safe for a signature or a certificate. It is
/// still what Git names an object with, what HMAC-SHA-1 inside TOTP and
/// PBKDF2 uses -- where the collision resistance is not what is relied on --
/// and what a dozen older protocols specify.
public sealed class Sha1 : HashAlgorithm
{
    uint[] _state;

    public Sha1()
    {
        base(64u, 8u, true);
        _state = new uint[5u];
        InitializeState();
    }

    public override String Name => "SHA-1";

    public override nuint HashSizeInBytes => 20u;

    /// The digest of `data`, with no object to keep.
    public static byte[] HashData(byte[:] data) => new Sha1().ComputeHash(data);

    protected override void InitializeState()
    {
        _state[0u] = 0x67452301u;
        _state[1u] = 0xEFCDAB89u;
        _state[2u] = 0x98BADCFEu;
        _state[3u] = 0x10325476u;
        _state[4u] = 0xC3D2E1F0u;
    }

    protected override void CompressBlock(byte[] block)
    {
        uint[] schedule = new uint[80u];
        for (nuint i = 0u; i < 16u; i++)
            schedule[i] = ReadBigWord(block, i * 4u);

        for (nuint i = 16u; i < 80u; i++)
        {
            uint mixed = schedule[i - 3u] ^ schedule[i - 8u] ^
                         schedule[i - 14u] ^ schedule[i - 16u];
            schedule[i] = RotateLeft(mixed, 1);
        }

        uint a = _state[0u];
        uint b = _state[1u];
        uint c = _state[2u];
        uint d = _state[3u];
        uint e = _state[4u];

        for (nuint i = 0u; i < 80u; i++)
        {
            uint mixed = 0u;
            uint constant = 0u;

            if (i < 20u)
            {
                mixed = (b & c) | (~b & d);
                constant = 0x5A827999u;
            }
            else if (i < 40u)
            {
                mixed = b ^ c ^ d;
                constant = 0x6ED9EBA1u;
            }
            else if (i < 60u)
            {
                mixed = (b & c) | (b & d) | (c & d);
                constant = 0x8F1BBCDCu;
            }
            else
            {
                mixed = b ^ c ^ d;
                constant = 0xCA62C1D6u;
            }

            uint next = RotateLeft(a, 5) + mixed + e + constant + schedule[i];
            e = d;
            d = c;
            c = RotateLeft(b, 30);
            b = a;
            a = next;
        }

        _state[0u] += a;
        _state[1u] += b;
        _state[2u] += c;
        _state[3u] += d;
        _state[4u] += e;
    }

    protected override byte[] ComputeDigest()
    {
        byte[] digest = new byte[20u];
        for (nuint i = 0u; i < 5u; i++)
            WriteBigWord(digest, i * 4u, _state[i]);
        return digest;
    }
}

// ---------------------------------------------------------------- SHA-256

/// SHA-256: the one to reach for when nothing else decides.
public sealed class Sha256 : HashAlgorithm
{
    uint[] _state;
    uint[] _constants;

    public Sha256()
    {
        base(64u, 8u, true);

        _state = new uint[8u];
        _constants = [
            0x428A2F98u, 0x71374491u, 0xB5C0FBCFu, 0xE9B5DBA5u,
            0x3956C25Bu, 0x59F111F1u, 0x923F82A4u, 0xAB1C5ED5u,
            0xD807AA98u, 0x12835B01u, 0x243185BEu, 0x550C7DC3u,
            0x72BE5D74u, 0x80DEB1FEu, 0x9BDC06A7u, 0xC19BF174u,
            0xE49B69C1u, 0xEFBE4786u, 0x0FC19DC6u, 0x240CA1CCu,
            0x2DE92C6Fu, 0x4A7484AAu, 0x5CB0A9DCu, 0x76F988DAu,
            0x983E5152u, 0xA831C66Du, 0xB00327C8u, 0xBF597FC7u,
            0xC6E00BF3u, 0xD5A79147u, 0x06CA6351u, 0x14292967u,
            0x27B70A85u, 0x2E1B2138u, 0x4D2C6DFCu, 0x53380D13u,
            0x650A7354u, 0x766A0ABBu, 0x81C2C92Eu, 0x92722C85u,
            0xA2BFE8A1u, 0xA81A664Bu, 0xC24B8B70u, 0xC76C51A3u,
            0xD192E819u, 0xD6990624u, 0xF40E3585u, 0x106AA070u,
            0x19A4C116u, 0x1E376C08u, 0x2748774Cu, 0x34B0BCB5u,
            0x391C0CB3u, 0x4ED8AA4Au, 0x5B9CCA4Fu, 0x682E6FF3u,
            0x748F82EEu, 0x78A5636Fu, 0x84C87814u, 0x8CC70208u,
            0x90BEFFFAu, 0xA4506CEBu, 0xBEF9A3F7u, 0xC67178F2u,
        ];

        InitializeState();
    }

    public override String Name => "SHA-256";

    public override nuint HashSizeInBytes => 32u;

    /// The digest of `data`, with no object to keep.
    public static byte[] HashData(byte[:] data) => new Sha256().ComputeHash(data);

    protected override void InitializeState()
    {
        _state[0u] = 0x6A09E667u;
        _state[1u] = 0xBB67AE85u;
        _state[2u] = 0x3C6EF372u;
        _state[3u] = 0xA54FF53Au;
        _state[4u] = 0x510E527Fu;
        _state[5u] = 0x9B05688Cu;
        _state[6u] = 0x1F83D9ABu;
        _state[7u] = 0x5BE0CD19u;
    }

    protected override void CompressBlock(byte[] block)
    {
        uint[] schedule = new uint[64u];
        for (nuint i = 0u; i < 16u; i++)
            schedule[i] = ReadBigWord(block, i * 4u);

        for (nuint i = 16u; i < 64u; i++)
        {
            uint previous = schedule[i - 15u];
            uint recent = schedule[i - 2u];
            uint small = RotateLeft(previous, 25) ^ RotateLeft(previous, 14) ^ (previous >> 3);
            uint large = RotateLeft(recent, 15) ^ RotateLeft(recent, 13) ^ (recent >> 10);
            schedule[i] = schedule[i - 16u] + small + schedule[i - 7u] + large;
        }

        uint a = _state[0u];
        uint b = _state[1u];
        uint c = _state[2u];
        uint d = _state[3u];
        uint e = _state[4u];
        uint f = _state[5u];
        uint g = _state[6u];
        uint h = _state[7u];

        for (nuint i = 0u; i < 64u; i++)
        {
            uint sum1 = RotateLeft(e, 26) ^ RotateLeft(e, 21) ^ RotateLeft(e, 7);
            uint choose = (e & f) ^ (~e & g);
            uint first = h + sum1 + choose + _constants[i] + schedule[i];
            uint sum0 = RotateLeft(a, 30) ^ RotateLeft(a, 19) ^ RotateLeft(a, 10);
            uint majority = (a & b) ^ (a & c) ^ (b & c);
            uint second = sum0 + majority;

            h = g;
            g = f;
            f = e;
            e = d + first;
            d = c;
            c = b;
            b = a;
            a = first + second;
        }

        _state[0u] += a;
        _state[1u] += b;
        _state[2u] += c;
        _state[3u] += d;
        _state[4u] += e;
        _state[5u] += f;
        _state[6u] += g;
        _state[7u] += h;
    }

    protected override byte[] ComputeDigest()
    {
        byte[] digest = new byte[32u];
        for (nuint i = 0u; i < 8u; i++)
            WriteBigWord(digest, i * 4u, _state[i]);
        return digest;
    }
}

// ------------------------------------------------------ SHA-384 and SHA-512

/// The 64-bit half of SHA-2, which SHA-384 and SHA-512 share entirely except
/// for where they start and how much of the answer they keep.
///
/// Public because a public class cannot usefully hide its base, and documented
/// as machinery: there is nothing here to construct. `Sha384` and `Sha512` are
/// the two that exist.
public abstract class Sha2Wide : HashAlgorithm
{
    /// Eight doublewords, which both algorithms carry and only the initial
    /// value of distinguishes.
    protected ulong[] _state;

    ulong[] _constants;

    protected Sha2Wide()
    {
        base(128u, 16u, true);

        _state = new ulong[8u];
        _constants = [
            0x428A2F98D728AE22u, 0x7137449123EF65CDu, 0xB5C0FBCFEC4D3B2Fu, 0xE9B5DBA58189DBBCu,
            0x3956C25BF348B538u, 0x59F111F1B605D019u, 0x923F82A4AF194F9Bu, 0xAB1C5ED5DA6D8118u,
            0xD807AA98A3030242u, 0x12835B0145706FBEu, 0x243185BE4EE4B28Cu, 0x550C7DC3D5FFB4E2u,
            0x72BE5D74F27B896Fu, 0x80DEB1FE3B1696B1u, 0x9BDC06A725C71235u, 0xC19BF174CF692694u,
            0xE49B69C19EF14AD2u, 0xEFBE4786384F25E3u, 0x0FC19DC68B8CD5B5u, 0x240CA1CC77AC9C65u,
            0x2DE92C6F592B0275u, 0x4A7484AA6EA6E483u, 0x5CB0A9DCBD41FBD4u, 0x76F988DA831153B5u,
            0x983E5152EE66DFABu, 0xA831C66D2DB43210u, 0xB00327C898FB213Fu, 0xBF597FC7BEEF0EE4u,
            0xC6E00BF33DA88FC2u, 0xD5A79147930AA725u, 0x06CA6351E003826Fu, 0x142929670A0E6E70u,
            0x27B70A8546D22FFCu, 0x2E1B21385C26C926u, 0x4D2C6DFC5AC42AEDu, 0x53380D139D95B3DFu,
            0x650A73548BAF63DEu, 0x766A0ABB3C77B2A8u, 0x81C2C92E47EDAEE6u, 0x92722C851482353Bu,
            0xA2BFE8A14CF10364u, 0xA81A664BBC423001u, 0xC24B8B70D0F89791u, 0xC76C51A30654BE30u,
            0xD192E819D6EF5218u, 0xD69906245565A910u, 0xF40E35855771202Au, 0x106AA07032BBD1B8u,
            0x19A4C116B8D2D0C8u, 0x1E376C085141AB53u, 0x2748774CDF8EEB99u, 0x34B0BCB5E19B48A8u,
            0x391C0CB3C5C95A63u, 0x4ED8AA4AE3418ACBu, 0x5B9CCA4F7763E373u, 0x682E6FF3D6B2B8A3u,
            0x748F82EE5DEFB2FCu, 0x78A5636F43172F60u, 0x84C87814A1F0AB72u, 0x8CC702081A6439ECu,
            0x90BEFFFA23631E28u, 0xA4506CEBDE82BDE9u, 0xBEF9A3F7B2C67915u, 0xC67178F2E372532Bu,
            0xCA273ECEEA26619Cu, 0xD186B8C721C0C207u, 0xEADA7DD6CDE0EB1Eu, 0xF57D4F7FEE6ED178u,
            0x06F067AA72176FBAu, 0x0A637DC5A2C898A6u, 0x113F9804BEF90DAEu, 0x1B710B35131C471Bu,
            0x28DB77F523047D84u, 0x32CAAB7B40C72493u, 0x3C9EBE0A15C9BEBCu, 0x431D67C49C100D4Cu,
            0x4CC5D4BECB3E42B6u, 0x597F299CFC657E2Au, 0x5FCB6FAB3AD6FAECu, 0x6C44198C4A475817u,
        ];
    }

    protected override void CompressBlock(byte[] block)
    {
        ulong[] schedule = new ulong[80u];
        for (nuint i = 0u; i < 16u; i++)
            schedule[i] = ReadBigDoubleWord(block, i * 8u);

        for (nuint i = 16u; i < 80u; i++)
        {
            ulong previous = schedule[i - 15u];
            ulong recent = schedule[i - 2u];
            ulong small = RotateRight(previous, 1) ^ RotateRight(previous, 8) ^ (previous >> 7);
            ulong large = RotateRight(recent, 19) ^ RotateRight(recent, 61) ^ (recent >> 6);
            schedule[i] = schedule[i - 16u] + small + schedule[i - 7u] + large;
        }

        ulong a = _state[0u];
        ulong b = _state[1u];
        ulong c = _state[2u];
        ulong d = _state[3u];
        ulong e = _state[4u];
        ulong f = _state[5u];
        ulong g = _state[6u];
        ulong h = _state[7u];

        for (nuint i = 0u; i < 80u; i++)
        {
            ulong sum1 = RotateRight(e, 14) ^ RotateRight(e, 18) ^ RotateRight(e, 41);
            ulong choose = (e & f) ^ (~e & g);
            ulong first = h + sum1 + choose + _constants[i] + schedule[i];
            ulong sum0 = RotateRight(a, 28) ^ RotateRight(a, 34) ^ RotateRight(a, 39);
            ulong majority = (a & b) ^ (a & c) ^ (b & c);
            ulong second = sum0 + majority;

            h = g;
            g = f;
            f = e;
            e = d + first;
            d = c;
            c = b;
            b = a;
            a = first + second;
        }

        _state[0u] += a;
        _state[1u] += b;
        _state[2u] += c;
        _state[3u] += d;
        _state[4u] += e;
        _state[5u] += f;
        _state[6u] += g;
        _state[7u] += h;
    }

    protected override byte[] ComputeDigest()
    {
        byte[] whole = new byte[64u];
        for (nuint i = 0u; i < 8u; i++)
            WriteBigDoubleWord(whole, i * 8u, _state[i]);

        if (HashSizeInBytes == 64u)
            return whole;

        byte[] digest = new byte[HashSizeInBytes];
        for (nuint i = 0u; i < digest.Length; i++)
            digest[i] = whole[i];
        return digest;
    }
}

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

// ===================================================== message authentication

/// HMAC over any hash: RFC 2104, and .NET's `HMACSHA256` and its siblings.
///
/// A hash is not a MAC. `Sha256.HashData(key + message)` can be extended by
/// anyone who has the digest and not the key, because the digest *is* the
/// state; this is the construction that fixes that, and it is what every
/// protocol means when it says "keyed hash".
///
/// Any key length works. A key longer than the hash's block is replaced by its
/// digest, a shorter one is padded with zeros, and both of those are the
/// standard's rules rather than a convenience.
public sealed class Hmac : IHashAlgorithm
{
    IHashAlgorithm _inner;
    byte[] _innerPad;
    byte[] _outerPad;
    String _name;

    /// `hash` is used for both passes and is left reset. It belongs to this
    /// object afterwards: appending to it from outside would corrupt the MAC.
    public Hmac(IHashAlgorithm hash, byte[:] key)
    {
        _inner = hash;
        _name = "HMAC-" + hash.Name;

        nuint blockSize = hash.BlockSizeInBytes;
        byte[] shortened = new byte[blockSize];

        if (key.Length > blockSize)
        {
            hash.Reset();
            hash.AppendData(key);
            byte[] digest = hash.GetHashAndReset();
            for (nuint i = 0u; i < digest.Length; i++)
                shortened[i] = digest[i];
        }
        else
        {
            for (nuint i = 0u; i < key.Length; i++)
                shortened[i] = key[i];
        }

        _innerPad = new byte[blockSize];
        _outerPad = new byte[blockSize];
        for (nuint i = 0u; i < blockSize; i++)
        {
            _innerPad[i] = (byte)(shortened[i] ^ 0x36u);
            _outerPad[i] = (byte)(shortened[i] ^ 0x5Cu);
        }

        CryptographicOperations.ZeroMemory(shortened);
        Reset();
    }

    public String Name => _name;

    public nuint HashSizeInBytes => _inner.HashSizeInBytes;

    public nuint BlockSizeInBytes => _inner.BlockSizeInBytes;

    public void AppendData(byte[:] data) => _inner.AppendData(data);

    public byte[] GetHashAndReset()
    {
        byte[] first = _inner.GetHashAndReset();
        _inner.AppendData(_outerPad);
        _inner.AppendData(first);
        byte[] mac = _inner.GetHashAndReset();
        Reset();
        return mac;
    }

    public void Reset()
    {
        _inner.Reset();
        _inner.AppendData(_innerPad);
    }

    /// The MAC of `data` under `key`, with no object to keep.
    public byte[] ComputeHash(byte[:] data)
    {
        Reset();
        AppendData(data);
        return GetHashAndReset();
    }
}

/// HMAC-SHA-1, as .NET spells `HMACSHA1`.
public static class HmacSha1
{
    /// A keyed hash to append to.
    public static Hmac Create(byte[:] key) => new Hmac(new Sha1(), key);

    /// The MAC of `data` under `key`.
    public static byte[] HashData(byte[:] key, byte[:] data) =>
        Create(key).ComputeHash(data);
}

/// HMAC-SHA-256, as .NET spells `HMACSHA256`. The default for anything new.
public static class HmacSha256
{
    /// A keyed hash to append to.
    public static Hmac Create(byte[:] key) => new Hmac(new Sha256(), key);

    /// The MAC of `data` under `key`.
    public static byte[] HashData(byte[:] key, byte[:] data) =>
        Create(key).ComputeHash(data);
}

/// HMAC-SHA-384, as .NET spells `HMACSHA384`.
public static class HmacSha384
{
    /// A keyed hash to append to.
    public static Hmac Create(byte[:] key) => new Hmac(new Sha384(), key);

    /// The MAC of `data` under `key`.
    public static byte[] HashData(byte[:] key, byte[:] data) =>
        Create(key).ComputeHash(data);
}

/// HMAC-SHA-512, as .NET spells `HMACSHA512`.
public static class HmacSha512
{
    /// A keyed hash to append to.
    public static Hmac Create(byte[:] key) => new Hmac(new Sha512(), key);

    /// The MAC of `data` under `key`.
    public static byte[] HashData(byte[:] key, byte[:] data) =>
        Create(key).ComputeHash(data);
}

/// HMAC-MD5, as .NET spells `HMACMD5`. Here for the protocols that specify it
/// -- and unlike a bare MD5 digest it is not broken by the collision attacks,
/// because a collision an attacker cannot compute without the key is no use.
public static class HmacMd5
{
    /// A keyed hash to append to.
    public static Hmac Create(byte[:] key) => new Hmac(new Md5(), key);

    /// The MAC of `data` under `key`.
    public static byte[] HashData(byte[:] key, byte[:] data) =>
        Create(key).ComputeHash(data);
}

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

/// HKDF (RFC 5869), which .NET has as `HKDF` and which is what to use when the
/// input is already a key rather than a password.
///
/// PBKDF2 is slow on purpose because a password has little entropy. HKDF is
/// fast on purpose because its input -- a Diffie-Hellman shared secret, a
/// master key -- already has plenty, and all that is wanted is to spread it
/// into several keys that reveal nothing about each other.
public static class Hkdf
{
    /// The extract step: a uniformly random key from input that is random but
    /// not uniform. `salt` may be empty, and then a block of zeros is used.
    ///
    /// @param hash      the HMAC's inner hash
    /// @param inputKey  the secret that is random but not uniform
    /// @param salt      a non-secret value, or empty for a block of zeros
    /// @see Hkdf.Expand
    public static byte[] Extract(IHashAlgorithm hash, byte[:] inputKey, byte[:] salt)
    {
        byte[] actual = salt.Length == 0u ? new byte[hash.HashSizeInBytes] : ToArray(salt);
        return new Hmac(hash, actual).ComputeHash(inputKey);
    }

    /// The expand step: as many bytes as asked for, bound to `info`.
    ///
    /// `info` is what separates one derived key from another -- "encryption"
    /// and "authentication" from the same secret -- and is the argument that
    /// makes this worth using over a bare hash.
    ///
    /// @param hash       the HMAC's inner hash, the same one `Extract` used
    /// @param pseudoKey  what `Extract` answered
    /// @param info       what separates one derived key from another
    /// @param length     how many bytes to derive, at most 255 digests' worth
    /// @failure CryptoError.Parameter  `length` is zero, or past 255 times the digest size
    /// @see Hkdf.Extract
    public static Result<byte[], CryptoError> Expand(IHashAlgorithm hash, byte[:] pseudoKey,
                                                     byte[:] info, nuint length)
    {
        nuint macSize = hash.HashSizeInBytes;
        if (length == 0u || length > macSize * 255u)
            return Fail(CryptoError.Parameter);

        var mac = new Hmac(hash, pseudoKey);
        byte[] derived = new byte[length];
        byte[] previous = new byte[0u];
        byte[] counter = new byte[1u];
        nuint filled = 0u;
        uint index = 1u;

        while (filled < length)
        {
            counter[0u] = (byte)index;
            mac.Reset();
            mac.AppendData(previous);
            mac.AppendData(info);
            mac.AppendData(counter);
            previous = mac.GetHashAndReset();

            nuint take = length - filled;
            if (take > macSize)
                take = macSize;

            for (nuint i = 0u; i < take; i++)
                derived[filled + i] = previous[i];

            filled += take;
            index++;
        }

        return Ok(derived);
    }

    /// Extract and expand together, which is how HKDF is nearly always used.
    ///
    /// @param hash      the HMAC's inner hash
    /// @param inputKey  the secret that is random but not uniform
    /// @param salt      a non-secret value, or empty for a block of zeros
    /// @param info      what separates one derived key from another
    /// @param length    how many bytes to derive, at most 255 digests' worth
    /// @failure CryptoError.Parameter  `length` is zero, or past 255 times the digest size
    /// @see Hkdf.Extract
    /// @see Hkdf.Expand
    public static Result<byte[], CryptoError> DeriveKey(IHashAlgorithm hash, byte[:] inputKey,
                                                        byte[:] salt, byte[:] info,
                                                        nuint length)
    {
        byte[] pseudoKey = Extract(hash, inputKey, salt);
        return Expand(hash, pseudoKey, info, length);
    }

    static byte[] ToArray(byte[:] data)
    {
        byte[] copy = new byte[data.Length];
        for (nuint i = 0u; i < data.Length; i++)
            copy[i] = data[i];
        return copy;
    }
}

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

/// AES, in ECB, CBC, CFB and CTR.
///
/// ```csharp
/// var cipher = try Aes.FromKey(key);          // 16, 24 or 32 bytes
/// var sealed = try cipher.EncryptCbc(plaintext, iv, PaddingMode.Pkcs7);
/// var opened = try cipher.DecryptCbc(sealed, iv, PaddingMode.Pkcs7);
/// ```
///
/// **None of these modes authenticates anything.** A ciphertext an attacker
/// can modify is a plaintext they can modify, and CBC in particular hands them
/// a bit-flipping attack on the block after the one they touched. Reach for
/// `AesGcm` unless a format forces one of these; where one is forced, put an
/// HMAC over the ciphertext and check it with `FixedTimeEquals` before
/// decrypting anything.
///
/// The one-shot methods are .NET 6's `EncryptCbc` and friends rather than its
/// older `CreateEncryptor`/`ICryptoTransform` pair. A transform object exists
/// to stream a message larger than memory; `CryptoStream` is the piece that
/// would want one and is not written, so the object with no stream to feed
/// would be a shape with no user.
///
/// @see AesGcm
public sealed class Aes
{
    /// One block, for every key length. AES is a 128-bit block cipher; it is
    /// Rijndael that had others, and no standard uses them.
    public const nuint BlockSize = 16u;

    byte[] _forward;
    byte[] _reverse;
    byte[] _schedule;
    nuint _rounds;

    Aes(byte[:] key)
    {
        _forward = BuildSubstitutionBox();
        _reverse = new byte[256u];
        for (nuint i = 0u; i < 256u; i++)
            _reverse[(nuint)_forward[i]] = (byte)i;

        // Written out rather than as a ternary: `nuint` is four bytes on a
        // 32-bit target and eight on a 64-bit one, and the arms of a ternary
        // over unsuffixed literals meet at a type that is neither.
        _rounds = 14u;
        if (key.Length == 16u)
            _rounds = 10u;
        else if (key.Length == 24u)
            _rounds = 12u;

        _schedule = ExpandKey(key);
    }

    /// A cipher under `key`, which must be 16, 24 or 32 bytes -- AES-128,
    /// AES-192 or AES-256.
    ///
    /// @failure CryptoError.KeyLength  `key` is not 16, 24 or 32 bytes
    public static Result<Aes, CryptoError> FromKey(byte[:] key)
    {
        if (key.Length != 16u && key.Length != 24u && key.Length != 32u)
            return Fail(CryptoError.KeyLength);
        return Ok(new Aes(key));
    }

    /// A cipher under a fresh 256-bit key from the platform, which is what
    /// .NET's `Aes.Create()` gives. Aborts if the machine will supply no
    /// entropy, which is a broken machine rather than an outcome to plan for.
    public static Aes Create()
    {
        byte[] key = new byte[32u];
        if (!sl_random_bytes(&key[0u], key.Length))
            sl_fail("Aes.Create: the platform supplied no entropy".ToPointer());
        return new Aes(key);
    }

    /// How many rounds this key length runs: 10, 12 or 14.
    public nuint Rounds => _rounds;

    // ------------------------------------------------------------- one block

    /// One block enciphered in place, at `offset` in `block`.
    ///
    /// Public because AES-GCM and a CTR keystream are built on it and a caller
    /// implementing a mode this class does not have needs the same door.
    /// **Not a way to encrypt a message**: a bare block cipher applied twice
    /// to the same input gives the same output, which is what a mode exists to
    /// fix.
    public void EncryptBlock(byte[] block, nuint offset)
    {
        AddRoundKey(block, offset, 0u);

        for (nuint round = 1u; round < _rounds; round++)
        {
            SubstituteBytes(block, offset, _forward);
            ShiftRows(block, offset);
            MixColumns(block, offset);
            AddRoundKey(block, offset, round);
        }

        SubstituteBytes(block, offset, _forward);
        ShiftRows(block, offset);
        AddRoundKey(block, offset, _rounds);
    }

    /// One block deciphered in place, at `offset` in `block`.
    public void DecryptBlock(byte[] block, nuint offset)
    {
        AddRoundKey(block, offset, _rounds);

        for (nuint round = _rounds - 1u; round > 0u; round--)
        {
            UnshiftRows(block, offset);
            SubstituteBytes(block, offset, _reverse);
            AddRoundKey(block, offset, round);
            UnmixColumns(block, offset);
        }

        UnshiftRows(block, offset);
        SubstituteBytes(block, offset, _reverse);
        AddRoundKey(block, offset, 0u);
    }

    // ------------------------------------------------------------------ ECB

    /// Every block on its own. See `CipherMode.Ecb` for why this is almost
    /// always the wrong answer.
    ///
    /// @failure CryptoError.BlockLength  `padding` is `None` and the input is not a whole
    ///                                   number of blocks
    /// @see CipherMode.Ecb
    /// @see Aes.DecryptEcb
    public Result<byte[], CryptoError> EncryptEcb(byte[:] plaintext, PaddingMode padding)
    {
        var padded = AddPadding(plaintext, padding);
        if (!padded.Ok)
            return Fail(padded.Error);

        byte[] output = padded.Value;
        for (nuint at = 0u; at < output.Length; at += BlockSize)
            EncryptBlock(output, at);

        return Ok(output);
    }

    /// The inverse of `EncryptEcb`.
    ///
    /// @failure CryptoError.BlockLength  the input is empty or not a whole number of blocks
    /// @failure CryptoError.Padding      the padding does not describe itself, which is usually
    ///                                   the wrong key
    /// @see Aes.EncryptEcb
    public Result<byte[], CryptoError> DecryptEcb(byte[:] ciphertext, PaddingMode padding)
    {
        if (ciphertext.Length == 0u || ciphertext.Length % BlockSize != 0u)
            return Fail(CryptoError.BlockLength);

        byte[] output = CopyBytes(ciphertext);
        for (nuint at = 0u; at < output.Length; at += BlockSize)
            DecryptBlock(output, at);

        return RemovePadding(output, padding);
    }

    // ------------------------------------------------------------------ CBC

    /// Chained blocks. `iv` must be one block and must never be reused with
    /// this key; `RandomNumberGenerator.GetBytes(16u)` is how to make one, and
    /// it is not secret -- send it alongside the ciphertext.
    ///
    /// @failure CryptoError.IvLength     `iv` is not one block
    /// @failure CryptoError.BlockLength  `padding` is `None` and the input is not a whole
    ///                                   number of blocks
    /// @see Aes.DecryptCbc
    /// @seealso RandomNumberGenerator.GetBytes
    public Result<byte[], CryptoError> EncryptCbc(byte[:] plaintext, byte[:] iv,
                                                  PaddingMode padding)
    {
        if (iv.Length != BlockSize)
            return Fail(CryptoError.IvLength);

        var padded = AddPadding(plaintext, padding);
        if (!padded.Ok)
            return Fail(padded.Error);

        byte[] output = padded.Value;
        byte[] chain = CopyBytes(iv);

        for (nuint at = 0u; at < output.Length; at += BlockSize)
        {
            for (nuint i = 0u; i < BlockSize; i++)
                output[at + i] = (byte)(output[at + i] ^ chain[i]);

            EncryptBlock(output, at);

            for (nuint i = 0u; i < BlockSize; i++)
                chain[i] = output[at + i];
        }

        return Ok(output);
    }

    /// The inverse of `EncryptCbc`.
    ///
    /// A wrong key shows up as `CryptoError.Padding` about 255 times in 256,
    /// and as a plausible-looking wrong plaintext the rest of the time. That
    /// is the whole reason to authenticate a ciphertext before decrypting it.
    ///
    /// @failure CryptoError.IvLength     `iv` is not one block
    /// @failure CryptoError.BlockLength  the input is empty or not a whole number of blocks
    /// @failure CryptoError.Padding      the padding does not describe itself
    /// @see Aes.EncryptCbc
    public Result<byte[], CryptoError> DecryptCbc(byte[:] ciphertext, byte[:] iv,
                                                  PaddingMode padding)
    {
        if (iv.Length != BlockSize)
            return Fail(CryptoError.IvLength);
        if (ciphertext.Length == 0u || ciphertext.Length % BlockSize != 0u)
            return Fail(CryptoError.BlockLength);

        byte[] output = CopyBytes(ciphertext);
        byte[] chain = CopyBytes(iv);
        byte[] carry = new byte[BlockSize];

        for (nuint at = 0u; at < output.Length; at += BlockSize)
        {
            for (nuint i = 0u; i < BlockSize; i++)
                carry[i] = output[at + i];

            DecryptBlock(output, at);

            for (nuint i = 0u; i < BlockSize; i++)
            {
                output[at + i] = (byte)(output[at + i] ^ chain[i]);
                chain[i] = carry[i];
            }
        }

        return RemovePadding(output, padding);
    }

    // ------------------------------------------------------------------ CFB

    /// Cipher feedback over whole blocks, which is .NET's `CipherMode.CFB`
    /// with a feedback size of 128 bits. No padding: the mode is a stream.
    ///
    /// @failure CryptoError.IvLength  `iv` is not one block
    /// @see Aes.DecryptCfb
    public Result<byte[], CryptoError> EncryptCfb(byte[:] plaintext, byte[:] iv)
    {
        if (iv.Length != BlockSize)
            return Fail(CryptoError.IvLength);

        byte[] output = CopyBytes(plaintext);
        byte[] chain = CopyBytes(iv);

        for (nuint at = 0u; at < output.Length; at += BlockSize)
        {
            EncryptBlock(chain, 0u);

            nuint span = output.Length - at;
            if (span > BlockSize)
                span = BlockSize;

            for (nuint i = 0u; i < span; i++)
            {
                output[at + i] = (byte)(output[at + i] ^ chain[i]);
                chain[i] = output[at + i];
            }
        }

        return Ok(output);
    }

    /// The inverse of `EncryptCfb`.
    ///
    /// @failure CryptoError.IvLength  `iv` is not one block
    /// @see Aes.EncryptCfb
    public Result<byte[], CryptoError> DecryptCfb(byte[:] ciphertext, byte[:] iv)
    {
        if (iv.Length != BlockSize)
            return Fail(CryptoError.IvLength);

        byte[] output = CopyBytes(ciphertext);
        byte[] chain = CopyBytes(iv);

        for (nuint at = 0u; at < output.Length; at += BlockSize)
        {
            EncryptBlock(chain, 0u);

            nuint span = output.Length - at;
            if (span > BlockSize)
                span = BlockSize;

            for (nuint i = 0u; i < span; i++)
            {
                byte enciphered = output[at + i];
                output[at + i] = (byte)(enciphered ^ chain[i]);
                chain[i] = enciphered;
            }
        }

        return Ok(output);
    }

    // ------------------------------------------------------------------ CTR

    /// Counter mode, which is its own inverse: the same call decrypts.
    ///
    /// `counter` is sixteen bytes and is incremented as one big-endian number
    /// per block, which is what NIST SP 800-38A and every protocol built on it
    /// do. **A counter value used twice under one key is fatal** -- the two
    /// messages XOR to the XOR of their plaintexts -- so the usual arrangement
    /// is a random nonce in the high bytes and a block counter in the low.
    ///
    /// @failure CryptoError.IvLength  `counter` is not one block
    public Result<byte[], CryptoError> ApplyCtr(byte[:] data, byte[:] counter) =>
        ApplyCounter(data, counter, 0u);

    /// The same, stepping only the bytes from `from` onward.
    ///
    /// GCM increments the last four bytes and leaves the nonce in the first
    /// twelve alone, so a message long enough to carry past 2^32 blocks wraps
    /// within the counter rather than walking into the nonce. That is the one
    /// difference between GCM's CTR and SP 800-38A's, and it is why this is a
    /// parameter rather than two loops.
    Result<byte[], CryptoError> ApplyCounter(byte[:] data, byte[:] counter, nuint from)
    {
        if (counter.Length != BlockSize)
            return Fail(CryptoError.IvLength);

        byte[] output = CopyBytes(data);
        byte[] position = CopyBytes(counter);
        byte[] keystream = new byte[BlockSize];

        for (nuint at = 0u; at < output.Length; at += BlockSize)
        {
            for (nuint i = 0u; i < BlockSize; i++)
                keystream[i] = position[i];

            EncryptBlock(keystream, 0u);

            nuint span = output.Length - at;
            if (span > BlockSize)
                span = BlockSize;

            for (nuint i = 0u; i < span; i++)
                output[at + i] = (byte)(output[at + i] ^ keystream[i]);

            IncrementCounter(position, from);
        }

        CryptographicOperations.ZeroMemory(keystream);
        return Ok(output);
    }

    /// One added to a big-endian counter in `block`, from byte `from` to the
    /// end. GCM increments only the last four bytes, which is what `from` is
    /// for.
    static void IncrementCounter(byte[] block, nuint from)
    {
        nuint at = block.Length;
        while (at > from)
        {
            at--;
            block[at] = (byte)(block[at] + 1u);
            if (block[at] != 0)
                return;
        }
    }

    // -------------------------------------------------------------- padding

    Result<byte[], CryptoError> AddPadding(byte[:] data, PaddingMode padding)
    {
        nuint remainder = data.Length % BlockSize;

        switch (padding)
        {
            case PaddingMode.None:
                if (remainder != 0u)
                    return Fail(CryptoError.BlockLength);
                return Ok(CopyBytes(data));

            case PaddingMode.Pkcs7:
            {
                // Always adds, even to a whole number of blocks -- that is what
                // makes it removable without ambiguity.
                nuint added = BlockSize - remainder;
                byte[] output = new byte[data.Length + added];
                for (nuint i = 0u; i < data.Length; i++)
                    output[i] = data[i];
                for (nuint i = data.Length; i < output.Length; i++)
                    output[i] = (byte)added;
                return Ok(output);
            }

            case PaddingMode.Zeros:
            {
                nuint added = 0u;
                if (remainder != 0u)
                    added = BlockSize - remainder;

                byte[] output = new byte[data.Length + added];
                for (nuint i = 0u; i < data.Length; i++)
                    output[i] = data[i];
                return Ok(output);
            }

            case PaddingMode.AnsiX923:
            {
                nuint added = BlockSize - remainder;
                byte[] output = new byte[data.Length + added];
                for (nuint i = 0u; i < data.Length; i++)
                    output[i] = data[i];
                output[output.Length - 1u] = (byte)added;
                return Ok(output);
            }
        }

        // Every case above returns; the binder wants a path out of the switch
        // itself, and this is it.
        return Fail(CryptoError.Parameter);
    }

    Result<byte[], CryptoError> RemovePadding(byte[] data, PaddingMode padding)
    {
        if (padding == PaddingMode.None || padding == PaddingMode.Zeros)
            return Ok(data);

        nuint added = (nuint)data[data.Length - 1u];
        if (added == 0u || added > BlockSize || added > data.Length)
            return Fail(CryptoError.Padding);

        if (padding == PaddingMode.Pkcs7)
        {
            for (nuint i = data.Length - added; i < data.Length; i++)
            {
                if ((nuint)data[i] != added)
                    return Fail(CryptoError.Padding);
            }
        }
        else
        {
            for (nuint i = data.Length - added; i < data.Length - 1u; i++)
            {
                if (data[i] != 0)
                    return Fail(CryptoError.Padding);
            }
        }

        byte[] output = new byte[data.Length - added];
        for (nuint i = 0u; i < output.Length; i++)
            output[i] = data[i];
        return Ok(output);
    }

    // ------------------------------------------------------------ the cipher

    void AddRoundKey(byte[] block, nuint offset, nuint round)
    {
        nuint at = round * BlockSize;
        for (nuint i = 0u; i < BlockSize; i++)
            block[offset + i] = (byte)(block[offset + i] ^ _schedule[at + i]);
    }

    static void SubstituteBytes(byte[] block, nuint offset, byte[] box)
    {
        for (nuint i = 0u; i < BlockSize; i++)
            block[offset + i] = box[(nuint)block[offset + i]];
    }

    /// The state is column-major, so row `r` is bytes r, r+4, r+8, r+12.
    static void ShiftRows(byte[] s, nuint at)
    {
        byte carry = s[at + 1u];
        s[at + 1u] = s[at + 5u];
        s[at + 5u] = s[at + 9u];
        s[at + 9u] = s[at + 13u];
        s[at + 13u] = carry;

        carry = s[at + 2u];
        s[at + 2u] = s[at + 10u];
        s[at + 10u] = carry;
        carry = s[at + 6u];
        s[at + 6u] = s[at + 14u];
        s[at + 14u] = carry;

        carry = s[at + 15u];
        s[at + 15u] = s[at + 11u];
        s[at + 11u] = s[at + 7u];
        s[at + 7u] = s[at + 3u];
        s[at + 3u] = carry;
    }

    static void UnshiftRows(byte[] s, nuint at)
    {
        byte carry = s[at + 13u];
        s[at + 13u] = s[at + 9u];
        s[at + 9u] = s[at + 5u];
        s[at + 5u] = s[at + 1u];
        s[at + 1u] = carry;

        carry = s[at + 2u];
        s[at + 2u] = s[at + 10u];
        s[at + 10u] = carry;
        carry = s[at + 6u];
        s[at + 6u] = s[at + 14u];
        s[at + 14u] = carry;

        carry = s[at + 3u];
        s[at + 3u] = s[at + 7u];
        s[at + 7u] = s[at + 11u];
        s[at + 11u] = s[at + 15u];
        s[at + 15u] = carry;
    }

    static void MixColumns(byte[] s, nuint at)
    {
        for (nuint column = 0u; column < 4u; column++)
        {
            nuint c = at + column * 4u;
            byte a0 = s[c];
            byte a1 = s[c + 1u];
            byte a2 = s[c + 2u];
            byte a3 = s[c + 3u];

            s[c] = (byte)(MultiplyByTwo(a0) ^ MultiplyByTwo(a1) ^ a1 ^ a2 ^ a3);
            s[c + 1u] = (byte)(a0 ^ MultiplyByTwo(a1) ^ MultiplyByTwo(a2) ^ a2 ^ a3);
            s[c + 2u] = (byte)(a0 ^ a1 ^ MultiplyByTwo(a2) ^ MultiplyByTwo(a3) ^ a3);
            s[c + 3u] = (byte)(MultiplyByTwo(a0) ^ a0 ^ a1 ^ a2 ^ MultiplyByTwo(a3));
        }
    }

    static void UnmixColumns(byte[] s, nuint at)
    {
        for (nuint column = 0u; column < 4u; column++)
        {
            nuint c = at + column * 4u;
            byte a0 = s[c];
            byte a1 = s[c + 1u];
            byte a2 = s[c + 2u];
            byte a3 = s[c + 3u];

            s[c] = (byte)(MultiplyInField(a0, 14) ^ MultiplyInField(a1, 11) ^
                          MultiplyInField(a2, 13) ^ MultiplyInField(a3, 9));
            s[c + 1u] = (byte)(MultiplyInField(a0, 9) ^ MultiplyInField(a1, 14) ^
                               MultiplyInField(a2, 11) ^ MultiplyInField(a3, 13));
            s[c + 2u] = (byte)(MultiplyInField(a0, 13) ^ MultiplyInField(a1, 9) ^
                               MultiplyInField(a2, 14) ^ MultiplyInField(a3, 11));
            s[c + 3u] = (byte)(MultiplyInField(a0, 11) ^ MultiplyInField(a1, 13) ^
                               MultiplyInField(a2, 9) ^ MultiplyInField(a3, 14));
        }
    }

    byte[] ExpandKey(byte[:] key)
    {
        nuint words = 4u * (_rounds + 1u);
        nuint keyWords = key.Length / 4u;
        byte[] schedule = new byte[words * 4u];

        for (nuint i = 0u; i < key.Length; i++)
            schedule[i] = key[i];

        byte constant = 1;

        for (nuint i = keyWords; i < words; i++)
        {
            nuint previous = (i - 1u) * 4u;
            byte t0 = schedule[previous];
            byte t1 = schedule[previous + 1u];
            byte t2 = schedule[previous + 2u];
            byte t3 = schedule[previous + 3u];

            if (i % keyWords == 0u)
            {
                // RotWord, SubWord, and the round constant on the first byte.
                byte carry = t0;
                t0 = _forward[(nuint)t1];
                t1 = _forward[(nuint)t2];
                t2 = _forward[(nuint)t3];
                t3 = _forward[(nuint)carry];

                t0 = (byte)(t0 ^ constant);
                constant = MultiplyByTwo(constant);
            }
            else if (keyWords > 6u && i % keyWords == 4u)
            {
                // AES-256 substitutes without rotating every fourth word.
                t0 = _forward[(nuint)t0];
                t1 = _forward[(nuint)t1];
                t2 = _forward[(nuint)t2];
                t3 = _forward[(nuint)t3];
            }

            nuint back = (i - keyWords) * 4u;
            nuint here = i * 4u;
            schedule[here] = (byte)(schedule[back] ^ t0);
            schedule[here + 1u] = (byte)(schedule[back + 1u] ^ t1);
            schedule[here + 2u] = (byte)(schedule[back + 2u] ^ t2);
            schedule[here + 3u] = (byte)(schedule[back + 3u] ^ t3);
        }

        return schedule;
    }

    /// The S-box, derived rather than transcribed.
    ///
    /// It is defined as the multiplicative inverse in GF(2^8) followed by an
    /// affine transform, and computing it is twenty lines where copying it is
    /// 256 hex constants that nothing would catch a typo in. The cost is a
    /// table built per cipher object, which is a few thousand instructions
    /// once.
    static byte[] BuildSubstitutionBox()
    {
        byte[] box = new byte[256u];
        box[0u] = 0x63;

        for (nuint i = 1u; i < 256u; i++)
        {
            uint inverse = (uint)InvertInField((byte)i);
            uint folded = inverse ^ RotateOctet(inverse, 1u) ^ RotateOctet(inverse, 2u) ^
                          RotateOctet(inverse, 3u) ^ RotateOctet(inverse, 4u) ^ 0x63u;
            box[i] = (byte)(folded & 0xFFu);
        }

        return box;
    }

    static uint RotateOctet(uint value, uint by) =>
        ((value << by) | (value >> (8u - by))) & 0xFFu;

    /// x times 2 in GF(2^8) with the AES polynomial, which is the only
    /// multiplication the forward direction needs.
    static byte MultiplyByTwo(byte value)
    {
        uint doubled = (uint)value << 1;
        if ((value & 0x80u) != 0u)
            doubled ^= 0x1Bu;
        return (byte)(doubled & 0xFFu);
    }

    /// A full GF(2^8) multiply, for the inverse mix columns.
    static byte MultiplyInField(byte left, byte right)
    {
        uint result = 0u;
        uint a = (uint)left;
        uint b = (uint)right;

        for (nuint i = 0u; i < 8u; i++)
        {
            if ((b & 1u) != 0u)
                result ^= a;

            bool overflowed = (a & 0x80u) != 0u;
            a = (a << 1) & 0xFFu;
            if (overflowed)
                a ^= 0x1Bu;

            b >>= 1;
        }

        return (byte)(result & 0xFFu);
    }

    /// The multiplicative inverse, as a^254 -- which it is, because the group
    /// has 255 elements.
    static byte InvertInField(byte value)
    {
        if (value == 0)
            return 0;

        byte result = 1;
        byte power = value;

        for (nuint bit = 1u; bit < 8u; bit++)
        {
            power = MultiplyInField(power, power);
            result = MultiplyInField(result, power);
        }

        return result;
    }

    static byte[] CopyBytes(byte[:] data)
    {
        byte[] copy = new byte[data.Length];
        for (nuint i = 0u; i < data.Length; i++)
            copy[i] = data[i];
        return copy;
    }
}

// =========================================================== authenticated

/// AES-GCM: encryption and authentication in one pass, as .NET's `AesGcm`.
///
/// ```csharp
/// var box = try AesGcm.FromKey(key);
/// byte[] tag = new byte[16u];
/// var sealed = try box.Encrypt(nonce, plaintext, associated, tag);
/// var opened = try box.Decrypt(nonce, sealed, associated, tag);
/// ```
///
/// **The nonce must never repeat under one key.** GCM is CTR mode with a MAC
/// over the result, and a repeated nonce gives an attacker the XOR of two
/// plaintexts *and*, worse, the authentication key itself -- after which they
/// can forge. Twelve random bytes per message is fine up to about 2^32
/// messages; a counter is better where one can be kept.
///
/// `Decrypt` returns `CryptoError.AuthenticationFailed` and no plaintext when
/// the tag does not match. That is not a convenience: releasing unauthenticated
/// plaintext is the single most common way AEAD is misused, and a `Result` is
/// what makes it impossible here.
public sealed class AesGcm
{
    /// What the tag is, and the only length this produces. .NET allows 12 to
    /// 16; a shorter tag weakens forgery resistance by exactly the bits it
    /// drops, and no format here asks for one.
    ///
    /// @value sixteen bytes.
    public const nuint TagSize = 16u;

    /// What every protocol built on GCM uses, and the only length for which
    /// the nonce is used directly rather than hashed.
    ///
    /// @value twelve bytes.
    public const nuint NonceSize = 12u;

    Aes _cipher;
    byte[] _hashKey;

    AesGcm(Aes cipher)
    {
        _cipher = cipher;
        _hashKey = new byte[16u];
        cipher.EncryptBlock(_hashKey, 0u);
    }

    /// A GCM box under `key`, which must be 16, 24 or 32 bytes.
    ///
    /// @failure CryptoError.KeyLength  `key` is not 16, 24 or 32 bytes
    public static Result<AesGcm, CryptoError> FromKey(byte[:] key)
    {
        var cipher = Aes.FromKey(key);
        if (!cipher.Ok)
            return Fail(cipher.Error);
        return Ok(new AesGcm(cipher.Value));
    }

    /// The ciphertext, with the tag written into `tag`.
    ///
    /// `associatedData` is authenticated and not encrypted -- a message header,
    /// a record number, anything the recipient must be sure of and that is not
    /// secret. Pass an empty array when there is none.
    ///
    /// @param nonce           never to repeat under this key; twelve bytes is what every
    ///                        protocol uses
    /// @param plaintext       the message to encipher
    /// @param associatedData  authenticated and not encrypted; empty when there is none
    /// @param tag             a `TagSize` array the tag is written into
    /// @failure CryptoError.NonceLength  `nonce` is empty
    /// @failure CryptoError.TagLength    `tag` is not `TagSize` long
    /// @see AesGcm.Decrypt
    public Result<byte[], CryptoError> Encrypt(byte[:] nonce, byte[:] plaintext,
                                               byte[:] associatedData, byte[] tag)
    {
        if (nonce.Length == 0u)
            return Fail(CryptoError.NonceLength);
        if (tag.Length != TagSize)
            return Fail(CryptoError.TagLength);

        byte[] counter = ComputeInitialCounter(nonce);
        byte[] keystream = new byte[16u];
        for (nuint i = 0u; i < 16u; i++)
            keystream[i] = counter[i];

        Aes.IncrementCounter(counter, 12u);
        var enciphered = _cipher.ApplyCounter(plaintext, counter, 12u);
        if (!enciphered.Ok)
            return Fail(enciphered.Error);

        byte[] ciphertext = enciphered.Value;
        byte[] computed = ComputeTag(associatedData, ciphertext, keystream);
        for (nuint i = 0u; i < TagSize; i++)
            tag[i] = computed[i];

        return Ok(ciphertext);
    }

    /// The plaintext, or `AuthenticationFailed` and nothing.
    ///
    /// @param nonce           the one the message was enciphered under
    /// @param ciphertext      the message to open
    /// @param associatedData  the same bytes the sender authenticated
    /// @param tag             the tag the sender sent
    /// @failure CryptoError.NonceLength           `nonce` is empty
    /// @failure CryptoError.TagLength             `tag` is not `TagSize` long
    /// @failure CryptoError.AuthenticationFailed  the tag does not match, and no plaintext is
    ///                                            returned
    /// @see AesGcm.Encrypt
    public Result<byte[], CryptoError> Decrypt(byte[:] nonce, byte[:] ciphertext,
                                               byte[:] associatedData, byte[:] tag)
    {
        if (nonce.Length == 0u)
            return Fail(CryptoError.NonceLength);
        if (tag.Length != TagSize)
            return Fail(CryptoError.TagLength);

        byte[] counter = ComputeInitialCounter(nonce);
        byte[] keystream = new byte[16u];
        for (nuint i = 0u; i < 16u; i++)
            keystream[i] = counter[i];

        byte[] expected = ComputeTag(associatedData, ciphertext, keystream);
        if (!CryptographicOperations.FixedTimeEquals(expected, tag))
            return Fail(CryptoError.AuthenticationFailed);

        Aes.IncrementCounter(counter, 12u);
        var deciphered = _cipher.ApplyCounter(ciphertext, counter, 12u);
        if (!deciphered.Ok)
            return Fail(deciphered.Error);

        return Ok(deciphered.Value);
    }

    /// J0: the nonce and a one when the nonce is twelve bytes, and GHASH of
    /// the nonce otherwise -- which is the standard's rule and the reason
    /// twelve is the length everything uses.
    byte[] ComputeInitialCounter(byte[:] nonce)
    {
        byte[] counter = new byte[16u];

        if (nonce.Length == NonceSize)
        {
            for (nuint i = 0u; i < NonceSize; i++)
                counter[i] = nonce[i];
            counter[15u] = 1;
            return counter;
        }

        UpdateGhash(counter, nonce);
        byte[] lengths = new byte[16u];
        WriteLength(lengths, 8u, (ulong)nonce.Length * 8u);
        UpdateGhash(counter, lengths);
        return counter;
    }

    /// GHASH over the associated data and the ciphertext, enciphered under the
    /// first counter block. That last step is what stops GHASH -- which is a
    /// keyed hash and not a MAC on its own -- from being invertible.
    byte[] ComputeTag(byte[:] associatedData, byte[:] ciphertext, byte[] keystream)
    {
        byte[] accumulator = new byte[16u];
        UpdateGhash(accumulator, associatedData);
        UpdateGhash(accumulator, ciphertext);

        byte[] lengths = new byte[16u];
        WriteLength(lengths, 0u, (ulong)associatedData.Length * 8u);
        WriteLength(lengths, 8u, (ulong)ciphertext.Length * 8u);
        UpdateGhash(accumulator, lengths);

        byte[] mask = new byte[16u];
        for (nuint i = 0u; i < 16u; i++)
            mask[i] = keystream[i];
        _cipher.EncryptBlock(mask, 0u);

        byte[] tag = new byte[TagSize];
        for (nuint i = 0u; i < TagSize; i++)
            tag[i] = (byte)(accumulator[i] ^ mask[i]);

        return tag;
    }

    /// `data` folded into the accumulator, a block at a time and zero-padded.
    void UpdateGhash(byte[] accumulator, byte[:] data)
    {
        byte[] block = new byte[16u];

        for (nuint at = 0u; at < data.Length; at += 16u)
        {
            nuint span = data.Length - at;
            if (span > 16u)
                span = 16u;

            for (nuint i = 0u; i < 16u; i++)
                block[i] = 0;

            for (nuint i = 0u; i < span; i++)
                block[i] = data[at + i];

            for (nuint i = 0u; i < 16u; i++)
                accumulator[i] = (byte)(accumulator[i] ^ block[i]);

            MultiplyGhash(accumulator, _hashKey);
        }
    }

    /// `left` times `right` in GF(2^128), bit by bit.
    ///
    /// The tabulated version is four times faster and leaks through the cache
    /// the way an AES table does; this one is the shift-and-add definition,
    /// which is what a reference implementation should be. 128 iterations per
    /// block is the price.
    static void MultiplyGhash(byte[] left, byte[] right)
    {
        byte[] product = new byte[16u];
        byte[] running = new byte[16u];
        for (nuint i = 0u; i < 16u; i++)
            running[i] = right[i];

        for (nuint bit = 0u; bit < 128u; bit++)
        {
            nuint at = bit / 8u;
            uint mask = (uint)(0x80u >> (uint)(bit % 8u));

            if (((uint)left[at] & mask) != 0u)
            {
                for (nuint i = 0u; i < 16u; i++)
                    product[i] = (byte)(product[i] ^ running[i]);
            }

            bool odd = (running[15u] & 1u) != 0u;
            for (nuint i = 16u; i > 0u; i--)
            {
                nuint index = i - 1u;
                uint shifted = (uint)running[index] >> 1;
                if (index > 0u)
                    shifted |= ((uint)running[index - 1u] & 1u) << 7;
                running[index] = (byte)shifted;
            }

            // The reduction polynomial, whose only set bits above the low byte
            // are in the first: x^128 + x^7 + x^2 + x + 1.
            if (odd)
                running[0u] = (byte)(running[0u] ^ 0xE1u);
        }

        for (nuint i = 0u; i < 16u; i++)
            left[i] = product[i];
    }

    static void WriteLength(byte[] into, nuint at, ulong bits)
    {
        for (nuint i = 0u; i < 8u; i++)
            into[at + i] = (byte)((bits >> (uint)(8u * (7u - i))) & 0xFFu);
    }
}

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
    public static bool FixedTimeEquals(byte[:] left, byte[:] right)
    {
        if (left.Length != right.Length)
            return false;

        uint difference = 0u;
        for (nuint i = 0u; i < left.Length; i++)
            difference |= (uint)left[i] ^ (uint)right[i];

        return difference == 0u;
    }

    /// Overwrites `buffer` with zeros.
    ///
    /// **Not a guarantee.** An optimiser is entitled to remove a write nothing
    /// reads, and this is an ordinary loop in an ordinary language -- .NET's
    /// version is a compiler intrinsic and this one is not. It is worth doing
    /// because a key that is overwritten is a key that is not in the next core
    /// dump, and it is not worth relying on.
    public static void ZeroMemory(byte[] buffer)
    {
        for (nuint i = 0u; i < buffer.Length; i++)
            buffer[i] = 0;
    }
}
