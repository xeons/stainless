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

/// A certificate's extensions, in the order they are encoded.
///
/// ```csharp
/// foreach (X509Extension extension in certificate.Extensions)
///     Console.WriteLine($"{extension.Oid} {extension.Critical}");
/// X509Extension? constraints = certificate.Extensions["2.5.29.19"];
/// ```
///
/// Read-only: a certificate is signed as it is, so there is nothing to add
/// to. `CertificateRequest.CertificateExtensions` is where extensions are
/// gathered for a new one.
public sealed class X509ExtensionCollection
{
    private List<X509Extension> _items;

    private X509ExtensionCollection(List<X509Extension> items)
    {
        _items = items;
    }

    /// No extensions, as a version 1 certificate has.
    internal static X509ExtensionCollection CreateEmpty() =>
        new X509ExtensionCollection(new List<X509Extension>());

    /// How many there are.
    public nuint Count => _items.Count;

    /// Extension `index`, in encoded order; aborts past `Count`.
    public X509Extension this[nuint index] => _items[index];

    /// The extension whose identifier is `oid`, or null. No identifier
    /// appears twice.
    public X509Extension? this[String oid]
    {
        get
        {
            foreach (X509Extension extension in _items)
            {
                if (extension.Oid == oid)
                    return extension;
            }
            return null;
        }
    }

    /// Each extension in turn.
    public IEnumerator<X509Extension> GetEnumerator() => _items.GetEnumerator();

    /// Whether a critical extension is one this module does not understand.
    internal bool ContainsUnsupportedCriticalExtension()
    {
        foreach (X509Extension extension in _items)
        {
            if (extension.Critical && !IsUnderstoodExtension(extension.Oid))
                return true;
        }
        return false;
    }

    /// RFC 5280's `Extensions`: one or more, none twice, each known one
    /// decoded into its own class.
    internal static Result<X509ExtensionCollection, CryptoError> DecodeExtensions(
        AsnReader extensions)
    {
        if (!extensions.HasData)
            return Fail(CryptoError.Encoding);

        var items = new List<X509Extension>();
        while (extensions.HasData)
        {
            AsnReader one = try ConvertAsnResult(extensions.ReadSequence());
            String oid = try ConvertAsnResult(one.ReadObjectIdentifier());
            bool critical = false;
            if (try ConvertAsnResult(one.PeekTag()) == Asn1Tag.Boolean)
                critical = try ConvertAsnResult(one.ReadBoolean());
            ReadOnlySpan<byte> value = try ConvertAsnResult(one.ReadOctetString());
            if (one.VerifyEndOfData() != AsnError.None)
                return Fail(CryptoError.Encoding);

            foreach (X509Extension earlier in items)
            {
                if (earlier.Oid == oid)
                    return Fail(CryptoError.Encoding);
            }
            items.Add(try DecodeExtension(oid, value, critical));
        }
        return Ok(new X509ExtensionCollection(items));
    }

    private static Result<X509Extension, CryptoError> DecodeExtension(
        String oid, ReadOnlySpan<byte> value, bool critical)
    {
        switch (oid)
        {
            case "2.5.29.14":
                return Ok(try X509SubjectKeyIdentifierExtension.DecodeExtension(value, critical));
            case "2.5.29.15":
                return Ok(try X509KeyUsageExtension.DecodeExtension(value, critical));
            case "2.5.29.17":
                return Ok(try X509SubjectAlternativeNameExtension.DecodeExtension(value, critical));
            case "2.5.29.19":
                return Ok(try X509BasicConstraintsExtension.DecodeExtension(value, critical));
            case "2.5.29.30":
                return Ok(try X509NameConstraintsExtension.DecodeExtension(value, critical));
            case "2.5.29.35":
                return Ok(try X509AuthorityKeyIdentifierExtension.DecodeExtension(value, critical));
            case "2.5.29.37":
                return Ok(try X509EnhancedKeyUsageExtension.DecodeExtension(value, critical));
        }
        return Ok(new X509Extension(oid, value, critical));
    }
}
