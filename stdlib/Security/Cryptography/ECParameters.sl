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

/// An elliptic-curve key as its numbers: .NET's `ECParameters`.
///
/// ```csharp
/// var parameters = new ECParameters(ECCurve.NamedCurves.NistP256,
///                                   new ECPoint(x, y), d);
/// var key = try ECDsa.Create(parameters);
/// ```
///
/// `D` is empty for a public key. `Q`'s coordinates may be empty when `D` is
/// not, and the public point is then computed from `D`; when both are given
/// they MUST agree.
///
/// **Make one with a constructor.** The zero value's arrays are not arrays
/// yet, and reading one aborts.
public struct ECParameters
{
    /// Which curve the key is on.
    public ECCurve Curve;

    /// The public point.
    public ECPoint Q;

    /// The private scalar, big-endian and as wide as the curve's order, or
    /// empty.
    public byte[] D;

    /// A public key.
    ///
    /// @param curve  which curve the point is on
    /// @param q      the point
    public ECParameters(ECCurve curve, ECPoint q)
    {
        Curve = curve;
        Q = q;
        D = new byte[0u];
    }

    /// A private key.
    ///
    /// @param curve  which curve the key is on
    /// @param q      the public point, or one with empty coordinates to have it computed
    /// @param d      the private scalar, big-endian
    public ECParameters(ECCurve curve, ECPoint q, byte[] d)
    {
        Curve = curve;
        Q = q;
        D = d;
    }
}
