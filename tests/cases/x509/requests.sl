// SPDX-License-Identifier: 0BSD
//
// Certificates made here. The Ed25519, ECDSA, RSA and RSA-PSS pairs this
// makes were written out once and `openssl verify -x509_strict -purpose
// sslserver` accepted each.
module X509Case;

import Standard.Console;
import Standard.Security.Cryptography;
import Standard.Security.Cryptography.X509Certificates;

const long MintedNotBefore = 1767225600;
const long MintedNotAfter = 2082758400;

X500DistinguishedName CreateMintedName(String commonName)
{
    var builder = new X500DistinguishedNameBuilder();
    builder.AddCountryOrRegion("us");
    builder.AddOrganizationName("Stainless Minted");
    builder.AddCommonName(commonName);
    var built = builder.Build();
    if (built.Ok)
        return built.Value;
    Console.WriteLine("minted name FAIL");
    return LoadFixture("root", RootPem).SubjectName;
}

byte[] CreateFilledBytes(nuint length, byte value)
{
    var bytes = new byte[length];
    for (nuint i = 0u; i < length; i++)
        bytes[i] = value;
    return bytes;
}

Result<X509Certificate2, CryptoError> MintAuthority(X509SignatureGenerator key, String name,
                                                   HashAlgorithmName hash)
{
    var request = new CertificateRequest(CreateMintedName(name), key, hash);
    request.CertificateExtensions.Add(new X509BasicConstraintsExtension(true, true, 0, true));
    request.CertificateExtensions.Add(new X509KeyUsageExtension(
        X509KeyUsageFlags.KeyCertSign | X509KeyUsageFlags.CrlSign, true));
    request.CertificateExtensions.Add(new X509SubjectKeyIdentifierExtension(key.PublicKey, false));
    String[] permitted = ["example.com"];
    byte[][] permittedRanges = [[192, 0, 2, 0, 255, 255, 255, 0]];
    String[] excluded = ["bad.example.com"];
    byte[][] excludedRanges = [];
    request.CertificateExtensions.Add(new X509NameConstraintsExtension(
        permitted, permittedRanges, excluded, excludedRanges, true));
    return request.CreateSelfSigned(MintedNotBefore, MintedNotAfter);
}

Result<X509Certificate2, CryptoError> MintLeaf(X509Certificate2 authority,
                                               X509SignatureGenerator authorityKey,
                                               PublicKey key, String dnsName,
                                               HashAlgorithmName hash)
{
    var request = new CertificateRequest(CreateMintedName(dnsName), key, hash);
    request.CertificateExtensions.Add(new X509BasicConstraintsExtension(false, false, 0, true));
    request.CertificateExtensions.Add(
        new X509KeyUsageExtension(X509KeyUsageFlags.DigitalSignature, true));
    String[] usages = [X509EnhancedKeyUsageExtension.ServerAuthenticationOid];
    request.CertificateExtensions.Add(new X509EnhancedKeyUsageExtension(usages, false));
    var names = new SubjectAlternativeNameBuilder();
    names.AddDnsName(dnsName);
    names.AddIPAddress([192, 0, 2, 9]);
    request.CertificateExtensions.Add(names.Build());
    request.CertificateExtensions.Add(
        X509AuthorityKeyIdentifierExtension.CreateFromCertificate(authority, true, false));
    byte[] serial = [0x00, 0x00, 0x7F, 0x01];
    return request.Create(authority, authorityKey, MintedNotBefore, MintedNotAfter - 1, serial);
}

bool BuildMintedChain(X509Certificate2 authority, X509Certificate2 leaf)
{
    var chain = new X509Chain();
    chain.ChainPolicy.TrustMode = X509ChainTrustMode.CustomRootTrust;
    chain.ChainPolicy.VerificationTime = VerificationTime;
    chain.ChainPolicy.ApplicationPolicy.Add(X509EnhancedKeyUsageExtension.ServerAuthenticationOid);
    chain.ChainPolicy.CustomTrustStore.Add(authority);
    return chain.Build(leaf);
}

void CreateRequests()
{
    var run = MintEverything();
    if (!run.Ok)
        Console.WriteLine($"minting FAIL: {run.Error}");
}

Result<bool, CryptoError> MintEverything()
{
    // Ed25519 signs deterministically, so these two are the same every run
    // but for the authority's random serial number.
    var authorityKey = try X509SignatureGenerator.CreateForEd25519(CreateFilledBytes(32u, 0x11));
    var leafKey = try X509SignatureGenerator.CreateForEd25519(CreateFilledBytes(32u, 0x22));
    X509Certificate2 authority = try MintAuthority(authorityKey, "Minted Ed25519 CA",
                                                   HashAlgorithmName.Sha256);
    X509Certificate2 leaf = try MintLeaf(authority, authorityKey, leafKey.PublicKey,
                                         "www.example.com", HashAlgorithmName.Sha256);

    CheckText("minted authority subject", authority.Subject,
              "CN=Minted Ed25519 CA, O=Stainless Minted, C=US");
    Check("minted authority is self-issued", authority.IsSelfIssued && authority.Version == 3);
    CheckNumber("minted authority serial length", (long)authority.SerialNumberBytes.Length, 16);
    CheckText("minted leaf serial", leaf.SerialNumber, "7F01");
    CheckText("minted leaf issuer", leaf.Issuer, authority.Subject);
    CheckNumber("minted leaf not after", leaf.NotAfter, MintedNotAfter - 1);
    CheckText("minted leaf algorithm", leaf.SignatureAlgorithm, "1.3.101.112");
    CheckNumber("minted leaf extensions", (long)leaf.Extensions.Count, 5);
    Check("minted leaf names", leaf.MatchesHostname("www.example.com") &&
                               leaf.MatchesHostname("192.0.2.9") &&
                               !leaf.MatchesHostname("example.com"));
    X509SubjectKeyIdentifierExtension? subjectKey = authority.SubjectKeyIdentifier;
    X509AuthorityKeyIdentifierExtension? authorityKeyId = leaf.AuthorityKeyIdentifier;
    Check("minted key identifiers agree",
          subjectKey != null && authorityKeyId != null &&
          ToHex(authorityKeyId.KeyIdentifier.GetValueOrDefault(new byte[0u])) ==
              subjectKey.SubjectKeyIdentifier);
    Check("minted chain", BuildMintedChain(authority, leaf));
    var readBack = X509Certificate2.FromPem(leaf.ExportCertificatePem());
    Check("minted leaf reads back", readBack.Ok && readBack.Value.Equals(leaf));

    // Outside the authority's name constraints.
    X509Certificate2 outside = try MintLeaf(authority, authorityKey, leafKey.PublicKey,
                                            "www.example.org", HashAlgorithmName.Sha256);
    Check("minted leaf outside the constraints", !BuildMintedChain(authority, outside));

    // ECDSA: a P-384 authority over SHA-384, and a P-256 leaf.
    var ecAuthorityKey = try X509SignatureGenerator.CreateForECDsa(
        try ECDsa.Create(ECCurve.NamedCurves.NistP384));
    var ecLeafKey = try ECDsa.Create(ECCurve.NamedCurves.NistP256);
    X509Certificate2 ecAuthority = try MintAuthority(ecAuthorityKey, "Minted ECDSA CA",
                                                     HashAlgorithmName.Sha384);
    X509Certificate2 ecLeaf = try MintLeaf(ecAuthority, ecAuthorityKey,
                                           try PublicKey.CreateFromECDsa(ecLeafKey),
                                           "api.example.com", HashAlgorithmName.Sha384);
    CheckText("minted ecdsa algorithm", ecLeaf.SignatureAlgorithm, "1.2.840.10045.4.3.3");
    Check("minted ecdsa chain", BuildMintedChain(ecAuthority, ecLeaf));

    // RSA, once as PSS and once as PKCS #1 v1.5.
    Rsa rsa = try Rsa.Create(2048);
    var pssKey = try X509SignatureGenerator.CreateForRsa(rsa, RsaSignaturePadding.Pss);
    X509Certificate2 pssAuthority = try MintAuthority(pssKey, "Minted RSA-PSS CA",
                                                      HashAlgorithmName.Sha256);
    CheckText("minted rsa-pss algorithm", pssAuthority.SignatureAlgorithm, "1.2.840.113549.1.1.10");
    X509Certificate2 pssLeaf = try MintLeaf(pssAuthority, pssKey, leafKey.PublicKey,
                                            "pss.example.com", HashAlgorithmName.Sha256);
    Check("minted rsa-pss chain", BuildMintedChain(pssAuthority, pssLeaf));

    var pkcs1Key = try X509SignatureGenerator.CreateForRsa(rsa, RsaSignaturePadding.Pkcs1);
    X509Certificate2 pkcs1Authority = try MintAuthority(pkcs1Key, "Minted RSA CA",
                                                        HashAlgorithmName.Sha512);
    CheckText("minted rsa algorithm", pkcs1Authority.SignatureAlgorithm, "1.2.840.113549.1.1.13");
    X509Certificate2 pkcs1Leaf = try MintLeaf(pkcs1Authority, pkcs1Key, leafKey.PublicKey,
                                              "rsa.example.com", HashAlgorithmName.Sha512);
    Check("minted rsa chain", BuildMintedChain(pkcs1Authority, pkcs1Leaf));

    CheckRequestRefusals(authority, authorityKey, leaf, leafKey);
    return Ok(true);
}

void CheckRequestRefusals(X509Certificate2 authority, X509SignatureGenerator authorityKey,
                          X509Certificate2 leaf, X509SignatureGenerator leafKey)
{
    byte[] serial = [1];
    var request = new CertificateRequest(CreateMintedName("refused.example.com"),
                                         leafKey.PublicKey, HashAlgorithmName.Sha256);

    var selfSigned = request.CreateSelfSigned(MintedNotBefore, MintedNotAfter);
    Check("request with no private key refuses to self-sign",
          !selfSigned.Ok && selfSigned.Error == CryptoError.InvalidKey);

    var notCa = request.Create(leaf, leafKey, MintedNotBefore, MintedNotAfter - 1, serial);
    Check("request refuses an issuer that is not a CA",
          !notCa.Ok && notCa.Error == CryptoError.Parameter);

    var wrongKey = request.Create(authority, leafKey, MintedNotBefore, MintedNotAfter, serial);
    Check("request refuses the wrong issuer key",
          !wrongKey.Ok && wrongKey.Error == CryptoError.InvalidKey);

    var tooLong = request.Create(authority, authorityKey, MintedNotBefore, MintedNotAfter + 1,
                                 serial);
    Check("request refuses validity past the issuer's",
          !tooLong.Ok && tooLong.Error == CryptoError.Parameter);

    byte[] zero = [0, 0];
    var zeroSerial = request.Create(authority, authorityKey, MintedNotBefore, MintedNotAfter,
                                    zero);
    Check("request refuses a zero serial number",
          !zeroSerial.Ok && zeroSerial.Error == CryptoError.Parameter);

    request.CertificateExtensions.Add(new X509BasicConstraintsExtension(false, false, 0, true));
    request.CertificateExtensions.Add(new X509BasicConstraintsExtension(false, false, 0, true));
    var twice = request.Create(authority, authorityKey, MintedNotBefore, MintedNotAfter, serial);
    Check("request with an extension twice does not read back",
          !twice.Ok && twice.Error == CryptoError.Encoding);

    var badName = new X500DistinguishedNameBuilder();
    badName.AddCountryOrRegion("USA");
    Check("name builder refuses a three-letter country", !badName.Build().Ok);
}
