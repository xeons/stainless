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

import Standard.Collections;
import Standard.Formats.Asn1;
import Standard.Security.Cryptography;

/// The names the certificate is for: RFC 5280 §4.2.1.6, `2.5.29.17`.
///
/// Four kinds of name are read out: DNS names, IP addresses as their four or
/// sixteen bytes, URIs and e-mail addresses. The other kinds — a directory
/// name, an `otherName`, a registered identifier — are checked to be
/// well-formed and are otherwise left in `RawData`.
///
/// @see SubjectAlternativeNameBuilder
/// @see X509Certificate2.MatchesHostname
public sealed class X509SubjectAlternativeNameExtension : X509Extension
{
    private String[] _dnsNames;
    private byte[][] _ipAddresses;
    private String[] _uris;
    private String[] _emailAddresses;

    internal X509SubjectAlternativeNameExtension(ReadOnlySpan<byte> rawData, bool critical,
                                                 String[] dnsNames, byte[][] ipAddresses,
                                                 String[] uris, String[] emailAddresses)
    {
        base("2.5.29.17", rawData, critical);
        _dnsNames = dnsNames;
        _ipAddresses = ipAddresses;
        _uris = uris;
        _emailAddresses = emailAddresses;
    }

    /// The `dNSName` entries, as written.
    public String[] DnsNames => _dnsNames;

    /// The `iPAddress` entries: four bytes for IPv4, sixteen for IPv6.
    public byte[][] IPAddresses => _ipAddresses;

    /// The `uniformResourceIdentifier` entries.
    public String[] Uris => _uris;

    /// The `rfc822Name` entries.
    public String[] EmailAddresses => _emailAddresses;

    internal static Result<X509SubjectAlternativeNameExtension, CryptoError> DecodeExtension(
        ReadOnlySpan<byte> rawData, bool critical)
    {
        var document = new AsnReader(rawData, AsnEncodingRules.Der);
        AsnReader names = try ConvertAsnResult(document.ReadSequence());
        if (document.VerifyEndOfData() != AsnError.None || !names.HasData)
            return Fail(CryptoError.Encoding);

        var dnsNames = new List<String>();
        var ipAddresses = new List<byte[]>();
        var uris = new List<String>();
        var emailAddresses = new List<String>();
        while (names.HasData)
        {
            Asn1Tag tag = try ConvertAsnResult(names.PeekTag());
            if (tag.TagClass != TagClass.ContextSpecific)
                return Fail(CryptoError.Encoding);

            switch (tag.TagValue)
            {
                case 1:
                    emailAddresses.Add(try ReadGeneralNameText(names, 1));
                    break;
                case 2:
                    dnsNames.Add(try ReadGeneralNameText(names, 2));
                    break;
                case 6:
                    uris.Add(try ReadGeneralNameText(names, 6));
                    break;
                case 7:
                {
                    ReadOnlySpan<byte> address =
                        try ConvertAsnResult(names.ReadOctetString(CreateContextTag(7, false)));
                    if (address.Length != 4u && address.Length != 16u)
                        return Fail(CryptoError.Encoding);
                    ipAddresses.Add(address.ToArray());
                    break;
                }
                default:
                    if (tag.TagValue < 0 || tag.TagValue > 8)
                        return Fail(CryptoError.Encoding);
                    try ConvertAsnResult(names.ReadEncodedValue());
                    break;
            }
        }

        return Ok(new X509SubjectAlternativeNameExtension(
            rawData, critical, dnsNames.ToArray(), ipAddresses.ToArray(), uris.ToArray(),
            emailAddresses.ToArray()));
    }

    /// An `IA5String` name under its implicit context tag.
    internal static Result<String, CryptoError> ReadGeneralNameText(AsnReader names, int number) =>
        ConvertAsnResult(names.ReadCharacterString(UniversalTagNumber.IA5String,
                                                   CreateContextTag(number, false)));
}
