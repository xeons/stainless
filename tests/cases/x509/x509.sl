// SPDX-License-Identifier: 0BSD
//
// The fixtures are a small PKI OpenSSL 3.5 made (fixtures.sh is how), and four
// real certificates from Let's Encrypt: ISRG Root X1 and X2, and the R10 and
// E6 intermediates. Every expected thumbprint, identifier and name below is
// what `openssl x509` printed for the same file.
module X509Case;

import Standard.Console;
import Standard.Convert;
import Standard.Time;
import Standard.Security.Cryptography;
import Standard.Security.Cryptography.X509Certificates;

[Embed("root.pem")]
static readonly byte[] RootPem;
[Embed("rootb.pem")]
static readonly byte[] RootBPem;
[Embed("inter.pem")]
static readonly byte[] InterPem;
[Embed("intercross.pem")]
static readonly byte[] InterCrossPem;
[Embed("noca.pem")]
static readonly byte[] NoCaPem;
[Embed("sub.pem")]
static readonly byte[] SubPem;
[Embed("noku.pem")]
static readonly byte[] NoKuPem;
[Embed("nc.pem")]
static readonly byte[] NcPem;
[Embed("caa.pem")]
static readonly byte[] CycleAPem;
[Embed("cab.pem")]
static readonly byte[] CycleBPem;
[Embed("good.pem")]
static readonly byte[] GoodPem;
[Embed("good.der")]
static readonly byte[] GoodDer;
[Embed("expired.pem")]
static readonly byte[] ExpiredPem;
[Embed("notyet.pem")]
static readonly byte[] NotYetPem;
[Embed("wrongeku.pem")]
static readonly byte[] WrongEkuPem;
[Embed("badku.pem")]
static readonly byte[] BadKuPem;
[Embed("wildcard.pem")]
static readonly byte[] WildcardPem;
[Embed("ip.pem")]
static readonly byte[] IpPem;
[Embed("critical.pem")]
static readonly byte[] CriticalPem;
[Embed("undernoca.pem")]
static readonly byte[] UnderNoCaPem;
[Embed("undersub.pem")]
static readonly byte[] UnderSubPem;
[Embed("undernoku.pem")]
static readonly byte[] UnderNoKuPem;
[Embed("ncok.pem")]
static readonly byte[] NcOkPem;
[Embed("ncgood.pem")]
static readonly byte[] NcWildcardPem;
[Embed("ncother.pem")]
static readonly byte[] NcOtherPem;
[Embed("ncexcluded.pem")]
static readonly byte[] NcExcludedPem;
[Embed("ncip.pem")]
static readonly byte[] NcIpPem;
[Embed("cyclic.pem")]
static readonly byte[] CyclicPem;
[Embed("rsaroot.pem")]
static readonly byte[] RsaRootPem;
[Embed("rsaleaf.pem")]
static readonly byte[] RsaLeafPem;
[Embed("rsapss.pem")]
static readonly byte[] RsaPssPem;
[Embed("p256root.pem")]
static readonly byte[] P256RootPem;
[Embed("p256leaf.pem")]
static readonly byte[] P256LeafPem;
[Embed("isrgx1.pem")]
static readonly byte[] IsrgX1Pem;
[Embed("isrgx2.pem")]
static readonly byte[] IsrgX2Pem;
[Embed("r10.pem")]
static readonly byte[] R10Pem;
[Embed("e6.pem")]
static readonly byte[] E6Pem;

// 2026-10-01T00:00:00Z: inside every fixture's validity but the three made
// to be outside it.
const long VerificationTime = 1790812800;

void Check(String label, bool passed)
{
    if (passed)
    {
        Console.WriteLine($"{label} ok");
    }
    else
    {
        Console.WriteLine($"{label} FAIL");
    }
}

void CheckText(String label, String got, String want)
{
    if (got == want)
    {
        Console.WriteLine($"{label} ok");
    }
    else
    {
        Console.WriteLine($"{label} FAIL: got {got}, want {want}");
    }
}

void CheckNumber(String label, long got, long want)
{
    if (got == want)
    {
        Console.WriteLine($"{label} ok");
    }
    else
    {
        Console.WriteLine($"{label} FAIL: got {got}, want {want}");
    }
}

String CreateTextFromBytes(byte[] bytes)
{
    var built = new StringBuilder();
    built.AppendBytes(bytes);
    return built.ToText();
}

String ToHex(ReadOnlySpan<byte> data) => Convert.ToHexString(data.ToArray(), true);

byte[] Hex(String text) => Convert.FromHexString(text).GetValueOrDefault(new byte[0u]);

/// The certificate a fixture holds; a fixture that does not parse is a
/// failure printed here and the root in its place.
X509Certificate2 LoadFixture(String label, byte[] pem)
{
    var parsed = X509Certificate2.FromPem(CreateTextFromBytes(pem));
    if (parsed.Ok)
        return parsed.Value;
    Console.WriteLine($"{label} FAIL: {parsed.Error}");
    return LoadFixture("root", RootPem);
}

public int Main()
{
    ParseFields();
    ParseOthers();
    ParseRefusals();
    MatchHostnames();
    BuildChains();
    CreateRequests();
    if (!CheckTwinRoots().Ok)
        Console.WriteLine("twin roots FAIL: could not mint");
    CheckHardening();
    return 0;
}

// ------------------------------------------------------------ fields

void ParseFields()
{
    X509Certificate2 good = LoadFixture("good", GoodPem);
    CheckNumber("good version", good.Version, 3);
    CheckText("good serial", good.SerialNumber, "0123456789ABCDEF");
    CheckText("good serial bytes", ToHex(good.SerialNumberBytes), "0123456789ABCDEF");
    CheckText("good signature algorithm", good.SignatureAlgorithm, "1.3.101.112");
    CheckText("good subject", good.Subject,
              "CN=www.example.com, OU=Web, O=Example Ünïcode, L=Austin, S=Texas, C=US");
    CheckText("good issuer", good.Issuer,
              "CN=Stainless Test Intermediate, O=Stainless Test, C=US");
    CheckNumber("good not before", good.NotBefore, 1767225600);
    CheckNumber("good not after", good.NotAfter, 1830297600);

    var notBefore = good.GetNotBeforeDateTimeOffset();
    Check("good not before as DateTimeOffset",
          notBefore.Ok && notBefore.Value == DateTimeOffset.FromUtc(2026, 1, 1, 0, 0, 0));

    CheckText("good thumbprint", good.Thumbprint, "45FC358508E04FED6E4517C41353F7F4B58A02F9");
    CheckText("good sha-256 thumbprint", good.Sha256Thumbprint,
              "EBBC93CFC9179260D5B9E7D9A067D747CE0A9DB916B41CFA19F9A8565A89EAD6");
    var sha512 = good.GetCertHashString(HashAlgorithmName.Sha512);
    Check("good sha-512 hash", sha512.Ok && sha512.Value.ByteLength() == 128u);

    // The relative distinguished names, most specific first and in encoded order.
    var steps = good.SubjectName.EnumerateRelativeDistinguishedNames();
    CheckNumber("good subject steps", (long)steps.Count, 6);
    CheckText("good subject first type", steps[0u].GetSingleElementType(), "2.5.4.3");
    CheckText("good subject first value",
              steps[0u].GetSingleElementValue().GetValueOrDefault("?"), "www.example.com");
    var encodedOrder = good.SubjectName.EnumerateRelativeDistinguishedNames(false);
    CheckText("good subject encoded first", encodedOrder[0u].GetElementValue(0u), "US");
    CheckText("good organization",
              good.SubjectName.GetFirstValue("2.5.4.10").GetValueOrDefault("?"), "Example Ünïcode");
    Check("good no email", good.SubjectName.GetFirstValue("1.2.840.113549.1.9.1").IsEmpty);

    // The key.
    CheckText("good key algorithm", good.PublicKey.Oid, PublicKey.Ed25519Oid);
    var raw = good.PublicKey.GetEd25519PublicKey();
    CheckText("good key", raw.Ok ? ToHex(raw.Value) : "?",
              "8FC87614F6A6E2C5D99F781D50D0ADC4312C2FDCA6A54BE3D12565AF1486106D");
    Check("good key is not RSA", !good.PublicKey.GetRsaModulus().Ok);

    // The extensions, in the order they are encoded.
    CheckNumber("good extensions", (long)good.Extensions.Count, 6);
    String order = "";
    foreach (X509Extension extension in good.Extensions)
        order = order + $"{extension.Oid}{(extension.Critical ? "!" : "")} ";
    CheckText("good extension order", order,
              "2.5.29.19! 2.5.29.15! 2.5.29.37 2.5.29.14 2.5.29.35 2.5.29.17 ");

    X509BasicConstraintsExtension? basic = good.BasicConstraints;
    Check("good basic constraints", basic != null && !basic.CertificateAuthority &&
                                    !basic.HasPathLengthConstraint && basic.Critical);
    X509KeyUsageExtension? usage = good.KeyUsage;
    Check("good key usage",
          usage != null && usage.KeyUsages == X509KeyUsageFlags.DigitalSignature);
    X509EnhancedKeyUsageExtension? enhanced = good.EnhancedKeyUsage;
    Check("good extended key usage",
          enhanced != null && enhanced.EnhancedKeyUsages.Length == 2u &&
          enhanced.EnhancedKeyUsages[0u] == X509EnhancedKeyUsageExtension.ServerAuthenticationOid &&
          enhanced.EnhancedKeyUsages[1u] == X509EnhancedKeyUsageExtension.ClientAuthenticationOid);
    X509SubjectKeyIdentifierExtension? subjectKey = good.SubjectKeyIdentifier;
    CheckText("good subject key identifier",
              subjectKey != null ? subjectKey.SubjectKeyIdentifier : "?",
              "F564F3AA17891636CE6398E8BA143D7D9C4C4013");
    X509AuthorityKeyIdentifierExtension? authorityKey = good.AuthorityKeyIdentifier;
    CheckText("good authority key identifier",
              authorityKey != null ? ToHex(authorityKey.KeyIdentifier.GetValueOrDefault(new byte[0u]))
                                   : "?",
              "0567D0D91C8C3B45B503C6912ACC9C0CF91EF33F");
    X509SubjectAlternativeNameExtension? names = good.SubjectAlternativeName;
    Check("good alternative names",
          names != null && names.DnsNames.Length == 2u && names.DnsNames[0u] == "www.example.com" &&
          names.DnsNames[1u] == "example.com" && names.IPAddresses.Length == 0u);
    Check("good extension by identifier", good.Extensions["2.5.29.17"] != null &&
                                          good.Extensions["1.2.3"] == null);

    // DER and PEM are the same certificate, and it writes back as OpenSSL wrote it.
    var fromDer = X509Certificate2.FromDer(GoodDer);
    Check("good from der", fromDer.Ok && fromDer.Value.Equals(good));
    CheckText("good raw data", ToHex(good.RawData), ToHex(GoodDer));
    Check("good pem round trip", good.ExportCertificatePem() + "\n" == CreateTextFromBytes(GoodPem));
    Check("good is not self-issued", !good.IsSelfIssued);

    X509Certificate2 inter = LoadFixture("inter", InterPem);
    X509BasicConstraintsExtension? interBasic = inter.BasicConstraints;
    Check("intermediate path length", interBasic != null && interBasic.CertificateAuthority &&
                                      interBasic.HasPathLengthConstraint &&
                                      interBasic.PathLengthConstraint == 0);
    X509KeyUsageExtension? interUsage = inter.KeyUsage;
    Check("intermediate key usage",
          interUsage != null &&
          interUsage.KeyUsages == (X509KeyUsageFlags.KeyCertSign | X509KeyUsageFlags.CrlSign));

    X509Certificate2 root = LoadFixture("root", RootPem);
    CheckText("root name quotes a comma", root.Subject,
              "CN=Stainless Test Root, O=\"Stainless, Test\", C=US");
    Check("root is self-issued", root.IsSelfIssued);
    Check("issuer names compare", inter.IssuerName.Equals(root.SubjectName));
}

void ParseOthers()
{
    X509Certificate2 ip = LoadFixture("ip", IpPem);
    X509SubjectAlternativeNameExtension? names = ip.SubjectAlternativeName;
    if (names != null)
    {
        CheckNumber("ip addresses", (long)names.IPAddresses.Length, 2);
        CheckText("ip v4", ToHex(names.IPAddresses[0u]), "C0000201");
        CheckText("ip v6", ToHex(names.IPAddresses[1u]), "20010DB8000000000000000000000001");
        CheckText("ip uri", names.Uris[0u], "https://example.com/path");
        CheckText("ip email", names.EmailAddresses[0u], "admin@example.com");
        CheckText("ip dns", names.DnsNames[0u], "ip.example.com");
    }
    else
    {
        Check("ip alternative names", false);
    }

    X509Certificate2 constrained = LoadFixture("nc", NcPem);
    X509NameConstraintsExtension? constraints = constrained.NameConstraints;
    if (constraints != null)
    {
        Check("nc critical", constraints.Critical);
        CheckText("nc permitted dns", constraints.PermittedDnsNames[0u], "example.com");
        CheckText("nc permitted ip", ToHex(constraints.PermittedIPRanges[0u]), "C0000200FFFFFF00");
        CheckText("nc excluded dns", constraints.ExcludedDnsNames[0u], "bad.example.com");
        CheckText("nc excluded ip", ToHex(constraints.ExcludedIPRanges[0u]),
                  "20010DB8000000000000000000000000FFFFFFFF000000000000000000000000");
    }
    else
    {
        Check("nc name constraints", false);
    }

    X509Certificate2 critical = LoadFixture("critical", CriticalPem);
    X509Extension? unknown = critical.Extensions["1.3.6.1.4.1.55555.1"];
    Check("unknown extension kept", unknown != null && unknown.Critical &&
                                    ToHex(unknown.RawData) == "0500");

    X509Certificate2 rsaRoot = LoadFixture("rsaroot", RsaRootPem);
    CheckText("rsa signature algorithm", rsaRoot.SignatureAlgorithm, "1.2.840.113549.1.1.11");
    CheckText("rsa key algorithm", rsaRoot.PublicKey.Oid, PublicKey.RsaOid);
    var modulus = rsaRoot.PublicKey.GetRsaModulus();
    Check("rsa modulus", modulus.Ok && modulus.Value.Length == 256u &&
                         ToHex(modulus.Value).StartsWith("AF25860825DB5058FF69EDF6F1AC36CD"));
    var exponent = rsaRoot.PublicKey.GetRsaExponent();
    CheckText("rsa exponent", exponent.Ok ? ToHex(exponent.Value) : "?", "010001");
    CheckText("rsa thumbprint", rsaRoot.Thumbprint, "560FFAFCED39D73A1E5B2E425E0CDE2D6534E57D");
    var rsaKey = rsaRoot.PublicKey.GetRsaPublicKey();
    Check("rsa key size", rsaKey.Ok && rsaKey.Value.KeySize == 2048);

    X509Certificate2 pss = LoadFixture("rsapss", RsaPssPem);
    CheckText("rsa-pss signature algorithm", pss.SignatureAlgorithm, "1.2.840.113549.1.1.10");
    CheckText("rsa-pss thumbprint", pss.Thumbprint, "7AF2EB776EEDE0237F26325BA1493599AC4E2B6E");

    X509Certificate2 p256 = LoadFixture("p256leaf", P256LeafPem);
    CheckText("p-256 signature algorithm", p256.SignatureAlgorithm, "1.2.840.10045.4.3.2");
    var curve = p256.PublicKey.GetECCurve();
    CheckText("p-256 curve", curve.Ok ? curve.Value.OidValue : "?", "1.2.840.10045.3.1.7");
    var point = p256.PublicKey.GetECPoint();
    Check("p-256 point", point.Ok && point.Value.Length == 65u &&
                         ToHex(point.Value).StartsWith("04E497340C3B5176B278DDA46F90E4"));
    var ecKey = p256.PublicKey.GetECDsaPublicKey();
    Check("p-256 key", ecKey.Ok && ecKey.Value.KeySize == 256u);
    CheckText("p-256 thumbprint", p256.Thumbprint, "D1A013EFDADAA60BC2C9BA3E78824152045B49E9");

    X509Certificate2 x1 = LoadFixture("isrgx1", IsrgX1Pem);
    CheckText("isrg x1 subject", x1.Subject,
              "CN=ISRG Root X1, O=Internet Security Research Group, C=US");
    CheckText("isrg x1 serial", x1.SerialNumber, "008210CFB0D240E3594463E0BB63828B00");
    CheckText("isrg x1 thumbprint", x1.Thumbprint, "CABD2A79A1076A31F21D253635CB039D4329A5E8");
    CheckText("isrg x1 sha-256", x1.Sha256Thumbprint,
              "96BCEC06264976F37460779ACF28C5A7CFE8A3C0AAE11A8FFCEE05C0BDDF08C6");
    var x1Modulus = x1.PublicKey.GetRsaModulus();
    Check("isrg x1 4096-bit", x1Modulus.Ok && x1Modulus.Value.Length == 512u);

    X509Certificate2 x2 = LoadFixture("isrgx2", IsrgX2Pem);
    CheckText("isrg x2 thumbprint", x2.Thumbprint, "BDB1B93CD5978D45C6261455F8DB95C75AD153AF");
    var x2Curve = x2.PublicKey.GetECCurve();
    CheckText("isrg x2 curve", x2Curve.Ok ? x2Curve.Value.OidValue : "?", "1.3.132.0.34");

    X509Certificate2 e6 = LoadFixture("e6", E6Pem);
    CheckText("e6 subject", e6.Subject, "CN=E6, O=Let's Encrypt, C=US");
    CheckText("e6 thumbprint", e6.Thumbprint, "C7BA5AA7E91080FA95E157476639736852C6BDF6");
    CheckNumber("e6 extensions", (long)e6.Extensions.Count, 8);

    X509Certificate2 r10 = LoadFixture("r10", R10Pem);
    CheckText("r10 thumbprint", r10.Thumbprint, "00ABEFD055F9A9C784FFDEABD1DCDD8FED741436");
    CheckText("r10 sha-256", r10.Sha256Thumbprint,
              "9D7C3F1AA6AD2B2EC0D5CF1E246F8D9AE6CBC9FD0755AD37BB974B1F2FB603F3");

    // A bundle of every fixture; the one given twice is kept once.
    var bundle = new X509Certificate2Collection();
    String text = CreateTextFromBytes(RootPem) + CreateTextFromBytes(InterPem) +
                  "-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----\n" +
                  CreateTextFromBytes(GoodPem) + CreateTextFromBytes(RootPem);
    var added = bundle.ImportFromPem(text);
    CheckNumber("bundle added", added.Ok ? (long)added.Value : -1, 3);
    CheckNumber("bundle count", (long)bundle.Count, 3);
    var again = new X509Certificate2Collection();
    var readBack = again.ImportFromPem(bundle.ExportCertificatePems());
    Check("bundle round trip", readBack.Ok && again.Count == 3u && again[2u].Equals(bundle[2u]));
    Check("bundle refuses a bad block",
          !again.ImportFromPem("-----BEGIN CERTIFICATE-----\nAAAA\n-----END CERTIFICATE-----\n").Ok);
}

// ------------------------------------------------------------ refusals

void CheckRefused(String label, ReadOnlySpan<byte> der)
{
    var parsed = X509Certificate2.FromDer(der);
    Check(label, !parsed.Ok && parsed.Error == CryptoError.Encoding);
}

void ParseRefusals()
{
    byte[] good = GoodDer;
    CheckRefused("refuses empty", new byte[0u]);
    CheckRefused("refuses truncated", good[:good.Length - 1u]);

    byte[] trailing = new byte[good.Length + 1u];
    for (nuint i = 0u; i < good.Length; i++)
        trailing[i] = good[i];
    CheckRefused("refuses trailing data", trailing);

    // The outer sha256WithRSAEncryption made sha384 while the signed one is not.
    X509Certificate2 rsa = LoadFixture("rsaleaf", RsaLeafPem);
    byte[] mismatched = rsa.RawData;
    byte[] identifier = Hex("2A864886F70D01010B");
    nuint last = 0u;
    for (nuint at = 0u; at + identifier.Length <= mismatched.Length; at++)
    {
        bool same = true;
        for (nuint j = 0u; j < identifier.Length; j++)
        {
            if (mismatched[at + j] != identifier[j])
                same = false;
        }
        if (same)
            last = at;
    }
    mismatched[last + identifier.Length - 1u] = 0x0C;
    CheckRefused("refuses a signature algorithm that differs", mismatched);

    // The explicit version, A0 03 02 01 02, made 3: a version 4 there is not.
    byte[] versioned = GoodDer[:].ToArray();
    Check("version is where it is expected", versioned[8u] == 0xA0 && versioned[12u] == 0x02);
    versioned[12u] = 0x03;
    CheckRefused("refuses version 4", versioned);

    var noCertificate =
        X509Certificate2.FromPem("-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----");
    Check("refuses pem with no certificate block", !noCertificate.Ok);
}
