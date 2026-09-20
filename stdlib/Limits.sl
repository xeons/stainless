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

/// What each number type holds.
///
/// A primitive is not a class, so there is nowhere to hang a `MaxValue` on and
/// these are named for their type instead -- `Limits.MaxLong`, not
/// `long.MaxValue`. That is the same reason `Text.FromInteger` is a function
/// rather than a method on `int`.
///
/// **A limit is worth naming because the literal is not checkable.** A reader
/// can see that `MaxInt` is right; nobody can see that `2147483647` is, and a
/// digit dropped from it still compiles.
///
/// `MinNInt` and the two `NUInt` limits depend on the target, so they are the
/// only ones written twice.
module Standard.Limits;

// ------------------------------------------------------------------- signed

public const sbyte MinSByte = -128;
public const sbyte MaxSByte = 127;

public const short MinShort = -32768;
public const short MaxShort = 32767;

public const int MinInt = -2147483648;
public const int MaxInt = 2147483647;

/// The magnitude of this one is not itself a `long` -- `9223372036854775808`
/// alone is a `ulong`. The minus is read as part of the literal rather than as
/// an operator on it, which is what makes the smallest long writable at all.
public const long MinLong = -9223372036854775808;
public const long MaxLong = 9223372036854775807;

// ----------------------------------------------------------------- unsigned

/// Zero, and named rather than assumed: a loop written against `MinUInt`
/// survives the day its type changes to a signed one.
public const byte MinByte = 0;
public const byte MaxByte = 255;

public const ushort MinUShort = 0;
public const ushort MaxUShort = 65535;

public const uint MinUInt = 0;
public const uint MaxUInt = 4294967295;

public const ulong MinULong = 0;
public const ulong MaxULong = 18446744073709551615;

// ------------------------------------------------------------ pointer width

#if X86
public const nint MinNInt = -2147483648;
public const nint MaxNInt = 2147483647;
public const nuint MinNUInt = 0;
public const nuint MaxNUInt = 4294967295;
#else
public const nint MinNInt = -9223372036854775808;
public const nint MaxNInt = 9223372036854775807;
public const nuint MinNUInt = 0;
public const nuint MaxNUInt = 18446744073709551615;
#endif

// ------------------------------------------------------------------ floating

/// The largest finite value. Anything above it is the infinity that `Math`'s
/// `IsFinite` reports on, not an error.
public const float MaxFloat = 3.4028234663852886e+38f;
public const float MinFloat = -3.4028234663852886e+38f;

/// The smallest positive value that is not denormal. Below this a `float`
/// still holds numbers, with fewer bits of precision at each step down.
public const float SmallestFloat = 1.1754943508222875e-38f;

public const double MaxDouble = 1.7976931348623157e+308;
public const double MinDouble = -1.7976931348623157e+308;

/// The smallest positive double that is not denormal.
public const double SmallestDouble = 2.2250738585072014e-308;
