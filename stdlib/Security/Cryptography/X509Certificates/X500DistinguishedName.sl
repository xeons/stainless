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

/// An X.500 name, as a certificate's issuer and subject are: a sequence of
/// relative distinguished names from the most general to the most specific.
///
/// ```csharp
/// Console.WriteLine(certificate.SubjectName.Name);   // CN=www.example.com, O=Example, C=US
/// var common = certificate.SubjectName.GetFirstValue("2.5.4.3");
/// ```
///
/// **`Name` is written as .NET writes it**: most specific first, separated by
/// `, `, with the short names `CN`, `O`, `OU`, `L`, `S`, `C`, `E`, `DC`,
/// `STREET`, `T`, `G`, `I`, `SN` and `SERIALNUMBER`, and `OID.` and the
/// dotted identifier for any other type. A value holding `,`, `+`, `=`, `"`,
/// `<`, `>`, `#`, `;`, a newline, or a space at either end is quoted, with a
/// `"` inside doubled. The attributes of a multi-valued step are joined by
/// ` + `.
///
/// **Two names are equal as RFC 5280 §7.1 compares them**: the same types in
/// the same order, and each string value equal once runs of spaces are one
/// space, spaces at either end are gone, and ASCII letters are one case. The
/// string type does not matter; a value that is not a string is compared as
/// DER. This is what finds an issuer whose CA wrote its name differently.
public sealed class X500DistinguishedName
{
    private byte[] _rawData;
    private List<X500RelativeDistinguishedName> _names;
    private String _name;
    private String _canonical;

    private X500DistinguishedName(byte[] rawData, List<X500RelativeDistinguishedName> names)
    {
        _rawData = rawData;
        _names = names;
        _name = FormatDistinguishedName(names);
        _canonical = FormatCanonicalName(names);
    }

    /// The name one `Name` value in DER encodes.
    ///
    /// @param encoded  exactly one `SEQUENCE` of relative distinguished names
    /// @failure CryptoError.Encoding  it is not one, or a string value is not
    ///                                valid for its type
    public static Result<X500DistinguishedName, CryptoError> FromDer(ReadOnlySpan<byte> encoded)
    {
        var document = new AsnReader(encoded, AsnEncodingRules.Der);
        AsnReader sequence = try ConvertAsnResult(document.ReadSequence());
        if (document.VerifyEndOfData() != AsnError.None)
            return Fail(CryptoError.Encoding);

        var names = new List<X500RelativeDistinguishedName>();
        while (sequence.HasData)
        {
            ReadOnlySpan<byte> setEncoded = try ConvertAsnResult(sequence.PeekEncodedValue());
            AsnReader set = try ConvertAsnResult(sequence.ReadSetOf());
            if (!set.HasData)
                return Fail(CryptoError.Encoding);

            var types = new List<String>();
            var values = new List<String>();
            var isText = new List<bool>();
            while (set.HasData)
            {
                AsnReader pair = try ConvertAsnResult(set.ReadSequence());
                types.Add(try ConvertAsnResult(pair.ReadObjectIdentifier()));
                bool text = false;
                values.Add(try ReadAttributeValue(pair, out text));
                isText.Add(text);
                if (pair.VerifyEndOfData() != AsnError.None)
                    return Fail(CryptoError.Encoding);
            }

            names.Add(new X500RelativeDistinguishedName(
                setEncoded.ToArray(), types.ToArray(), values.ToArray(), isText.ToArray()));
        }

        return Ok(new X500DistinguishedName(encoded.ToArray(), names));
    }

    /// The name as DER.
    public byte[] RawData => _rawData;

    /// The name as .NET writes it: `CN=www.example.com, O=Example, C=US`.
    public String Name => _name;

    /// Whether the name has no relative distinguished names at all.
    public bool IsEmpty => _names.Count == 0u;

    /// Each relative distinguished name.
    ///
    /// @param reversed  most specific first, as `Name` writes them, which is
    ///                  .NET's default; otherwise in the order they are encoded
    public List<X500RelativeDistinguishedName> EnumerateRelativeDistinguishedNames(
        bool reversed = true)
    {
        var copied = new List<X500RelativeDistinguishedName>();
        for (nuint i = 0u; i < _names.Count; i++)
            copied.Add(_names[reversed ? _names.Count - 1u - i : i]);
        return copied;
    }

    /// The text of the first attribute of type `typeOid`, most specific
    /// first, or `None` when there is none or it is not a character string.
    ///
    /// @param typeOid  the attribute type, as `2.5.4.3` for a common name
    public Optional<String> GetFirstValue(String typeOid)
    {
        for (nuint i = _names.Count; i > 0u; i--)
        {
            X500RelativeDistinguishedName step = _names[i - 1u];
            for (nuint j = 0u; j < step.Count; j++)
            {
                if (step.GetElementType(j) != typeOid)
                    continue;
                if (!step.IsElementText(j))
                    return None;
                return Some(step.GetElementValue(j));
            }
        }
        return None;
    }

    /// Whether `other` names the same thing, as RFC 5280 compares names.
    public bool Equals(X500DistinguishedName other)
    {
        if (AreBytesEqual(_rawData, other._rawData))
            return true;
        return _canonical == other._canonical;
    }

    // ------------------------------------------------------------ reading

    /// An `AttributeValue`: text for a character string type, and otherwise
    /// `#` and its DER in hexadecimal.
    private static Result<String, CryptoError> ReadAttributeValue(AsnReader pair, out bool isText)
    {
        isText = false;
        Asn1Tag tag = try ConvertAsnResult(pair.PeekTag());
        if (tag.TagClass == TagClass.Universal && !tag.IsConstructed)
        {
            var type = (UniversalTagNumber)tag.TagValue;
            switch (type)
            {
                case UniversalTagNumber.Utf8String:
                case UniversalTagNumber.IA5String:
                case UniversalTagNumber.VisibleString:
                case UniversalTagNumber.NumericString:
                case UniversalTagNumber.T61String:
                case UniversalTagNumber.BmpString:
                case UniversalTagNumber.UniversalString:
                    isText = true;
                    return ConvertAsnResult(pair.ReadCharacterString(type));

                case UniversalTagNumber.PrintableString:
                {
                    isText = true;
                    var printable = pair.ReadCharacterString(type);
                    if (printable.Ok)
                        return Ok(printable.Value);
                    // `*` and `@` are common in a PrintableString and not
                    // allowed in one; read it as the ASCII it is.
                    return ConvertAsnResult(pair.ReadCharacterString(
                        UniversalTagNumber.IA5String, new Asn1Tag(type)));
                }
            }
        }

        ReadOnlySpan<byte> encoded = try ConvertAsnResult(pair.ReadEncodedValue());
        return Ok("#" + FormatHexadecimalUpper(encoded));
    }

    // ------------------------------------------------------------ writing

    private static String FormatDistinguishedName(List<X500RelativeDistinguishedName> names)
    {
        var built = new StringBuilder();
        for (nuint i = names.Count; i > 0u; i--)
        {
            if (i < names.Count)
                built.Append(", ");
            X500RelativeDistinguishedName step = names[i - 1u];
            for (nuint j = 0u; j < step.Count; j++)
            {
                if (j > 0u)
                    built.Append(" + ");
                built.Append(FormatAttributeTypeName(step.GetElementType(j)));
                built.Append("=");
                String value = step.GetElementValue(j);
                if (step.IsElementText(j) && IsQuotingNeeded(value))
                {
                    built.Append("\"");
                    built.Append(value.Replace("\"", "\"\""));
                    built.Append("\"");
                }
                else
                {
                    built.Append(value);
                }
            }
        }
        return built.ToText();
    }

    /// The short name Windows and .NET give an attribute type.
    private static String FormatAttributeTypeName(String oid)
    {
        switch (oid)
        {
            case "2.5.4.3": return "CN";
            case "2.5.4.4": return "SN";
            case "2.5.4.5": return "SERIALNUMBER";
            case "2.5.4.6": return "C";
            case "2.5.4.7": return "L";
            case "2.5.4.8": return "S";
            case "2.5.4.9": return "STREET";
            case "2.5.4.10": return "O";
            case "2.5.4.11": return "OU";
            case "2.5.4.12": return "T";
            case "2.5.4.42": return "G";
            case "2.5.4.43": return "I";
            case "1.2.840.113549.1.9.1": return "E";
            case "0.9.2342.19200300.100.1.25": return "DC";
        }
        return "OID." + oid;
    }

    private static bool IsQuotingNeeded(String value)
    {
        byte[] text = value.ToBytes();
        if (text.Length == 0u)
            return false;
        if (text[0u] == 32 || text[text.Length - 1u] == 32)
            return true;
        foreach (byte one in text)
        {
            switch (one)
            {
                case 44:                                            // ','
                case 43:                                            // '+'
                case 61:                                            // '='
                case 34:                                            // '"'
                case 10:                                            // '\n'
                case 60:                                            // '<'
                case 62:                                            // '>'
                case 35:                                            // '#'
                case 59:                                            // ';'
                    return true;
            }
        }
        return false;
    }

    /// Each type and value, length-prefixed so that no value can pass for a
    /// separator, with every text value in the form RFC 5280 §7.1 compares.
    private static String FormatCanonicalName(List<X500RelativeDistinguishedName> names)
    {
        var built = new StringBuilder();
        foreach (X500RelativeDistinguishedName step in names)
        {
            built.Append($"[{step.Count}");
            for (nuint j = 0u; j < step.Count; j++)
            {
                String value = step.GetElementValue(j);
                if (step.IsElementText(j))
                    value = FoldAttributeValue(value);
                built.Append($"|{step.GetElementType(j)}|{value.ByteLength()}:{value}");
            }
            built.Append("]");
        }
        return built.ToText();
    }

    /// Spaces at either end removed, runs of them made one, ASCII lower-cased.
    private static String FoldAttributeValue(String value)
    {
        byte[] text = value.ToBytes();
        var built = new StringBuilder();
        bool pendingSpace = false;
        foreach (byte one in text)
        {
            if (one == 32)
            {
                pendingSpace = built.HasContent;
                continue;
            }
            if (pendingSpace)
            {
                built.AppendByte(32);
                pendingSpace = false;
            }
            built.AppendByte(one >= 65 && one <= 90 ? (byte)(one + 32) : one);
        }
        return built.ToText();
    }
}
