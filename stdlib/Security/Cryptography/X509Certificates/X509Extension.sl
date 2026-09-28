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

/// One certificate extension: its identifier, whether it is critical, and
/// its value as DER.
///
/// An extension this module knows is one of the classes derived from this,
/// already decoded: `X509BasicConstraintsExtension`,
/// `X509KeyUsageExtension`, `X509EnhancedKeyUsageExtension`,
/// `X509SubjectAlternativeNameExtension`,
/// `X509SubjectKeyIdentifierExtension`,
/// `X509AuthorityKeyIdentifierExtension` and
/// `X509NameConstraintsExtension`. Any other is this class, as it was read.
///
/// **A critical extension this module does not understand makes a chain
/// fail** with `HasNotSupportedCriticalExtension`, as RFC 5280 requires.
public class X509Extension
{
    private String _oid;
    private bool _critical;
    private byte[] _rawData;

    /// An extension of any type.
    ///
    /// @param oid       its identifier, dotted
    /// @param rawData   its value: the DER an `OCTET STRING` wraps
    /// @param critical  whether a reader that does not understand it MUST refuse
    ///                  the certificate
    public X509Extension(String oid, ReadOnlySpan<byte> rawData, bool critical)
    {
        _oid = oid;
        _rawData = rawData.ToArray();
        _critical = critical;
    }

    /// The identifier, dotted: `2.5.29.19` for basic constraints.
    public String Oid => _oid;

    /// Whether it is marked critical.
    public bool Critical => _critical;

    /// The value, as DER.
    public byte[] RawData => _rawData;
}
