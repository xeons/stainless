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

/// An odd modulus, and what Montgomery multiplication by it needs.
///
/// A number `a` is held in Montgomery form as `a * R mod m`, where `R` is
/// `2^(64 * Count)`.
struct EcModulus
{
    public EcElement Value;

    /// `R mod m`, which is one in Montgomery form.
    public EcElement One;

    /// `R^2 mod m`. Multiplying by it takes a number into Montgomery form.
    public EcElement RSquared;

    /// `-m^-1 mod 2^64`.
    public ulong Inverse;

    /// How many limbs a number takes: four or six.
    public nuint Count;
}
