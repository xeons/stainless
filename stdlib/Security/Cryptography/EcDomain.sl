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

/// A curve `y^2 = x^3 - 3x + b` of prime order over a prime field: P-256 or
/// P-384, which are the curves FIPS 186-5 and TLS name.
struct EcDomain
{
    /// The prime `p` the coordinates are taken modulo.
    public EcModulus Field;

    /// The group order `n` the scalars are taken modulo.
    public EcModulus Order;

    /// `b`, in Montgomery form modulo `p`.
    public EcElement B;

    /// The base point, with `Z` one.
    public EcProjectivePoint Generator;

    /// How many bytes a coordinate or a scalar takes: 32 or 48.
    public nuint Size;
}
