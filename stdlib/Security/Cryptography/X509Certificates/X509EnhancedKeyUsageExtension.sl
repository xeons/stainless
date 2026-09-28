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

/// The purposes the key may serve: RFC 5280 §4.2.1.12's extended key usage,
/// `2.5.29.37`.
///
/// ```csharp
/// var usage = new X509EnhancedKeyUsageExtension(
///     [X509EnhancedKeyUsageExtension.ServerAuthenticationOid], false);
/// ```
///
/// A chain asked for an application policy requires the leaf, and any
/// intermediate that has this, to list that purpose or
/// `AnyExtendedKeyUsageOid`. A certificate without it is not restricted.
public sealed class X509EnhancedKeyUsageExtension : X509Extension
{
    private String[] _enhancedKeyUsages;

    /// The extension listing `enhancedKeyUsages`.
    ///
    /// @param enhancedKeyUsages  dotted identifiers; each MUST be one, and this
    ///                           aborts on one that is not
    /// @param critical           whether it is critical
    public X509EnhancedKeyUsageExtension(String[] enhancedKeyUsages, bool critical)
        : this(EncodeEnhancedKeyUsage(enhancedKeyUsages), critical, enhancedKeyUsages)
    {
    }

    private X509EnhancedKeyUsageExtension(ReadOnlySpan<byte> rawData, bool critical,
                                          String[] enhancedKeyUsages)
    {
        base("2.5.29.37", rawData, critical);
        _enhancedKeyUsages = enhancedKeyUsages;
    }

    /// `id-kp-serverAuth`: a TLS server.
    public static String ServerAuthenticationOid => "1.3.6.1.5.5.7.3.1";

    /// `id-kp-clientAuth`: a TLS client.
    public static String ClientAuthenticationOid => "1.3.6.1.5.5.7.3.2";

    /// `id-kp-codeSigning`.
    public static String CodeSigningOid => "1.3.6.1.5.5.7.3.3";

    /// `id-kp-emailProtection`.
    public static String EmailProtectionOid => "1.3.6.1.5.5.7.3.4";

    /// `id-kp-timeStamping`.
    public static String TimeStampingOid => "1.3.6.1.5.5.7.3.8";

    /// `id-kp-OCSPSigning`.
    public static String OcspSigningOid => "1.3.6.1.5.5.7.3.9";

    /// `anyExtendedKeyUsage`, which allows every purpose.
    public static String AnyExtendedKeyUsageOid => "2.5.29.37.0";

    /// The purposes, dotted, in the order they are listed.
    public String[] EnhancedKeyUsages => _enhancedKeyUsages;

    /// Whether `usage` is listed, or `AnyExtendedKeyUsageOid` is.
    public bool AllowsUsage(String usage)
    {
        foreach (String listed in _enhancedKeyUsages)
        {
            if (listed == usage || listed == AnyExtendedKeyUsageOid)
                return true;
        }
        return false;
    }

    private static byte[] EncodeEnhancedKeyUsage(String[] enhancedKeyUsages)
    {
        var writer = new AsnWriter();
        writer.PushSequence();
        foreach (String usage in enhancedKeyUsages)
        {
            if (writer.WriteObjectIdentifier(usage) != AsnError.None)
                sl_fail("X509EnhancedKeyUsageExtension: a usage is not a dotted identifier");
        }
        writer.PopSequence();
        return writer.Encode();
    }

    internal static Result<X509EnhancedKeyUsageExtension, CryptoError> DecodeExtension(
        ReadOnlySpan<byte> rawData, bool critical)
    {
        var document = new AsnReader(rawData, AsnEncodingRules.Der);
        AsnReader sequence = try ConvertAsnResult(document.ReadSequence());
        if (document.VerifyEndOfData() != AsnError.None || !sequence.HasData)
            return Fail(CryptoError.Encoding);

        var usages = new List<String>();
        while (sequence.HasData)
            usages.Add(try ConvertAsnResult(sequence.ReadObjectIdentifier()));
        return Ok(new X509EnhancedKeyUsageExtension(rawData, critical, usages.ToArray()));
    }
}
