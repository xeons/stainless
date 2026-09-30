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

/// Makes a subject alternative name extension: .NET's
/// `SubjectAlternativeNameBuilder`.
///
/// ```csharp
/// var names = new SubjectAlternativeNameBuilder();
/// names.AddDnsName("www.example.com");
/// names.AddIPAddress([192, 0, 2, 1]);
/// request.CertificateExtensions.Add(names.Build());
/// ```
///
/// The names are written in the order they were added. Each MUST be ASCII,
/// which is what the `IA5String` they are written as holds: an
/// internationalized domain name is added as its `xn--` form. Anything else
/// aborts, as a mistake in the program rather than in its data.
public sealed class SubjectAlternativeNameBuilder
{
    private List<byte[]> _encoded;
    private List<String> _dnsNames;
    private List<byte[]> _ipAddresses;
    private List<String> _uris;
    private List<String> _emailAddresses;

    /// A builder with no names.
    public SubjectAlternativeNameBuilder()
    {
        _encoded = new List<byte[]>();
        _dnsNames = new List<String>();
        _ipAddresses = new List<byte[]>();
        _uris = new List<String>();
        _emailAddresses = new List<String>();
    }

    /// A DNS name, `www.example.com` or `*.example.com`.
    public void AddDnsName(String dnsName)
    {
        AddGeneralNameText(2, dnsName);
        _dnsNames.Add(dnsName);
    }

    /// An e-mail address.
    public void AddEmailAddress(String emailAddress)
    {
        AddGeneralNameText(1, emailAddress);
        _emailAddresses.Add(emailAddress);
    }

    /// A URI.
    public void AddUri(String uri)
    {
        AddGeneralNameText(6, uri);
        _uris.Add(uri);
    }

    /// An IP address: four bytes for IPv4, sixteen for IPv6; any other length
    /// aborts.
    public void AddIPAddress(ReadOnlySpan<byte> address)
    {
        if (address.Length != 4u && address.Length != 16u)
            sl_fail("SubjectAlternativeNameBuilder.AddIPAddress: an address is 4 or 16 bytes");
        var writer = new AsnWriter();
        writer.WriteOctetString(address, CreateContextTag(7, false));
        _encoded.Add(writer.Encode());
        _ipAddresses.Add(address.ToArray());
    }

    /// The extension, holding every name added so far. At least one MUST
    /// have been; this aborts otherwise.
    ///
    /// @param critical  whether it is critical, which RFC 5280 requires only
    ///                  when the subject name is empty
    public X509SubjectAlternativeNameExtension Build(bool critical = false)
    {
        if (_encoded.Count == 0u)
            sl_fail("SubjectAlternativeNameBuilder.Build: a name is required");
        var writer = new AsnWriter();
        writer.PushSequence();
        foreach (byte[] one in _encoded)
            writer.WriteEncodedValue(one);
        writer.PopSequence();
        return new X509SubjectAlternativeNameExtension(
            writer.Encode(), critical, _dnsNames.ToArray(), _ipAddresses.ToArray(),
            _uris.ToArray(), _emailAddresses.ToArray(), new X500DistinguishedName[0u]);
    }

    private void AddGeneralNameText(int number, String text)
    {
        var writer = new AsnWriter();
        if (writer.WriteCharacterString(UniversalTagNumber.IA5String, text,
                                        CreateContextTag(number, false)) != AsnError.None)
        {
            sl_fail("SubjectAlternativeNameBuilder: a name is not ASCII");
        }
        _encoded.Add(writer.Encode());
    }
}
