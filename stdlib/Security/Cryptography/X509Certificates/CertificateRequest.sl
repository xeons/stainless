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

/// Makes a certificate: .NET's `CertificateRequest`.
///
/// ```csharp
/// var rootKey = try X509SignatureGenerator.CreateForEd25519(Ed25519.GeneratePrivateKey());
/// var rootRequest = new CertificateRequest(rootName, rootKey, HashAlgorithmName.Sha256);
/// rootRequest.CertificateExtensions.Add(new X509BasicConstraintsExtension(true, false, 0, true));
/// var root = try rootRequest.CreateSelfSigned(notBefore, notAfter);
///
/// var leafRequest = new CertificateRequest(leafName, leafKey.PublicKey, HashAlgorithmName.Sha256);
/// var leaf = try leafRequest.Create(root, rootKey, notBefore, notAfter, serial);
/// ```
///
/// The certificate is version 3, its validity a `UTCTime` through 2049 and a
/// `GeneralizedTime` after, and its extensions exactly those added, in that
/// order: nothing is added on the caller's behalf, as .NET adds nothing.
/// What comes back is read back through `X509Certificate2.FromDer`, so it is
/// what any reader of it will see.
public sealed class CertificateRequest
{
    private X500DistinguishedName _subjectName;
    private PublicKey _publicKey;
    private HashAlgorithmName _hashAlgorithm;
    private X509SignatureGenerator? _generator;
    private List<X509Extension> _extensions;

    /// A request for `subjectName` with the key `key` signs with, which can be
    /// self-signed.
    ///
    /// @param subjectName    who the certificate is for
    /// @param key            the subject's key, private half included
    /// @param hashAlgorithm  the hash a signature is made over; Ed25519 ignores it
    public CertificateRequest(X500DistinguishedName subjectName, X509SignatureGenerator key,
                              HashAlgorithmName hashAlgorithm)
    {
        _subjectName = subjectName;
        _publicKey = key.PublicKey;
        _hashAlgorithm = hashAlgorithm;
        _generator = key;
        _extensions = new List<X509Extension>();
    }

    /// A request for `subjectName` with only a public key, which another
    /// key must sign.
    ///
    /// @param subjectName    who the certificate is for
    /// @param publicKey      the subject's key
    /// @param hashAlgorithm  the hash the issuer signs over; Ed25519 ignores it
    public CertificateRequest(X500DistinguishedName subjectName, PublicKey publicKey,
                              HashAlgorithmName hashAlgorithm)
    {
        _subjectName = subjectName;
        _publicKey = publicKey;
        _hashAlgorithm = hashAlgorithm;
        _generator = null;
        _extensions = new List<X509Extension>();
    }

    /// Who the certificate is for.
    public X500DistinguishedName SubjectName => _subjectName;

    /// The subject's key.
    public PublicKey PublicKey => _publicKey;

    /// The hash a signature is made over.
    public HashAlgorithmName HashAlgorithm => _hashAlgorithm;

    /// The extensions the certificate will carry, in order. No two MAY have
    /// the same identifier.
    public List<X509Extension> CertificateExtensions => _extensions;

    /// The certificate signed by its own key, with a random positive serial
    /// number of sixteen bytes.
    ///
    /// @param notBefore  the first moment it is valid, in seconds since the epoch
    /// @param notAfter   the last, no earlier than `notBefore`
    /// @failure CryptoError.InvalidKey  the request was made with a public key only
    /// @failure CryptoError.Parameter   `notAfter` is before `notBefore`, or either is
    ///                                  outside the years 0 to 9999
    /// @failure CryptoError.NoEntropy   the platform would not supply a serial number
    public Result<X509Certificate2, CryptoError> CreateSelfSigned(long notBefore, long notAfter)
    {
        X509SignatureGenerator? generator = _generator;
        if (generator == null)
            return Fail(CryptoError.InvalidKey);

        byte[] serial = new byte[16u];
        if (!RandomNumberGenerator.Fill(serial))
            return Fail(CryptoError.NoEntropy);
        serial[0u] = (byte)((serial[0u] & 0x7F) | 0x40);
        return Create(_subjectName, generator, notBefore, notAfter, serial);
    }

    /// The certificate issued by `issuerCertificate`, signed with its key.
    ///
    /// As .NET requires, the issuer MUST be a CA by its basic constraints,
    /// `issuerKey` MUST be the key its certificate names, and the new
    /// certificate's validity MUST lie within the issuer's.
    ///
    /// @param issuerCertificate  the CA
    /// @param issuerKey          its private key
    /// @param notBefore          the first moment it is valid
    /// @param notAfter           the last
    /// @param serialNumber       big-endian and unsigned, 1 to 20 bytes once leading zeros
    ///                           are gone, and not zero
    /// @failure CryptoError.InvalidKey  `issuerKey` is not the issuer's key
    /// @failure CryptoError.Parameter   the issuer is not a CA, the validity is not within
    ///                                  its, or the serial number is not one RFC 5280 allows
    public Result<X509Certificate2, CryptoError> Create(
        X509Certificate2 issuerCertificate, X509SignatureGenerator issuerKey, long notBefore,
        long notAfter, ReadOnlySpan<byte> serialNumber)
    {
        X509BasicConstraintsExtension? basic = issuerCertificate.BasicConstraints;
        if (basic == null || !basic.CertificateAuthority)
            return Fail(CryptoError.Parameter);
        if (!issuerKey.PublicKey.Equals(issuerCertificate.PublicKey))
            return Fail(CryptoError.InvalidKey);
        if (notBefore < issuerCertificate.NotBefore || notAfter > issuerCertificate.NotAfter)
            return Fail(CryptoError.Parameter);
        return Create(issuerCertificate.SubjectName, issuerKey, notBefore, notAfter, serialNumber);
    }

    /// The certificate issued in `issuerName`, signed by `generator`, with no
    /// check that the two belong together.
    ///
    /// @param issuerName    the issuer's name, exactly as its own certificate has it
    /// @param generator     the issuer's private key
    /// @param notBefore     the first moment it is valid
    /// @param notAfter      the last
    /// @param serialNumber  big-endian and unsigned, 1 to 20 bytes once leading zeros are
    ///                      gone, and not zero
    /// @failure CryptoError.Parameter  the validity or the serial number is not one RFC 5280
    ///                                 allows
    public Result<X509Certificate2, CryptoError> Create(
        X500DistinguishedName issuerName, X509SignatureGenerator generator, long notBefore,
        long notAfter, ReadOnlySpan<byte> serialNumber)
    {
        if (notAfter < notBefore || notBefore < -62167219200 || notAfter > 253402300799)
            return Fail(CryptoError.Parameter);

        nuint first = 0u;
        while (first < serialNumber.Length && serialNumber[first] == 0)
            first++;
        ReadOnlySpan<byte> serial = serialNumber[first:];
        if (serial.Length == 0u || serial.Length > 20u ||
            (serial.Length == 20u && (serial[0u] & 0x80) != 0))
        {
            return Fail(CryptoError.Parameter);
        }

        byte[] algorithm = try generator.GetSignatureAlgorithmIdentifier(_hashAlgorithm);

        var tbs = new AsnWriter();
        tbs.PushSequence();
        tbs.PushSequence(CreateContextTag(0, true));
        tbs.WriteInteger(2);
        tbs.PopSequence();
        tbs.WriteIntegerUnsigned(serial);
        tbs.WriteEncodedValue(algorithm);
        tbs.WriteEncodedValue(issuerName.RawData);
        tbs.PushSequence();
        WriteX509Time(tbs, notBefore);
        WriteX509Time(tbs, notAfter);
        tbs.PopSequence();
        tbs.WriteEncodedValue(_subjectName.RawData);
        tbs.WriteEncodedValue(_publicKey.ExportSubjectPublicKeyInfo());
        if (_extensions.Count > 0u)
        {
            tbs.PushSequence(CreateContextTag(3, true));
            tbs.PushSequence();
            foreach (X509Extension extension in _extensions)
            {
                tbs.PushSequence();
                if (tbs.WriteObjectIdentifier(extension.Oid) != AsnError.None)
                    return Fail(CryptoError.Encoding);
                if (extension.Critical)
                    tbs.WriteBoolean(true);
                tbs.WriteOctetString(extension.RawData);
                tbs.PopSequence();
            }
            tbs.PopSequence();
            tbs.PopSequence();
        }
        tbs.PopSequence();
        byte[] signedPart = tbs.Encode();

        byte[] signature = try generator.SignData(signedPart, _hashAlgorithm);

        var certificate = new AsnWriter();
        certificate.PushSequence();
        certificate.WriteEncodedValue(signedPart);
        certificate.WriteEncodedValue(algorithm);
        certificate.WriteBitString(signature);
        certificate.PopSequence();
        return X509Certificate2.FromDer(certificate.Encode());
    }
}
