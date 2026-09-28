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

/// X.509 certificates: reading them, checking a host name against one,
/// building and validating a chain to a trusted root, the platform's root
/// store, and making new ones.
///
/// ```csharp
/// var leaf = try X509Certificate2.FromPem(pem);
/// bool named = leaf.MatchesHostname("www.example.com");
///
/// var chain = new X509Chain();
/// chain.ChainPolicy.ApplicationPolicy.Add(X509EnhancedKeyUsageExtension.ServerAuthenticationOid);
/// chain.ChainPolicy.ExtraStore.AddRange(intermediates);
/// if (!chain.Build(leaf))
///     Console.WriteLine(chain.StatusFlags);
/// ```
///
/// **The shape is `System.Security.Cryptography.X509Certificates`'s**, with
/// the house casing and a `Result` where .NET throws. Every failure is a
/// `CryptoError`, the module underneath's own vocabulary, rather than an
/// enum of this module's: a certificate that does not parse is
/// `CryptoError.Encoding` whatever part of it was wrong, a key this does not
/// sign with is `CryptoError.Unsupported`, and a signing failure passes
/// through unchanged. A chain that does not validate is not a failure of the
/// call; `X509Chain.Build` answers `false` and says why in its status flags.
///
/// **Times are seconds since 1970-01-01 UTC, in a `long`**, as in
/// `Standard.Formats.Asn1`: a certificate can name 9999 and a
/// `DateTimeOffset` ends in 2262. The `DateTimeOffset` accessors cross over
/// where they can.
///
/// **Parsing is RFC 5280's, strictly, with the leniencies browsers have.**
/// The DER is held to the letter: minimal lengths and integers, a signature
/// algorithm outside the signed part identical to the one inside it, a
/// version of 1, 2 or 3, extensions only in version 3 and none twice. What
/// is tolerated is what real certificates do: a serial number of up to 20
/// octets that is zero or negative, a `GeneralizedTime` before 2050, an
/// explicit `critical FALSE`, and a `PrintableString` holding `*` or `@`.
/// Every extension this module knows is decoded as the certificate is read,
/// so a malformed one is a certificate that does not parse.
///
/// **Signatures** are Ed25519, ECDSA over P-256 and P-384 with SHA-256, -384
/// or -512, RSA PKCS #1 v1.5 with SHA-1, -256, -384 or -512, and RSASSA-PSS
/// whose mask hash is its message hash. A chain refuses SHA-1 as
/// `HasWeakSignature` though the signature is checked.
///
/// **Host names are matched as RFC 6125 and the CA/Browser Forum say**:
/// against the DNS names in the subject alternative name and never the
/// common name, whatever else the certificate holds; case-insensitively in
/// ASCII; with a wildcard only as the whole of the left-most label, matching
/// exactly one label, and only over at least two labels; an address only
/// against the address entries, as bytes.
///
/// **There is no revocation.** Nothing here fetches or reads a CRL or asks an
/// OCSP responder, so `X509RevocationMode.NoCheck` is the default and the
/// only mode that can succeed; asking for another is answered with
/// `RevocationStatusUnknown` on every element rather than silently ignored.
module Standard.Security.Cryptography.X509Certificates;

import Standard.Collections;
import Standard.Convert;
import Standard.Formats.Asn1;
import Standard.Security.Cryptography;

extern "C" void sl_fail(byte* message);

// --------------------------------------------------------------- reading

/// A read that failed as `CryptoError.Encoding`, which is what every
/// malformed part of a certificate is.
internal Result<T, CryptoError> ConvertAsnResult<T>(Result<T, AsnError> read)
{
    if (!read.Ok)
        return Fail(CryptoError.Encoding);
    return Ok(read.Value);
}

/// A context-specific tag, as every optional field of a certificate has.
internal Asn1Tag CreateContextTag(int number, bool constructed) =>
    new Asn1Tag(TagClass.ContextSpecific, number, constructed);

/// A `Time`: a `UTCTime` or a `GeneralizedTime`, as seconds since the epoch.
internal Result<long, CryptoError> ReadX509Time(AsnReader reader)
{
    Asn1Tag tag = try ConvertAsnResult(reader.PeekTag());
    if (tag == Asn1Tag.UtcTime)
        return ConvertAsnResult(reader.ReadUtcTime());
    return ConvertAsnResult(reader.ReadGeneralizedTime());
}

/// RFC 5280 §4.1.2.5: a `UTCTime` through 2049 and a `GeneralizedTime`
/// after it.
internal void WriteX509Time(AsnWriter writer, long seconds)
{
    if (writer.WriteUtcTime(seconds) != AsnError.None)
        writer.WriteGeneralizedTime(seconds);
}

/// `data` in upper-case hexadecimal, as .NET writes a thumbprint.
internal String FormatHexadecimalUpper(ReadOnlySpan<byte> data) =>
    Convert.ToHexString(data.ToArray(), true);

/// UTF-8 bytes as text.
internal String CreateStringFromBytes(ReadOnlySpan<byte> bytes)
{
    var built = new StringBuilder();
    built.AppendBytes(bytes.ToArray());
    return built.ToText();
}

/// Whether two runs of bytes are the same.
internal bool AreBytesEqual(ReadOnlySpan<byte> left, ReadOnlySpan<byte> right)
{
    if (left.Length != right.Length)
        return false;
    for (nuint i = 0u; i < left.Length; i++)
    {
        if (left[i] != right[i])
            return false;
    }
    return true;
}

// ----------------------------------------------------------- DNS names

/// `name` lower-cased with one trailing dot removed, or `None` when it is
/// not a DNS name this module compares: empty, a label empty, or a byte
/// other than an ASCII letter, a digit, `-`, `_` or `.`. A `*` is allowed
/// where `allowAsterisk` says, for a pattern rather than a host.
internal Optional<String> NormalizeDnsName(String name, bool allowAsterisk)
{
    byte[] text = name.ToBytes();
    nuint end = text.Length;
    if (end > 0u && text[end - 1u] == 46)                           // '.'
        end--;
    if (end == 0u)
        return None;

    var built = new StringBuilder();
    bool labelEmpty = true;
    for (nuint i = 0u; i < end; i++)
    {
        byte one = text[i];
        if (one == 46)
        {
            if (labelEmpty)
                return None;
            labelEmpty = true;
            built.AppendByte(one);
            continue;
        }

        if (one >= 65 && one <= 90)
        {
            one = (byte)(one + 32);
        }
        else if (!((one >= 97 && one <= 122) || (one >= 48 && one <= 57) || one == 45 ||
                   one == 95 || (one == 42 && allowAsterisk)))
        {
            return None;
        }
        labelEmpty = false;
        built.AppendByte(one);
    }

    if (labelEmpty)
        return None;
    return Some(built.ToText());
}

/// Whether the normalized `host` matches the normalized `pattern`: equal, or
/// under a wildcard that is the whole left-most label of a pattern with at
/// least two labels after it, standing for exactly one label.
internal bool MatchDnsNamePattern(String host, String pattern, bool allowWildcards)
{
    if (host == pattern)
        return !pattern.Contains('*');
    if (!allowWildcards || !pattern.StartsWith("*."))
        return false;

    String stem = pattern.Substring(2u);
    if (stem.Contains('*') || !stem.Contains('.'))
        return false;

    long dot = host.IndexOf('.');
    if (dot <= 0)
        return false;
    return host.Substring((nuint)dot + 1u) == stem;
}

/// Whether the normalized DNS `name` is inside the subtree `constraint`
/// names, as RFC 5280 §4.2.1.10 reads one: the name itself and everything
/// below it, or with a leading `.` only what is below it. An empty
/// constraint holds every name.
internal bool IsDnsNameInSubtree(String name, String constraint)
{
    String subtree = constraint.ToLowerAscii();
    if (subtree.IsEmpty)
        return true;
    if (subtree.StartsWith("."))
        return name.EndsWith(subtree) && name.ByteLength() > subtree.ByteLength();
    return name == subtree || name.EndsWith("." + subtree);
}

// ------------------------------------------------------------- addresses

/// Four decimal octets separated by dots, each 0 to 255 and none with a
/// leading zero, between `start` and `end` of `text`.
internal Optional<byte[]> ParseIPv4Literal(byte[] text, nuint start, nuint end)
{
    var address = new byte[4u];
    nuint at = start;
    for (nuint part = 0u; part < 4u; part++)
    {
        if (part > 0u)
        {
            if (at >= end || text[at] != 46)                        // '.'
                return None;
            at++;
        }

        nuint first = at;
        uint value = 0u;
        while (at < end && text[at] >= 48 && text[at] <= 57)
        {
            value = value * 10u + ((uint)text[at] - 48u);
            at++;
            if (at - first > 3u)
                return None;
        }

        nuint digits = at - first;
        if (digits == 0u || value > 255u || (digits > 1u && text[first] == 48))
            return None;
        address[part] = (byte)value;
    }

    if (at != end)
        return None;
    return Some(address);
}

/// The value of one hexadecimal digit, or 16 for anything else.
internal uint ParseHexadecimalDigit(byte digit)
{
    if (digit >= 48 && digit <= 57)
        return (uint)digit - 48u;
    if (digit >= 97 && digit <= 102)
        return (uint)digit - 87u;
    if (digit >= 65 && digit <= 70)
        return (uint)digit - 55u;
    return 16u;
}

/// RFC 4291 §2.2: eight groups of up to four hexadecimal digits, one run of
/// them written as `::`, and optionally the last two as a dotted IPv4
/// address. No zone.
internal Optional<byte[]> ParseIPv6Literal(byte[] text, nuint start, nuint end)
{
    var address = new byte[16u];
    nuint groups = 0u;
    long gap = -1;
    nuint at = start;

    if (end - start >= 2u && text[at] == 58 && text[at + 1u] == 58) // "::"
    {
        gap = 0;
        at += 2;
    }
    else if (at < end && text[at] == 58)
    {
        return None;
    }

    while (at < end)
    {
        nuint scan = at;
        bool dotted = false;
        while (scan < end && text[scan] != 58)
        {
            if (text[scan] == 46)
                dotted = true;
            scan++;
        }

        if (dotted)
        {
            if (scan != end || groups > 6u)
                return None;
            var tail = ParseIPv4Literal(text, at, end);
            if (!tail.Some)
                return None;
            for (nuint i = 0u; i < 4u; i++)
                address[groups * 2u + i] = tail.Value[i];
            groups += 2;
            break;
        }

        nuint length = scan - at;
        if (length == 0u || length > 4u || groups == 8u)
            return None;
        uint value = 0u;
        for (nuint i = at; i < scan; i++)
        {
            uint digit = ParseHexadecimalDigit(text[i]);
            if (digit > 15u)
                return None;
            value = (value << 4) | digit;
        }
        address[groups * 2u] = (byte)(value >> 8);
        address[groups * 2u + 1u] = (byte)(value & 0xFFu);
        groups++;

        at = scan;
        if (at == end)
            break;
        at++;
        if (at < end && text[at] == 58)
        {
            if (gap >= 0)
                return None;
            gap = (long)groups;
            at++;
        }
        else if (at == end)
        {
            return None;
        }
    }

    if (gap < 0)
    {
        if (groups != 8u)
            return None;
        return Some(address);
    }

    if (groups > 7u)
        return None;
    nuint moved = (groups - (nuint)gap) * 2u;
    nuint from = groups * 2u;
    for (nuint i = 0u; i < moved; i++)
        address[15u - i] = address[from - 1u - i];
    for (nuint i = (nuint)gap * 2u; i < 16u - moved; i++)
        address[i] = 0;
    return Some(address);
}

/// Whether `address` is inside `range`: an address and a mask of the same
/// length, as a name constraint holds one.
internal bool IsAddressInRange(ReadOnlySpan<byte> address, ReadOnlySpan<byte> range)
{
    if (range.Length != address.Length * 2u)
        return false;
    nuint width = address.Length;
    for (nuint i = 0u; i < width; i++)
    {
        byte mask = range[width + i];
        if ((address[i] & mask) != (range[i] & mask))
            return false;
    }
    return true;
}

// --------------------------------------------------- object identifiers

/// Whether this module decodes and acts on the extension `oid` names, so that
/// one marked critical may be accepted.
///
/// Certificate policies are understood in the sense that they constrain
/// nothing a chain here checks: no policy is ever required.
internal bool IsUnderstoodExtension(String oid)
{
    switch (oid)
    {
        case "2.5.29.14":                                           // subjectKeyIdentifier
        case "2.5.29.15":                                           // keyUsage
        case "2.5.29.17":                                           // subjectAltName
        case "2.5.29.19":                                           // basicConstraints
        case "2.5.29.30":                                           // nameConstraints
        case "2.5.29.32":                                           // certificatePolicies
        case "2.5.29.35":                                           // authorityKeyIdentifier
        case "2.5.29.37":                                           // extKeyUsage
            return true;
    }
    return false;
}

/// The hash a digest `AlgorithmIdentifier`'s identifier names, or `None`.
internal Optional<HashAlgorithmName> FindHashAlgorithmByOid(String oid)
{
    switch (oid)
    {
        case "1.3.14.3.2.26":
            return Some(HashAlgorithmName.Sha1);
        case "2.16.840.1.101.3.4.2.1":
            return Some(HashAlgorithmName.Sha256);
        case "2.16.840.1.101.3.4.2.2":
            return Some(HashAlgorithmName.Sha384);
        case "2.16.840.1.101.3.4.2.3":
            return Some(HashAlgorithmName.Sha512);
    }
    return None;
}

/// The identifier of a hash, for the other direction.
internal Optional<String> FindOidOfHashAlgorithm(HashAlgorithmName hash)
{
    if (hash == HashAlgorithmName.Sha1)
        return Some("1.3.14.3.2.26");
    if (hash == HashAlgorithmName.Sha256)
        return Some("2.16.840.1.101.3.4.2.1");
    if (hash == HashAlgorithmName.Sha384)
        return Some("2.16.840.1.101.3.4.2.2");
    if (hash == HashAlgorithmName.Sha512)
        return Some("2.16.840.1.101.3.4.2.3");
    return None;
}
