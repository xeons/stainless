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

// ================================================================== hashing

/// BLAKE2b (RFC 7693): a hash as strong as SHA-3 and faster than SHA-256, with
/// a key and a digest length of its own.
///
/// ```csharp
/// var digest = Blake2b.HashData(data);
/// var mac = try Blake2b.FromKey(key, 32u);
/// mac.AppendData(message);
/// var tag = mac.GetHashAndReset();
/// ```
///
/// **A keyed BLAKE2b is a MAC on its own.** It is not a Merkle-Damgård hash,
/// so it cannot be extended the way `Sha256.HashData(key + message)` can, and
/// HMAC's two passes buy nothing. The key goes in its own first block.
///
/// **The digest length is a parameter, not a truncation.** BLAKE2b-256 is not
/// the first half of BLAKE2b-512: the length is mixed into the initial state,
/// so every length is its own function.
///
/// Not in .NET. It is here because Argon2 is built on it, and it fits
/// `IHashAlgorithm` as it is, so `Hmac` takes it like any other.
///
/// @see Argon2id
public sealed class Blake2b : IHashAlgorithm
{
    /// The longest digest, and the one `new Blake2b()` gives.
    ///
    /// @value sixty-four bytes.
    public const nuint MaxHashSize = 64u;

    /// The longest key.
    ///
    /// @value sixty-four bytes.
    public const nuint MaxKeySize = 64u;

    private ulong[] _state;
    private ulong[] _words;
    private byte[] _block;
    private nuint _used;
    private ulong _countLow;
    private ulong _countHigh;
    private byte[] _key;
    private nuint _hashSize;
    private String _name;
    private byte[] _schedule;

    /// BLAKE2b-512, unkeyed.
    public Blake2b() : this(new byte[0u], MaxHashSize)
    {
    }

    Blake2b(ReadOnlySpan<byte> key, nuint hashSize)
    {
        _state = new ulong[8u];
        _words = new ulong[16u];
        _block = new byte[128u];
        _key = key.ToArray();
        _hashSize = hashSize;
        _name = "BLAKE2b-" + Text.FromInteger((long)(hashSize * 8u));

        // σ of RFC 7693 §2.7: which message word each G takes, per round.
        _schedule = [
            0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
            14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3,
            11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4,
            7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8,
            9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13,
            2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9,
            12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11,
            13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10,
            6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5,
            10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0,
        ];

        Reset();
    }

    ~Blake2b()
    {
        CryptographicOperations.ZeroMemory(_key);
        CryptographicOperations.ZeroMemory(_block);
        CryptographicOperations.ZeroMemory(_state);
        CryptographicOperations.ZeroMemory(_words);
    }

    /// A BLAKE2b under `key` giving `hashSize` bytes. An empty key is the
    /// unkeyed hash of that length.
    ///
    /// @param key       at most `MaxKeySize` bytes; empty for none
    /// @param hashSize  one to `MaxHashSize` bytes of digest
    /// @failure CryptoError.KeyLength  `key` is longer than `MaxKeySize`
    /// @failure CryptoError.Parameter  `hashSize` is zero or past `MaxHashSize`
    public static Result<Blake2b, CryptoError> FromKey(ReadOnlySpan<byte> key, nuint hashSize)
    {
        if (key.Length > MaxKeySize)
            return Fail(CryptoError.KeyLength);
        if (hashSize == 0u || hashSize > MaxHashSize)
            return Fail(CryptoError.Parameter);
        return Ok(new Blake2b(key, hashSize));
    }

    /// The BLAKE2b-512 digest of `data`, with no object to keep.
    public static byte[] HashData(ReadOnlySpan<byte> data) => new Blake2b().ComputeHash(data);

    /// `BLAKE2b-512`, or the length this one was made with, in bits.
    public String Name => _name;

    public nuint HashSizeInBytes => _hashSize;

    public nuint BlockSizeInBytes => 128u;

    public void AppendData(ReadOnlySpan<byte> data)
    {
        nuint at = 0u;
        while (at < data.Length)
        {
            // A full block is held back until more arrives, because the last
            // block is compressed differently and this one may be it.
            if (_used == 128u)
            {
                AddToCount(128u);
                CompressBlock(false);
                _used = 0u;
            }

            nuint take = data.Length - at;
            if (take > 128u - _used)
                take = 128u - _used;

            data[at:at + take].CopyTo(_block[_used:]);

            _used += take;
            at += take;
        }
    }

    public byte[] GetHashAndReset()
    {
        AddToCount(_used);
        for (nuint i = _used; i < 128u; i++)
            _block[i] = 0;
        CompressBlock(true);

        byte[] whole = new byte[64u];
        for (nuint i = 0u; i < 8u; i++)
            WriteLittleDoubleWord(whole, i * 8u, _state[i]);

        byte[] digest = whole[:_hashSize].ToArray();

        CryptographicOperations.ZeroMemory(whole);
        Reset();
        return digest;
    }

    public void Reset()
    {
        for (nuint i = 0u; i < 8u; i++)
            _state[i] = InitialWord(i);

        // The parameter block, of which only the first word is not zero here:
        // digest length, key length, fanout 1 and depth 1.
        _state[0u] ^= 0x01010000u ^ ((ulong)_key.Length << 8) ^ (ulong)_hashSize;

        _countLow = 0u;
        _countHigh = 0u;
        CryptographicOperations.ZeroMemory(_block);
        _used = 0u;

        if (_key.Length > 0u)
        {
            _key[:].CopyTo(_block);
            _used = 128u;
        }
    }

    /// The digest of `data` on its own. Resets first, so an object that has
    /// been appended to is still safe to ask.
    public byte[] ComputeHash(ReadOnlySpan<byte> data)
    {
        Reset();
        AppendData(data);
        return GetHashAndReset();
    }

    /// SHA-512's initial value, which BLAKE2b shares.
    static ulong InitialWord(nuint index)
    {
        switch (index)
        {
            case 0u: return 0x6A09E667F3BCC908u;
            case 1u: return 0xBB67AE8584CAA73Bu;
            case 2u: return 0x3C6EF372FE94F82Bu;
            case 3u: return 0xA54FF53A5F1D36F1u;
            case 4u: return 0x510E527FADE682D1u;
            case 5u: return 0x9B05688C2B3E6C1Fu;
            case 6u: return 0x1F83D9ABFB41BD6Bu;
            default: return 0x5BE0CD19137E2179u;
        }
    }

    void AddToCount(nuint bytes)
    {
        ulong before = _countLow;
        _countLow += (ulong)bytes;
        if (_countLow < before)
            _countHigh++;
    }

    /// F of RFC 7693 §3.2: twelve rounds over the state and `_block`.
    void CompressBlock(bool isLast)
    {
        for (nuint i = 0u; i < 16u; i++)
            _words[i] = ReadLittleDoubleWord(_block, i * 8u);

        ulong v0 = _state[0u];
        ulong v1 = _state[1u];
        ulong v2 = _state[2u];
        ulong v3 = _state[3u];
        ulong v4 = _state[4u];
        ulong v5 = _state[5u];
        ulong v6 = _state[6u];
        ulong v7 = _state[7u];
        ulong v8 = InitialWord(0u);
        ulong v9 = InitialWord(1u);
        ulong v10 = InitialWord(2u);
        ulong v11 = InitialWord(3u);
        ulong v12 = InitialWord(4u) ^ _countLow;
        ulong v13 = InitialWord(5u) ^ _countHigh;
        ulong v14 = InitialWord(6u);
        ulong v15 = InitialWord(7u);
        if (isLast)
            v14 = ~v14;

        for (nuint round = 0u; round < 12u; round++)
        {
            nuint s = (round % 10u) * 16u;
            MixBlakeQuarter(ref v0, ref v4, ref v8, ref v12,
                            _words[(nuint)_schedule[s]], _words[(nuint)_schedule[s + 1u]]);
            MixBlakeQuarter(ref v1, ref v5, ref v9, ref v13,
                            _words[(nuint)_schedule[s + 2u]], _words[(nuint)_schedule[s + 3u]]);
            MixBlakeQuarter(ref v2, ref v6, ref v10, ref v14,
                            _words[(nuint)_schedule[s + 4u]], _words[(nuint)_schedule[s + 5u]]);
            MixBlakeQuarter(ref v3, ref v7, ref v11, ref v15,
                            _words[(nuint)_schedule[s + 6u]], _words[(nuint)_schedule[s + 7u]]);
            MixBlakeQuarter(ref v0, ref v5, ref v10, ref v15,
                            _words[(nuint)_schedule[s + 8u]], _words[(nuint)_schedule[s + 9u]]);
            MixBlakeQuarter(ref v1, ref v6, ref v11, ref v12,
                            _words[(nuint)_schedule[s + 10u]], _words[(nuint)_schedule[s + 11u]]);
            MixBlakeQuarter(ref v2, ref v7, ref v8, ref v13,
                            _words[(nuint)_schedule[s + 12u]], _words[(nuint)_schedule[s + 13u]]);
            MixBlakeQuarter(ref v3, ref v4, ref v9, ref v14,
                            _words[(nuint)_schedule[s + 14u]], _words[(nuint)_schedule[s + 15u]]);
        }

        _state[0u] ^= v0 ^ v8;
        _state[1u] ^= v1 ^ v9;
        _state[2u] ^= v2 ^ v10;
        _state[3u] ^= v3 ^ v11;
        _state[4u] ^= v4 ^ v12;
        _state[5u] ^= v5 ^ v13;
        _state[6u] ^= v6 ^ v14;
        _state[7u] ^= v7 ^ v15;

        for (nuint i = 0u; i < 16u; i++)
            _words[i] = 0u;
    }

    /// G of RFC 7693 §3.1.
    static void MixBlakeQuarter(ref ulong a, ref ulong b, ref ulong c, ref ulong d, ulong x,
                                ulong y)
    {
        a = a + b + x;
        d = RotateRight(d ^ a, 32);
        c = c + d;
        b = RotateRight(b ^ c, 24);
        a = a + b + y;
        d = RotateRight(d ^ a, 16);
        c = c + d;
        b = RotateRight(b ^ c, 63);
    }
}
