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

/// How an RSA signature is encoded: PKCS #1 v1.5, or PSS with a salt length.
///
/// .NET's `RSASignaturePadding`, as a value. PSS masks with MGF1 over the same
/// hash that digests the message, which is the only combination .NET offers
/// and the one every protocol uses.
///
/// @see Rsa.SignData
public struct RsaSignaturePadding
{
    /// A salt as long as the hash's digest, which is what `Pss` uses.
    public const int PssSaltLengthIsHashLength = -1;

    /// The longest salt the key leaves room for. Verifying under it accepts
    /// a salt of any length.
    public const int PssSaltLengthMax = -2;

    private RsaSignaturePaddingMode _mode;
    private int _pssSaltLength;

    RsaSignaturePadding(RsaSignaturePaddingMode mode, int pssSaltLength)
    {
        _mode = mode;
        _pssSaltLength = pssSaltLength;
    }

    /// PKCS #1 v1.5.
    public static RsaSignaturePadding Pkcs1 =>
        new RsaSignaturePadding(RsaSignaturePaddingMode.Pkcs1, 0);

    /// PSS with a salt as long as the digest: RFC 8017's recommendation.
    public static RsaSignaturePadding Pss =>
        new RsaSignaturePadding(RsaSignaturePaddingMode.Pss, PssSaltLengthIsHashLength);

    /// Which encoding.
    public RsaSignaturePaddingMode Mode => _mode;

    /// The PSS salt's length in bytes, or one of the two constants. Zero for
    /// PKCS #1 v1.5.
    public int PssSaltLength => _pssSaltLength;

    /// PSS with a salt of `saltLength` bytes.
    ///
    /// @param saltLength  bytes of salt, or `PssSaltLengthIsHashLength`, or
    ///                    `PssSaltLengthMax`
    /// @failure CryptoError.Parameter  `saltLength` is negative and neither constant
    public static Result<RsaSignaturePadding, CryptoError> CreatePss(int saltLength)
    {
        if (saltLength < PssSaltLengthMax)
            return Fail(CryptoError.Parameter);
        return Ok(new RsaSignaturePadding(RsaSignaturePaddingMode.Pss, saltLength));
    }

    public bool Equals(RsaSignaturePadding other) =>
        _mode == other._mode && _pssSaltLength == other._pssSaltLength;

    public static bool operator ==(RsaSignaturePadding left, RsaSignaturePadding right) =>
        left.Equals(right);

    public static bool operator !=(RsaSignaturePadding left, RsaSignaturePadding right) =>
        !left.Equals(right);
}
