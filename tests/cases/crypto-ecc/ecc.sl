// SPDX-License-Identifier: 0BSD
module EccCase;

import Standard.Console;
import Standard.Convert;
import Standard.Encoding;
import Standard.Text;
import Standard.Formats.Asn1;
import Standard.Security.Cryptography;

// Every answer here is published or made by another implementation:
//
// - RFC 6979 appendix A.2.5 and A.2.6 for the deterministic signatures;
// - NIST CAVP's KAS ECC CDH primitive vectors (KAS_ECC_CDH_PrimitiveTest.txt
//   in ecccdhtestvectors.zip), COUNT 0 to 2, for the agreements;
// - Project Wycheproof for verification and agreement edge cases, in
//   wycheproof.sl;
// - OpenSSL 3.5.5 for the key files beside this one, made with `ecparam
//   -genkey`, `pkcs8 -topk8 -nocrypt` and `ec -pubout`, and for the
//   signatures and shared secrets quoted below, made with `dgst -sign` and
//   `pkeyutl -derive` from those keys. certificate.der is the asn1 case's.
//
// A number that changes here is a broken implementation, not a changed
// convention.

[Embed("p256-ec.pem")]
static readonly byte[] P256EcPem;

[Embed("p256-pkcs8.pem")]
static readonly byte[] P256Pkcs8Pem;

[Embed("p256-public.pem")]
static readonly byte[] P256PublicPem;

[Embed("p256-public-compressed.pem")]
static readonly byte[] P256CompressedPem;

[Embed("p256-peer-public.pem")]
static readonly byte[] P256PeerPem;

[Embed("p384-ec.pem")]
static readonly byte[] P384EcPem;

[Embed("p384-pkcs8.pem")]
static readonly byte[] P384Pkcs8Pem;

[Embed("p384-public.pem")]
static readonly byte[] P384PublicPem;

[Embed("p384-public-compressed.pem")]
static readonly byte[] P384CompressedPem;

[Embed("p384-peer-public.pem")]
static readonly byte[] P384PeerPem;

[Embed("certificate.der")]
static readonly byte[] CertificateDer;

// ------------------------------------------------------------------ helpers

byte[] Bytes(String text) => Encoding.CreateUtf8().GetBytes(text);

byte[] Hex(String text) => Convert.FromHexString(text).GetValueOrDefault(new byte[0u]);

String ToHex(ReadOnlySpan<byte> bytes) => Convert.ToHexString(bytes.ToArray());

byte[] Copy(ReadOnlySpan<byte> bytes) => bytes.ToArray();

String CreateText(byte[] bytes)
{
    var built = new StringBuilder();
    built.AppendBytes(bytes);
    return built.ToText();
}

byte[] Join(ReadOnlySpan<byte> first, ReadOnlySpan<byte> second)
{
    byte[] joined = new byte[first.Length + second.Length];
    for (nuint i = 0u; i < first.Length; i++)
        joined[i] = first[i];
    for (nuint i = 0u; i < second.Length; i++)
        joined[first.Length + i] = second[i];
    return joined;
}

byte[] CreateUncompressedPoint(String x, String y) => Join(Hex("04"), Join(Hex(x), Hex(y)));

byte[] Empty() => new byte[0u];

void Check(String label, String actual, String expected)
{
    if (actual == expected)
    {
        Console.WriteLine(label + " ok");
        return;
    }

    Console.WriteLine(label + " WRONG");
    Console.WriteLine("  got      " + actual);
    Console.WriteLine("  expected " + expected);
}

void CheckTrue(String label, bool condition) => Check(label, condition ? "true" : "false", "true");

String DescribeCryptoError(CryptoError error)
{
    switch (error)
    {
        case CryptoError.InvalidKey: return "InvalidKey";
        case CryptoError.InvalidPoint: return "InvalidPoint";
        case CryptoError.InvalidSignature: return "InvalidSignature";
        case CryptoError.Encoding: return "Encoding";
        case CryptoError.Unsupported: return "Unsupported";
        case CryptoError.NoEntropy: return "NoEntropy";
    }
    return "another error";
}

// "ok", or the failure's name: what a refusal is checked against.

String DescribeOutcome(Result<ECDsa, CryptoError> result) =>
    result.Ok ? "ok" : DescribeCryptoError(result.Error);

String DescribeOutcome(Result<ECDiffieHellman, CryptoError> result) =>
    result.Ok ? "ok" : DescribeCryptoError(result.Error);

String DescribeOutcome(Result<byte[], CryptoError> result) =>
    result.Ok ? "ok" : DescribeCryptoError(result.Error);

String DescribeOutcome(Result<bool, CryptoError> result) =>
    result.Ok ? "ok" : DescribeCryptoError(result.Error);

String DescribeOutcome(Result<nuint, CryptoError> result) =>
    result.Ok ? "ok" : DescribeCryptoError(result.Error);

String DescribeOutcome(Result<ECParameters, CryptoError> result) =>
    result.Ok ? "ok" : DescribeCryptoError(result.Error);

ECParameters CreatePrivateParameters(ECCurve curve, String d) =>
    new ECParameters(curve, new ECPoint(Empty(), Empty()), Hex(d));

/// Runs one group of checks, and says so if it stopped early.
void RunChecks(String name, Result<bool, CryptoError> outcome)
{
    if (!outcome.Ok)
        Console.WriteLine(name + " stopped: " + DescribeCryptoError(outcome.Error));
}

// ----------------------------------------------------------------- RFC 6979

Result<bool, CryptoError> CheckDeterministicSignature(String label, ECDsa key, String message,
                                                      HashAlgorithmName hash, String r, String s)
{
    byte[] signature = try key.SignData(Bytes(message), hash);
    Check(label, ToHex(signature), (r + s).ToLowerAscii());
    CheckTrue(label + " verifies", key.VerifyData(Bytes(message), signature, hash));
    return Ok(true);
}

Result<bool, CryptoError> CheckRfc6979P256()
{
    var curve = ECCurve.NamedCurves.NistP256;
    var key = try ECDsa.Create(CreatePrivateParameters(curve,
        "C9AFA9D845BA75166B5C215767B1D6934E50C3DB36E89B127B8A622B120F6721"));

    var exported = try key.ExportParameters(false);
    Check("p256 public from private", ToHex(exported.Q.X) + ToHex(exported.Q.Y),
          "60fed4ba255a9d31c961eb74c6356d68c049b8923b61fa6ce669622e60f29fb6" +
          "7903fe1008b8bc99a41ae9e95628bc64f2f1b20c2d7e9f5177a3c294d4462299");

    try CheckDeterministicSignature("p256 sha1 sample", key, "sample", HashAlgorithmName.Sha1,
        "61340C88C3AAEBEB4F6D667F672CA9759A6CCAA9FA8811313039EE4A35471D32",
        "6D7F147DAC089441BB2E2FE8F7A3FA264B9C475098FDCF6E00D7C996E1B8B7EB");
    try CheckDeterministicSignature("p256 sha256 sample", key, "sample", HashAlgorithmName.Sha256,
        "EFD48B2AACB6A8FD1140DD9CD45E81D69D2C877B56AAF991C34D0EA84EAF3716",
        "F7CB1C942D657C41D436C7A1B6E29F65F3E900DBB9AFF4064DC4AB2F843ACDA8");
    try CheckDeterministicSignature("p256 sha384 sample", key, "sample", HashAlgorithmName.Sha384,
        "0EAFEA039B20E9B42309FB1D89E213057CBF973DC0CFC8F129EDDDC800EF7719",
        "4861F0491E6998B9455193E34E7B0D284DDD7149A74B95B9261F13ABDE940954");
    try CheckDeterministicSignature("p256 sha512 sample", key, "sample", HashAlgorithmName.Sha512,
        "8496A60B5E9B47C825488827E0495B0E3FA109EC4568FD3F8D1097678EB97F00",
        "2362AB1ADBE2B8ADF9CB9EDAB740EA6049C028114F2460F96554F61FAE3302FE");
    try CheckDeterministicSignature("p256 sha1 test", key, "test", HashAlgorithmName.Sha1,
        "0CBCC86FD6ABD1D99E703E1EC50069EE5C0B4BA4B9AC60E409E8EC5910D81A89",
        "01B9D7B73DFAA60D5651EC4591A0136F87653E0FD780C3B1BC872FFDEAE479B1");
    try CheckDeterministicSignature("p256 sha256 test", key, "test", HashAlgorithmName.Sha256,
        "F1ABB023518351CD71D881567B1EA663ED3EFCF6C5132B354F28D3B0B7D38367",
        "019F4113742A2B14BD25926B49C649155F267E60D3814B4C0CC84250E46F0083");
    try CheckDeterministicSignature("p256 sha384 test", key, "test", HashAlgorithmName.Sha384,
        "83910E8B48BB0C74244EBDF7F07A1C5413D61472BD941EF3920E623FBCCEBEB6",
        "8DDBEC54CF8CD5874883841D712142A56A8D0F218F5003CB0296B6B509619F2C");
    try CheckDeterministicSignature("p256 sha512 test", key, "test", HashAlgorithmName.Sha512,
        "461D93F31B6540894788FD206C07CFA0CC35F46FA3C91816FFF1040AD1581A04",
        "39AF9F15DE0DB8D97E72719C74820D304CE5226E32DEDAE67519E840D1194E55");

    // SignHash picks the nonce's HMAC by the hash's length.
    byte[] hashed = try key.SignHash(Sha256.HashData(Bytes("sample")));
    Check("p256 sign hash", ToHex(hashed),
          "efd48b2aacb6a8fd1140dd9cd45e81d69d2c877b56aaf991c34d0ea84eaf3716" +
          "f7cb1c942d657c41d436c7a1b6e29f65f3e900dbb9aff4064dc4ab2f843acda8");
    return Ok(true);
}

Result<bool, CryptoError> CheckRfc6979P384()
{
    var curve = ECCurve.NamedCurves.NistP384;
    var key = try ECDsa.Create(CreatePrivateParameters(curve,
        "6B9D3DAD2E1B8C1C05B19875B6659F4DE23C3B667BF297BA9AA47740787137D8" +
        "96D5724E4C70A825F872C9EA60D2EDF5"));

    var exported = try key.ExportParameters(false);
    Check("p384 public from private", ToHex(exported.Q.X) + ToHex(exported.Q.Y),
          ("EC3A4E415B4E19A4568618029F427FA5DA9A8BC4AE92E02E06AAE5286B300C64" +
           "DEF8F0EA9055866064A254515480BC13" +
           "8015D9B72D7D57244EA8EF9AC0C621896708A59367F9DFB9F54CA84B3F1C9DB1" +
           "288B231C3AE0D4FE7344FD2533264720").ToLowerAscii());

    try CheckDeterministicSignature("p384 sha1 sample", key, "sample", HashAlgorithmName.Sha1,
        "EC748D839243D6FBEF4FC5C4859A7DFFD7F3ABDDF72014540C16D73309834FA3" +
        "7B9BA002899F6FDA3A4A9386790D4EB2",
        "A3BCFA947BEEF4732BF247AC17F71676CB31A847B9FF0CBC9C9ED4C1A5B3FACF" +
        "26F49CA031D4857570CCB5CA4424A443");
    try CheckDeterministicSignature("p384 sha256 sample", key, "sample", HashAlgorithmName.Sha256,
        "21B13D1E013C7FA1392D03C5F99AF8B30C570C6F98D4EA8E354B63A21D3DAA33" +
        "BDE1E888E63355D92FA2B3C36D8FB2CD",
        "F3AA443FB107745BF4BD77CB3891674632068A10CA67E3D45DB2266FA7D1FEEB" +
        "EFDC63ECCD1AC42EC0CB8668A4FA0AB0");
    try CheckDeterministicSignature("p384 sha384 sample", key, "sample", HashAlgorithmName.Sha384,
        "94EDBB92A5ECB8AAD4736E56C691916B3F88140666CE9FA73D64C4EA95AD133C" +
        "81A648152E44ACF96E36DD1E80FABE46",
        "99EF4AEB15F178CEA1FE40DB2603138F130E740A19624526203B6351D0A3A94F" +
        "A329C145786E679E7B82C71A38628AC8");
    try CheckDeterministicSignature("p384 sha512 sample", key, "sample", HashAlgorithmName.Sha512,
        "ED0959D5880AB2D869AE7F6C2915C6D60F96507F9CB3E047C0046861DA4A799C" +
        "FE30F35CC900056D7C99CD7882433709",
        "512C8CCEEE3890A84058CE1E22DBC2198F42323CE8ACA9135329F03C068E5112" +
        "DC7CC3EF3446DEFCEB01A45C2667FDD5");
    try CheckDeterministicSignature("p384 sha1 test", key, "test", HashAlgorithmName.Sha1,
        "4BC35D3A50EF4E30576F58CD96CE6BF638025EE624004A1F7789A8B8E43D0678" +
        "ACD9D29876DAF46638645F7F404B11C7",
        "D5A6326C494ED3FF614703878961C0FDE7B2C278F9A65FD8C4B7186201A29916" +
        "95BA1C84541327E966FA7B50F7382282");
    try CheckDeterministicSignature("p384 sha256 test", key, "test", HashAlgorithmName.Sha256,
        "6D6DEFAC9AB64DABAFE36C6BF510352A4CC27001263638E5B16D9BB51D451559" +
        "F918EEDAF2293BE5B475CC8F0188636B",
        "2D46F3BECBCC523D5F1A1256BF0C9B024D879BA9E838144C8BA6BAEB4B53B47D" +
        "51AB373F9845C0514EEFB14024787265");
    try CheckDeterministicSignature("p384 sha384 test", key, "test", HashAlgorithmName.Sha384,
        "8203B63D3C853E8D77227FB377BCF7B7B772E97892A80F36AB775D509D7A5FEB" +
        "0542A7F0812998DA8F1DD3CA3CF023DB",
        "DDD0760448D42D8A43AF45AF836FCE4DE8BE06B485E9B61B827C2F13173923E0" +
        "6A739F040649A667BF3B828246BAA5A5");
    try CheckDeterministicSignature("p384 sha512 test", key, "test", HashAlgorithmName.Sha512,
        "A0D5D090C9980FAF3C2CE57B7AE951D31977DD11C775D314AF55F76C676447D0" +
        "6FB6495CD21B4B6E340FC236584FB277",
        "976984E59B4C77B0E8E4460DCA3D9F20E07B9BB1F63BEEFAF576F6B2E8B22463" +
        "4A2092CD3792E0159AD9CEE37659C736");
    return Ok(true);
}

// ---------------------------------------------------------------- NIST CDH

Result<bool, CryptoError> CheckAgreement(String label, ECCurve curve, String otherX,
                                         String otherY, String d, String ourX, String ourY,
                                         String shared)
{
    var mine = try ECDiffieHellman.Create(
        new ECParameters(curve, new ECPoint(Hex(ourX), Hex(ourY)), Hex(d)));
    byte[] secret = try mine.DeriveRawSecretAgreement(CreateUncompressedPoint(otherX, otherY));
    Check(label, ToHex(secret), shared);
    return Ok(true);
}

Result<bool, CryptoError> CheckNistAgreements()
{
    var p256 = ECCurve.NamedCurves.NistP256;
    try CheckAgreement("cdh p256 count 0", p256,
        "700c48f77f56584c5cc632ca65640db91b6bacce3a4df6b42ce7cc838833d287",
        "db71e509e3fd9b060ddb20ba5c51dcc5948d46fbf640dfe0441782cab85fa4ac",
        "7d7dc5f71eb29ddaf80d6214632eeae03d9058af1fb6d22ed80badb62bc1a534",
        "ead218590119e8876b29146ff89ca61770c4edbbf97d38ce385ed281d8a6b230",
        "28af61281fd35e2fa7002523acc85a429cb06ee6648325389f59edfce1405141",
        "46fc62106420ff012e54a434fbdd2d25ccc5852060561e68040dd7778997bd7b");
    try CheckAgreement("cdh p256 count 1", p256,
        "809f04289c64348c01515eb03d5ce7ac1a8cb9498f5caa50197e58d43a86a7ae",
        "b29d84e811197f25eba8f5194092cb6ff440e26d4421011372461f579271cda3",
        "38f65d6dce47676044d58ce5139582d568f64bb16098d179dbab07741dd5caf5",
        "119f2f047902782ab0c9e27a54aff5eb9b964829ca99c06b02ddba95b0a3f6d0",
        "8f52b726664cac366fc98ac7a012b2682cbd962e5acb544671d41b9445704d1d",
        "057d636096cb80b67a8c038c890e887d1adfa4195e9b3ce241c8a778c59cda67");
    try CheckAgreement("cdh p256 count 2", p256,
        "a2339c12d4a03c33546de533268b4ad667debf458b464d77443636440ee7fec3",
        "ef48a3ab26e20220bcda2c1851076839dae88eae962869a497bf73cb66faf536",
        "1accfaf1b97712b85a6f54b148985a1bdc4c9bec0bd258cad4b3d603f49f32c8",
        "d9f2b79c172845bfdb560bbb01447ca5ecc0470a09513b6126902c6b4f8d1051",
        "f815ef5ec32128d3487834764678702e64e164ff7315185e23aff5facd96d7bc",
        "2d457b78b4614132477618a5b077965ec90730a8c81a1c75d6d4ec68005d67ec");

    var p384 = ECCurve.NamedCurves.NistP384;
    try CheckAgreement("cdh p384 count 0", p384,
        "a7c76b970c3b5fe8b05d2838ae04ab47697b9eaf52e764592efda27fe7513272" +
        "734466b400091adbf2d68c58e0c50066",
        "ac68f19f2e1cb879aed43a9969b91a0839c4c38a49749b661efedf243451915e" +
        "d0905a32b060992b468c64766fc8437a",
        "3cc3122a68f0d95027ad38c067916ba0eb8c38894d22e1b15618b6818a661774" +
        "ad463b205da88cf699ab4d43c9cf98a1",
        "9803807f2f6d2fd966cdd0290bd410c0190352fbec7ff6247de1302df86f25d3" +
        "4fe4a97bef60cff548355c015dbb3e5f",
        "ba26ca69ec2f5b5d9dad20cc9da711383a9dbe34ea3fa5a2af75b46502629ad5" +
        "4dd8b7d73a8abb06a3a3be47d650cc99",
        "5f9d29dc5e31a163060356213669c8ce132e22f57c9a04f40ba7fcead493b457" +
        "e5621e766c40a2e3d4d6a04b25e533f1");
    try CheckAgreement("cdh p384 count 1", p384,
        "30f43fcf2b6b00de53f624f1543090681839717d53c7c955d1d69efaf0349b73" +
        "63acb447240101cbb3af6641ce4b88e0",
        "25e46c0c54f0162a77efcc27b6ea792002ae2ba82714299c860857a68153ab62" +
        "e525ec0530d81b5aa15897981e858757",
        "92860c21bde06165f8e900c687f8ef0a05d14f290b3f07d8b3a8cc6404366e5d" +
        "5119cd6d03fb12dc58e89f13df9cd783",
        "ea4018f5a307c379180bf6a62fd2ceceebeeb7d4df063a66fb838aa352434197" +
        "91f7e2c9d4803c9319aa0eb03c416b66",
        "68835a91484f05ef028284df6436fb88ffebabcdd69ab0133e6735a1bcfb3720" +
        "3d10d340a8328a7b68770ca75878a1a6",
        "a23742a2c267d7425fda94b93f93bbcc24791ac51cd8fd501a238d40812f4cbf" +
        "c59aac9520d758cf789c76300c69d2ff");
    try CheckAgreement("cdh p384 count 2", p384,
        "1aefbfa2c6c8c855a1a216774550b79a24cda37607bb1f7cc906650ee4b3816d" +
        "68f6a9c75da6e4242cebfb6652f65180",
        "419d28b723ebadb7658fcebb9ad9b7adea674f1da3dc6b6397b55da0f61a3edd" +
        "acb4acdb14441cb214b04a0844c02fa3",
        "12cf6a223a72352543830f3f18530d5cb37f26880a0b294482c8a8ef8afad09a" +
        "a78b7dc2f2789a78c66af5d1cc553853",
        "fcfcea085e8cf74d0dced1620ba8423694f903a219bbf901b0b59d6ac81baad3" +
        "16a242ba32bde85cb248119b852fab66",
        "972e3c68c7ab402c5836f2a16ed451a33120a7750a6039f3ff15388ee622b706" +
        "5f7122bf6d51aefbc29b37b03404581b",
        "3d2e640f350805eed1ff43b40a72b2abed0a518bcebe8f2d15b111b6773223da" +
        "3c3489121db173d414b5bd5ad7153435");
    return Ok(true);
}

// --------------------------------------------------------------- Wycheproof

Result<bool, CryptoError> CheckSignatureVectors(String label, String[] vectors, ECCurve curve,
                                                HashAlgorithmName hash)
{
    nuint count = vectors.Length / 4u;
    nuint agreed = 0u;
    var verifier = try ECDsa.Create(curve);
    String loaded = "";
    for (nuint i = 0u; i < count; i++)
    {
        String key = vectors[4u * i];
        if (key != loaded)
        {
            var imported = verifier.ImportSubjectPublicKeyInfo(Hex(key));
            if (!imported.Ok)
                Console.WriteLine($"  {label} vector {i}: key refused");
            loaded = key;
        }

        bool verified = verifier.VerifyData(Hex(vectors[4u * i + 1u]), Hex(vectors[4u * i + 2u]),
                                            hash, DsaSignatureFormat.Rfc3279DerSequence);
        if (verified == (vectors[4u * i + 3u] == "valid"))
        {
            agreed++;
        }
        else
        {
            Console.WriteLine($"  {label} vector {i} disagrees");
        }
    }
    Check(label, $"{agreed} of {count}", $"{count} of {count}");
    return Ok(true);
}

Result<bool, CryptoError> CheckAgreementVectors(String label, String[] vectors, ECCurve curve)
{
    nuint count = vectors.Length / 4u;
    nuint agreed = 0u;
    for (nuint i = 0u; i < count; i++)
    {
        var mine = try ECDiffieHellman.Create(CreatePrivateParameters(curve, vectors[4u * i + 1u]));
        var secret = mine.DeriveRawSecretAgreement(Hex(vectors[4u * i]));
        bool right = false;
        if (vectors[4u * i + 3u] == "invalid")
        {
            right = !secret.Ok;
        }
        else if (secret.Ok)
        {
            right = ToHex(secret.Value) == vectors[4u * i + 2u];
        }

        if (right)
        {
            agreed++;
        }
        else
        {
            Console.WriteLine($"  {label} vector {i} disagrees: {DescribeOutcome(secret)}");
        }
    }
    Check(label, $"{agreed} of {count}", $"{count} of {count}");
    return Ok(true);
}

// ----------------------------------------------------------- signature forms

Result<bool, CryptoError> CheckSignatureFormats()
{
    var key = try ECDsa.Create(CreatePrivateParameters(ECCurve.NamedCurves.NistP256,
        "C9AFA9D845BA75166B5C215767B1D6934E50C3DB36E89B127B8A622B120F6721"));
    byte[] message = Bytes("sample");
    var sha256 = HashAlgorithmName.Sha256;

    byte[] fixedWidth = try key.SignData(message, sha256);
    byte[] der = try key.SignData(message, sha256, DsaSignatureFormat.Rfc3279DerSequence);

    // Both halves have their top bit set, so each INTEGER gains a zero.
    Check("der both padded", ToHex(der),
          "3046022100" + ToHex(fixedWidth[:32u]) + "022100" + ToHex(fixedWidth[32u:]));

    // r's leading byte is 0x0E: no padding, and no leading zero kept.
    byte[] small = try key.SignData(message, HashAlgorithmName.Sha384,
                                    DsaSignatureFormat.Rfc3279DerSequence);
    Check("der unpadded", ToHex(small),
          "30440220" + "0eafea039b20e9b42309fb1d89e213057cbf973dc0cfc8f129edddc800ef7719" +
          "0220" + "4861f0491e6998b9455193e34e7b0d284ddd7149a74b95b9261f13abde940954");

    // The DER read back with the ASN.1 reader: the same two numbers.
    var reader = new AsnReader(der, AsnEncodingRules.Der);
    var pair = reader.ReadSequence();
    if (pair.Ok)
    {
        var r = pair.Value.ReadIntegerBytes();
        var s = pair.Value.ReadIntegerBytes();
        if (r.Ok && s.Ok)
            Check("der to p1363", ToHex(r.Value[1u:]) + ToHex(s.Value[1u:]), ToHex(fixedWidth));
    }

    CheckTrue("der verifies", key.VerifyData(message, der, sha256,
                                             DsaSignatureFormat.Rfc3279DerSequence));
    CheckTrue("der is not p1363", !key.VerifyData(message, der, sha256));
    CheckTrue("p1363 is not der", !key.VerifyData(message, fixedWidth, sha256,
                                                  DsaSignatureFormat.Rfc3279DerSequence));
    CheckTrue("der with trailing byte refused",
              !key.VerifyData(message, Join(der, Hex("00")), sha256,
                              DsaSignatureFormat.Rfc3279DerSequence));

    // The unpadded r made negative: 0x8E... with no zero in front.
    byte[] negative = Copy(small);
    negative[4u] = 0x8E;
    CheckTrue("der negative integer refused",
              !key.VerifyData(message, negative, HashAlgorithmName.Sha384,
                              DsaSignatureFormat.Rfc3279DerSequence));

    Check("max sizes p256",
          $"{key.GetMaxSignatureSize(DsaSignatureFormat.IeeeP1363FixedFieldConcatenation)} " +
          $"{key.GetMaxSignatureSize(DsaSignatureFormat.Rfc3279DerSequence)}", "64 72");

    var wide = try ECDsa.Create(ECCurve.NamedCurves.NistP384);
    byte[] wideDer = try wide.SignData(message, HashAlgorithmName.Sha384,
                                       DsaSignatureFormat.Rfc3279DerSequence);
    CheckTrue("p384 der verifies", wide.VerifyData(message, wideDer, HashAlgorithmName.Sha384,
                                                   DsaSignatureFormat.Rfc3279DerSequence));
    Check("max sizes p384",
          $"{wide.GetMaxSignatureSize(DsaSignatureFormat.IeeeP1363FixedFieldConcatenation)} " +
          $"{wide.GetMaxSignatureSize(DsaSignatureFormat.Rfc3279DerSequence)}", "96 104");
    CheckTrue("p384 der fits",
              wideDer.Length <= wide.GetMaxSignatureSize(DsaSignatureFormat.Rfc3279DerSequence));
    return Ok(true);
}

// -------------------------------------------------------------- key formats

/// The DER inside the first PEM block of `text`, or nothing.
byte[] ReadPemData(String text)
{
    var found = PemEncoding.Find(text);
    if (!found.Some)
        return Empty();
    return found.Value.Data;
}

Result<bool, CryptoError> CheckKeyFiles(String label, ECCurve curve, byte[] ecPem,
                                        byte[] pkcs8Pem, byte[] publicPem, byte[] compressedPem,
                                        byte[] peerPem, String shared, String signature,
                                        HashAlgorithmName hash)
{
    String ecText = CreateText(ecPem);
    String pkcs8Text = CreateText(pkcs8Pem);
    String publicText = CreateText(publicPem);

    // OpenSSL ends each file with a newline, and PemEncoding.Write does not.
    var key = try ECDsa.Create(curve);
    Check(label + " import sec1 pem", DescribeOutcome(key.ImportFromPem(ecText)), "ok");
    Check(label + " sec1 pem", (try key.ExportECPrivateKeyPem()) + "\n", ecText);
    Check(label + " pkcs8 pem", (try key.ExportPkcs8PrivateKeyPem()) + "\n", pkcs8Text);
    Check(label + " spki pem", key.ExportSubjectPublicKeyInfoPem() + "\n", publicText);

    byte[] sec1Der = ReadPemData(ecText);
    byte[] pkcs8Der = ReadPemData(pkcs8Text);

    var fromPkcs8 = try ECDsa.Create(curve);
    nuint read = try fromPkcs8.ImportPkcs8PrivateKey(Join(pkcs8Der, Hex("0000")));
    Check(label + " pkcs8 bytes read", $"{read}", $"{pkcs8Der.Length}");
    Check(label + " pkcs8 der to sec1 der", ToHex(try fromPkcs8.ExportECPrivateKey()),
          ToHex(sec1Der));

    var fromSec1 = try ECDsa.Create(curve);
    Check(label + " sec1 der", DescribeOutcome(fromSec1.ImportECPrivateKey(sec1Der)), "ok");
    Check(label + " sec1 der to pkcs8 der", ToHex(try fromSec1.ExportPkcs8PrivateKey()),
          ToHex(pkcs8Der));

    var fromParameters = try ECDsa.Create(try key.ExportParameters(true));
    Check(label + " parameters round trip", ToHex(try fromParameters.ExportECPrivateKey()),
          ToHex(sec1Der));

    var compressed = try ECDsa.Create(curve);
    Check(label + " import compressed",
          DescribeOutcome(compressed.ImportFromPem(CreateText(compressedPem))), "ok");
    Check(label + " compressed to uncompressed",
          compressed.ExportSubjectPublicKeyInfoPem() + "\n", publicText);
    CheckTrue(label + " openssl signature verifies",
              compressed.VerifyData(Bytes("signed by OpenSSL"), Hex(signature), hash,
                                    DsaSignatureFormat.Rfc3279DerSequence));
    CheckTrue(label + " openssl signature is for its message",
              !compressed.VerifyData(Bytes("signed by OpenSSL."), Hex(signature), hash,
                                     DsaSignatureFormat.Rfc3279DerSequence));

    var mine = try ECDiffieHellman.Create(curve);
    try mine.ImportFromPem(pkcs8Text);
    var peer = try ECDiffieHellman.Create(curve);
    try peer.ImportFromPem(CreateText(peerPem));
    Check(label + " openssl agreement", ToHex(try mine.DeriveRawSecretAgreement(peer.PublicKey)),
          shared);
    Check(label + " ecdh spki pem", peer.ExportSubjectPublicKeyInfoPem() + "\n",
          CreateText(peerPem));
    return Ok(true);
}

Result<bool, CryptoError> CheckOpenSslKeys()
{
    try CheckKeyFiles("p256", ECCurve.NamedCurves.NistP256, P256EcPem, P256Pkcs8Pem,
        P256PublicPem, P256CompressedPem, P256PeerPem,
        "898479fdbf3cdd74f01f4d56c948714fd41af0cf017ca2279bf5a47153feece3",
        "30450221009906a22d3795f89e6a29472265f1fd17c9ba0fbdf47770161ea44b919dec9705" +
        "022011c4516950cb6f0012ae64e30eb468a4fc0a33f65d9739e11d46cb65befb5901",
        HashAlgorithmName.Sha256);
    try CheckKeyFiles("p384", ECCurve.NamedCurves.NistP384, P384EcPem, P384Pkcs8Pem,
        P384PublicPem, P384CompressedPem, P384PeerPem,
        "c2153d3961b91d80df127a150ac62c3090e857427989dad9f8941367bf3791ac" +
        "d925ff627a334a48afcfeeb8612c66b1",
        "306502305fb13402cd3b97bcb3221336b385cbbb2b08bb434eaa9376ff1fb6215ef4ec5f" +
        "dcca5e506690f9422f8a8f5000601d17023100968a542f436fc780421955a30b33223d2c" +
        "4e304a4ac3de7003379a60d2c837d5cfd66078f9b970203d06c03da529b40f",
        HashAlgorithmName.Sha384);
    return Ok(true);
}

/// The certificate signs its TBSCertificate with ecdsa-with-SHA256 under its
/// own SubjectPublicKeyInfo.
Result<bool, AsnError> CheckCertificate()
{
    var document = new AsnReader(CertificateDer, AsnEncodingRules.Der);
    var certificate = try document.ReadSequence();
    ReadOnlySpan<byte> signed = try certificate.ReadEncodedValue();
    Check("certificate algorithm", try (try certificate.ReadSequence()).ReadObjectIdentifier(),
          "1.2.840.10045.4.3.2");
    ReadOnlySpan<byte> signature = try certificate.ReadBitString(out int unused);

    var tbs = try new AsnReader(signed, AsnEncodingRules.Der).ReadSequence();
    for (nuint i = 0u; i < 6u; i++)
        try tbs.ReadEncodedValue();
    ReadOnlySpan<byte> publicKey = try tbs.ReadEncodedValue();

    var verifier = ECDsa.Create(ECCurve.NamedCurves.NistP256);
    if (!verifier.Ok)
        return Ok(false);
    Check("certificate key",
          DescribeOutcome(verifier.Value.ImportSubjectPublicKeyInfo(publicKey)), "ok");
    CheckTrue("certificate signature", verifier.Value.VerifyData(signed, signature,
        HashAlgorithmName.Sha256, DsaSignatureFormat.Rfc3279DerSequence));
    return Ok(true);
}

// ----------------------------------------------------------------- refusals

Result<bool, CryptoError> CheckPointRefusals()
{
    var p256 = ECCurve.NamedCurves.NistP256;
    String gx = "6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296";
    String gy = "4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5";
    String prime = "ffffffff00000001000000000000000000000000ffffffffffffffffffffffff";

    var agreement = try ECDiffieHellman.Create(p256);
    byte[] offCurve = CreateUncompressedPoint(gx, gy);
    offCurve[64u] ^= 0x01;
    Check("off-curve point", DescribeOutcome(agreement.DeriveRawSecretAgreement(offCurve)),
          "InvalidPoint");
    Check("infinity", DescribeOutcome(agreement.DeriveRawSecretAgreement(Hex("00"))),
          "InvalidPoint");
    Check("coordinate of p", DescribeOutcome(agreement.DeriveRawSecretAgreement(
        CreateUncompressedPoint(prime, gy))), "InvalidPoint");
    byte[] hybrid = CreateUncompressedPoint(gx, gy);
    hybrid[0u] = 0x07;
    Check("hybrid form", DescribeOutcome(agreement.DeriveRawSecretAgreement(hybrid)),
          "InvalidPoint");
    Check("truncated point", DescribeOutcome(agreement.DeriveRawSecretAgreement(
        CreateUncompressedPoint(gx, gy)[:64u])), "InvalidPoint");
    var other = try ECDiffieHellman.Create(ECCurve.NamedCurves.NistP384);
    Check("point on another curve", DescribeOutcome(agreement.DeriveRawSecretAgreement(
        other.PublicKey)), "InvalidPoint");
    Check("compressed generator", DescribeOutcome(agreement.DeriveRawSecretAgreement(
        Join(Hex("02"), Hex(gx)))), "ok");
    Check("compressed x of p", DescribeOutcome(agreement.DeriveRawSecretAgreement(
        Join(Hex("03"), Hex(prime)))), "InvalidPoint");

    Check("q off the curve", DescribeOutcome(ECDsa.Create(new ECParameters(p256,
        new ECPoint(Hex(gx), Hex(gx))))), "InvalidPoint");
    Check("q of the wrong width", DescribeOutcome(ECDsa.Create(new ECParameters(p256,
        new ECPoint(Copy(Hex(gx)[1u:]), Hex(gy))))), "InvalidPoint");
    Check("no q and no d", DescribeOutcome(ECDsa.Create(new ECParameters(p256,
        new ECPoint(Empty(), Empty())))), "InvalidPoint");

    var publicAgreement = try ECDiffieHellman.Create(new ECParameters(p256,
        new ECPoint(Hex(gx), Hex(gy))));
    Check("public key agrees", DescribeOutcome(publicAgreement.DeriveRawSecretAgreement(
        agreement.PublicKey)), "InvalidKey");
    return Ok(true);
}

Result<bool, CryptoError> CheckScalarRefusals()
{
    var p256 = ECCurve.NamedCurves.NistP256;
    String gx = "6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296";
    String gy = "4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5";
    String prime = "ffffffff00000001000000000000000000000000ffffffffffffffffffffffff";
    String order = "ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551";

    Check("d of zero", DescribeOutcome(ECDsa.Create(CreatePrivateParameters(p256,
        "0000000000000000000000000000000000000000000000000000000000000000"))), "InvalidKey");
    Check("d of n", DescribeOutcome(ECDsa.Create(CreatePrivateParameters(p256, order))),
          "InvalidKey");
    Check("d above n", DescribeOutcome(ECDsa.Create(CreatePrivateParameters(p256, prime))),
          "InvalidKey");
    Check("d too short", DescribeOutcome(ECDsa.Create(new ECParameters(p256,
        new ECPoint(Empty(), Empty()), Copy(Hex(gx)[1u:])))), "InvalidKey");

    // n - 1 is the largest scalar, and its point is -G.
    var last = try ECDsa.Create(CreatePrivateParameters(p256,
        "ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632550"));
    Check("d of n - 1 is -G", ToHex((try last.ExportParameters(false)).Q.X), gx);

    Check("q that d does not give", DescribeOutcome(ECDsa.Create(new ECParameters(p256,
        new ECPoint(Hex(gx), Hex(gy)),
        Hex("C9AFA9D845BA75166B5C215767B1D6934E50C3DB36E89B127B8A622B120F6721")))),
        "InvalidKey");

    var secp256k1 = ECCurve.CreateFromValue("1.3.132.0.10");
    Check("secp256k1", DescribeOutcome(ECDsa.Create(secp256k1)), "Unsupported");
    Check("unknown friendly name", DescribeOutcome(ECDiffieHellman.Create(
        ECCurve.CreateFromFriendlyName("nistP521"))), "Unsupported");
    Check("friendly names", ECCurve.CreateFromFriendlyName("secp384r1").OidValue + " " +
          ECCurve.NamedCurves.NistP256.FriendlyName, "1.3.132.0.34 nistP256");
    return Ok(true);
}

Result<bool, CryptoError> CheckFormatRefusals()
{
    var p256 = ECCurve.NamedCurves.NistP256;
    String gx = "6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296";
    String gy = "4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5";

    // Structures that are well-formed and not an EC key on a known curve.
    var writer = new AsnWriter();
    writer.PushSequence();
    writer.PushSequence();
    writer.WriteObjectIdentifier("1.2.840.113549.1.1.1");
    writer.WriteNull();
    writer.PopSequence();
    writer.WriteBitString(CreateUncompressedPoint(gx, gy));
    writer.PopSequence();
    var verifier = try ECDsa.Create(p256);
    byte[] before = verifier.ExportSubjectPublicKeyInfo();
    Check("rsa spki", DescribeOutcome(verifier.ImportSubjectPublicKeyInfo(writer.Encode())),
          "Encoding");
    Check("failed import keeps the key", ToHex(verifier.ExportSubjectPublicKeyInfo()),
          ToHex(before));

    writer = new AsnWriter();
    writer.PushSequence();
    writer.PushSequence();
    writer.WriteObjectIdentifier("1.2.840.10045.2.1");
    writer.WriteObjectIdentifier("1.3.132.0.10");
    writer.PopSequence();
    writer.WriteBitString(CreateUncompressedPoint(gx, gy));
    writer.PopSequence();
    Check("secp256k1 spki", DescribeOutcome(verifier.ImportSubjectPublicKeyInfo(
        writer.Encode())), "Unsupported");
    Check("empty der", DescribeOutcome(verifier.ImportSubjectPublicKeyInfo(Empty())), "Encoding");
    Check("no pem", DescribeOutcome(verifier.ImportFromPem("no key here")), "Encoding");
    Check("encrypted pem", DescribeOutcome(verifier.ImportFromPem(
        "-----BEGIN ENCRYPTED PRIVATE KEY-----\nAAAA\n-----END ENCRYPTED PRIVATE KEY-----")),
        "Unsupported");

    // A private key whose public point is someone else's.
    var signer = try ECDsa.Create(p256);
    byte[] sec1 = try signer.ExportECPrivateKey();
    var stranger = try ECDsa.Create(p256);
    byte[] foreign = try stranger.ExportECPrivateKey();
    for (nuint i = 0u; i < 65u; i++)
        sec1[sec1.Length - 65u + i] = foreign[foreign.Length - 65u + i];
    Check("sec1 with another point", DescribeOutcome(verifier.ImportECPrivateKey(sec1)),
          "InvalidKey");
    return Ok(true);
}

Result<bool, CryptoError> CheckSignatureRefusals()
{
    var p256 = ECCurve.NamedCurves.NistP256;
    var sha256 = HashAlgorithmName.Sha256;
    String order = "ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551";

    var signer = try ECDsa.Create(p256);
    byte[] message = Bytes("message");
    byte[] signature = try signer.SignData(message, sha256);
    CheckTrue("signature verifies", signer.VerifyData(message, signature, sha256));
    byte[] tampered = Copy(signature);
    tampered[40u] ^= 0x10;
    CheckTrue("tampered signature", !signer.VerifyData(message, tampered, sha256));
    CheckTrue("tampered message", !signer.VerifyData(Bytes("massage"), signature, sha256));
    CheckTrue("another hash", !signer.VerifyData(message, signature, HashAlgorithmName.Sha384));
    var stranger = try ECDsa.Create(p256);
    CheckTrue("another key", !stranger.VerifyData(message, signature, sha256));
    CheckTrue("r and s of zero", !signer.VerifyData(message, new byte[64u], sha256));
    CheckTrue("r of n", !signer.VerifyData(message, Join(Hex(order), signature[32u:]), sha256));
    CheckTrue("s of n", !signer.VerifyData(message, Join(signature[:32u], Hex(order)), sha256));
    CheckTrue("short signature", !signer.VerifyData(message, signature[:63u], sha256));

    // What a public key cannot do.
    var publicOnly = try ECDsa.Create(p256);
    try publicOnly.ImportSubjectPublicKeyInfo(signer.ExportSubjectPublicKeyInfo());
    CheckTrue("public key verifies", publicOnly.VerifyData(message, signature, sha256));
    Check("public key signs", DescribeOutcome(publicOnly.SignData(message, sha256)),
          "InvalidKey");
    Check("public key exports d", DescribeOutcome(publicOnly.ExportParameters(true)),
          "InvalidKey");
    Check("public key exports sec1", DescribeOutcome(publicOnly.ExportECPrivateKey()),
          "InvalidKey");

    HashAlgorithmName none;
    Check("no hash signs", DescribeOutcome(signer.SignData(message, none)), "Unsupported");
    CheckTrue("no hash verifies", !signer.VerifyData(message, signature, none));
    return Ok(true);
}

// ----------------------------------------------------------- generated keys

Result<bool, CryptoError> CheckGeneratedKeys(ECCurve curve, String keySize)
{
    String label = curve.FriendlyName;
    var alice = try ECDiffieHellman.Create(curve);
    var bob = try ECDiffieHellman.Create(curve);
    CheckTrue(label + " keys differ", ToHex(alice.PublicKey) != ToHex(bob.PublicKey));
    byte[] shared = try alice.DeriveRawSecretAgreement(bob.PublicKey);
    Check(label + " parties agree", ToHex(shared),
          ToHex(try bob.DeriveRawSecretAgreement(alice.PublicKey)));
    Check(label + " hashed agreement",
          ToHex(try alice.DeriveKeyFromHash(bob.PublicKey, HashAlgorithmName.Sha256)),
          ToHex(Sha256.HashData(shared)));
    Check(label + " hmac agreement",
          ToHex(try alice.DeriveKeyFromHmac(bob.PublicKey, HashAlgorithmName.Sha256,
                                            Bytes("key"))),
          ToHex(HmacSha256.HashData(Bytes("key"), shared)));
    Check(label + " key size", $"{alice.KeySize}", keySize);

    var signer = try ECDsa.Create(curve);
    byte[] message = Bytes("generated");
    byte[] signature = try signer.SignData(message, HashAlgorithmName.Sha512);
    CheckTrue(label + " generated signature",
              signer.VerifyData(message, signature, HashAlgorithmName.Sha512));
    Check(label + " deterministic", ToHex(signature),
          ToHex(try signer.SignData(message, HashAlgorithmName.Sha512)));
    return Ok(true);
}

int Main()
{
    RunChecks("rfc 6979 p256", CheckRfc6979P256());
    RunChecks("rfc 6979 p384", CheckRfc6979P384());
    RunChecks("nist cdh", CheckNistAgreements());
    RunChecks("wycheproof", CheckSignatureVectors("wycheproof ecdsa p256",
        CreateP256SignatureVectors(), ECCurve.NamedCurves.NistP256, HashAlgorithmName.Sha256));
    RunChecks("wycheproof", CheckSignatureVectors("wycheproof ecdsa p384",
        CreateP384SignatureVectors(), ECCurve.NamedCurves.NistP384, HashAlgorithmName.Sha384));
    RunChecks("wycheproof", CheckAgreementVectors("wycheproof ecdh p256",
        CreateP256AgreementVectors(), ECCurve.NamedCurves.NistP256));
    RunChecks("wycheproof", CheckAgreementVectors("wycheproof ecdh p384",
        CreateP384AgreementVectors(), ECCurve.NamedCurves.NistP384));
    RunChecks("signature formats", CheckSignatureFormats());
    RunChecks("openssl keys", CheckOpenSslKeys());
    if (!CheckCertificate().Ok)
        Console.WriteLine("certificate stopped");
    RunChecks("point refusals", CheckPointRefusals());
    RunChecks("scalar refusals", CheckScalarRefusals());
    RunChecks("format refusals", CheckFormatRefusals());
    RunChecks("signature refusals", CheckSignatureRefusals());
    RunChecks("generated p256", CheckGeneratedKeys(ECCurve.NamedCurves.NistP256, "256"));
    RunChecks("generated p384", CheckGeneratedKeys(ECCurve.NamedCurves.NistP384, "384"));
    return 0;
}
