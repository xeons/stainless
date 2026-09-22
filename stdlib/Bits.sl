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

/// Counting bits and rotating them.
///
/// These are here because they cannot be written in Stainless as well as the
/// target can do them. `LeadingZeroCount` is one instruction on every machine
/// this compiles for and about ten written out; `PopCount` is one instruction
/// where the target has it and the same arithmetic either way where it does
/// not, chosen per target rather than per author. A rotate written the obvious
/// way -- `(value << by) | (value >> (64 - by))` -- is worse than slow for a
/// count of zero: shifting by the width is undefined, so the answer is zero
/// rather than `value`. What is below is defined for every count.
///
/// The compiler declares the instructions ([Builtins](../src/Stainless.Compiler/Binding/Builtins.cs))
/// and this file declares the same module again to put names on them, which is
/// the ordinary second declaration of §1.2.1 rather than anything special.
///
/// Everything takes and answers `uint` or `ulong`. A count comes back as `int`
/// because it is a small number and arithmetic on it should not be unsigned.
module Standard.Bits;

// ------------------------------------------------------------------ counting

/// How many bits are set.
public int PopCount(uint value) => (int)CountOneBits(value);

/// How many bits are set.
public int PopCount(ulong value) => (int)CountOneBits(value);

/// How many zero bits sit above the highest set bit: 32 for zero, 0 for any
/// value with its top bit set.
public int LeadingZeroCount(uint value) => (int)CountLeadingZeroBits(value, false);

/// How many zero bits sit above the highest set bit: 64 for zero.
public int LeadingZeroCount(ulong value) => (int)CountLeadingZeroBits(value, false);

/// How many zero bits sit below the lowest set bit: 32 for zero, 0 for any
/// odd value.
public int TrailingZeroCount(uint value) => (int)CountTrailingZeroBits(value, false);

/// How many zero bits sit below the lowest set bit: 64 for zero.
public int TrailingZeroCount(ulong value) => (int)CountTrailingZeroBits(value, false);

// ------------------------------------------------------------------ rotating

/// The bits moved left, with what falls off the top arriving at the bottom.
///
/// The count is taken modulo the width, so rotating by 32 or by 64 is the
/// same as rotating by zero, which answers the value unchanged.
public uint RotateLeft(uint value, int by) =>
    FunnelShiftLeft(value, value, (uint)by);

/// The bits moved left, with what falls off the top arriving at the bottom.
public ulong RotateLeft(ulong value, int by) =>
    FunnelShiftLeft(value, value, (ulong)by);

/// The bits moved right, with what falls off the bottom arriving at the top.
public uint RotateRight(uint value, int by) =>
    FunnelShiftRight(value, value, (uint)by);

/// The bits moved right, with what falls off the bottom arriving at the top.
public ulong RotateRight(ulong value, int by) =>
    FunnelShiftRight(value, value, (ulong)by);

// -------------------------------------------------------------- powers of two

/// The position of the highest set bit, which is the floor of the base-2
/// logarithm.
///
/// Zero has no logarithm and no set bit to point at. This answers 0 for it,
/// as .NET does, rather than failing: every caller that reaches here with a
/// zero is sizing something and wants the smallest answer.
public int Log2(uint value) => 31 - LeadingZeroCount(value | 1u);

/// The position of the highest set bit. Zero answers 0.
public int Log2(ulong value) => 63 - LeadingZeroCount(value | 1u);

/// Whether exactly one bit is set, which is what makes a number a power of
/// two. Zero is not one.
public bool IsPowerOfTwo(uint value) => value != 0u && (value & (value - 1u)) == 0u;

/// Whether exactly one bit is set. Zero is not a power of two.
public bool IsPowerOfTwo(ulong value) => value != 0u && (value & (value - 1u)) == 0u;

/// The smallest power of two that is not below `value`.
///
/// Zero and one both answer one. A value above the largest power of two the
/// type holds answers zero, which is the wrap the shift produces and the only
/// answer available -- a caller sizing a table from untrusted input MUST check
/// for it.
public uint RoundUpToPowerOfTwo(uint value)
{
    if (value <= 1u)
        return 1u;
    return 2u << Log2(value - 1u);
}

/// The smallest power of two that is not below `value`. Zero and one both
/// answer one, and a value above the largest power of two answers zero.
public ulong RoundUpToPowerOfTwo(ulong value)
{
    if (value <= 1u)
        return 1u;
    return (ulong)2u << Log2(value - 1u);
}
