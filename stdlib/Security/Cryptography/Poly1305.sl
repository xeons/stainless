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

// ================================================== one-time authentication

/// Poly1305, the one-time authenticator of RFC 8439 §2.5: a 32-byte key and a
/// message give a 16-byte tag.
///
/// ```csharp
/// var tag = try Poly1305.ComputeTag(oneTimeKey, message);
/// ```
///
/// **A key MUST authenticate one message and no more.** Two tags under one key
/// give an attacker enough to forge a third. `ChaCha20Poly1305` derives a
/// fresh key from every nonce, which is how this is meant to be used; a key
/// from anywhere else has to come with the same guarantee.
///
/// The arithmetic is modulo 2^130 - 5 in five 26-bit limbs, so every product
/// fits a `ulong` and nothing needs a 128-bit multiply. It is constant time:
/// the final reduction selects with a mask rather than a branch.
///
/// @see ChaCha20Poly1305
public sealed class Poly1305
{
    /// @value thirty-two bytes: `r`, then `s`.
    public const nuint KeySize = 32u;

    /// @value sixteen bytes.
    public const nuint TagSize = 16u;

    private const ulong LimbMask = 0x3FFFFFFu;
    private const ulong WordMask = 0xFFFFFFFFu;

    private ulong[] _r;
    private ulong[] _pad;
    private ulong[] _accumulator;
    private byte[] _block;
    private nuint _used;

    Poly1305(ReadOnlySpan<byte> key)
    {
        byte[] copy = key.ToArray();

        // The clamp of §2.5.1, applied limb by limb.
        _r = new ulong[5u];
        _r[0u] = (ulong)(ReadLittleWord(copy, 0u) & 0x3FFFFFFu);
        _r[1u] = (ulong)((ReadLittleWord(copy, 3u) >> 2) & 0x3FFFF03u);
        _r[2u] = (ulong)((ReadLittleWord(copy, 6u) >> 4) & 0x3FFC0FFu);
        _r[3u] = (ulong)((ReadLittleWord(copy, 9u) >> 6) & 0x3F03FFFu);
        _r[4u] = (ulong)((ReadLittleWord(copy, 12u) >> 8) & 0x00FFFFFu);

        _pad = new ulong[4u];
        for (nuint i = 0u; i < 4u; i++)
            _pad[i] = (ulong)ReadLittleWord(copy, 16u + i * 4u);

        _accumulator = new ulong[5u];
        _block = new byte[16u];
        _used = 0u;
        CryptographicOperations.ZeroMemory(copy);
    }

    ~Poly1305() => EraseState();

    /// An authenticator under `key`, which must be 32 bytes and MUST NOT
    /// have been used before.
    ///
    /// @failure CryptoError.KeyLength  `key` is not 32 bytes
    public static Result<Poly1305, CryptoError> FromKey(ReadOnlySpan<byte> key)
    {
        if (key.Length != KeySize)
            return Fail(CryptoError.KeyLength);
        return Ok(new Poly1305(key));
    }

    /// The tag of `message` under `key`, with no object to keep.
    ///
    /// @param key      thirty-two bytes, used for this message only
    /// @param message  what to authenticate
    /// @failure CryptoError.KeyLength  `key` is not 32 bytes
    public static Result<byte[], CryptoError> ComputeTag(ReadOnlySpan<byte> key,
                                                         ReadOnlySpan<byte> message)
    {
        if (key.Length != KeySize)
            return Fail(CryptoError.KeyLength);

        var mac = new Poly1305(key);
        mac.AppendData(message);
        return Ok(mac.GetTag());
    }

    /// Adds bytes to what is being authenticated.
    public void AppendData(ReadOnlySpan<byte> data)
    {
        for (nuint i = 0u; i < data.Length; i++)
        {
            _block[_used] = data[i];
            _used++;
            if (_used == 16u)
            {
                ProcessBlock(0x1000000u);
                _used = 0u;
            }
        }
    }

    /// The tag of everything appended. **The key is erased**, so the object
    /// MUST NOT be used afterwards: it has done the one thing it may do.
    public byte[] GetTag()
    {
        if (_used > 0u)
        {
            _block[_used] = 1;
            for (nuint i = _used + 1u; i < 16u; i++)
                _block[i] = 0;
            ProcessBlock(0u);
            _used = 0u;
        }

        ulong h0 = _accumulator[0u];
        ulong h1 = _accumulator[1u];
        ulong h2 = _accumulator[2u];
        ulong h3 = _accumulator[3u];
        ulong h4 = _accumulator[4u];

        ulong carry = h1 >> 26;
        h1 &= LimbMask;
        h2 += carry;
        carry = h2 >> 26;
        h2 &= LimbMask;
        h3 += carry;
        carry = h3 >> 26;
        h3 &= LimbMask;
        h4 += carry;
        carry = h4 >> 26;
        h4 &= LimbMask;
        h0 += carry * 5u;
        carry = h0 >> 26;
        h0 &= LimbMask;
        h1 += carry;

        // h + 5 - 2^130, which is h - p, and is the answer when it is not
        // negative. The choice is a mask, opaque so that it stays one.
        ulong g0 = h0 + 5u;
        carry = g0 >> 26;
        g0 &= LimbMask;
        ulong g1 = h1 + carry;
        carry = g1 >> 26;
        g1 &= LimbMask;
        ulong g2 = h2 + carry;
        carry = g2 >> 26;
        g2 &= LimbMask;
        ulong g3 = h3 + carry;
        carry = g3 >> 26;
        g3 &= LimbMask;
        ulong g4 = h4 + carry - 0x4000000u;

        ulong keep = OpaqueCopy((g4 >> 63) - 1u);
        ulong discard = ~keep;
        h0 = (h0 & discard) | (g0 & keep);
        h1 = (h1 & discard) | (g1 & keep);
        h2 = (h2 & discard) | (g2 & keep);
        h3 = (h3 & discard) | (g3 & keep);
        h4 = (h4 & discard) | (g4 & keep);

        ulong w0 = (h0 | (h1 << 26)) & WordMask;
        ulong w1 = ((h1 >> 6) | (h2 << 20)) & WordMask;
        ulong w2 = ((h2 >> 12) | (h3 << 14)) & WordMask;
        ulong w3 = ((h3 >> 18) | (h4 << 8)) & WordMask;

        // Adding s is modulo 2^128, so the last carry falls off.
        byte[] tag = new byte[TagSize];
        ulong sum = w0 + _pad[0u];
        WriteLittleWord(tag, 0u, (uint)(sum & WordMask));
        sum = w1 + _pad[1u] + (sum >> 32);
        WriteLittleWord(tag, 4u, (uint)(sum & WordMask));
        sum = w2 + _pad[2u] + (sum >> 32);
        WriteLittleWord(tag, 8u, (uint)(sum & WordMask));
        sum = w3 + _pad[3u] + (sum >> 32);
        WriteLittleWord(tag, 12u, (uint)(sum & WordMask));

        EraseState();
        return tag;
    }

    /// The key, the accumulator and the pending block overwritten.
    void EraseState()
    {
        CryptographicOperations.ZeroMemory(_r);
        CryptographicOperations.ZeroMemory(_pad);
        CryptographicOperations.ZeroMemory(_accumulator);
        CryptographicOperations.ZeroMemory(_block);
    }

    /// `_block` added to the accumulator, which is then multiplied by `r`.
    /// `highBit` is the 2^128 of a whole block, and zero for the last, short
    /// one, whose terminating one byte is already in place.
    void ProcessBlock(ulong highBit)
    {
        ulong r0 = _r[0u];
        ulong r1 = _r[1u];
        ulong r2 = _r[2u];
        ulong r3 = _r[3u];
        ulong r4 = _r[4u];
        ulong s1 = r1 * 5u;
        ulong s2 = r2 * 5u;
        ulong s3 = r3 * 5u;
        ulong s4 = r4 * 5u;

        ulong h0 = _accumulator[0u] + (ulong)(ReadLittleWord(_block, 0u) & 0x3FFFFFFu);
        ulong h1 = _accumulator[1u] + (ulong)((ReadLittleWord(_block, 3u) >> 2) & 0x3FFFFFFu);
        ulong h2 = _accumulator[2u] + (ulong)((ReadLittleWord(_block, 6u) >> 4) & 0x3FFFFFFu);
        ulong h3 = _accumulator[3u] + (ulong)((ReadLittleWord(_block, 9u) >> 6) & 0x3FFFFFFu);
        ulong h4 = _accumulator[4u] + ((ulong)(ReadLittleWord(_block, 12u) >> 8) | highBit);

        ulong d0 = h0 * r0 + h1 * s4 + h2 * s3 + h3 * s2 + h4 * s1;
        ulong d1 = h0 * r1 + h1 * r0 + h2 * s4 + h3 * s3 + h4 * s2;
        ulong d2 = h0 * r2 + h1 * r1 + h2 * r0 + h3 * s4 + h4 * s3;
        ulong d3 = h0 * r3 + h1 * r2 + h2 * r1 + h3 * r0 + h4 * s4;
        ulong d4 = h0 * r4 + h1 * r3 + h2 * r2 + h3 * r1 + h4 * r0;

        ulong carry = d0 >> 26;
        h0 = d0 & LimbMask;
        d1 += carry;
        carry = d1 >> 26;
        h1 = d1 & LimbMask;
        d2 += carry;
        carry = d2 >> 26;
        h2 = d2 & LimbMask;
        d3 += carry;
        carry = d3 >> 26;
        h3 = d3 & LimbMask;
        d4 += carry;
        carry = d4 >> 26;
        h4 = d4 & LimbMask;
        h0 += carry * 5u;
        carry = h0 >> 26;
        h0 &= LimbMask;
        h1 += carry;

        _accumulator[0u] = h0;
        _accumulator[1u] = h1;
        _accumulator[2u] = h2;
        _accumulator[3u] = h3;
        _accumulator[4u] = h4;
    }
}
