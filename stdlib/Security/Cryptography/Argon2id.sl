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

/// Argon2id (RFC 9106), version 0x13: the password hash RFC 9106 recommends,
/// and the one to choose where no format decides.
///
/// ```csharp
/// var key = try Argon2id.DeriveKey(password, salt, 3u, 65536u, 4u, 32u);
/// ```
///
/// **Memory and passes are the cost.** `memoryKiB` is what each guess has to
/// hold, `iterations` how many times it is walked. RFC 9106 §4 gives two
/// starting points: 2 GiB and one pass where the memory can be spared, and
/// 64 MiB and three passes where it cannot. Raise memory before passes.
///
/// **Half of it is data-independent and half is not, and that is the design.**
/// The first half of the first pass chooses which blocks to mix from a counter,
/// as Argon2i does, so a cache-timing attacker watching it learns nothing
/// about the password. Everything after chooses them from the data, as Argon2d
/// does, which is what makes a trade of memory for time expensive and is also
/// a timing channel in principle. That second half is inherent in Argon2id.
///
/// **The lanes are computed one after another.** `parallelism` is part of the
/// function, so it changes the answer and has to match whatever else computes
/// it, but here it buys no speed.
///
/// @see Blake2b
/// @see Scrypt
public static class Argon2id
{
    /// The most memory a derivation may ask for: 4 GiB. Parameters read from
    /// a stored hash are input like any other, and this bounds what one can
    /// make a call allocate.
    ///
    /// @value 2^22 KiB.
    public const nuint MaxMemoryKiB = 4194304u;

    /// The most work a derivation may ask for, as `iterations` * `memoryKiB`:
    /// 256 GiB of blocks filled, which is minutes. RFC 9106's two settings
    /// are 2^21 and 3 * 2^16. It bounds the time one stored hash can make a
    /// call take, as `MaxMemoryKiB` bounds the memory, and so bounds
    /// `iterations` too.
    ///
    /// @value 2^28 KiB.
    public const ulong MaxWorkKiB = 0x10000000u;

    /// The longest output. RFC 9106 allows 2^32 - 1 bytes, but a password hash
    /// or a key wants tens, and the whole output is held in memory; a caller
    /// that needs more expands this with `Hkdf`.
    ///
    /// @value 2^20 bytes.
    public const nuint MaxLength = 1048576u;

    /// The shortest salt. RFC 9106 recommends sixteen random bytes.
    ///
    /// @value eight bytes.
    public const nuint MinSaltSize = 8u;

    /// `length` bytes derived from `password` and `salt`.
    ///
    /// @param password     the secret to stretch
    /// @param salt         at least `MinSaltSize` random bytes, sixteen recommended,
    ///                     stored beside the result
    /// @param iterations   t, how many passes over the memory
    /// @param memoryKiB    m, how many kibibytes to fill; at least eight per lane
    /// @param parallelism  p, how many lanes, computed one after another here
    /// @param length       how many bytes to derive, from four to `MaxLength`
    /// @failure CryptoError.Parameter  a parameter is outside RFC 9106 §3.1, `salt` is shorter
    ///                                 than `MinSaltSize`, `memoryKiB` is past
    ///                                 `MaxMemoryKiB`, `iterations` * `memoryKiB` is past
    ///                                 `MaxWorkKiB`, or `length` is past `MaxLength`
    public static Result<byte[], CryptoError> DeriveKey(ReadOnlySpan<byte> password,
                                                        ReadOnlySpan<byte> salt, nuint iterations,
                                                        nuint memoryKiB, nuint parallelism,
                                                        nuint length) =>
        DeriveKey(password, salt, iterations, memoryKiB, parallelism, length, new byte[0u],
                  new byte[0u]);

    /// `length` bytes derived from `password` and `salt`, bound to a secret
    /// kept apart from the stored hashes and to associated data.
    ///
    /// `secret` is a pepper: a key the server holds outside the database, so
    /// that a stolen table of hashes cannot be attacked without it as well.
    ///
    /// @param password        the secret to stretch
    /// @param salt            at least `MinSaltSize` random bytes, stored beside the result
    /// @param iterations      t, how many passes over the memory
    /// @param memoryKiB       m, how many kibibytes to fill; at least eight per lane
    /// @param parallelism     p, how many lanes, computed one after another here
    /// @param length          how many bytes to derive, from four to `MaxLength`
    /// @param secret          K, a key held apart from the hashes; empty for none
    /// @param associatedData  X, bound into the result and not secret; empty for none
    /// @failure CryptoError.Parameter  a parameter is outside RFC 9106 §3.1, `salt` is shorter
    ///                                 than `MinSaltSize`, `memoryKiB` is past
    ///                                 `MaxMemoryKiB`, `iterations` * `memoryKiB` is past
    ///                                 `MaxWorkKiB`, or `length` is past `MaxLength`
    public static Result<byte[], CryptoError> DeriveKey(ReadOnlySpan<byte> password,
                                                        ReadOnlySpan<byte> salt, nuint iterations,
                                                        nuint memoryKiB, nuint parallelism,
                                                        nuint length, ReadOnlySpan<byte> secret,
                                                        ReadOnlySpan<byte> associatedData)
    {
        if (!AreParametersValid(password, salt, iterations, memoryKiB, parallelism, length, secret,
                                associatedData))
            return Fail(CryptoError.Parameter);

        nuint lanes = parallelism;
        nuint laneLength = memoryKiB / (4u * lanes) * 4u;
        nuint segmentLength = laneLength / 4u;
        nuint blockCount = laneLength * lanes;

        byte[] seed = new byte[72u];
        byte[] initial = ComputeInitialHash(password, salt, iterations, memoryKiB, parallelism,
                                            length, secret, associatedData);
        for (nuint i = 0u; i < 64u; i++)
            seed[i] = initial[i];
        CryptographicOperations.ZeroMemory(initial);

        ulong[] memory = new ulong[blockCount * 128u];
        for (nuint lane = 0u; lane < lanes; lane++)
        {
            WriteLittleWord(seed, 68u, (uint)lane);
            for (nuint column = 0u; column < 2u; column++)
            {
                WriteLittleWord(seed, 64u, (uint)column);
                byte[] block = HashVariably(seed, 1024u);
                nuint at = (lane * laneLength + column) * 128u;
                for (nuint k = 0u; k < 128u; k++)
                    memory[at + k] = ReadLittleDoubleWord(block, k * 8u);
                CryptographicOperations.ZeroMemory(block);
            }
        }
        CryptographicOperations.ZeroMemory(seed);

        var filler = new Argon2Filler(memory, lanes, laneLength, segmentLength, blockCount,
                                      iterations);
        for (nuint pass = 0u; pass < iterations; pass++)
        {
            for (nuint slice = 0u; slice < 4u; slice++)
            {
                for (nuint lane = 0u; lane < lanes; lane++)
                    filler.FillSegment(pass, slice, lane);
            }
        }

        byte[] final = new byte[1024u];
        for (nuint k = 0u; k < 128u; k++)
        {
            ulong word = 0u;
            for (nuint lane = 0u; lane < lanes; lane++)
                word ^= memory[(lane * laneLength + laneLength - 1u) * 128u + k];
            WriteLittleDoubleWord(final, k * 8u, word);
        }

        CryptographicOperations.ZeroMemory(memory);

        byte[] tag = HashVariably(final, length);
        CryptographicOperations.ZeroMemory(final);
        return Ok(tag);
    }

    /// The limits of RFC 9106 section 3.1, `MinSaltSize`, `MaxMemoryKiB`, `MaxWorkKiB`
    /// and `MaxLength`.
    static bool AreParametersValid(ReadOnlySpan<byte> password, ReadOnlySpan<byte> salt,
                                   nuint iterations, nuint memoryKiB, nuint parallelism,
                                   nuint length, ReadOnlySpan<byte> secret,
                                   ReadOnlySpan<byte> associatedData)
    {
        if (parallelism == 0u || (ulong)parallelism > 0xFFFFFFu)
            return false;
        if (length < 4u || length > MaxLength)
            return false;
        if (iterations == 0u || (ulong)iterations > 0xFFFFFFFFu)
            return false;
        if (memoryKiB > MaxMemoryKiB || (ulong)memoryKiB < 8u * (ulong)parallelism)
            return false;
        if ((ulong)iterations * (ulong)memoryKiB > MaxWorkKiB)
            return false;
        if (salt.Length < MinSaltSize)
            return false;

        ulong most = 0xFFFFFFFFu;
        return (ulong)password.Length <= most && (ulong)salt.Length <= most &&
               (ulong)secret.Length <= most && (ulong)associatedData.Length <= most;
    }

    /// H0 of RFC 9106 §3.2: BLAKE2b-512 over every parameter and input, each
    /// input preceded by its length.
    static byte[] ComputeInitialHash(ReadOnlySpan<byte> password, ReadOnlySpan<byte> salt,
                                     nuint iterations, nuint memoryKiB, nuint parallelism,
                                     nuint length, ReadOnlySpan<byte> secret,
                                     ReadOnlySpan<byte> associatedData)
    {
        var hash = new Blake2b();
        byte[] word = new byte[4u];

        uint[] fields = [(uint)parallelism, (uint)length, (uint)memoryKiB, (uint)iterations,
                         0x13u, 2u];
        for (nuint i = 0u; i < fields.Length; i++)
        {
            WriteLittleWord(word, 0u, fields[i]);
            hash.AppendData(word);
        }

        WriteLittleWord(word, 0u, (uint)password.Length);
        hash.AppendData(word);
        hash.AppendData(password);
        WriteLittleWord(word, 0u, (uint)salt.Length);
        hash.AppendData(word);
        hash.AppendData(salt);
        WriteLittleWord(word, 0u, (uint)secret.Length);
        hash.AppendData(word);
        hash.AppendData(secret);
        WriteLittleWord(word, 0u, (uint)associatedData.Length);
        hash.AppendData(word);
        hash.AppendData(associatedData);

        return hash.GetHashAndReset();
    }

    /// H' of RFC 9106 §3.3: BLAKE2b stretched to `length` bytes by chaining
    /// 64-byte digests and keeping half of each.
    static byte[] HashVariably(ReadOnlySpan<byte> input, nuint length)
    {
        byte[] prefix = new byte[4u];
        WriteLittleWord(prefix, 0u, (uint)length);

        if (length <= 64u)
        {
            var brief = new Blake2b(new byte[0u], length);
            brief.AppendData(prefix);
            brief.AppendData(input);
            return brief.GetHashAndReset();
        }

        byte[] output = new byte[length];
        var hash = new Blake2b();
        hash.AppendData(prefix);
        hash.AppendData(input);
        byte[] link = hash.GetHashAndReset();

        nuint whole = (length + 31u) / 32u - 2u;
        for (nuint i = 0u; i < whole; i++)
        {
            if (i > 0u)
                link = hash.ComputeHash(link);
            for (nuint k = 0u; k < 32u; k++)
                output[i * 32u + k] = link[k];
        }

        nuint rest = length - 32u * whole;
        var last = new Blake2b(new byte[0u], rest);
        last.AppendData(link);
        byte[] tail = last.GetHashAndReset();
        for (nuint k = 0u; k < rest; k++)
            output[32u * whole + k] = tail[k];

        CryptographicOperations.ZeroMemory(link);
        return output;
    }
}

/// The memory of one Argon2id derivation, and the scratch blocks its filling
/// needs, so that nothing is allocated per block.
class Argon2Filler
{
    private ulong[] _memory;
    private nuint _lanes;
    private nuint _laneLength;
    private nuint _segmentLength;
    private nuint _blockCount;
    private nuint _iterations;

    private ulong[] _mixed;
    private ulong[] _kept;
    private ulong[] _input;
    private ulong[] _addresses;
    private ulong[] _zero;

    Argon2Filler(ulong[] memory, nuint lanes, nuint laneLength, nuint segmentLength,
                 nuint blockCount, nuint iterations)
    {
        _memory = memory;
        _lanes = lanes;
        _laneLength = laneLength;
        _segmentLength = segmentLength;
        _blockCount = blockCount;
        _iterations = iterations;
        _mixed = new ulong[128u];
        _kept = new ulong[128u];
        _input = new ulong[128u];
        _addresses = new ulong[128u];
        _zero = new ulong[128u];
    }

    ~Argon2Filler()
    {
        CryptographicOperations.ZeroMemory(_mixed);
        CryptographicOperations.ZeroMemory(_kept);
    }

    /// One segment of RFC 9106 §3.4: a quarter of one lane in one pass.
    void FillSegment(nuint pass, nuint slice, nuint lane)
    {
        bool isIndependent = pass == 0u && slice < 2u;
        if (isIndependent)
        {
            for (nuint k = 0u; k < 128u; k++)
                _input[k] = 0u;
            _input[0u] = (ulong)pass;
            _input[1u] = (ulong)lane;
            _input[2u] = (ulong)slice;
            _input[3u] = (ulong)_blockCount;
            _input[4u] = (ulong)_iterations;
            _input[5u] = 2u;
        }

        // The first two blocks of a lane were made from H0.
        nuint start = 0u;
        if (pass == 0u && slice == 0u)
        {
            start = 2u;
            if (isIndependent)
                ComputeNextAddresses();
        }

        for (nuint index = start; index < _segmentLength; index++)
        {
            nuint current = lane * _laneLength + slice * _segmentLength + index;
            nuint previous = current - 1u;
            if (current % _laneLength == 0u)
                previous = current + _laneLength - 1u;

            ulong random;
            if (isIndependent)
            {
                if (index % 128u == 0u)
                    ComputeNextAddresses();
                random = _addresses[index % 128u];
            }
            else
            {
                random = _memory[previous * 128u];
            }

            nuint referenceLane = (nuint)((random >> 32) % (ulong)_lanes);
            if (pass == 0u && slice == 0u)
                referenceLane = lane;

            nuint reference = ComputeReferenceIndex(pass, slice, index, random & 0xFFFFFFFFu,
                                                    referenceLane == lane);
            CompressInto(_memory, previous * 128u, _memory,
                         (referenceLane * _laneLength + reference) * 128u, _memory,
                         current * 128u, pass > 0u);
        }
    }

    /// Which block of the reference lane to mix in: a position drawn from the
    /// blocks already made, skewed towards the recent ones (RFC 9106 §3.4.1.2).
    nuint ComputeReferenceIndex(nuint pass, nuint slice, nuint index, ulong random, bool isSameLane)
    {
        ulong area;
        if (pass == 0u)
        {
            if (slice == 0u)
            {
                area = (ulong)index - 1u;
            }
            else if (isSameLane)
            {
                area = (ulong)(slice * _segmentLength + index) - 1u;
            }
            else
            {
                area = (ulong)(slice * _segmentLength);
                if (index == 0u)
                    area--;
            }
        }
        else if (isSameLane)
        {
            area = (ulong)(_laneLength - _segmentLength + index) - 1u;
        }
        else
        {
            area = (ulong)(_laneLength - _segmentLength);
            if (index == 0u)
                area--;
        }

        ulong relative = (random * random) >> 32;
        relative = area - 1u - ((area * relative) >> 32);

        ulong first = 0u;
        if (pass > 0u && slice < 3u)
            first = (ulong)((slice + 1u) * _segmentLength);

        return (nuint)((first + relative) % (ulong)_laneLength);
    }

    /// The next 128 pseudo-random words of the data-independent half:
    /// G(0, G(0, input)), with the input's counter stepped first.
    void ComputeNextAddresses()
    {
        _input[6u]++;
        CompressInto(_zero, 0u, _input, 0u, _addresses, 0u, false);
        CompressInto(_zero, 0u, _addresses, 0u, _addresses, 0u, false);
    }

    /// G of RFC 9106 §3.5 over the blocks of `x` and `y` at the given word
    /// offsets, written into `into`, or exclusive-ored into it when
    /// `isAccumulating` — which every pass after the first is.
    void CompressInto(ulong[] x, nuint xAt, ulong[] y, nuint yAt, ulong[] into, nuint intoAt,
                      bool isAccumulating)
    {
        for (nuint k = 0u; k < 128u; k++)
        {
            _mixed[k] = x[xAt + k] ^ y[yAt + k];
            _kept[k] = _mixed[k];
        }

        if (isAccumulating)
        {
            for (nuint k = 0u; k < 128u; k++)
                _kept[k] ^= into[intoAt + k];
        }

        for (nuint i = 0u; i < 8u; i++)
            PermuteArgon(_mixed, i * 16u, 2u);
        for (nuint i = 0u; i < 8u; i++)
            PermuteArgon(_mixed, i * 2u, 16u);

        for (nuint k = 0u; k < 128u; k++)
            into[intoAt + k] = _kept[k] ^ _mixed[k];
    }

    /// P of RFC 9106 §3.6 on sixteen words of `block`, taken in pairs: word
    /// `k` is at `first + (k / 2) · pairStride + k % 2`. A stride of two is a
    /// row of the 8×8 matrix of 16-byte registers, and sixteen a column.
    static void PermuteArgon(ulong[] block, nuint first, nuint pairStride)
    {
        nuint a = first;
        nuint b = first + pairStride;
        nuint c = first + 2u * pairStride;
        nuint d = first + 3u * pairStride;
        nuint e = first + 4u * pairStride;
        nuint f = first + 5u * pairStride;
        nuint g = first + 6u * pairStride;
        nuint h = first + 7u * pairStride;

        ulong v0 = block[a];
        ulong v1 = block[a + 1u];
        ulong v2 = block[b];
        ulong v3 = block[b + 1u];
        ulong v4 = block[c];
        ulong v5 = block[c + 1u];
        ulong v6 = block[d];
        ulong v7 = block[d + 1u];
        ulong v8 = block[e];
        ulong v9 = block[e + 1u];
        ulong v10 = block[f];
        ulong v11 = block[f + 1u];
        ulong v12 = block[g];
        ulong v13 = block[g + 1u];
        ulong v14 = block[h];
        ulong v15 = block[h + 1u];

        MixArgonQuarter(ref v0, ref v4, ref v8, ref v12);
        MixArgonQuarter(ref v1, ref v5, ref v9, ref v13);
        MixArgonQuarter(ref v2, ref v6, ref v10, ref v14);
        MixArgonQuarter(ref v3, ref v7, ref v11, ref v15);
        MixArgonQuarter(ref v0, ref v5, ref v10, ref v15);
        MixArgonQuarter(ref v1, ref v6, ref v11, ref v12);
        MixArgonQuarter(ref v2, ref v7, ref v8, ref v13);
        MixArgonQuarter(ref v3, ref v4, ref v9, ref v14);

        block[a] = v0;
        block[a + 1u] = v1;
        block[b] = v2;
        block[b + 1u] = v3;
        block[c] = v4;
        block[c + 1u] = v5;
        block[d] = v6;
        block[d + 1u] = v7;
        block[e] = v8;
        block[e + 1u] = v9;
        block[f] = v10;
        block[f + 1u] = v11;
        block[g] = v12;
        block[g + 1u] = v13;
        block[h] = v14;
        block[h + 1u] = v15;
    }

    /// GB of RFC 9106 §3.6: BLAKE2b's G with each addition carrying twice the
    /// product of the two low halves, which is what makes it cost a multiply.
    static void MixArgonQuarter(ref ulong a, ref ulong b, ref ulong c, ref ulong d)
    {
        a = a + b + 2u * (a & 0xFFFFFFFFu) * (b & 0xFFFFFFFFu);
        d = RotateRight(d ^ a, 32);
        c = c + d + 2u * (c & 0xFFFFFFFFu) * (d & 0xFFFFFFFFu);
        b = RotateRight(b ^ c, 24);
        a = a + b + 2u * (a & 0xFFFFFFFFu) * (b & 0xFFFFFFFFu);
        d = RotateRight(d ^ a, 16);
        c = c + d + 2u * (c & 0xFFFFFFFFu) * (d & 0xFFFFFFFFu);
        b = RotateRight(b ^ c, 63);
    }
}
