// SPDX-License-Identifier: 0BSD
//
// Chains made to be refused: more work than a chain is allowed, weak
// signatures and keys, names outside a constraint, and DER that is not DER.
module X509Case;

import Standard.Console;
import Standard.Collections;
import Standard.Formats.Asn1;
import Standard.Security.Cryptography;
import Standard.Security.Cryptography.X509Certificates;

// RFC 8448's server key, which is 1024 bits.
static readonly String Rfc8448Modulus =
    "b4bb498f8279303d980836399b36c6988c0c68de55e1bdb826d3901a2461eafd" +
    "2de49a91d015abbc9a95137ace6c1af19eaa6af98c7ced43120998e187a80ee0" +
    "ccb0524b1b018c3e0b63264d449a6d38e22a5fda430846748030530ef0461c8c" +
    "a9d9efbfae8ea6d1d03e2bd193eff0ab9a8002c47428a6d35a8d88d79f7f1e3f";
static readonly String Rfc8448D =
    "04dea705d43a6ea7209dd8072111a83c81e322a59278b33480641eaf7c0a6985" +
    "b8e31c44f6de62e1b4c2309f6126e77b7c41e923314bbfa3881305dc1217f16c" +
    "819ce538e922f369828d0e57195d8c8488460207b2faa726bcf708bbd7db7f67" +
    "9f893492fc2a622e08970aac441ce4e0c3088df25ae679233df8a3bda2ff9941";
static readonly String Rfc8448P =
    "e435fb7cc83737756dacea96ab7f59a2cc1069db7deb190e17e33a532b273f30" +
    "a327aa0aaabc58cd67466af9845fadc675fe094af92c4bd1f2c1bc33dd2e0515";
static readonly String Rfc8448Q =
    "cabd3bc0e0438664c8d4cc9f99977a94d9bbfead8e43870abae3f7eb8b4e0eee" +
    "8af1d9b4719ba6196cf2cbbaeeebf8b3490afe9e9ffa74a88aa51fc645629303";
static readonly String Rfc8448Dp =
    "3f57345c27fe1b687e6e761627b78b1b826433dd760fa0bea6a6acf39490aa1b" +
    "47cda4869d68f584dd5b5029bd32093b8258661fe715025e5d70a45a08d3d319";
static readonly String Rfc8448Dq =
    "183da01363bd2f2885cacbdc9964bf4764f1517636f86401286f71893c52ccfe" +
    "40a6c23d0d086b47c6fb10d8fd1041e04def7e9a40ce957c417794e10412d139";
static readonly String Rfc8448InverseQ =
    "839ca9a085e4286b2c90e466997a2c681f21339aa3477814e4dec11833050ed5" +
    "0dd13cc038048a43c59b2acc416889c037665fe5afa605969f8c01dfa5ca969d";

void CheckHardening()
{
    var run = RunHardening();
    if (!run.Ok)
        Console.WriteLine($"hardening FAIL: {run.Error}");
    CheckExplicitDefaultVersion();
    CheckPolicyTime();
}

Result<bool, CryptoError> RunHardening()
{
    try CheckVerificationBudget();
    try CheckWeakSignatures();
    try CheckNameConstraintForms();
    try CheckLeafKeyUsage();
    try CheckWildcardSuffixes();
    return Ok(true);
}

// ------------------------------------------------------------ minting

X500DistinguishedName CreateHardeningName(String organization, String commonName, String email)
{
    var builder = new X500DistinguishedNameBuilder();
    builder.AddOrganizationName(organization);
    builder.AddCommonName(commonName);
    if (!email.IsEmpty)
        builder.AddEmailAddress(email);
    var built = builder.Build();
    if (built.Ok)
        return built.Value;
    Console.WriteLine("hardening name FAIL");
    return LoadFixture("root", RootPem).SubjectName;
}

byte[] CreateSeed(nuint index)
{
    byte[] seed = CreateFilledBytes(32u, 0x60);
    seed[0u] = (byte)(index & 0xFFu);
    seed[1u] = (byte)(index >> 8);
    return seed;
}

Result<X509Certificate2, CryptoError> MintHardeningAuthority(X509SignatureGenerator key,
                                                            X500DistinguishedName name,
                                                            X509Extension[] extensions)
{
    var request = new CertificateRequest(name, key, HashAlgorithmName.Sha256);
    request.CertificateExtensions.Add(new X509BasicConstraintsExtension(true, false, 0, true));
    foreach (X509Extension extension in extensions)
        request.CertificateExtensions.Add(extension);
    return request.CreateSelfSigned(MintedNotBefore, MintedNotAfter);
}

Result<X509Certificate2, CryptoError> MintHardeningLeaf(X509Certificate2 issuer,
                                                       X509SignatureGenerator issuerKey,
                                                       X500DistinguishedName subject,
                                                       X509Extension[] extensions,
                                                       HashAlgorithmName hash, byte serial)
{
    var leafKey = try X509SignatureGenerator.CreateForEd25519(CreateFilledBytes(32u, 0x52));
    var request = new CertificateRequest(subject, leafKey.PublicKey, hash);
    foreach (X509Extension extension in extensions)
        request.CertificateExtensions.Add(extension);
    byte[] serialNumber = [serial];
    return request.Create(issuer, issuerKey, MintedNotBefore, MintedNotAfter - 1, serialNumber);
}

X509Extension CreateDnsNames(String name)
{
    var names = new SubjectAlternativeNameBuilder();
    names.AddDnsName(name);
    return names.Build();
}

X509Extension CreateEmailName(String email)
{
    var names = new SubjectAlternativeNameBuilder();
    names.AddEmailAddress(email);
    return names.Build();
}

X509ChainStatusFlags BuildHardeningChain(X509Certificate2 leaf, List<X509Certificate2> anchors,
                                         List<X509Certificate2> extra, String purpose,
                                         out nuint length)
{
    var chain = new X509Chain();
    chain.ChainPolicy.TrustMode = X509ChainTrustMode.CustomRootTrust;
    chain.ChainPolicy.VerificationTime = VerificationTime;
    chain.ChainPolicy.ApplicationPolicy.Add(purpose);
    foreach (X509Certificate2 anchor in anchors)
        chain.ChainPolicy.CustomTrustStore.Add(anchor);
    foreach (X509Certificate2 one in extra)
        chain.ChainPolicy.ExtraStore.Add(one);
    bool built = chain.Build(leaf);
    length = chain.ChainElements.Length;
    if (built != (chain.StatusFlags == X509ChainStatusFlags.NoError))
        Console.WriteLine("hardening build answer FAIL");
    return chain.StatusFlags;
}

void CheckHardeningChain(String label, X509Certificate2 leaf, List<X509Certificate2> anchors,
                         List<X509Certificate2> extra, String purpose,
                         X509ChainStatusFlags want, nuint wantLength)
{
    X509ChainStatusFlags got = BuildHardeningChain(leaf, anchors, extra, purpose,
                                                   out nuint length);
    if (got == want && length == wantLength)
    {
        Console.WriteLine($"chain {label} ok: {got}");
    }
    else
    {
        Console.WriteLine($"chain {label} FAIL: {got} length {length}");
    }
}

List<X509Certificate2> CreateCertificateList(X509Certificate2 one)
{
    var list = new List<X509Certificate2>();
    list.Add(one);
    return list;
}

List<X509Certificate2> TakeCertificates(List<X509Certificate2> from, nuint count)
{
    var list = new List<X509Certificate2>();
    for (nuint i = 0u; i < count; i++)
        list.Add(from[i]);
    return list;
}

// ------------------------------------------------------------ the work bound

/// Anchors that share the leaf's issuer name, none of which signed it: each
/// is a signature to verify before the real one, and a Build verifies at
/// most 100. And a chain reads only the first 64 extra certificates.
Result<bool, CryptoError> CheckVerificationBudget()
{
    String server = X509EnhancedKeyUsageExtension.ServerAuthenticationOid;
    X500DistinguishedName crowdedName = CreateHardeningName("Hardening", "Crowded Root", "");
    var rootKey = try X509SignatureGenerator.CreateForEd25519(CreateFilledBytes(32u, 0x51));
    X509Certificate2 root = try MintHardeningAuthority(rootKey, crowdedName, []);
    X509Certificate2 leaf = try MintHardeningLeaf(
        root, rootKey, CreateHardeningName("Hardening", "www.example.com", ""),
        [CreateDnsNames("www.example.com")], HashAlgorithmName.Sha256, 1);

    var crowd = new List<X509Certificate2>();
    for (nuint i = 0u; i < 110u; i++)
    {
        var key = try X509SignatureGenerator.CreateForEd25519(CreateSeed(i));
        crowd.Add(try MintHardeningAuthority(key, crowdedName, []));
    }

    List<X509Certificate2> none = new List<X509Certificate2>();
    List<X509Certificate2> few = TakeCertificates(crowd, 20u);
    few.Add(root);
    CheckHardeningChain("twenty impostor anchors", leaf, few, none, server,
                        X509ChainStatusFlags.NoError, 2u);
    List<X509Certificate2> many = TakeCertificates(crowd, 110u);
    many.Add(root);
    CheckHardeningChain("more impostor anchors than the budget", leaf, many, none, server,
                        X509ChainStatusFlags.NotSignatureValid, 2u);

    var cappedKey = try X509SignatureGenerator.CreateForEd25519(CreateFilledBytes(32u, 0x53));
    X509Certificate2 capped = try MintHardeningAuthority(
        cappedKey, CreateHardeningName("Hardening", "Capped Root", ""), []);
    var middleKey = try X509SignatureGenerator.CreateForEd25519(CreateFilledBytes(32u, 0x54));
    var middleRequest = new CertificateRequest(
        CreateHardeningName("Hardening", "Capped Intermediate", ""), middleKey,
        HashAlgorithmName.Sha256);
    middleRequest.CertificateExtensions.Add(
        new X509BasicConstraintsExtension(true, false, 0, true));
    byte[] middleSerial = [2];
    X509Certificate2 middle = try middleRequest.Create(capped, cappedKey, MintedNotBefore,
                                                       MintedNotAfter - 1, middleSerial);
    X509Certificate2 below = try MintHardeningLeaf(
        middle, middleKey, CreateHardeningName("Hardening", "www.example.com", ""),
        [CreateDnsNames("www.example.com")], HashAlgorithmName.Sha256, 3);

    List<X509Certificate2> sixtyFour = TakeCertificates(crowd, 63u);
    sixtyFour.Add(middle);
    CheckHardeningChain("intermediate as the 64th extra", below, CreateCertificateList(capped),
                        sixtyFour, server, X509ChainStatusFlags.NoError, 3u);
    List<X509Certificate2> sixtyFive = TakeCertificates(crowd, 64u);
    sixtyFive.Add(middle);
    CheckHardeningChain("intermediate as the 65th extra", below, CreateCertificateList(capped),
                        sixtyFive, server, X509ChainStatusFlags.PartialChain, 1u);
    return Ok(true);
}

// ------------------------------------------------------------ weak signatures

Result<bool, CryptoError> CheckWeakSignatures()
{
    String server = X509EnhancedKeyUsageExtension.ServerAuthenticationOid;
    List<X509Certificate2> none = new List<X509Certificate2>();
    X500DistinguishedName leafName = CreateHardeningName("Hardening", "www.example.com", "");
    X509Extension[] leafExtensions = [CreateDnsNames("www.example.com")];

    Rsa rsa = try Rsa.Create(2048);
    var pkcs1 = try X509SignatureGenerator.CreateForRsa(rsa, RsaSignaturePadding.Pkcs1);
    var pss = try X509SignatureGenerator.CreateForRsa(rsa, RsaSignaturePadding.Pss);
    X509Certificate2 root = try MintHardeningAuthority(
        pkcs1, CreateHardeningName("Hardening", "RSA Root", ""), []);
    List<X509Certificate2> anchors = CreateCertificateList(root);

    X509Certificate2 pssSha256 = try MintHardeningLeaf(root, pss, leafName, leafExtensions,
                                                      HashAlgorithmName.Sha256, 4);
    CheckHardeningChain("rsa-pss over sha-256", pssSha256, anchors, none, server,
                        X509ChainStatusFlags.NoError, 2u);
    X509Certificate2 pssSha1 = try MintHardeningLeaf(root, pss, leafName, leafExtensions,
                                                    HashAlgorithmName.Sha1, 5);
    CheckHardeningChain("rsa-pss over sha-1", pssSha1, anchors, none, server,
                        X509ChainStatusFlags.HasWeakSignature, 2u);

    // An empty RSASSA-PSS-params: every field its default, which is SHA-1.
    var writer = new AsnWriter();
    writer.PushSequence();
    writer.WriteObjectIdentifier("1.2.840.113549.1.1.10");
    writer.PushSequence();
    writer.PopSequence();
    writer.PopSequence();
    byte[] defaults = writer.Encode();
    List<byte[]> fields = ReadTbsFields(pssSha256.RawData, out byte[] algorithm,
                                        out byte[] signature);
    fields[2u] = defaults;
    byte[] tbs = EncodeTbs(fields);
    byte[] signed = try rsa.SignData(tbs, HashAlgorithmName.Sha1, RsaSignaturePadding.Pss);
    var bits = new AsnWriter();
    bits.WriteBitString(signed);
    X509Certificate2 pssDefaults = try X509Certificate2.FromDer(
        AssembleCertificate(tbs, defaults, bits.Encode()));
    CheckHardeningChain("rsa-pss with default parameters", pssDefaults, anchors, none, server,
                        X509ChainStatusFlags.HasWeakSignature, 2u);

    var parameters = new RsaParameters();
    parameters.Modulus = Hex(Rfc8448Modulus);
    parameters.Exponent = [0x01, 0x00, 0x01];
    parameters.D = Hex(Rfc8448D);
    parameters.P = Hex(Rfc8448P);
    parameters.Q = Hex(Rfc8448Q);
    parameters.DP = Hex(Rfc8448Dp);
    parameters.DQ = Hex(Rfc8448Dq);
    parameters.InverseQ = Hex(Rfc8448InverseQ);
    Rsa small = try Rsa.Create(parameters);
    var smallKey = try X509SignatureGenerator.CreateForRsa(small, RsaSignaturePadding.Pkcs1);
    X509Certificate2 smallRoot = try MintHardeningAuthority(
        smallKey, CreateHardeningName("Hardening", "Small RSA Root", ""), []);
    X509Certificate2 underSmall = try MintHardeningLeaf(smallRoot, smallKey, leafName,
                                                       leafExtensions, HashAlgorithmName.Sha256, 6);
    CheckHardeningChain("rsa key of 1024 bits", underSmall, CreateCertificateList(smallRoot), none,
                        server, X509ChainStatusFlags.HasWeakSignature, 2u);
    return Ok(true);
}

/// The fields of a certificate's `TBSCertificate`, each as DER, and in
/// `algorithm` and `signature` the two fields after it.
List<byte[]> ReadTbsFields(byte[] der, out byte[] algorithm, out byte[] signature)
{
    var fields = new List<byte[]>();
    algorithm = new byte[0u];
    signature = new byte[0u];
    var document = new AsnReader(der, AsnEncodingRules.Der);
    var certificate = document.ReadSequence();
    if (!certificate.Ok)
        return fields;
    AsnReader outer = certificate.Value;
    var tbs = outer.ReadSequence();
    var outerAlgorithm = outer.ReadEncodedValue();
    var outerSignature = outer.ReadEncodedValue();
    if (!tbs.Ok || !outerAlgorithm.Ok || !outerSignature.Ok)
        return fields;
    algorithm = outerAlgorithm.Value.ToArray();
    signature = outerSignature.Value.ToArray();
    AsnReader inside = tbs.Value;
    while (inside.HasData)
    {
        var field = inside.ReadEncodedValue();
        if (!field.Ok)
            break;
        fields.Add(field.Value.ToArray());
    }
    return fields;
}

byte[] EncodeTbs(List<byte[]> fields)
{
    var writer = new AsnWriter();
    writer.PushSequence();
    foreach (byte[] field in fields)
        writer.WriteEncodedValue(field);
    writer.PopSequence();
    return writer.Encode();
}

byte[] AssembleCertificate(byte[] tbs, byte[] algorithm, byte[] signature)
{
    var writer = new AsnWriter();
    writer.PushSequence();
    writer.WriteEncodedValue(tbs);
    writer.WriteEncodedValue(algorithm);
    writer.WriteEncodedValue(signature);
    writer.PopSequence();
    return writer.Encode();
}

// ------------------------------------------------------------ name constraints

byte[] EncodeGeneralNameText(int tag, String text)
{
    var writer = new AsnWriter();
    writer.WriteCharacterString(UniversalTagNumber.IA5String, text,
                                new Asn1Tag(TagClass.ContextSpecific, tag, false));
    return writer.Encode();
}

byte[] EncodeGeneralNameDirectory(X500DistinguishedName name)
{
    var writer = new AsnWriter();
    writer.PushSequence(new Asn1Tag(TagClass.ContextSpecific, 4, true));
    writer.WriteEncodedValue(name.RawData);
    writer.PopSequence();
    return writer.Encode();
}

/// A critical name constraints extension permitting each of `names`.
X509Extension CreatePermittedSubtrees(byte[][] names)
{
    var writer = new AsnWriter();
    writer.PushSequence();
    writer.PushSequence(new Asn1Tag(TagClass.ContextSpecific, 0, true));
    foreach (byte[] name in names)
    {
        writer.PushSequence();
        writer.WriteEncodedValue(name);
        writer.PopSequence();
    }
    writer.PopSequence();
    writer.PopSequence();
    return new X509Extension("2.5.29.30", writer.Encode(), true);
}

/// A subject alternative name of `names`, each already a `GeneralName`.
X509Extension CreateAlternativeNames(byte[][] names)
{
    var writer = new AsnWriter();
    writer.PushSequence();
    foreach (byte[] name in names)
        writer.WriteEncodedValue(name);
    writer.PopSequence();
    return new X509Extension("2.5.29.17", writer.Encode(), false);
}

Result<bool, CryptoError> CheckNameConstraintForms()
{
    String client = X509EnhancedKeyUsageExtension.ClientAuthenticationOid;
    String server = X509EnhancedKeyUsageExtension.ServerAuthenticationOid;
    List<X509Certificate2> none = new List<X509Certificate2>();
    var caKey = try X509SignatureGenerator.CreateForEd25519(CreateFilledBytes(32u, 0x55));

    // Permitted: e-mail on partner.example, and the directory under O=Partner.
    var partnerBuilder = new X500DistinguishedNameBuilder();
    partnerBuilder.AddOrganizationName("Partner");
    X500DistinguishedName partner = try partnerBuilder.Build();
    X509Certificate2 partnerCa = try MintHardeningAuthority(
        caKey, CreateHardeningName("Partner", "Partner CA", ""),
        [CreatePermittedSubtrees([EncodeGeneralNameText(1, "partner.example"),
                                  EncodeGeneralNameDirectory(partner)])]);
    List<X509Certificate2> anchors = CreateCertificateList(partnerCa);

    X500DistinguishedName inside = CreateHardeningName("Partner", "alice", "");
    X500DistinguishedName outside = CreateHardeningName("Our Company", "admin", "");
    X509Certificate2 good = try MintHardeningLeaf(
        partnerCa, caKey, inside, [CreateEmailName("alice@partner.example")],
        HashAlgorithmName.Sha256, 7);
    CheckHardeningChain("names inside every constraint", good, anchors, none, client,
                        X509ChainStatusFlags.NoError, 2u);

    X509Certificate2 both = try MintHardeningLeaf(
        partnerCa, caKey, outside, [CreateEmailName("ceo@ourcompany.example")],
        HashAlgorithmName.Sha256, 8);
    CheckHardeningChain("subject and e-mail outside", both, anchors, none, client,
                        X509ChainStatusFlags.HasNotPermittedNameConstraint, 2u);

    X509Certificate2 subject = try MintHardeningLeaf(
        partnerCa, caKey, outside, [CreateEmailName("alice@partner.example")],
        HashAlgorithmName.Sha256, 9);
    CheckHardeningChain("subject outside the directory", subject, anchors, none, client,
                        X509ChainStatusFlags.HasNotPermittedNameConstraint, 2u);

    X509Certificate2 email = try MintHardeningLeaf(
        partnerCa, caKey, inside, [CreateEmailName("ceo@ourcompany.example")],
        HashAlgorithmName.Sha256, 10);
    CheckHardeningChain("e-mail name outside", email, anchors, none, client,
                        X509ChainStatusFlags.HasNotPermittedNameConstraint, 2u);

    X509Certificate2 subjectEmail = try MintHardeningLeaf(
        partnerCa, caKey, CreateHardeningName("Partner", "alice", "ceo@ourcompany.example"),
        [CreateEmailName("alice@partner.example")], HashAlgorithmName.Sha256, 11);
    CheckHardeningChain("subject e-mail outside", subjectEmail, anchors, none, client,
                        X509ChainStatusFlags.HasNotPermittedNameConstraint, 2u);

    var elsewhereBuilder = new X500DistinguishedNameBuilder();
    elsewhereBuilder.AddOrganizationName("Elsewhere");
    X500DistinguishedName elsewhere = try elsewhereBuilder.Build();
    X509Certificate2 directory = try MintHardeningLeaf(
        partnerCa, caKey, inside,
        [CreateAlternativeNames([EncodeGeneralNameText(1, "alice@partner.example"),
                                 EncodeGeneralNameDirectory(elsewhere)])],
        HashAlgorithmName.Sha256, 12);
    CheckHardeningChain("directory name outside", directory, anchors, none, client,
                        X509ChainStatusFlags.HasNotPermittedNameConstraint, 2u);

    // A URI subtree is not enforced, so a critical extension holding one is
    // not understood.
    X509Certificate2 uriCa = try MintHardeningAuthority(
        caKey, CreateHardeningName("Partner", "URI CA", ""),
        [CreatePermittedSubtrees([EncodeGeneralNameText(6, ".example.com")])]);
    X509Certificate2 underUri = try MintHardeningLeaf(
        uriCa, caKey, inside, [CreateDnsNames("www.example.com")], HashAlgorithmName.Sha256, 13);
    CheckHardeningChain("uri constraint", underUri, CreateCertificateList(uriCa), none, server,
                        X509ChainStatusFlags.InvalidExtension |
                        X509ChainStatusFlags.HasNotSupportedCriticalExtension, 2u);

    String[] dotted = [".example.com"];
    byte[][] noRanges = [];
    String[] noNames = [];
    X509Certificate2 dotCa = try MintHardeningAuthority(
        caKey, CreateHardeningName("Partner", "Dotted CA", ""),
        [new X509NameConstraintsExtension(dotted, noRanges, noNames, noRanges, true)]);
    X509Certificate2 wildcard = try MintHardeningLeaf(
        dotCa, caKey, inside, [CreateDnsNames("*.example.com")], HashAlgorithmName.Sha256, 14);
    CheckHardeningChain("wildcard under a leading-dot subtree", wildcard,
                        CreateCertificateList(dotCa), none, server,
                        X509ChainStatusFlags.NoError, 2u);

    X509Certificate2 directoryCa = try MintHardeningAuthority(
        caKey, CreateHardeningName("Partner", "Directory CA", ""),
        [CreatePermittedSubtrees([EncodeGeneralNameDirectory(partner)])]);
    X509Certificate2 oddName = try MintHardeningLeaf(
        directoryCa, caKey, inside, [CreateDnsNames("not a host name")],
        HashAlgorithmName.Sha256, 15);
    CheckHardeningChain("odd dns name with no dns constraint", oddName,
                        CreateCertificateList(directoryCa), none, client,
                        X509ChainStatusFlags.NoError, 2u);
    return Ok(true);
}

// ------------------------------------------------------------ usage and names

Result<bool, CryptoError> CheckLeafKeyUsage()
{
    String server = X509EnhancedKeyUsageExtension.ServerAuthenticationOid;
    List<X509Certificate2> none = new List<X509Certificate2>();
    var caKey = try X509SignatureGenerator.CreateForEd25519(CreateFilledBytes(32u, 0x56));
    X509Certificate2 ca = try MintHardeningAuthority(
        caKey, CreateHardeningName("Hardening", "Usage CA", ""), []);
    X500DistinguishedName name = CreateHardeningName("Hardening", "www.example.com", "");

    X509Certificate2 encipher = try MintHardeningLeaf(
        ca, caKey, name,
        [CreateDnsNames("www.example.com"),
         new X509KeyUsageExtension(X509KeyUsageFlags.KeyEncipherment |
                                   X509KeyUsageFlags.KeyAgreement, true)],
        HashAlgorithmName.Sha256, 16);
    CheckHardeningChain("tls leaf without digital signature", encipher,
                        CreateCertificateList(ca), none, server,
                        X509ChainStatusFlags.NotValidForUsage, 2u);

    X509Certificate2 signs = try MintHardeningLeaf(
        ca, caKey, name,
        [CreateDnsNames("www.example.com"),
         new X509KeyUsageExtension(X509KeyUsageFlags.DigitalSignature, true)],
        HashAlgorithmName.Sha256, 17);
    CheckHardeningChain("tls leaf with digital signature", signs, CreateCertificateList(ca),
                        none, server, X509ChainStatusFlags.NoError, 2u);
    return Ok(true);
}

Result<bool, CryptoError> CheckWildcardSuffixes()
{
    var caKey = try X509SignatureGenerator.CreateForEd25519(CreateFilledBytes(32u, 0x57));
    X509Certificate2 ca = try MintHardeningAuthority(
        caKey, CreateHardeningName("Hardening", "Wildcard CA", ""), []);
    var names = new SubjectAlternativeNameBuilder();
    names.AddDnsName("*.co.uk");
    names.AddDnsName("*.example.co.uk");
    names.AddDnsName("*.github.io");
    X509Certificate2 leaf = try MintHardeningLeaf(
        ca, caKey, CreateHardeningName("Hardening", "wildcards", ""), [names.Build()],
        HashAlgorithmName.Sha256, 18);
    CheckHostname(leaf, "foo.co.uk", false);
    CheckHostname(leaf, "www.example.co.uk", true);
    CheckHostname(leaf, "pages.github.io", true);
    return Ok(true);
}

// ------------------------------------------------------------ DER and policy

/// Version 1 is the DEFAULT, so DER leaves it out and an explicit one is
/// not DER.
void CheckExplicitDefaultVersion()
{
    List<byte[]> fields = ReadTbsFields(GoodDer, out byte[] algorithm, out byte[] signature);
    if (fields.Count < 7u)
    {
        Check("version 1 fields", false);
        return;
    }

    var implicitFields = new List<byte[]>();
    for (nuint i = 1u; i < 7u; i++)
        implicitFields.Add(fields[i]);
    var implicitVersion = X509Certificate2.FromDer(
        AssembleCertificate(EncodeTbs(implicitFields), algorithm, signature));
    Check("version 1 left out parses", implicitVersion.Ok && implicitVersion.Value.Version == 1);

    var writer = new AsnWriter();
    writer.PushSequence(new Asn1Tag(TagClass.ContextSpecific, 0, true));
    writer.WriteInteger(0L);
    writer.PopSequence();
    var explicitFields = new List<byte[]>();
    explicitFields.Add(writer.Encode());
    foreach (byte[] field in implicitFields)
        explicitFields.Add(field);
    CheckRefused("refuses version 1 written out",
                 AssembleCertificate(EncodeTbs(explicitFields), algorithm, signature));
}

void CheckPolicyTime()
{
    var policy = new X509ChainPolicy();
    bool ignored = policy.VerificationTimeIgnored;
    policy.VerificationTime = VerificationTime;
    Check("policy time is each build's until it is set",
          ignored && !policy.VerificationTimeIgnored);
    policy.Reset();
    Check("policy reset forgets the time", policy.VerificationTimeIgnored);
}
