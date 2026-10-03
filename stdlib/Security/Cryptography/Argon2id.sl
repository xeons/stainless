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
