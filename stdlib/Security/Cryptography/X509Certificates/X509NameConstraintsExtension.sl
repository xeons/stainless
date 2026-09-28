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

/// Which names a CA may issue for: RFC 5280 §4.2.1.10, `2.5.29.30`. Not in
/// .NET, which reads the extension only through the platform's chain.
///
/// DNS names and IP address ranges are read out and enforced by
/// `X509Chain` over the leaf's subject alternative names: a name is
/// refused when it is inside an excluded subtree, or when there are
/// permitted subtrees of its kind and it is inside none of them. Subtrees
/// of the other kinds — directory names, e-mail addresses, URIs — are
/// checked to be well-formed and are not enforced.
///
/// A range is an address followed by a mask of the same length: eight bytes
/// for IPv4, thirty-two for IPv6.
public sealed class X509NameConstraintsExtension : X509Extension
{
    private String[] _permittedDnsNames;
    private byte[][] _permittedIPRanges;
    private String[] _excludedDnsNames;
    private byte[][] _excludedIPRanges;

    /// The extension with these subtrees.
    ///
    /// @param permittedDnsNames  DNS subtrees names MUST be inside, when not empty
    /// @param permittedIPRanges  address ranges addresses MUST be inside, when not
    ///                           empty; each MUST be 8 or 32 bytes, and this aborts
    ///                           otherwise
    /// @param excludedDnsNames   DNS subtrees no name may be inside
    /// @param excludedIPRanges   address ranges no address may be inside
    /// @param critical           whether it is critical, which RFC 5280 requires
    public X509NameConstraintsExtension(String[] permittedDnsNames, byte[][] permittedIPRanges,
                                        String[] excludedDnsNames, byte[][] excludedIPRanges,
                                        bool critical)
        : this(EncodeNameConstraints(permittedDnsNames, permittedIPRanges, excludedDnsNames,
                                     excludedIPRanges),
               critical, permittedDnsNames, permittedIPRanges, excludedDnsNames,
               excludedIPRanges)
    {
    }

    private X509NameConstraintsExtension(ReadOnlySpan<byte> rawData, bool critical,
                                         String[] permittedDnsNames, byte[][] permittedIPRanges,
                                         String[] excludedDnsNames, byte[][] excludedIPRanges)
    {
        base("2.5.29.30", rawData, critical);
        _permittedDnsNames = permittedDnsNames;
        _permittedIPRanges = permittedIPRanges;
        _excludedDnsNames = excludedDnsNames;
        _excludedIPRanges = excludedIPRanges;
    }

    /// The permitted DNS subtrees.
    public String[] PermittedDnsNames => _permittedDnsNames;

    /// The permitted address ranges.
    public byte[][] PermittedIPRanges => _permittedIPRanges;

    /// The excluded DNS subtrees.
    public String[] ExcludedDnsNames => _excludedDnsNames;

    /// The excluded address ranges.
    public byte[][] ExcludedIPRanges => _excludedIPRanges;

    /// Whether the normalized DNS name `name` is allowed. A wildcard name
    /// `*.stem` is allowed only when every name it could stand for is: its
    /// stem must be permitted, and no excluded subtree may lie under it.
    internal X509ChainStatusFlags CheckDnsName(String name)
    {
        bool wildcard = name.StartsWith("*.");
        String stem = wildcard ? name.Substring(2u) : name;

        foreach (String excluded in _excludedDnsNames)
        {
            if (IsDnsNameInSubtree(stem, excluded))
                return X509ChainStatusFlags.HasExcludedNameConstraint;
            String subtree = excluded.ToLowerAscii();
            if (subtree.StartsWith("."))
                subtree = subtree.Substring(1u);
            if (wildcard && IsDnsNameInSubtree(subtree, stem))
                return X509ChainStatusFlags.HasExcludedNameConstraint;
        }

        if (_permittedDnsNames.Length == 0u)
            return X509ChainStatusFlags.NoError;
        foreach (String permitted in _permittedDnsNames)
        {
            if (IsDnsNameInSubtree(stem, permitted))
                return X509ChainStatusFlags.NoError;
        }
        return X509ChainStatusFlags.HasNotPermittedNameConstraint;
    }

    /// Whether `address` is allowed.
    internal X509ChainStatusFlags CheckIPAddress(ReadOnlySpan<byte> address)
    {
        foreach (byte[] excluded in _excludedIPRanges)
        {
            if (IsAddressInRange(address, excluded))
                return X509ChainStatusFlags.HasExcludedNameConstraint;
        }

        bool anyOfKind = false;
        foreach (byte[] permitted in _permittedIPRanges)
        {
            if (permitted.Length != address.Length * 2u)
                continue;
            anyOfKind = true;
            if (IsAddressInRange(address, permitted))
                return X509ChainStatusFlags.NoError;
        }
        return anyOfKind ? X509ChainStatusFlags.HasNotPermittedNameConstraint
                         : X509ChainStatusFlags.NoError;
    }

    private static byte[] EncodeNameConstraints(String[] permittedDnsNames,
                                                byte[][] permittedIPRanges,
                                                String[] excludedDnsNames,
                                                byte[][] excludedIPRanges)
    {
        var writer = new AsnWriter();
        writer.PushSequence();
        if (permittedDnsNames.Length > 0u || permittedIPRanges.Length > 0u)
        {
            writer.PushSequence(CreateContextTag(0, true));
            WriteGeneralSubtrees(writer, permittedDnsNames, permittedIPRanges);
            writer.PopSequence();
        }
        if (excludedDnsNames.Length > 0u || excludedIPRanges.Length > 0u)
        {
            writer.PushSequence(CreateContextTag(1, true));
            WriteGeneralSubtrees(writer, excludedDnsNames, excludedIPRanges);
            writer.PopSequence();
        }
        writer.PopSequence();
        return writer.Encode();
    }

    private static void WriteGeneralSubtrees(AsnWriter writer, String[] dnsNames,
                                             byte[][] ipRanges)
    {
        foreach (String name in dnsNames)
        {
            writer.PushSequence();
            if (writer.WriteCharacterString(UniversalTagNumber.IA5String, name,
                                            CreateContextTag(2, false)) != AsnError.None)
            {
                sl_fail("X509NameConstraintsExtension: a DNS name is not ASCII");
            }
            writer.PopSequence();
        }
        foreach (byte[] range in ipRanges)
        {
            if (range.Length != 8u && range.Length != 32u)
                sl_fail("X509NameConstraintsExtension: an address range is 8 or 32 bytes");
            writer.PushSequence();
            writer.WriteOctetString(range, CreateContextTag(7, false));
            writer.PopSequence();
        }
    }

    internal static Result<X509NameConstraintsExtension, CryptoError> DecodeExtension(
        ReadOnlySpan<byte> rawData, bool critical)
    {
        var document = new AsnReader(rawData, AsnEncodingRules.Der);
        AsnReader sequence = try ConvertAsnResult(document.ReadSequence());
        if (document.VerifyEndOfData() != AsnError.None)
            return Fail(CryptoError.Encoding);

        var permittedDnsNames = new List<String>();
        var permittedIPRanges = new List<byte[]>();
        var excludedDnsNames = new List<String>();
        var excludedIPRanges = new List<byte[]>();
        if (sequence.HasData &&
            try ConvertAsnResult(sequence.PeekTag()) == CreateContextTag(0, true))
        {
            AsnReader permitted =
                try ConvertAsnResult(sequence.ReadSequence(CreateContextTag(0, true)));
            try ReadGeneralSubtrees(permitted, permittedDnsNames, permittedIPRanges);
        }
        if (sequence.HasData)
        {
            AsnReader excluded =
                try ConvertAsnResult(sequence.ReadSequence(CreateContextTag(1, true)));
            try ReadGeneralSubtrees(excluded, excludedDnsNames, excludedIPRanges);
        }
        if (sequence.VerifyEndOfData() != AsnError.None)
            return Fail(CryptoError.Encoding);

        return Ok(new X509NameConstraintsExtension(
            rawData, critical, permittedDnsNames.ToArray(), permittedIPRanges.ToArray(),
            excludedDnsNames.ToArray(), excludedIPRanges.ToArray()));
    }

    /// `GeneralSubtrees`: one or more `GeneralSubtree`, whose minimum and
    /// maximum RFC 5280 fixes and this reads past.
    private static Result<bool, CryptoError> ReadGeneralSubtrees(
        AsnReader subtrees, List<String> dnsNames, List<byte[]> ipRanges)
    {
        if (!subtrees.HasData)
            return Fail(CryptoError.Encoding);
        while (subtrees.HasData)
        {
            AsnReader subtree = try ConvertAsnResult(subtrees.ReadSequence());
            Asn1Tag tag = try ConvertAsnResult(subtree.PeekTag());
            if (tag.TagClass != TagClass.ContextSpecific || tag.TagValue < 0 || tag.TagValue > 8)
                return Fail(CryptoError.Encoding);

            switch (tag.TagValue)
            {
                case 2:
                    dnsNames.Add(
                        try X509SubjectAlternativeNameExtension.ReadGeneralNameText(subtree, 2));
                    break;
                case 7:
                {
                    ReadOnlySpan<byte> range =
                        try ConvertAsnResult(subtree.ReadOctetString(CreateContextTag(7, false)));
                    if (range.Length != 8u && range.Length != 32u)
                        return Fail(CryptoError.Encoding);
                    ipRanges.Add(range.ToArray());
                    break;
                }
                default:
                    try ConvertAsnResult(subtree.ReadEncodedValue());
                    break;
            }

            // minimum [0] and maximum [1], if they are there at all.
            while (subtree.HasData)
                try ConvertAsnResult(subtree.ReadEncodedValue());
        }
        return Ok(true);
    }
}
