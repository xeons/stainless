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

/// Makes an `X500DistinguishedName` one attribute at a time: .NET's
/// `X500DistinguishedNameBuilder`.
///
/// ```csharp
/// var builder = new X500DistinguishedNameBuilder();
/// builder.AddCountryOrRegion("US");
/// builder.AddOrganizationName("Example");
/// builder.AddCommonName("www.example.com");
/// var name = try builder.Build();              // CN=www.example.com, O=Example, C=US
/// ```
///
/// **Each call adds one relative distinguished name, most general first**, so
/// the order of the calls is the order of the encoding and the reverse of
/// `Name`. Values are `UTF8String` except a country, which is a two-letter
/// `PrintableString`, and an e-mail address and a domain component, which
/// are `IA5String`.
public sealed class X500DistinguishedNameBuilder
{
    private List<byte[]> _encoded;
    private bool _valid;

    /// A builder with nothing in it.
    public X500DistinguishedNameBuilder()
    {
        _encoded = new List<byte[]>();
        _valid = true;
    }

    /// An attribute of any type.
    ///
    /// A value its string type cannot hold, or a type that is not a dotted
    /// identifier, is reported by `Build` rather than here.
    ///
    /// @param typeOid       the attribute type, dotted
    /// @param value         its text
    /// @param encodingType  the string type to write it as
    public void Add(String typeOid, String value,
                    UniversalTagNumber encodingType = UniversalTagNumber.Utf8String)
    {
        var writer = new AsnWriter();
        writer.PushSetOf();
        writer.PushSequence();
        if (writer.WriteObjectIdentifier(typeOid) != AsnError.None)
            _valid = false;
        if (writer.WriteCharacterString(encodingType, value) != AsnError.None)
            _valid = false;
        writer.PopSequence();
        writer.PopSetOf();
        _encoded.Add(writer.Encode());
    }

    /// A common name, `CN`.
    public void AddCommonName(String commonName) => Add("2.5.4.3", commonName);

    /// An organization, `O`.
    public void AddOrganizationName(String organizationName) => Add("2.5.4.10", organizationName);

    /// An organizational unit, `OU`.
    public void AddOrganizationalUnitName(String organizationalUnitName) =>
        Add("2.5.4.11", organizationalUnitName);

    /// A locality, `L`.
    public void AddLocalityName(String localityName) => Add("2.5.4.7", localityName);

    /// A state or province, `S`.
    public void AddStateOrProvinceName(String stateOrProvinceName) =>
        Add("2.5.4.8", stateOrProvinceName);

    /// A country, `C`: two letters, as ISO 3166 writes it. Anything else is
    /// reported by `Build`.
    public void AddCountryOrRegion(String twoLetterCode)
    {
        if (twoLetterCode.ByteLength() != 2u)
            _valid = false;
        Add("2.5.4.6", twoLetterCode.ToUpperAscii(), UniversalTagNumber.PrintableString);
    }

    /// An e-mail address, `E`, as PKCS #9 names one.
    public void AddEmailAddress(String emailAddress) =>
        Add("1.2.840.113549.1.9.1", emailAddress, UniversalTagNumber.IA5String);

    /// A domain component, `DC`.
    public void AddDomainComponent(String domainComponent) =>
        Add("0.9.2342.19200300.100.1.25", domainComponent, UniversalTagNumber.IA5String);

    /// The name, in the order the attributes were added.
    ///
    /// @failure CryptoError.Encoding  an attribute type was not an identifier, or a
    ///                                value was not valid for its string type
    public Result<X500DistinguishedName, CryptoError> Build()
    {
        if (!_valid)
            return Fail(CryptoError.Encoding);
        var writer = new AsnWriter();
        writer.PushSequence();
        foreach (byte[] one in _encoded)
            writer.WriteEncodedValue(one);
        writer.PopSequence();
        return X500DistinguishedName.FromDer(writer.Encode());
    }
}
