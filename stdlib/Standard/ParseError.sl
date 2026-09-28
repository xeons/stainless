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


module Standard;

/// Why text could not be read as a value: what C#'s `FormatException` and
/// `OverflowException` say, as the error of a `Result`.
public enum ParseError
{
    /// There was nothing to read.
    Empty,

    /// Not the shape the value is written in.
    Malformed,

    /// The right shape, and a number in it too large to hold.
    OutOfRange,
}

/// The value of `text` read as decimal digits and nothing else.
Result<int, ParseError> ParseDecimal(String text)
{
    if (text.IsEmpty)
        return Fail(ParseError.Empty);

    long value = 0;
    for (nuint i = 0u; i < text.ByteLength(); i++)
    {
        byte digit = text.GetByteAt(i);
        if (digit < (byte)'0' || digit > (byte)'9')
            return Fail(ParseError.Malformed);

        value = value * 10 + (long)(digit - (byte)'0');
        if (value > 2147483647)
            return Fail(ParseError.OutOfRange);
    }
    return Ok((int)value);
}

/// Folds `value` into a running hash. The same values in the same order give
/// the same hash, and a change to any one changes it.
nuint MixHash(nuint hash, ulong value)
{
    ulong mixed = ((ulong)hash ^ value) * 1099511628211u;
    return (nuint)(mixed ^ (mixed >> 29));
}
