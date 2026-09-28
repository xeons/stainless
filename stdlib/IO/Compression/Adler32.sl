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

module Standard.IO.Compression;

// ---------------------------------------------------------------- Adler-32

/// Adler-32, the checksum a zlib stream ends with (RFC 1950 §8.2).
///
///     uint check = Adler32.Compute("Wikipedia"u8);    // 0x11E60398
///
/// Two sums modulo 65521, the second a running total of the first. Weaker
/// than CRC-32 on short inputs and faster everywhere, which is why zlib
/// chose it.
public sealed class Adler32
{
    const uint Modulus = 65521;

    // The most bytes that can be summed before the second sum could overflow
    // 32 bits, so the modulo is taken once per run of this many.
    const nuint RunLength = 5552;

    uint _low;
    uint _high;

    /// A checksum of nothing, ready to be appended to.
    public Adler32()
    {
        _low = 1;
        _high = 0;
    }

    /// The checksum of everything appended since construction or `Reset`.
    public uint Value => (_high << 16) | _low;

    /// The checksum of `data` on its own.
    public static uint Compute(ReadOnlySpan<byte> data)
    {
        var adler = new Adler32();
        adler.Append(data);
        return adler.Value;
    }

    /// Adds `data` to what has been checked so far.
    public void Append(ReadOnlySpan<byte> data)
    {
        uint low = _low;
        uint high = _high;
        nuint at = 0;
        nuint count = data.Length;
        while (at < count)
        {
            nuint run = count - at;
            if (run > RunLength)
                run = RunLength;

            nuint stop = at + run;
            for (nuint i = at; i < stop; i++)
            {
                low += (uint)data[i];
                high += low;
            }

            low %= Modulus;
            high %= Modulus;
            at = stop;
        }

        _low = low;
        _high = high;
    }

    /// Forgets everything appended, as though the object were new.
    public void Reset()
    {
        _low = 1;
        _high = 0;
    }
}
