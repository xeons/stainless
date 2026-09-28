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
import Standard.Security.Cryptography;

/// An ordered set of certificates: .NET's `X509Certificate2Collection`.
///
/// ```csharp
/// var bundle = new X509Certificate2Collection();
/// nuint added = try bundle.ImportFromPem(File.ReadAllText("chain.pem"));
/// foreach (X509Certificate2 certificate in bundle)
///     Console.WriteLine(certificate.Subject);
/// ```
///
/// A certificate already present, byte for byte, is not added a second time.
public sealed class X509Certificate2Collection
{
    private List<X509Certificate2> _items;

    /// An empty collection.
    public X509Certificate2Collection()
    {
        _items = new List<X509Certificate2>();
    }

    /// How many certificates there are.
    public nuint Count => _items.Count;

    /// Certificate `index`, in the order they were added; aborts past `Count`.
    public X509Certificate2 this[nuint index] => _items[index];

    /// Each certificate in turn.
    public IEnumerator<X509Certificate2> GetEnumerator() => _items.GetEnumerator();

    /// Adds `certificate` unless it is already here.
    ///
    /// @returns whether it was added
    public bool Add(X509Certificate2 certificate)
    {
        if (Contains(certificate))
            return false;
        _items.Add(certificate);
        return true;
    }

    /// Adds each of `certificates` that is not already here.
    public void AddRange(X509Certificate2Collection certificates)
    {
        foreach (X509Certificate2 certificate in certificates)
            Add(certificate);
    }

    /// Whether `certificate` is here, byte for byte.
    public bool Contains(X509Certificate2 certificate)
    {
        foreach (X509Certificate2 held in _items)
        {
            if (held.Equals(certificate))
                return true;
        }
        return false;
    }

    /// Removes `certificate`, when it is here.
    ///
    /// @returns whether it was
    public bool Remove(X509Certificate2 certificate)
    {
        for (nuint i = 0u; i < _items.Count; i++)
        {
            if (_items[i].Equals(certificate))
            {
                _items.RemoveAt(i);
                return true;
            }
        }
        return false;
    }

    /// Every certificate in the `CERTIFICATE` blocks of `text`, as a PEM
    /// bundle holds them. Blocks with other labels are passed over.
    ///
    /// **All or nothing**: when one block does not hold a certificate,
    /// nothing is added.
    ///
    /// @param text  PEM, perhaps among other text
    /// @returns how many were added, not counting any already here
    /// @failure CryptoError.Encoding  a `CERTIFICATE` block does not hold a certificate
    public Result<nuint, CryptoError> ImportFromPem(String text)
    {
        var found = new List<X509Certificate2>();
        nuint at = 0u;
        while (PemEncoding.Find(text, at) is Some block)
        {
            at = block.Value.Location.End.Value;
            if (block.Value.Label == "CERTIFICATE")
                found.Add(try X509Certificate2.FromDer(block.Value.Data));
        }

        nuint added = 0u;
        foreach (X509Certificate2 certificate in found)
        {
            if (Add(certificate))
                added++;
        }
        return Ok(added);
    }

    /// The same, adding every certificate that parses and passing over those
    /// that do not, as a system bundle is read.
    internal nuint ImportFromPemSkippingFailures(String text)
    {
        nuint added = 0u;
        nuint at = 0u;
        while (PemEncoding.Find(text, at) is Some block)
        {
            at = block.Value.Location.End.Value;
            if (block.Value.Label != "CERTIFICATE")
                continue;
            var certificate = X509Certificate2.FromDer(block.Value.Data);
            if (certificate.Ok && Add(certificate.Value))
                added++;
        }
        return added;
    }

    /// Every certificate as PEM, one block after another, each followed by a
    /// newline: a bundle `ImportFromPem` reads back.
    public String ExportCertificatePems()
    {
        var built = new StringBuilder();
        foreach (X509Certificate2 certificate in _items)
        {
            built.Append(certificate.ExportCertificatePem());
            built.Append("\n");
        }
        return built.ToText();
    }
}
