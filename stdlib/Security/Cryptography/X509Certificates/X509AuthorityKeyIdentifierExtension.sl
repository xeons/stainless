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

/// Which key signed the certificate: RFC 5280 §4.2.1.1, `2.5.29.35`.
///
/// A chain building from a certificate with a key identifier here passes
/// over any issuer whose subject key identifier is different, which is what
/// picks the right one of two CAs with the same name.
public sealed class X509AuthorityKeyIdentifierExtension : X509Extension
{
    private Optional<byte[]> _keyIdentifier;
    private Optional<byte[]> _rawIssuer;
    private Optional<byte[]> _serialNumber;

    private X509AuthorityKeyIdentifierExtension(ReadOnlySpan<byte> rawData, bool critical,
                                                Optional<byte[]> keyIdentifier,
                                                Optional<byte[]> rawIssuer,
                                                Optional<byte[]> serialNumber)
    {
        base("2.5.29.35", rawData, critical);
        _keyIdentifier = keyIdentifier;
        _rawIssuer = rawIssuer;
        _serialNumber = serialNumber;
    }

    /// The signing key's identifier, when there is one.
    public Optional<byte[]> KeyIdentifier => _keyIdentifier;

    /// The issuer's issuer as `GeneralNames` in DER, when there is one.
    public Optional<byte[]> RawIssuer => _rawIssuer;

    /// The issuer's serial number, big-endian, when there is one.
    public Optional<byte[]> SerialNumber => _serialNumber;

    /// The extension naming the key `subjectKeyIdentifier`, and nothing else:
    /// what a CA puts in what it issues.
    public static X509AuthorityKeyIdentifierExtension CreateFromSubjectKeyIdentifier(
        ReadOnlySpan<byte> subjectKeyIdentifier)
    {
        var writer = new AsnWriter();
        writer.PushSequence();
        writer.WriteOctetString(subjectKeyIdentifier, CreateContextTag(0, false));
        writer.PopSequence();
        return new X509AuthorityKeyIdentifierExtension(
            writer.Encode(), false, Some(subjectKeyIdentifier.ToArray()), None, None);
    }

    /// The extension a certificate issued by `certificateAuthority` carries.
    ///
    /// @param certificateAuthority    the issuer
    /// @param includeKeyIdentifier    whether to name its key: its subject key
    ///                                identifier, or one made from its key
    ///                                when it has none
    /// @param includeIssuerAndSerial  whether to name it by its own issuer and
    ///                                serial number as well
    public static X509AuthorityKeyIdentifierExtension CreateFromCertificate(
        X509Certificate2 certificateAuthority, bool includeKeyIdentifier,
        bool includeIssuerAndSerial)
    {
        Optional<byte[]> keyIdentifier = None;
        if (includeKeyIdentifier)
        {
            X509SubjectKeyIdentifierExtension? own = certificateAuthority.SubjectKeyIdentifier;
            if (own != null)
            {
                keyIdentifier = Some(own.SubjectKeyIdentifierBytes);
            }
            else
            {
                keyIdentifier = Some(Sha1.HashData(certificateAuthority.PublicKey.EncodedKeyValue));
            }
        }

        var writer = new AsnWriter();
        writer.PushSequence();
        if (keyIdentifier is Some key)
            writer.WriteOctetString(key.Value, CreateContextTag(0, false));

        Optional<byte[]> rawIssuer = None;
        Optional<byte[]> serialNumber = None;
        if (includeIssuerAndSerial)
        {
            var names = new AsnWriter();
            names.PushSequence(CreateContextTag(1, true));
            names.PushSequence(CreateContextTag(4, true));
            names.WriteEncodedValue(certificateAuthority.IssuerName.RawData);
            names.PopSequence();
            names.PopSequence();
            byte[] issuer = names.Encode();
            writer.WriteEncodedValue(issuer);
            writer.WriteIntegerBytes(certificateAuthority.SerialNumberBytes,
                                     CreateContextTag(2, false));
            rawIssuer = Some(issuer);
            serialNumber = Some(certificateAuthority.SerialNumberBytes);
        }
        writer.PopSequence();

        return new X509AuthorityKeyIdentifierExtension(
            writer.Encode(), false, keyIdentifier, rawIssuer, serialNumber);
    }

    internal static Result<X509AuthorityKeyIdentifierExtension, CryptoError> DecodeExtension(
        ReadOnlySpan<byte> rawData, bool critical)
    {
        var document = new AsnReader(rawData, AsnEncodingRules.Der);
        AsnReader sequence = try ConvertAsnResult(document.ReadSequence());
        if (document.VerifyEndOfData() != AsnError.None)
            return Fail(CryptoError.Encoding);

        Optional<byte[]> keyIdentifier = None;
        Optional<byte[]> rawIssuer = None;
        Optional<byte[]> serialNumber = None;
        if (sequence.HasData &&
            try ConvertAsnResult(sequence.PeekTag()) == CreateContextTag(0, false))
        {
            ReadOnlySpan<byte> key =
                try ConvertAsnResult(sequence.ReadOctetString(CreateContextTag(0, false)));
            keyIdentifier = Some(key.ToArray());
        }
        if (sequence.HasData &&
            try ConvertAsnResult(sequence.PeekTag()) == CreateContextTag(1, true))
        {
            ReadOnlySpan<byte> issuer = try ConvertAsnResult(sequence.ReadEncodedValue());
            rawIssuer = Some(issuer.ToArray());
        }
        if (sequence.HasData)
        {
            ReadOnlySpan<byte> serial =
                try ConvertAsnResult(sequence.ReadIntegerBytes(CreateContextTag(2, false)));
            serialNumber = Some(serial.ToArray());
        }
        if (sequence.VerifyEndOfData() != AsnError.None)
            return Fail(CryptoError.Encoding);

        return Ok(new X509AuthorityKeyIdentifierExtension(
            rawData, critical, keyIdentifier, rawIssuer, serialNumber));
    }
}
