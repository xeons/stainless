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
/// DNS names, IP address ranges, directory names and e-mail addresses are
/// read out and enforced by `X509Chain`: a name is refused when it is inside
/// an excluded subtree, or when there are permitted subtrees of its kind and
/// it is inside none of them. Subtrees of the other kinds, URIs among them,
/// are checked to be well-formed and are not enforced, so a critical
/// extension holding one is an extension this module does not support.
///
/// A range is an address followed by a mask of the same length: eight bytes
/// for IPv4, thirty-two for IPv6.
public sealed class X509NameConstraintsExtension : X509Extension
{
    private String[] _permittedDnsNames;
    private byte[][] _permittedIPRanges;
    private String[] _excludedDnsNames;
    private byte[][] _excludedIPRanges;
    private X500DistinguishedName[] _permittedDirectoryNames;
    private X500DistinguishedName[] _excludedDirectoryNames;
    private String[] _permittedEmailAddresses;
    private String[] _excludedEmailAddresses;
    private bool _hasUnenforcedSubtrees;

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
               excludedIPRanges, new X500DistinguishedName[0u], new X500DistinguishedName[0u],
               new String[0u], new String[0u], false)
    {
    }

    private X509NameConstraintsExtension(ReadOnlySpan<byte> rawData, bool critical,
                                         String[] permittedDnsNames, byte[][] permittedIPRanges,
                                         String[] excludedDnsNames, byte[][] excludedIPRanges,
                                         X500DistinguishedName[] permittedDirectoryNames,
                                         X500DistinguishedName[] excludedDirectoryNames,
                                         String[] permittedEmailAddresses,
                                         String[] excludedEmailAddresses,
                                         bool hasUnenforcedSubtrees)
    {
        base("2.5.29.30", rawData, critical);
        _permittedDnsNames = permittedDnsNames;
        _permittedIPRanges = permittedIPRanges;
        _excludedDnsNames = excludedDnsNames;
        _excludedIPRanges = excludedIPRanges;
        _permittedDirectoryNames = permittedDirectoryNames;
        _excludedDirectoryNames = excludedDirectoryNames;
        _permittedEmailAddresses = permittedEmailAddresses;
        _excludedEmailAddresses = excludedEmailAddresses;
        _hasUnenforcedSubtrees = hasUnenforcedSubtrees;
    }

    /// The permitted DNS subtrees.
    public String[] PermittedDnsNames => _permittedDnsNames;

    /// The permitted address ranges.
    public byte[][] PermittedIPRanges => _permittedIPRanges;

    /// The excluded DNS subtrees.
    public String[] ExcludedDnsNames => _excludedDnsNames;

    /// The excluded address ranges.
    public byte[][] ExcludedIPRanges => _excludedIPRanges;

    /// The permitted directory subtrees.
    public X500DistinguishedName[] PermittedDirectoryNames => _permittedDirectoryNames;

    /// The excluded directory subtrees.
    public X500DistinguishedName[] ExcludedDirectoryNames => _excludedDirectoryNames;

    /// The permitted e-mail subtrees: a mailbox, a host, or with a leading
    /// `.` every host under a domain.
    public String[] PermittedEmailAddresses => _permittedEmailAddresses;

    /// The excluded e-mail subtrees.
    public String[] ExcludedEmailAddresses => _excludedEmailAddresses;

    /// Whether a subtree is of a kind this module does not enforce: a URI,
    /// an `otherName`, an X.400 address, an EDI party or a registered
    /// identifier.
    internal bool HasUnenforcedSubtrees => _hasUnenforcedSubtrees;

    /// Whether there is a DNS subtree, permitted or excluded.
    internal bool HasDnsConstraints =>
        _permittedDnsNames.Length > 0u || _excludedDnsNames.Length > 0u;

    /// Whether there is an e-mail subtree, permitted or excluded.
    internal bool HasEmailConstraints =>
        _permittedEmailAddresses.Length > 0u || _excludedEmailAddresses.Length > 0u;

    /// Whether the normalized DNS name `name` is allowed. A wildcard name
    /// `*.stem` is allowed only when every name it could stand for is: each
    /// is permitted, and no excluded subtree may lie under it.
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
            // `*.example.com` stands only for names below `.example.com`.
            if (wildcard && permitted.StartsWith(".") &&
                permitted.Substring(1u).ToLowerAscii() == stem)
            {
                return X509ChainStatusFlags.NoError;
            }
        }
        return X509ChainStatusFlags.HasNotPermittedNameConstraint;
    }

    /// Whether the directory name `name` is allowed. An empty name names
    /// nothing and is allowed.
    internal X509ChainStatusFlags CheckDirectoryName(X500DistinguishedName name)
    {
        if (name.IsEmpty)
            return X509ChainStatusFlags.NoError;
        foreach (X500DistinguishedName excluded in _excludedDirectoryNames)
        {
            if (name.IsInSubtree(excluded))
                return X509ChainStatusFlags.HasExcludedNameConstraint;
        }

        if (_permittedDirectoryNames.Length == 0u)
            return X509ChainStatusFlags.NoError;
        foreach (X500DistinguishedName permitted in _permittedDirectoryNames)
        {
            if (name.IsInSubtree(permitted))
                return X509ChainStatusFlags.NoError;
        }
        return X509ChainStatusFlags.HasNotPermittedNameConstraint;
    }

    /// Whether the e-mail address `address` is allowed. One that is not
    /// `local@host` with a DNS host is refused when there is any e-mail
    /// subtree at all.
    internal X509ChainStatusFlags CheckEmailAddress(String address)
    {
        if (!HasEmailConstraints)
            return X509ChainStatusFlags.NoError;

        long at = address.LastIndexOf('@');
        if (at <= 0)
            return X509ChainStatusFlags.HasNotPermittedNameConstraint;
        String local = address.Substring(0u, (nuint)at);
        var host = NormalizeDnsName(address.Substring((nuint)at + 1u), false);
        if (!host.Some)
            return X509ChainStatusFlags.HasNotPermittedNameConstraint;

        foreach (String excluded in _excludedEmailAddresses)
        {
            if (IsEmailAddressInSubtree(local, host.Value, excluded))
                return X509ChainStatusFlags.HasExcludedNameConstraint;
        }

        if (_permittedEmailAddresses.Length == 0u)
            return X509ChainStatusFlags.NoError;
        foreach (String permitted in _permittedEmailAddresses)
        {
            if (IsEmailAddressInSubtree(local, host.Value, permitted))
                return X509ChainStatusFlags.NoError;
        }
        return X509ChainStatusFlags.HasNotPermittedNameConstraint;
    }

    /// RFC 5280 section 4.2.1.10: a constraint with `@` is one mailbox, whose
    /// local part compares exactly; one with a leading `.` is every host
    /// below that domain; any other is every mailbox on that one host.
    private static bool IsEmailAddressInSubtree(String local, String host, String constraint)
    {
        long at = constraint.LastIndexOf('@');
        if (at >= 0)
        {
            if (constraint.Substring(0u, (nuint)at) != local)
                return false;
            var wanted = NormalizeDnsName(constraint.Substring((nuint)at + 1u), false);
            return wanted.Some && wanted.Value == host;
        }

        String subtree = constraint.ToLowerAscii();
        if (subtree.StartsWith("."))
            return host.EndsWith(subtree) && host.ByteLength() > subtree.ByteLength();
        var normalized = NormalizeDnsName(subtree, false);
        return normalized.Some && normalized.Value == host;
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

        var permitted = new GeneralSubtrees();
        var excluded = new GeneralSubtrees();
        if (sequence.HasData &&
            try ConvertAsnResult(sequence.PeekTag()) == CreateContextTag(0, true))
        {
            AsnReader subtrees =
                try ConvertAsnResult(sequence.ReadSequence(CreateContextTag(0, true)));
            try ReadGeneralSubtrees(subtrees, permitted);
        }
        if (sequence.HasData)
        {
            AsnReader subtrees =
                try ConvertAsnResult(sequence.ReadSequence(CreateContextTag(1, true)));
            try ReadGeneralSubtrees(subtrees, excluded);
        }
        if (sequence.VerifyEndOfData() != AsnError.None)
            return Fail(CryptoError.Encoding);

        return Ok(new X509NameConstraintsExtension(
            rawData, critical, permitted.DnsNames.ToArray(), permitted.IPRanges.ToArray(),
            excluded.DnsNames.ToArray(), excluded.IPRanges.ToArray(),
            permitted.DirectoryNames.ToArray(), excluded.DirectoryNames.ToArray(),
            permitted.EmailAddresses.ToArray(), excluded.EmailAddresses.ToArray(),
            permitted.HasUnenforced || excluded.HasUnenforced));
    }

    /// `GeneralSubtrees`: one or more `GeneralSubtree`, whose minimum and
    /// maximum RFC 5280 fixes and this reads past.
    private static Result<bool, CryptoError> ReadGeneralSubtrees(AsnReader subtrees,
                                                                 GeneralSubtrees into)
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
                case 1:
                    into.EmailAddresses.Add(
                        try X509SubjectAlternativeNameExtension.ReadGeneralNameText(subtree, 1));
                    break;
                case 2:
                    into.DnsNames.Add(
                        try X509SubjectAlternativeNameExtension.ReadGeneralNameText(subtree, 2));
                    break;
                case 4:
                    into.DirectoryNames.Add(
                        try X509SubjectAlternativeNameExtension.ReadGeneralNameDirectory(subtree));
                    break;
                case 7:
                {
                    ReadOnlySpan<byte> range =
                        try ConvertAsnResult(subtree.ReadOctetString(CreateContextTag(7, false)));
                    if (range.Length != 8u && range.Length != 32u)
                        return Fail(CryptoError.Encoding);
                    into.IPRanges.Add(range.ToArray());
                    break;
                }
                default:
                    into.HasUnenforced = true;
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
