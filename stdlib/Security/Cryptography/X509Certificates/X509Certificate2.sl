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

import Standard.Time;
import Standard.Formats.Asn1;
import Standard.Security.Cryptography;

/// An X.509 certificate, read from DER or PEM: .NET's `X509Certificate2`,
/// without a private key.
///
/// ```csharp
/// var certificate = try X509Certificate2.FromPem(File.ReadAllText("server.pem"));
/// Console.WriteLine(certificate.Subject);        // CN=www.example.com, O=Example, C=US
/// Console.WriteLine(certificate.Thumbprint);     // the SHA-1, as .NET and Windows show it
/// bool mine = certificate.MatchesHostname("www.example.com");
/// ```
///
/// **Everything is read when the certificate is**, and checked then: the DER,
/// the names, the key's `SubjectPublicKeyInfo`, and every extension this
/// module knows. What comes back is immutable, so one MAY be shared between
/// threads. The signature is not checked here; that is `X509Chain`'s job,
/// since it needs the issuer.
///
/// @see X509Chain
public sealed class X509Certificate2
{
    private byte[] _rawData;
    private ReadOnlySpan<byte> _signedPart;
    private int _version;
    private byte[] _serialNumber;
    private String _signatureAlgorithm;
    private byte[] _signatureParameters;
    private byte[] _signature;
    private X500DistinguishedName _issuerName;
    private X500DistinguishedName _subjectName;
    private long _notBefore;
    private long _notAfter;
    private PublicKey _publicKey;
    private X509ExtensionCollection _extensions;
    private byte[] _sha1;
    private byte[] _sha256;

    private X509BasicConstraintsExtension? _basicConstraints;
    private X509KeyUsageExtension? _keyUsage;
    private X509EnhancedKeyUsageExtension? _enhancedKeyUsage;
    private X509SubjectAlternativeNameExtension? _subjectAlternativeName;
    private X509SubjectKeyIdentifierExtension? _subjectKeyIdentifier;
    private X509AuthorityKeyIdentifierExtension? _authorityKeyIdentifier;
    private X509NameConstraintsExtension? _nameConstraints;

    private X509Certificate2(byte[] rawData, ReadOnlySpan<byte> signedPart, int version,
                             byte[] serialNumber, String signatureAlgorithm,
                             byte[] signatureParameters, byte[] signature,
                             X500DistinguishedName issuerName, X500DistinguishedName subjectName,
                             long notBefore, long notAfter, PublicKey publicKey,
                             X509ExtensionCollection extensions)
    {
        _rawData = rawData;
        _signedPart = signedPart;
        _version = version;
        _serialNumber = serialNumber;
        _signatureAlgorithm = signatureAlgorithm;
        _signatureParameters = signatureParameters;
        _signature = signature;
        _issuerName = issuerName;
        _subjectName = subjectName;
        _notBefore = notBefore;
        _notAfter = notAfter;
        _publicKey = publicKey;
        _extensions = extensions;
        _sha1 = Sha1.HashData(rawData);
        _sha256 = Sha256.HashData(rawData);

        foreach (X509Extension extension in extensions)
        {
            if (extension is X509BasicConstraintsExtension basic)
            {
                _basicConstraints = basic;
            }
            else if (extension is X509KeyUsageExtension usage)
            {
                _keyUsage = usage;
            }
            else if (extension is X509EnhancedKeyUsageExtension enhanced)
            {
                _enhancedKeyUsage = enhanced;
            }
            else if (extension is X509SubjectAlternativeNameExtension names)
            {
                _subjectAlternativeName = names;
            }
            else if (extension is X509SubjectKeyIdentifierExtension subjectKey)
            {
                _subjectKeyIdentifier = subjectKey;
            }
            else if (extension is X509AuthorityKeyIdentifierExtension authorityKey)
            {
                _authorityKeyIdentifier = authorityKey;
            }
            else if (extension is X509NameConstraintsExtension constraints)
            {
                _nameConstraints = constraints;
            }
        }
    }

    // ------------------------------------------------------------ reading one

    /// The certificate `data` holds, as DER.
    ///
    /// @param data  exactly one `Certificate`, with nothing after it
    /// @failure CryptoError.Encoding  it is not one, as the module's summary reads RFC 5280
    public static Result<X509Certificate2, CryptoError> FromDer(ReadOnlySpan<byte> data)
    {
        byte[] rawData = data.ToArray();
        var document = new AsnReader(rawData, AsnEncodingRules.Der);
        AsnReader certificate = try ConvertAsnResult(document.ReadSequence());
        if (document.VerifyEndOfData() != AsnError.None)
            return Fail(CryptoError.Encoding);

        ReadOnlySpan<byte> signedPart = try ConvertAsnResult(certificate.ReadEncodedValue());
        ReadOnlySpan<byte> outerAlgorithm = try ConvertAsnResult(certificate.ReadEncodedValue());
        ReadOnlySpan<byte> signature =
            try ConvertAsnResult(certificate.ReadBitString(out int unusedBits));
        if (unusedBits != 0 || certificate.VerifyEndOfData() != AsnError.None)
            return Fail(CryptoError.Encoding);

        var outer = new AsnReader(signedPart, AsnEncodingRules.Der);
        AsnReader tbs = try ConvertAsnResult(outer.ReadSequence());

        long version = 0;
        if (try ConvertAsnResult(tbs.PeekTag()) == CreateContextTag(0, true))
        {
            AsnReader explicitVersion = try ConvertAsnResult(tbs.ReadSequence(CreateContextTag(0, true)));
            version = try ConvertAsnResult(explicitVersion.ReadInt64());
            // Version 1 is the DEFAULT, which DER leaves out.
            if (explicitVersion.VerifyEndOfData() != AsnError.None || version < 1 || version > 2)
                return Fail(CryptoError.Encoding);
        }

        ReadOnlySpan<byte> serialNumber = try ConvertAsnResult(tbs.ReadIntegerBytes());
        if (serialNumber.Length > 20u)
            return Fail(CryptoError.Encoding);

        ReadOnlySpan<byte> innerAlgorithm = try ConvertAsnResult(tbs.ReadEncodedValue());
        if (!AreBytesEqual(innerAlgorithm, outerAlgorithm))
            return Fail(CryptoError.Encoding);
        var algorithm = new AsnReader(innerAlgorithm, AsnEncodingRules.Der);
        AsnReader identifier = try ConvertAsnResult(algorithm.ReadSequence());
        String signatureAlgorithm = try ConvertAsnResult(identifier.ReadObjectIdentifier());
        byte[] signatureParameters = new byte[0u];
        if (identifier.HasData)
            signatureParameters = (try ConvertAsnResult(identifier.ReadEncodedValue())).ToArray();
        if (identifier.VerifyEndOfData() != AsnError.None)
            return Fail(CryptoError.Encoding);

        X500DistinguishedName issuerName =
            try X500DistinguishedName.FromDer(try ConvertAsnResult(tbs.ReadEncodedValue()));

        AsnReader validity = try ConvertAsnResult(tbs.ReadSequence());
        long notBefore = try ReadX509Time(validity);
        long notAfter = try ReadX509Time(validity);
        if (validity.VerifyEndOfData() != AsnError.None)
            return Fail(CryptoError.Encoding);

        X500DistinguishedName subjectName =
            try X500DistinguishedName.FromDer(try ConvertAsnResult(tbs.ReadEncodedValue()));
        PublicKey publicKey =
            try PublicKey.DecodeSubjectPublicKeyInfo(try ConvertAsnResult(tbs.ReadEncodedValue()));

        // issuerUniqueID [1] and subjectUniqueID [2], which version 1 lacks.
        for (int number = 1; number <= 2; number++)
        {
            if (tbs.HasData && try ConvertAsnResult(tbs.PeekTag()) == CreateContextTag(number, false))
            {
                if (version < 1)
                    return Fail(CryptoError.Encoding);
                try ConvertAsnResult(tbs.ReadEncodedValue());
            }
        }

        X509ExtensionCollection extensions = X509ExtensionCollection.CreateEmpty();
        if (tbs.HasData)
        {
            if (version != 2)
                return Fail(CryptoError.Encoding);
            AsnReader wrapper = try ConvertAsnResult(tbs.ReadSequence(CreateContextTag(3, true)));
            AsnReader list = try ConvertAsnResult(wrapper.ReadSequence());
            if (wrapper.VerifyEndOfData() != AsnError.None)
                return Fail(CryptoError.Encoding);
            extensions = try X509ExtensionCollection.DecodeExtensions(list);
        }
        if (tbs.VerifyEndOfData() != AsnError.None || outer.VerifyEndOfData() != AsnError.None)
            return Fail(CryptoError.Encoding);

        return Ok(new X509Certificate2(
            rawData, signedPart, (int)version + 1, serialNumber.ToArray(), signatureAlgorithm,
            signatureParameters, signature.ToArray(), issuerName, subjectName, notBefore,
            notAfter, publicKey, extensions));
    }

    /// The first `CERTIFICATE` block in `text`, as .NET's `CreateFromPem`
    /// finds it. Blocks with other labels are passed over.
    ///
    /// @param text  PEM, perhaps among other text
    /// @failure CryptoError.Encoding  there is no `CERTIFICATE` block, or the first
    ///                                one does not hold a certificate
    public static Result<X509Certificate2, CryptoError> FromPem(String text)
    {
        nuint at = 0u;
        byte[] bytes = text.ToBytes();
        while (PemEncoding.FindUtf8(bytes, at) is Some block)
        {
            if (block.Value.Label == "CERTIFICATE")
                return FromDer(block.Value.Data);
            at = block.Value.Location.End.Value;
        }
        return Fail(CryptoError.Encoding);
    }

    // ------------------------------------------------------------ the fields

    /// The whole certificate, as DER: a copy, so that changing it changes
    /// nothing here.
    public byte[] RawData => _rawData[:].ToArray();

    /// 1, 2 or 3.
    public int Version => _version;

    /// The serial number in upper-case hexadecimal, as its DER contents are
    /// written: `00FF` for a positive number whose top bit is set.
    public String SerialNumber => FormatHexadecimalUpper(_serialNumber);

    /// The serial number's DER contents, big-endian and two's complement.
    public byte[] SerialNumberBytes => _serialNumber;

    /// The signature algorithm, dotted: `1.3.101.112` for Ed25519,
    /// `1.2.840.10045.4.3.2` for ECDSA with SHA-256.
    public String SignatureAlgorithm => _signatureAlgorithm;

    /// Who issued it.
    public X500DistinguishedName IssuerName => _issuerName;

    /// Who it is for.
    public X500DistinguishedName SubjectName => _subjectName;

    /// `IssuerName.Name`.
    public String Issuer => _issuerName.Name;

    /// `SubjectName.Name`.
    public String Subject => _subjectName.Name;

    /// The first moment it is valid, in seconds since the epoch.
    public long NotBefore => _notBefore;

    /// The last moment it is valid, in seconds since the epoch.
    public long NotAfter => _notAfter;

    /// The subject's key.
    public PublicKey PublicKey => _publicKey;

    /// Every extension.
    public X509ExtensionCollection Extensions => _extensions;

    /// The SHA-1 of the DER in upper-case hexadecimal: what .NET, Windows and
    /// `openssl x509 -fingerprint` show.
    public String Thumbprint => FormatHexadecimalUpper(_sha1);

    /// The SHA-256 of the DER in upper-case hexadecimal.
    public String Sha256Thumbprint => FormatHexadecimalUpper(_sha256);

    /// Whether the issuer and the subject are the same name, which a root's
    /// are and a leaf's usually are not.
    public bool IsSelfIssued => _issuerName.Equals(_subjectName);

    /// The basic constraints extension, or null.
    public X509BasicConstraintsExtension? BasicConstraints => _basicConstraints;

    /// The key usage extension, or null.
    public X509KeyUsageExtension? KeyUsage => _keyUsage;

    /// The extended key usage extension, or null.
    public X509EnhancedKeyUsageExtension? EnhancedKeyUsage => _enhancedKeyUsage;

    /// The subject alternative name extension, or null.
    public X509SubjectAlternativeNameExtension? SubjectAlternativeName => _subjectAlternativeName;

    /// The subject key identifier extension, or null.
    public X509SubjectKeyIdentifierExtension? SubjectKeyIdentifier => _subjectKeyIdentifier;

    /// The authority key identifier extension, or null.
    public X509AuthorityKeyIdentifierExtension? AuthorityKeyIdentifier => _authorityKeyIdentifier;

    /// The name constraints extension, or null.
    public X509NameConstraintsExtension? NameConstraints => _nameConstraints;

    /// The part the signature covers, as DER.
    internal ReadOnlySpan<byte> SignedPart => _signedPart;

    /// The signature algorithm's parameters as DER, or empty.
    internal byte[] SignatureParameters => _signatureParameters;

    /// The signature.
    internal byte[] Signature => _signature;

    /// The SHA-256 of the DER, which is how two certificates are told apart.
    internal byte[] Identity => _sha256;

    // ------------------------------------------------------------ asking it

    /// `NotBefore` as a `DateTimeOffset`.
    ///
    /// @failure CryptoError.Parameter  the moment is outside 1677 to 2262, which is what a
    ///                                 `DateTimeOffset` holds
    public Result<DateTimeOffset, CryptoError> GetNotBeforeDateTimeOffset() =>
        ConvertSecondsToDateTimeOffset(_notBefore);

    /// `NotAfter` as a `DateTimeOffset`.
    ///
    /// @failure CryptoError.Parameter  the moment is outside 1677 to 2262, which is what a
    ///                                 `DateTimeOffset` holds
    public Result<DateTimeOffset, CryptoError> GetNotAfterDateTimeOffset() =>
        ConvertSecondsToDateTimeOffset(_notAfter);

    private static Result<DateTimeOffset, CryptoError> ConvertSecondsToDateTimeOffset(long seconds)
    {
        var converted = ConvertAsnTimeToDateTimeOffset(seconds);
        if (!converted.Ok)
            return Fail(CryptoError.Parameter);
        return Ok(converted.Value);
    }

    /// The hash of the DER under `hashAlgorithm`.
    ///
    /// @failure CryptoError.Unsupported  `hashAlgorithm` is not one this library has
    public Result<byte[], CryptoError> GetCertHash(HashAlgorithmName hashAlgorithm)
    {
        IHashAlgorithm hash = try hashAlgorithm.CreateHashAlgorithm();
        hash.AppendData(_rawData);
        return Ok(hash.GetHashAndReset());
    }

    /// The same, in upper-case hexadecimal.
    ///
    /// @failure CryptoError.Unsupported  `hashAlgorithm` is not one this library has
    public Result<String, CryptoError> GetCertHashString(HashAlgorithmName hashAlgorithm) =>
        Ok(FormatHexadecimalUpper(try GetCertHash(hashAlgorithm)));

    /// The certificate as PEM, with a `CERTIFICATE` label and no newline after
    /// the last line.
    public String ExportCertificatePem() => PemEncoding.Write("CERTIFICATE", _rawData);

    /// Whether `other` is this certificate, byte for byte.
    public bool Equals(X509Certificate2 other) => AreBytesEqual(_sha256, other._sha256);

    /// Whether the certificate names `hostname`, by RFC 6125 and the CA/Browser
    /// Forum's rules.
    ///
    /// - **Only the subject alternative name is consulted.** A certificate
    ///   with no DNS name there matches no host name, whatever its common name
    ///   says; no current browser falls back, and neither does this.
    /// - A DNS name compares case-insensitively in ASCII, with one trailing
    ///   dot on either side ignored. A name that is not ASCII letters, digits,
    ///   `-`, `_` and dots matches nothing; an internationalized name MUST be
    ///   given as its `xn--` form.
    /// - A wildcard is only the whole left-most label, `*.example.com`; it
    ///   stands for exactly one non-empty label, and is honoured only with at
    ///   least two labels after it, so `*.com` matches nothing. Nor does a
    ///   wildcard over a common second-level label under a country code,
    ///   `*.co.uk` or `*.com.au`; other public suffixes are not known.
    /// - An address — dotted IPv4, or IPv6 with or without brackets —
    ///   matches only an `iPAddress` entry, compared as bytes, and never a DNS
    ///   name that spells it.
    ///
    /// @param hostname        what the client asked to connect to
    /// @param allowWildcards  whether a wildcard entry may match
    public bool MatchesHostname(String hostname, bool allowWildcards = true)
    {
        X509SubjectAlternativeNameExtension? names = _subjectAlternativeName;
        if (names == null)
            return false;

        var address = ParseHostAddress(hostname, out bool isAddress);
        if (isAddress)
        {
            if (!address.Some)
                return false;
            foreach (byte[] entry in names.IPAddresses)
            {
                if (AreBytesEqual(entry, address.Value))
                    return true;
            }
            return false;
        }

        var host = NormalizeDnsName(hostname, false);
        if (!host.Some)
            return false;
        foreach (String entry in names.DnsNames)
        {
            var pattern = NormalizeDnsName(entry, true);
            if (pattern.Some && MatchDnsNamePattern(host.Value, pattern.Value, allowWildcards))
                return true;
        }
        return false;
    }

    /// The address `hostname` spells, and in `isAddress` whether it is
    /// written as one at all: in brackets, with a colon, or all digits and
    /// dots. One that is written as an address and is not a valid one is
    /// `None` with `isAddress` set.
    private static Optional<byte[]> ParseHostAddress(String hostname, out bool isAddress)
    {
        byte[] text = hostname.ToBytes();
        nuint end = text.Length;
        isAddress = true;
        if (end >= 2u && text[0u] == 91 && text[end - 1u] == 93)     // '[' and ']'
            return ParseIPv6Literal(text, 1u, end - 1u);

        bool digitsAndDots = end > 0u;
        foreach (byte one in text)
        {
            if (one == 58)                                              // ':'
                return ParseIPv6Literal(text, 0u, end);
            if (!(one == 46 || (one >= 48 && one <= 57)))
                digitsAndDots = false;
        }
        if (digitsAndDots)
            return ParseIPv4Literal(text, 0u, end);

        isAddress = false;
        return None;
    }
}
