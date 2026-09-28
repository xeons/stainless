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

/// A point on an elliptic curve, as its two affine coordinates: .NET's
/// `ECPoint`.
///
/// Each coordinate is big-endian and exactly as wide as the curve's field —
/// 32 bytes for P-256, 48 for P-384 — leading zeros included.
///
/// **Make one with its constructor.** The zero value's arrays are not arrays
/// yet, and reading one aborts.
public struct ECPoint
{
    /// The x coordinate.
    public byte[] X;

    /// The y coordinate.
    public byte[] Y;

    /// A point from its coordinates, which are kept rather than copied.
    ///
    /// @param x  the x coordinate, big-endian
    /// @param y  the y coordinate, big-endian
    public ECPoint(byte[] x, byte[] y)
    {
        X = x;
        Y = y;
    }
}
