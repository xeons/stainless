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

/// Pseudo-random numbers.
///
/// A class rather than a set of free functions, and deliberately: the state has
/// to live somewhere, the language has no mutable global to put it in, and a
/// hidden one shared by every caller is what makes a program impossible to
/// reproduce. A `Random` you made is a `Random` you can seed and replay.
///
/// **This is not cryptographic.** xoshiro256** is fast and well-distributed,
/// and its entire future is computable from 256 bits of state -- which is what
/// makes a seeded run reproducible and what makes it unfit for a key, a token
/// or a password. `FillSecureBytes` from the platform is what that needs; `sl_random_bytes`
/// is what this seeds from and is right there.
module Standard.Random;

extern "C"
{
    void sl_fail(byte* message);

    long sl_random_seed();
    bool sl_random_bytes(byte* buffer, nuint length);
}

/// xoshiro256**, which is the current answer for a general-purpose generator:
/// four words of state, no multiply in the step, and it passes the test suites
/// that killed the older ones.
public class Random
{
    ulong _a;
    ulong _b;
    ulong _c;
    ulong _d;

    /// A generator seeded from a number you chose. The same seed gives the
    /// same sequence, on every platform and every run -- which is the point.
    public Random(long seed) => SeedState((ulong)seed);

    /// A generator seeded by the operating system, so two runs differ.
    ///
    /// Aborts if the platform will not supply any entropy at all, which is a
    /// broken machine rather than an outcome a caller can plan around -- and a
    /// constructor has nowhere to report one anyway (§2.9). Where that has to
    /// be survivable, `Random.FillSecureBytes` says whether it managed, and
    /// `new Random(seed)` takes the number it produced.
    ///
    /// @see Random.FillSecureBytes
    /// @seealso Random.GenerateSeed
    public Random() => SeedState((ulong)sl_random_seed());

    /// SplitMix64 spreads one word into four.
    ///
    /// Seeding the state directly from the seed would start a small seed in a
    /// corner of the state space, and xoshiro takes a while to escape one --
    /// `new Random(1)` would produce a poor first few numbers. This is the
    /// remedy its authors specify.
    void SeedState(ulong seed)
    {
        _a = MixSplit(&seed);
        _b = MixSplit(&seed);
        _c = MixSplit(&seed);
        _d = MixSplit(&seed);

        // All-zero state is the one xoshiro cannot leave.
        if ((_a | _b | _c | _d) == 0u)
            _a = 0x9E3779B97F4A7C15u;
    }

    ulong MixSplit(ulong* state)
    {
        *state = *state + 0x9E3779B97F4A7C15u;

        ulong z = *state;
        z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9u;
        z = (z ^ (z >> 27)) * 0x94D049BB133111EBu;
        return z ^ (z >> 31);
    }

    ulong RotateBitsLeft(ulong value, uint by)
    {
        return (value << by) | (value >> (64u - by));
    }

    /// The next 64 bits. Every other method here is built on this one.
    public ulong NextULong()
    {
        ulong result = RotateBitsLeft(_b * 5u, 7u) * 9u;
        ulong t = _b << 17;

        _c = _c ^ _a;
        _d = _d ^ _b;
        _b = _b ^ _c;
        _a = _a ^ _d;
        _c = _c ^ t;
        _d = RotateBitsLeft(_d, 45u);

        return result;
    }

    /// The next 64 bits read as signed, so negative half the time. Reach for
    /// `NextBelow` when a range is what is wanted.
    ///
    /// @see Random.NextBelow
    public long NextLong() => (long)NextULong();

    /// A number in `[0, limit)`. Aborts on a limit of zero, which names an
    /// empty range and has no answer.
    ///
    /// Rejection rather than a modulo: `NextULong() % limit` is biased toward
    /// the low end whenever the limit does not divide 2^64, and the bias is
    /// large exactly when the limit is large. The loop discards the short tail
    /// instead, and runs more than once with probability below one half.
    public ulong NextBelow(ulong limit)
    {
        if (limit == 0u)
            sl_fail("Random.NextBelow: the limit must be more than zero");

        ulong ceiling = 18446744073709551615u - (18446744073709551615u % limit) - 1u;

        ulong drawn = NextULong();
        while (drawn > ceiling)
            drawn = NextULong();

        return drawn % limit;
    }

    /// A number in `[low, high)`. Aborts when the range is empty.
    public long NextBetween(long low, long high)
    {
        if (high <= low)
            sl_fail("Random.NextBetween: the range is empty");
        return low + (long)NextBelow((ulong)(high - low));
    }

    /// A number in `[0, limit)`, for the common case of an `int`.
    public int NextInt(int limit) => (int)NextBetween(0, (long)limit);

    /// True about half the time.
    public bool NextBool() => (NextULong() >> 63) != 0u;

    /// A double in `[0, 1)`.
    ///
    /// The top 53 bits, which is exactly the precision a double has: taking
    /// fewer would leave gaps, and taking more would round some draws up to
    /// 1.0 and break the half-open range.
    public double NextDouble()
    {
        return (double)(NextULong() >> 11) * 0.00000000000000011102230246251565;
    }

    /// Fills an array with random bytes.
    public void NextBytes(byte[] buffer)
    {
        nuint at = 0u;
        while (at < buffer.Length)
        {
            ulong word = NextULong();
            for (nuint i = 0u; i < 8u && at < buffer.Length; i++)
            {
                buffer[at] = (byte)(word >> (uint)(i * 8u));
                at++;
            }
        }
    }

    /// Reorders an array in place, every ordering equally likely.
    ///
    /// Fisher-Yates, walking down: element i is swapped with a uniformly
    /// chosen element at or below it. Walking up, or choosing from the whole
    /// array each time, is the classic wrong version -- it produces n^n equally
    /// likely paths over n! orderings, which cannot come out even.
    public void Shuffle(long[] items)
    {
        if (items.Length < 2u)
            return;

        for (nuint i = items.Length - 1u; i > 0u; i--)
        {
            nuint j = (nuint)NextBelow((ulong)i + 1u);
            long swap = items[i];
            items[i] = items[j];
            items[j] = swap;
        }
    }
}

/// Bytes straight from the operating system's cryptographic source, which is
/// what a key or a token wants. Reports whether it managed; a false is not a
/// reason to fall back on the clock.
///
/// @see GenerateSeed
public bool FillSecureBytes(byte[] buffer)
{
    if (buffer.Length == 0u)
        return true;
    return sl_random_bytes(&buffer[0], buffer.Length);
}

/// One unpredictable 64-bit value from the platform, for seeding something
/// else deliberately. Aborts if the platform supplies none; `FillSecureBytes` is the
/// form that reports instead.
///
/// @see FillSecureBytes
public long GenerateSeed() => sl_random_seed();
