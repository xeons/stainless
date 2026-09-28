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

/// The numbers of an RSA key, each big-endian and unsigned.
///
/// ```csharp
/// var key = try Rsa.Create(new RsaParameters { Modulus = n, Exponent = e });
/// ```
///
/// .NET's `RSAParameters`. A public key has `Modulus` and `Exponent` and
/// nothing else; a private key has all eight. A number that is absent is an
/// empty array, which is what every field starts as.
///
/// **A class, where .NET's is a struct.** A struct's zero value would hold
/// null arrays, and an array here cannot be asked whether it is null; a class
/// gives every field an empty array to start from.
///
/// `Rsa.ExportParameters` gives `D` as many bytes as `Modulus` and the five
/// CRT values half as many, rounded up, with leading zeros where a value is
/// shorter, as .NET does; `Rsa.Create` takes any length and ignores leading
/// zeros.
///
/// @see Rsa.Create
/// @see Rsa.ExportParameters
public sealed class RsaParameters
{
    /// `n`.
    public byte[] Modulus = new byte[0u];

    /// `e`, the public exponent.
    public byte[] Exponent = new byte[0u];

    /// `d`, the private exponent.
    public byte[] D = new byte[0u];

    /// `p`, the first prime.
    public byte[] P = new byte[0u];

    /// `q`, the second prime.
    public byte[] Q = new byte[0u];

    /// `d mod (p - 1)`.
    public byte[] DP = new byte[0u];

    /// `d mod (q - 1)`.
    public byte[] DQ = new byte[0u];

    /// `q^-1 mod p`.
    public byte[] InverseQ = new byte[0u];
}
