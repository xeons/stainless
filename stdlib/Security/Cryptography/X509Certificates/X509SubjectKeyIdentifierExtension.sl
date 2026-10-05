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

/// A short name for the subject's key: RFC 5280 §4.2.1.2, `2.5.29.14`.
///
/// A chain uses it to tell apart two issuers with the same name, matching it
/// against the authority key identifier of what they issued.
public sealed class X509SubjectKeyIdentifierExtension : X509Extension
{
    private byte[] _subjectKeyIdentifier;

    /// The extension naming the key `subjectKeyIdentifier`.
    ///
    /// @param subjectKeyIdentifier  the identifier's bytes
    /// @param critical              whether it is critical, which RFC 5280 forbids
    public X509SubjectKeyIdentifierExtension(ReadOnlySpan<byte> subjectKeyIdentifier,
                                             bool critical)
        : this(EncodeSubjectKeyIdentifier(subjectKeyIdentifier), critical,
               subjectKeyIdentifier.ToArray())
    {
    }

    /// The extension naming `key` as .NET and RFC 5280's first method do:
    /// the SHA-1 of the key's `BIT STRING` contents.
    ///
    /// @param key       the subject's key
    /// @param critical  whether it is critical, which RFC 5280 forbids
    public X509SubjectKeyIdentifierExtension(PublicKey key, bool critical)
        : this(Sha1.HashData(key.EncodedKeyValue), critical)
    {
    }

    private X509SubjectKeyIdentifierExtension(ReadOnlySpan<byte> rawData, bool critical,
                                              byte[] subjectKeyIdentifier)
    {
        _subjectKeyIdentifier = subjectKeyIdentifier;
        base("2.5.29.14", rawData, critical);
    }

    /// The identifier in upper-case hexadecimal, as .NET gives it.
    public String SubjectKeyIdentifier => FormatHexadecimalUpper(_subjectKeyIdentifier);

    /// The identifier's bytes.
    public byte[] SubjectKeyIdentifierBytes => _subjectKeyIdentifier;

    private static byte[] EncodeSubjectKeyIdentifier(ReadOnlySpan<byte> identifier)
    {
        var writer = new AsnWriter();
        writer.WriteOctetString(identifier);
        return writer.Encode();
    }

    internal static Result<X509SubjectKeyIdentifierExtension, CryptoError> DecodeExtension(
        ReadOnlySpan<byte> rawData, bool critical)
    {
        var document = new AsnReader(rawData, AsnEncodingRules.Der);
        ReadOnlySpan<byte> identifier = try ConvertAsnResult(document.ReadOctetString());
        if (document.VerifyEndOfData() != AsnError.None)
            return Fail(CryptoError.Encoding);
        return Ok(new X509SubjectKeyIdentifierExtension(rawData, critical, identifier.ToArray()));
    }
}
