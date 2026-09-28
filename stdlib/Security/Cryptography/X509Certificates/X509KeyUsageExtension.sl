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

/// What the key may be used for: RFC 5280 §4.2.1.3, `2.5.29.15`.
///
/// A CA's key MUST allow `KeyCertSign` for a chain to pass through it when
/// this is present; with none, the key is not restricted.
public sealed class X509KeyUsageExtension : X509Extension
{
    private X509KeyUsageFlags _keyUsages;

    /// The extension with these usages, encoded as DER's named bits: with
    /// the trailing zero bits left off.
    ///
    /// @param keyUsages  what the key may do
    /// @param critical   whether it is critical, which RFC 5280 recommends
    public X509KeyUsageExtension(X509KeyUsageFlags keyUsages, bool critical)
        : this(EncodeKeyUsage(keyUsages), critical, keyUsages)
    {
    }

    private X509KeyUsageExtension(ReadOnlySpan<byte> rawData, bool critical,
                                  X509KeyUsageFlags keyUsages)
    {
        base("2.5.29.15", rawData, critical);
        _keyUsages = keyUsages;
    }

    /// What the key may do.
    public X509KeyUsageFlags KeyUsages => _keyUsages;

    private static byte[] EncodeKeyUsage(X509KeyUsageFlags keyUsages)
    {
        uint bits = (uint)(int)keyUsages;
        byte low = (byte)(bits & 0xFFu);
        var writer = new AsnWriter();
        if ((bits & 0x8000u) != 0u)
        {
            byte[] both = [low, 0x80];
            writer.WriteBitString(both, 7);
        }
        else if (low != 0)
        {
            int unused = 0;
            while (((uint)low & (1u << unused)) == 0u)
                unused++;
            byte[] one = [low];
            writer.WriteBitString(one, unused);
        }
        else
        {
            writer.WriteBitString(new byte[0u]);
        }
        return writer.Encode();
    }

    internal static Result<X509KeyUsageExtension, CryptoError> DecodeExtension(
        ReadOnlySpan<byte> rawData, bool critical)
    {
        var document = new AsnReader(rawData, AsnEncodingRules.Der);
        ReadOnlySpan<byte> bits = try ConvertAsnResult(document.ReadBitString(out int unused));
        if (document.VerifyEndOfData() != AsnError.None)
            return Fail(CryptoError.Encoding);

        uint value = 0u;
        if (bits.Length > 0u)
            value = (uint)bits[0u];
        if (bits.Length > 1u)
            value |= ((uint)bits[1u] & 0x80u) << 8;
        return Ok(new X509KeyUsageExtension(rawData, critical, (X509KeyUsageFlags)(int)value));
    }
}
