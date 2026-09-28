// SPDX-License-Identifier: 0BSD
module RsaCase;

import Standard.Console;
import Standard.Convert;
import Standard.Encoding;
import Standard.Security.Cryptography;

// key.pem was made by OpenSSL 3.5.5 with `openssl genpkey -algorithm RSA
// -pkeyopt rsa_keygen_bits:2048`, and the other three from it with `openssl
// rsa` (-traditional, -pubout, -RSAPublicKey_out). What this program exports
// MUST match those files byte for byte.
//
// The OpenSSL vectors are from the same key: PKCS #1 v1.5 signatures of "abc"
// by `openssl dgst -sign`, which are deterministic and so pin the private
// operation exactly; ciphertexts by `openssl pkeyutl -encrypt`; and three
// random ciphertexts with what `openssl pkeyutl -decrypt` answers for them
// under PKCS #1 v1.5, which is implicit rejection's synthetic message.

[Embed("key.pem")]
static readonly byte[] KeyPem;

[Embed("key-rsa.pem")]
static readonly byte[] KeyRsaPem;

[Embed("public.pem")]
static readonly byte[] PublicPem;

[Embed("public-rsa.pem")]
static readonly byte[] PublicRsaPem;

byte[] Hex(String text) => Convert.FromHexString(text).GetValueOrDefault(new byte[0u]);

byte[] Bytes(String text) => Encoding.CreateUtf8().GetBytes(text);

String ToHex(byte[] bytes) => Convert.ToHexString(bytes);

byte[] CopyBytes(byte[] bytes) => bytes[:].ToArray();

RsaParameters CopyParameters(RsaParameters from) => new RsaParameters
{
    Modulus = CopyBytes(from.Modulus),
    Exponent = CopyBytes(from.Exponent),
    D = CopyBytes(from.D),
    P = CopyBytes(from.P),
    Q = CopyBytes(from.Q),
    DP = CopyBytes(from.DP),
    DQ = CopyBytes(from.DQ),
    InverseQ = CopyBytes(from.InverseQ),
};

String CreateTextFromBytes(byte[] bytes)
{
    var built = new StringBuilder();
    built.AppendBytes(bytes);
    return built.ToText();
}

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

String DescribeError(CryptoError error)
{
    switch (error)
    {
        case CryptoError.Parameter: return "Parameter";
        case CryptoError.Padding: return "Padding";
        case CryptoError.KeyLength: return "KeyLength";
        case CryptoError.InvalidKey: return "InvalidKey";
        case CryptoError.Encoding: return "Encoding";
        case CryptoError.MessageLength: return "MessageLength";
        case CryptoError.Unsupported: return "Unsupported";
    }
    return "another error";
}

String DescribeKey(Result<Rsa, CryptoError> key)
{
    if (!key.Ok)
        return DescribeError(key.Error);
    return key.Value.HasPrivateKey ? "private" : "public";
}

String DescribeBytes(Result<byte[], CryptoError> bytes)
{
    if (!bytes.Ok)
        return DescribeError(bytes.Error);
    return ToHex(bytes.Value);
}

String DescribeText(Result<String, CryptoError> text)
{
    if (!text.Ok)
        return DescribeError(text.Error);
    return text.Value;
}

/// `message` signed by `signer` and checked by `verifier`.
bool SignAndVerify(Rsa signer, Rsa verifier, byte[] message, HashAlgorithmName hash,
                   RsaSignaturePadding padding)
{
    var signature = signer.SignData(message, hash, padding);
    if (!signature.Ok)
        return false;
    return verifier.VerifyData(message, signature.Value, hash, padding);
}

/// `message` encrypted to `publicKey` and decrypted by `key`, as hex.
String EncryptAndDecrypt(Rsa key, Rsa publicKey, byte[] message, RsaEncryptionPadding padding)
{
    var encrypted = publicKey.Encrypt(message, padding);
    if (!encrypted.Ok)
        return DescribeError(encrypted.Error);
    return DescribeBytes(key.Decrypt(encrypted.Value, padding));
}

bool Verifies(Rsa key, byte[] message, byte[] signature, HashAlgorithmName hash,
              RsaSignaturePadding padding) =>
    key.VerifyData(message, signature, hash, padding);

String VerifyWith(Result<Rsa, CryptoError> key, RsaSignaturePadding padding, String message,
                  String signature)
{
    if (!key.Ok)
        return "no key";
    bool valid = key.Value.VerifyData(Hex(message), Hex(signature), HashAlgorithmName.Sha256,
                                      padding);
    return valid ? "valid" : "invalid";
}

String DecryptOaepWith(Result<Rsa, CryptoError> key, String label, String ciphertext)
{
    if (!key.Ok)
        return "no key";
    var padding = RsaEncryptionPadding.CreateOaep(HashAlgorithmName.Sha256, Hex(label));
    var plain = key.Value.Decrypt(Hex(ciphertext), padding);
    return plain.Ok ? ToHex(plain.Value) : "refused";
}

/// Every check that needs no key generation, which is all the 32-bit case
/// runs.
void CheckRsaVectors()
{
    var loaded = Rsa.ImportFromPem(CreateTextFromBytes(KeyPem));
    if (!loaded.Ok)
    {
        Console.WriteLine("key.pem refused: " + DescribeError(loaded.Error));
        return;
    }
    Rsa key = loaded.Value;

    CheckKeyFormats(key);
    CheckOpenSslVectors(key);
    CheckWycheproofPkcs1Signatures();
    CheckWycheproofPss();
    CheckWycheproofOaep();
    CheckRoundTrips(key);
    CheckRefusals(key);
}

void CheckKeyFormats(Rsa key)
{
    String pkcs8 = CreateTextFromBytes(KeyPem);
    String pkcs1 = CreateTextFromBytes(KeyRsaPem);
    String spki = CreateTextFromBytes(PublicPem);
    String pkcs1Public = CreateTextFromBytes(PublicRsaPem);

    Check("key size", $"{key.KeySize}", "2048");
    CheckTrue("key is private", key.HasPrivateKey);

    // OpenSSL ends each file with a newline, which PEM does not count.
    Check("export pkcs8 pem", DescribeText(key.ExportPkcs8PrivateKeyPem()) + "\n", pkcs8);
    Check("export pkcs1 pem", DescribeText(key.ExportRsaPrivateKeyPem()) + "\n", pkcs1);
    Check("export spki pem", key.ExportSubjectPublicKeyInfoPem() + "\n", spki);
    Check("export pkcs1 public pem", key.ExportRsaPublicKeyPem() + "\n", pkcs1Public);

    // Each file read in and written out as another of the four.
    Rsa fromPkcs1 = Rsa.ImportFromPem(pkcs1).GetValueOrDefault(key);
    CheckTrue("import pkcs1 pem", fromPkcs1 != key && fromPkcs1.HasPrivateKey);
    Check("pkcs1 as pkcs8", DescribeText(fromPkcs1.ExportPkcs8PrivateKeyPem()) + "\n", pkcs8);

    Rsa fromSpki = Rsa.ImportFromPem(spki).GetValueOrDefault(key);
    CheckTrue("import spki pem", !fromSpki.HasPrivateKey);
    Check("spki as pkcs1", fromSpki.ExportRsaPublicKeyPem() + "\n", pkcs1Public);

    Rsa fromPkcs1Public = Rsa.ImportFromPem(pkcs1Public).GetValueOrDefault(key);
    CheckTrue("import pkcs1 public pem", !fromPkcs1Public.HasPrivateKey);
    Check("pkcs1 public as spki", fromPkcs1Public.ExportSubjectPublicKeyInfoPem() + "\n", spki);

    // Every DER form, through its importer and back.
    byte[] pkcs8Der = key.ExportPkcs8PrivateKey().GetValueOrDefault(new byte[0u]);
    byte[] pkcs1Der = key.ExportRsaPrivateKey().GetValueOrDefault(new byte[0u]);
    byte[] spkiDer = key.ExportSubjectPublicKeyInfo();
    byte[] publicDer = key.ExportRsaPublicKey();
    Rsa again = Rsa.ImportPkcs8PrivateKey(pkcs8Der).GetValueOrDefault(fromSpki);
    Check("der pkcs8", DescribeBytes(again.ExportPkcs8PrivateKey()), ToHex(pkcs8Der));
    again = Rsa.ImportRsaPrivateKey(pkcs1Der).GetValueOrDefault(fromSpki);
    Check("der pkcs1", DescribeBytes(again.ExportRsaPrivateKey()), ToHex(pkcs1Der));
    again = Rsa.ImportSubjectPublicKeyInfo(spkiDer).GetValueOrDefault(fromPkcs1);
    CheckTrue("der spki", again != fromPkcs1 && ToHex(again.ExportSubjectPublicKeyInfo()) ==
                                                ToHex(spkiDer));
    again = Rsa.ImportRsaPublicKey(publicDer).GetValueOrDefault(fromPkcs1);
    CheckTrue("der pkcs1 public", again != fromPkcs1 && ToHex(again.ExportRsaPublicKey()) ==
                                                        ToHex(publicDer));

    // Parameters are padded as .NET pads them, and make the same key again.
    var exported = key.ExportParameters(true);
    if (!exported.Ok)
    {
        Check("export parameters", DescribeError(exported.Error), "ok");
        return;
    }
    RsaParameters parameters = exported.Value;
    Check("parameter lengths",
          $"{parameters.Modulus.Length} {parameters.Exponent.Length} {parameters.D.Length} " +
          $"{parameters.P.Length} {parameters.Q.Length} {parameters.DP.Length} " +
          $"{parameters.DQ.Length} {parameters.InverseQ.Length}",
          "256 3 256 128 128 128 128 128");
    Rsa rebuilt = Rsa.Create(parameters).GetValueOrDefault(fromSpki);
    Check("parameters again", DescribeBytes(rebuilt.ExportRsaPrivateKey()), ToHex(pkcs1Der));

    var publicOnly = key.ExportParameters(false);
    if (publicOnly.Ok)
    {
        Check("public parameters", $"{publicOnly.Value.D.Length}", "0");
        Check("public parameters key", DescribeKey(Rsa.Create(publicOnly.Value)), "public");
    }
}

void CheckOpenSslVectors(Rsa key)
{
    byte[] abc = Bytes("abc");
    Check("openssl pkcs1 sha1",
          DescribeBytes(key.SignData(abc, HashAlgorithmName.Sha1, RsaSignaturePadding.Pkcs1)),
          SignatureSha1);
    Check("openssl pkcs1 sha256",
          DescribeBytes(key.SignData(abc, HashAlgorithmName.Sha256, RsaSignaturePadding.Pkcs1)),
          SignatureSha256);
    Check("openssl pkcs1 sha384",
          DescribeBytes(key.SignData(abc, HashAlgorithmName.Sha384, RsaSignaturePadding.Pkcs1)),
          SignatureSha384);
    Check("openssl pkcs1 sha512",
          DescribeBytes(key.SignData(abc, HashAlgorithmName.Sha512, RsaSignaturePadding.Pkcs1)),
          SignatureSha512);

    Check("openssl pkcs1 decrypt",
          DescribeBytes(key.Decrypt(Hex(CiphertextPkcs1), RsaEncryptionPadding.Pkcs1)),
          ToHex(Bytes("hello, implicit rejection")));

    var labelled = RsaEncryptionPadding.CreateOaep(HashAlgorithmName.Sha256, Bytes("label"));
    Check("openssl oaep label", DescribeBytes(key.Decrypt(Hex(CiphertextOaepLabelled), labelled)),
          ToHex(Bytes("OAEP label test")));

    // Bad padding decrypts to OpenSSL's synthetic message, not a failure.
    Check("implicit rejection 1",
          DescribeBytes(key.Decrypt(Hex(RejectedCiphertext1), RsaEncryptionPadding.Pkcs1)),
          SyntheticMessage1);
    Check("implicit rejection 2",
          DescribeBytes(key.Decrypt(Hex(RejectedCiphertext2), RsaEncryptionPadding.Pkcs1)),
          SyntheticMessage2);
    Check("implicit rejection 3",
          DescribeBytes(key.Decrypt(Hex(RejectedCiphertext3), RsaEncryptionPadding.Pkcs1)),
          SyntheticMessage3);
}

void CheckRoundTrips(Rsa key)
{
    var publicKey = Rsa.ImportSubjectPublicKeyInfo(key.ExportSubjectPublicKeyInfo())
                       .GetValueOrDefault(key);
    byte[] message = Bytes("The quick brown fox jumps over the lazy dog");
    HashAlgorithmName[] hashes = [HashAlgorithmName.Sha1, HashAlgorithmName.Sha256,
                                  HashAlgorithmName.Sha384, HashAlgorithmName.Sha512];

    foreach (HashAlgorithmName hash in hashes)
    {
        CheckTrue($"pss {hash.Name}",
                  SignAndVerify(key, publicKey, message, hash, RsaSignaturePadding.Pss));
        CheckTrue($"pkcs1 {hash.Name}",
                  SignAndVerify(key, publicKey, message, hash, RsaSignaturePadding.Pkcs1));
        Check($"oaep {hash.Name}",
              EncryptAndDecrypt(key, publicKey, message, RsaEncryptionPadding.CreateOaep(hash)),
              ToHex(message));
    }

    // PSS signatures are randomized; two of one message differ.
    HashAlgorithmName sha256 = HashAlgorithmName.Sha256;
    String first = DescribeBytes(key.SignData(message, sha256, RsaSignaturePadding.Pss));
    String second = DescribeBytes(key.SignData(message, sha256, RsaSignaturePadding.Pss));
    CheckTrue("pss randomized", first != second);

    var noSalt = RsaSignaturePadding.CreatePss(0).GetValueOrDefault(RsaSignaturePadding.Pss);
    var longest = RsaSignaturePadding.CreatePss(RsaSignaturePadding.PssSaltLengthMax)
                                     .GetValueOrDefault(RsaSignaturePadding.Pss);
    CheckTrue("pss no salt", SignAndVerify(key, publicKey, message, sha256, noSalt));
    CheckTrue("pss no salt is deterministic",
              DescribeBytes(key.SignData(message, sha256, noSalt)) ==
              DescribeBytes(key.SignData(message, sha256, noSalt)));
    CheckTrue("pss longest salt", SignAndVerify(key, publicKey, message, sha256, longest));
    CheckTrue("pss any salt", Verifies(publicKey, message, Hex(first), sha256, longest));

    byte[] digest = Sha256.HashData(message);
    RsaSignaturePadding pkcs1 = RsaSignaturePadding.Pkcs1;
    byte[] hashSigned = key.SignHash(digest, sha256, pkcs1).GetValueOrDefault(new byte[0u]);
    CheckTrue("sign hash", Verifies(publicKey, message, hashSigned, sha256, pkcs1) &&
                           publicKey.VerifyHash(digest, hashSigned, sha256, pkcs1));

    var label = RsaEncryptionPadding.CreateOaep(sha256, Bytes("context"));
    Check("oaep with label", EncryptAndDecrypt(key, publicKey, message, label), ToHex(message));
    Check("pkcs1 encryption",
          EncryptAndDecrypt(key, publicKey, message, RsaEncryptionPadding.Pkcs1), ToHex(message));

    // The longest message each padding carries, and the empty one.
    byte[] longestPkcs1 = new byte[245u];
    longestPkcs1[0u] = 0x42;
    Check("pkcs1 longest",
          EncryptAndDecrypt(key, publicKey, longestPkcs1, RsaEncryptionPadding.Pkcs1),
          ToHex(longestPkcs1));
    byte[] longestOaep = new byte[190u];
    longestOaep[189u] = 0x42;
    Check("oaep longest",
          EncryptAndDecrypt(key, publicKey, longestOaep, RsaEncryptionPadding.OaepSha256),
          ToHex(longestOaep));
    Check("oaep empty",
          EncryptAndDecrypt(key, publicKey, new byte[0u], RsaEncryptionPadding.OaepSha1), "");
}

void CheckRefusals(Rsa key)
{
    var publicKey = Rsa.ImportSubjectPublicKeyInfo(key.ExportSubjectPublicKeyInfo())
                       .GetValueOrDefault(key);
    byte[] message = Bytes("attack at dawn");
    byte[] signature = key.SignData(message, HashAlgorithmName.Sha256, RsaSignaturePadding.Pss)
                          .GetValueOrDefault(new byte[0u]);

    HashAlgorithmName sha256 = HashAlgorithmName.Sha256;
    RsaSignaturePadding pss = RsaSignaturePadding.Pss;
    CheckTrue("genuine", Verifies(publicKey, message, signature, sha256, pss));
    byte[] tampered = CopyBytes(signature);
    tampered[100u] ^= 0x04;
    CheckTrue("tampered signature", !Verifies(publicKey, message, tampered, sha256, pss));
    CheckTrue("other message",
              !Verifies(publicKey, Bytes("attack at dusk"), signature, sha256, pss));
    CheckTrue("wrong hash",
              !Verifies(publicKey, message, signature, HashAlgorithmName.Sha384, pss));
    CheckTrue("wrong padding",
              !Verifies(publicKey, message, signature, sha256, RsaSignaturePadding.Pkcs1));
    CheckTrue("short signature",
              !Verifies(publicKey, message, signature[1u:].ToArray(), sha256, pss));
    var md5 = new HashAlgorithmName("MD5");
    CheckTrue("unknown hash", !Verifies(publicKey, message, signature, md5, pss));
    Check("sign unknown hash", DescribeBytes(key.SignData(message, md5, pss)), "Unsupported");
    Check("sign short hash", DescribeBytes(key.SignHash(new byte[31u], sha256, pss)), "Parameter");
    CheckTrue("pss salt length", !RsaSignaturePadding.CreatePss(-3).Ok);

    // A public key signs, decrypts and exports nothing private.
    Check("public sign", DescribeBytes(publicKey.SignData(message, sha256, pss)), "InvalidKey");
    Check("public decrypt",
          DescribeBytes(publicKey.Decrypt(signature, RsaEncryptionPadding.Pkcs1)), "InvalidKey");
    Check("public export", DescribeBytes(publicKey.ExportPkcs8PrivateKey()), "InvalidKey");
    CheckTrue("public parameters", !publicKey.ExportParameters(true).Ok);

    RsaEncryptionPadding oaep = RsaEncryptionPadding.OaepSha256;
    byte[] encrypted = publicKey.Encrypt(message, oaep).GetValueOrDefault(new byte[0u]);
    Check("truncated ciphertext",
          DescribeBytes(key.Decrypt(encrypted[1u:], oaep)), "MessageLength");
    byte[] tooLarge = new byte[256u];
    for (nuint i = 0u; i < tooLarge.Length; i++)
        tooLarge[i] = 0xFF;
    Check("ciphertext above modulus", DescribeBytes(key.Decrypt(tooLarge, oaep)), "MessageLength");
    var otherLabel = RsaEncryptionPadding.CreateOaep(sha256, Bytes("other"));
    Check("oaep label mismatch", DescribeBytes(key.Decrypt(encrypted, otherLabel)), "Padding");
    Check("oaep hash mismatch",
          DescribeBytes(key.Decrypt(encrypted, RsaEncryptionPadding.OaepSha1)), "Padding");
    Check("pkcs1 too long",
          DescribeBytes(publicKey.Encrypt(new byte[246u], RsaEncryptionPadding.Pkcs1)),
          "MessageLength");
    Check("oaep too long", DescribeBytes(publicKey.Encrypt(new byte[191u], oaep)), "MessageLength");

    // Encodings that do not parse, or parse as something else.
    byte[] der = key.ExportPkcs8PrivateKey().GetValueOrDefault(new byte[0u]);
    Check("truncated der",
          DescribeKey(Rsa.ImportPkcs8PrivateKey(der[:der.Length - 1u])), "Encoding");
    Check("der with trailing byte",
          DescribeKey(Rsa.ImportPkcs8PrivateKey([..der, 0x00])), "Encoding");
    Check("garbage der", DescribeKey(Rsa.ImportRsaPublicKey(Bytes("not a key"))), "Encoding");
    Check("private as public", DescribeKey(Rsa.ImportSubjectPublicKeyInfo(der)), "Encoding");
    byte[] multiPrime = key.ExportRsaPrivateKey().GetValueOrDefault(new byte[7u]);
    multiPrime[6u] = 0x01;
    Check("multi-prime version", DescribeKey(Rsa.ImportRsaPrivateKey(multiPrime)), "Unsupported");
    Check("pem without key", DescribeKey(Rsa.ImportFromPem("no key here")), "Encoding");
    String spki = key.ExportSubjectPublicKeyInfoPem();
    Check("pem with two keys", DescribeKey(Rsa.ImportFromPem(spki + "\n" + spki)), "Encoding");
    String encryptedPem = PemEncoding.Write("ENCRYPTED PRIVATE KEY", der);
    Check("pem encrypted", DescribeKey(Rsa.ImportFromPem(encryptedPem)), "Unsupported");

    // Numbers that are not a key, or not the same key.
    var exported = key.ExportParameters(true);
    if (!exported.Ok)
        return;
    RsaParameters good = exported.Value;
    RsaParameters changed = CopyParameters(good);
    changed.DP[127u] ^= 0x01;
    Check("inconsistent dp", DescribeKey(Rsa.Create(changed)), "InvalidKey");
    changed = CopyParameters(good);
    changed.P = good.Q;
    changed.Q = good.P;
    Check("swapped primes", DescribeKey(Rsa.Create(changed)), "InvalidKey");
    changed = CopyParameters(good);
    changed.D[255u] ^= 0x02;
    Check("inconsistent d", DescribeKey(Rsa.Create(changed)), "InvalidKey");
    changed = CopyParameters(good);
    changed.InverseQ = new byte[0u];
    Check("missing inverse", DescribeKey(Rsa.Create(changed)), "InvalidKey");

    var numbers = new RsaParameters { Modulus = CopyBytes(good.Modulus), Exponent = good.Exponent };
    numbers.Modulus[255u] ^= 0x01;
    Check("even modulus", DescribeKey(Rsa.Create(numbers)), "InvalidKey");
    numbers.Modulus = good.Modulus[:64u].ToArray();
    Check("small modulus", DescribeKey(Rsa.Create(numbers)), "InvalidKey");
    numbers.Modulus = good.Modulus;
    numbers.Exponent = [0x01];
    Check("exponent of one", DescribeKey(Rsa.Create(numbers)), "InvalidKey");
    numbers.Exponent = [0x01, 0x00];
    Check("even exponent", DescribeKey(Rsa.Create(numbers)), "InvalidKey");
}

// ------------------------------------------------------------ the OpenSSL vectors

static readonly String SignatureSha1 =
    "0cb8d78c07b33412a6870245242a0e7fcfd378dece53d48b34bd07642d90e4bb" +
    "ad4d7279a918eb26a50f9ee2c62c11327642963938f21e19f59191d688aa6513" +
    "8791496dac2a06b4ca9641dc2942e03ae8119709ae0a9c10f06613cd6374bb30" +
    "d444b8de4e31a40f10406ecf7c20232ac03d59427e4770f47d856096352e8c75" +
    "e617eb6205186dae1be4cf4dc85e9e2b0d5243c6b3400c31518d2582c1789f11" +
    "8b7ff1635cb16714f6a265b78bbe5a4bcf74cf56dd4ca204cec392a58f70212f" +
    "05dfc23a641989d5c3c301dbe0fbc8d027834031e77fc9a204f9189b409ea407" +
    "1c54a5ecbe862cf7d126a8e1b24661279739a1b5c8e81e3fc12d3b64abd7dc85";

static readonly String SignatureSha256 =
    "548cdd51a1c48c3b37af427118ddcaa99065f2269e33369e6305a75fa1b5570b" +
    "1bf8d6e61218bb2ac7916204064aa764ac422c6e61185b997a08de109f811532" +
    "83cc8323cf5822b6e725012648103f1ec5519b129bfe4524708baa3b7c4625d6" +
    "f92f0fc6994154ba6a1186081d6766676f6cd8c789ba686be850840e642a89a2" +
    "395a22bd2e1c67e425ea88509f2c74dbe020199fb1ecbabe3c8f6befafda4a6e" +
    "db6247ddee81a4112b877e2abc4773943e68abf1192c9d63c4210cacedad914e" +
    "53594f95efce2f41150b37931cc1a3d3df9b7cbb55c24499b09c162eed8ca1db" +
    "483b900f92d6db7b4fe2d1ccb7bd95e95f1e6ce7bd7ba574785ee27baf7d4e14";

static readonly String SignatureSha384 =
    "42590e47c4f7881cc237bfd216408ea0e24e95a8af956e48de3166af9f05c64e" +
    "6eaee22fb3b34a98c53a03248e5665aad3d44fe7defdd2c96f3aa5d8292cad33" +
    "b35c03c0dedfca5baadfcf622b5f241405582237f4b04796ef0e27eac2b4204a" +
    "22ef11007b2bf2fa44b00d90a0fc1d0e4b74a246665a2957ee39349e4cfef225" +
    "1489ba3c2e8e306d81aa411480c1bb0cc5acdb209c428e385407c34e0e048009" +
    "7964a80aab2c8d6c21e9187ef1d18d13e3aa8cd8cca6a49b684136456ea876dc" +
    "7d450365bc135659d312cdc5954fbe55fd71b9ab966c9fa2a2a088afa402df1e" +
    "4bf9c205cb5facab44325430ce96eeb31ccf19ec6b9fb64219e78443dfd295a0";

static readonly String SignatureSha512 =
    "1d6099e964d02460a800cba89de8a8bdd2ac2ed21d8d3ad63ed2d920da5cdb9f" +
    "8c20c3be5eb9ed29fe6352ecc76f43da5945ace51255e36aaa2bb4ce7d72b2b2" +
    "c76407b010c2a194070c0c20a03006273c10860aec3863ea2f9a62868d3a501e" +
    "b6ee04a7521bab9449b2239c3ed989cf1298b5f948fadd09ea1856a819f86497" +
    "ec3fcbd14615bdf03b03adb1df68a33ef40f2a93f55138d675ebec7754fa460d" +
    "d65158d9452202bad0faeb155e70530265d87db85b56e051584ab7d09932b865" +
    "fc516341179789f23be0cf8455cb1a9897e3a1b7591801c64855819f323bb344" +
    "796262cc396c1651f5cd3de0bd06152cb820b1c7ffb07e0b11042bc7bee39481";

static readonly String CiphertextPkcs1 =
    "5024c191be04ba260fbe73a1eb6570b8d9cb85c25b05c166efa8a554c762e56f" +
    "8463c41797403d68f8c1c38d07b8014e5f8356795b2d5f3504c41fad1de83383" +
    "7f5b11bb89f55b3bb53a46e8a2800dcc5af37981fb05a4025c0c24e8283a9146" +
    "7001442b7bb9cde2f7733aa344d29deb09497ec38ec46dd7afe4ef3650311c92" +
    "08ccdb4e52e90fc8253c196f078f39071e95ab0002527b0f444611e41a8dd410" +
    "3b1196e846db849b74e37cb1c722f7ce2035770f89eadda78dcca3611e09bfd2" +
    "cb44cb12d2c0ed1f04287effc48d09a07881fc0e92e2ba34c9cbcad68dbb7aa1" +
    "a35f068caabb4d4a0c148e86a4d52af3fc377124e7433a6f3f0f8f10b5388f34";

static readonly String CiphertextOaepLabelled =
    "1c6ef6ed8ff56737f64e134828e47e365390c219999e0ac4a2449091905cfb8e" +
    "876e5c3e6b8b4496b4c279bbedf3e4b5e155e1523f3d6d2fac35e0181c4eb5b8" +
    "1734e5dedbca83be3b6072a1289d1185973f0fad41224d7b0de2a1624c0f7b9f" +
    "37a382550c7555088f70b34b82000729aa572ad605959b87606913a27d420981" +
    "76b1e277ba06b9777ac9225a7a73c86c186f077a314d52884345d6f947d71ca4" +
    "967a65522971ba3dd9b331341f87e92dc67aa3c23d524a178273d4d6be411424" +
    "43760a52aaae248b995ad96ffda93e07ff14f133bb59eb6be385cdbf029539d0" +
    "d0d40753478f860bc77e53c4b9537d78d37f4621c0611ea21d4d922c78ec86b7";

static readonly String RejectedCiphertext1 =
    "04043f1aa2d7a162b5e8adfa110c12684e0886012cff92e71be49a913c428110" +
    "c0eccf42368244990db90bf355d174ec569f21f390419df849c358703704ffbe" +
    "bd3c8c9f96a5e088809713ba966ca5e60838bac84efe731300fb6223e878eb28" +
    "26768d30e713642bf1590e90e2bba2bc6cd1a0acc96f28be2e89e5461e7b6494" +
    "ecb193d29f8ec5a43b7b0c87716afbfcd068205df167869eeed85ccebf258e18" +
    "0612b6faa745d78ff8cc6169311780f9d56e5d3520708af03059542da7530571" +
    "65aafc5486aaf54bdebbfef37f6b52570af9ae4f788dd4c797708974eb115922" +
    "f787dbab261a24b775bb0059d4b1ea77ef73401785818c8789fd5184fb2cf86d";

static readonly String SyntheticMessage1 =
    "02026888ff6527774d86eda792e9c2f3be506471d05e6a7c54ae722200073b27" +
    "8fdaadd4e11ba6b90332e110f3350e63915ec30fe2f0d98d42c165bd3d40f548" +
    "e80fac9365c22bc2fe26f26fa54dc71d2f5fe05d720e568d6c54e3c4a58b437f" +
    "c95b8aef2a003d2a26995ea6fec593c69d2be51aef9b7ee9f2927bda0a024889" +
    "d2db1c93a5805a74c57da930d4843d4c55ddc66aef5e7dfad9c0faa75cd7bb38" +
    "22524a7cb12de89691a86d9a98e301f2a1696a857f9344d4a09a8c72b6a69f4f" +
    "83de14e27235fdb9b64f8471ec627ce95b878e420bc543b50a03";

static readonly String RejectedCiphertext2 =
    "5762f591e926cded5deb295c286e9779a5293109f62f2fd7a64be3c964a86dd5" +
    "fd69a809e55bb21eb475a01e96e466fc0574419d6bd7821a94b1fe9cece3b697" +
    "af0f18cec2530f3fd9d8178896150c547f0a25a6a1578fa875001cdc59def48c" +
    "07e5e7962cd8a6ac1ad8d3fb1a0cb3c10f1179e8145a415838abf58e985e9752" +
    "de457f29ce00c916a3586532b5b704a073e31c4c2faae4f6d6ffe955f5b99fe3" +
    "07b1394dffaeddac339ada5237114ec49141ebd509f8df6559d0ee1003c77779" +
    "221e8942c3e3fc7af1f5a4a684630269bfc5655fccc31612f3e1b78fb8dfe8c6" +
    "0f391c770e3c3b4f446cde5b928a44f6f6606035a3cc432561cd10a1f5569677";

static readonly String SyntheticMessage2 =
    "c300c7f201413a2401a407e9b853e1780f756e9f7603a8ce186bb6fad58404ea" +
    "857498694f718dc5df45e0676179d3d599f92bd5653c34188ab5197d8cde69ac" +
    "42393c365e9d5a46fed6547c4abaad427c6bd8c879540f5bea02fdcddb265301" +
    "a81a897c821b0120eab701baa51e61ff6bd18a09563a200f4993";

static readonly String RejectedCiphertext3 =
    "36060dd2d7c2522980d8757d74de0ada413ecf0024622562be91859e6de638d5" +
    "d73c25ed25ee7075b7827d86c24983064512d31e72681832ca0271b433acef15" +
    "0937c6216205fe82ee1da6a43c664ead7a2f7b9c163955638b50bc57cdf07096" +
    "a257c66a4206a70bf210b6b42ac7661962353f8bb28731e6ef799334e021e843" +
    "38b9b6c45b35355ba19bf58f428a1732c4bf6d63874448345a0220819a9aed3a" +
    "1c50b9718e4179c9bc407fef84fbad915d2d2102bd6d1f0bb5c55b34ccdc8a4e" +
    "3626be67e442165268583e6bd92b56b90d7a91fed21f72ce94436b1de095d564" +
    "a73755740ec8a68a876509c4bffa70a13789ffacb350ed668b6fc4c68dc9e140";

static readonly String SyntheticMessage3 =
    "a519e3530164d904bd1c75a7029a362c846d2f7753ff7d858a841d3d9a8cca21" +
    "0323eeac53bcec5c7b3fccc84878b041cf4f";
