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

module Standard.Security.Cryptography.X509Certificates;

import Standard.Formats.Asn1;
import Standard.Security.Cryptography;

/// Whether the subject is a CA, and how many CAs may follow it: RFC 5280
/// §4.2.1.9, `2.5.29.19`.
///
/// A CA's certificate MUST have this with `CertificateAuthority` set for a
/// chain to pass through it. The path length counts the intermediate CAs
/// that may stand between this one and a leaf.
public sealed class X509BasicConstraintsExtension : X509Extension
{
    private bool _certificateAuthority;
    private bool _hasPathLengthConstraint;
    private int _pathLengthConstraint;

    /// The extension with these values, encoded.
    ///
    /// @param certificateAuthority     whether the subject is a CA
    /// @param hasPathLengthConstraint  whether the path length is limited
    /// @param pathLengthConstraint     the limit, zero or more; ignored when there is none
    /// @param critical                 whether it is critical, which RFC 5280 requires
    ///                                 for a CA
    public X509BasicConstraintsExtension(bool certificateAuthority, bool hasPathLengthConstraint,
                                         int pathLengthConstraint, bool critical)
        : this(EncodeBasicConstraints(certificateAuthority, hasPathLengthConstraint,
                                      pathLengthConstraint),
               critical, certificateAuthority, hasPathLengthConstraint, pathLengthConstraint)
    {
    }

    private X509BasicConstraintsExtension(ReadOnlySpan<byte> rawData, bool critical,
                                          bool certificateAuthority, bool hasPathLengthConstraint,
                                          int pathLengthConstraint)
    {
        _certificateAuthority = certificateAuthority;
        base("2.5.29.19", rawData, critical);
        _hasPathLengthConstraint = hasPathLengthConstraint && pathLengthConstraint >= 0;
        _pathLengthConstraint = _hasPathLengthConstraint ? pathLengthConstraint : 0;
    }

    /// Whether the subject is a CA.
    public bool CertificateAuthority => _certificateAuthority;

    /// Whether the path length is limited.
    public bool HasPathLengthConstraint => _hasPathLengthConstraint;

    /// How many intermediate CAs may follow this one; zero when there is no
    /// limit.
    public int PathLengthConstraint => _pathLengthConstraint;

    private static byte[] EncodeBasicConstraints(bool certificateAuthority,
                                                 bool hasPathLengthConstraint,
                                                 int pathLengthConstraint)
    {
        var writer = new AsnWriter();
        writer.PushSequence();
        if (certificateAuthority)
            writer.WriteBoolean(true);
        if (hasPathLengthConstraint && pathLengthConstraint >= 0)
            writer.WriteInteger((long)pathLengthConstraint);
        writer.PopSequence();
        return writer.Encode();
    }

    /// The extension a certificate holds.
    internal static Result<X509BasicConstraintsExtension, CryptoError> DecodeExtension(
        ReadOnlySpan<byte> rawData, bool critical)
    {
        var document = new AsnReader(rawData, AsnEncodingRules.Der);
        AsnReader sequence = try ConvertAsnResult(document.ReadSequence());
        if (document.VerifyEndOfData() != AsnError.None)
            return Fail(CryptoError.Encoding);

        bool authority = false;
        bool limited = false;
        long limit = 0;
        if (sequence.HasData && try ConvertAsnResult(sequence.PeekTag()) == Asn1Tag.Boolean)
            authority = try ConvertAsnResult(sequence.ReadBoolean());
        if (sequence.HasData)
        {
            limit = try ConvertAsnResult(sequence.ReadInt64());
            if (limit < 0 || limit > 2147483647)
                return Fail(CryptoError.Encoding);
            limited = true;
        }
        if (sequence.VerifyEndOfData() != AsnError.None)
            return Fail(CryptoError.Encoding);

        return Ok(new X509BasicConstraintsExtension(rawData, critical, authority, limited,
                                                    (int)limit));
    }
}
