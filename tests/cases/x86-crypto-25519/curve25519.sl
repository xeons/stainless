// SPDX-License-Identifier: 0BSD
module Curve25519;

import Standard.Console;
import Standard.Convert;
import Standard.Security.Cryptography;

// Every answer here is a published test vector: RFC 7748 §5.2 for the two
// X25519 pairs and the iterated test, RFC 7748 §6.1 for the Diffie-Hellman
// example, and RFC 8032 §7.1 for TEST 1, 2, 3, 1024 and SHA(abc). The
// refused inputs are built from those: the low-order points every X25519
// implementation is expected to catch, and TEST 2's signature altered.

byte[] Hex(String text) => Convert.FromHexString(text).GetValueOrDefault(new byte[0u]);

String HexOf(Result<byte[], CryptoError> result) =>
    result.Ok ? Convert.ToHexString(result.Value) : "failed";

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

void CheckTrue(String label, bool actual) =>
    Console.WriteLine(label + (actual ? " ok" : " WRONG"));

void CheckRefused(String label, bool accepted) =>
    Console.WriteLine(label + (accepted ? " WRONG" : " refused"));

byte[] FlipBit(byte[] data, nuint bit)
{
    byte[] flipped = new byte[data.Length];
    for (nuint i = 0u; i < data.Length; i++)
        flipped[i] = data[i];
    flipped[bit / 8u] = (byte)(flipped[bit / 8u] ^ (1u << (int)(bit % 8u)));
    return flipped;
}

/// Whether `signature` verifies under `publicKey` for any of 64 one-byte
/// messages.
bool AcceptsForgery(byte[] publicKey, byte[] signature)
{
    byte[] message = new byte[1u];
    for (nuint i = 0u; i < 64u; i++)
    {
        message[0u] = (byte)i;
        if (Ed25519.Verify(publicKey, message, signature))
            return true;
    }
    return false;
}

// ------------------------------------------------------------------ X25519

void KeyAgreement()
{
    Check("x25519-1",
          HexOf(X25519.DeriveSharedSecret(
              Hex("a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4"),
              Hex("e6db6867583030db3594c1a424b15f7c726624ec26b3353b10a903a6d0ab1c4c"))),
          "c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552");

    // The second u has its top bit set, which the function MUST ignore.
    Check("x25519-2",
          HexOf(X25519.DeriveSharedSecret(
              Hex("4b66e9d4d1b4673c5ad22691957d6af5c11b6421e0ea01d42ca4169e7918ba0d"),
              Hex("e5210f12786811d3f4b7959d0538ae2c31dbe7106fc03c3efc4cd549c715a493"))),
          "95cbde9476e8907d7aade45cb4b873f88b595a68799fa152e6f8f7647aac7957");

    // k and u both start as 9; each round k becomes X25519(k, u) and u the
    // old k. The million-round value is left out for time.
    byte[] k = Hex("0900000000000000000000000000000000000000000000000000000000000000");
    byte[] u = Hex("0900000000000000000000000000000000000000000000000000000000000000");
    for (int i = 1; i <= 1000; i++)
    {
        byte[] next = X25519.DeriveSharedSecret(k, u).GetValueOrDefault(new byte[32u]);
        u = k;
        k = next;
        if (i == 1)
            Check("x25519-iterated-1", Convert.ToHexString(k),
                  "422c8e7a6227d7bca1350b3e2bb7279f7897b87bb6854b783c60e80311ae3079");
    }
    Check("x25519-iterated-1000", Convert.ToHexString(k),
          "684cf59ba83309552800ef566f2f4d3c1c3887c49360e3875f2eb94d99532c51");

    byte[] alice = Hex("77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a");
    byte[] bob = Hex("5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb");
    String alicePublic = "8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a";
    String bobPublic = "de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f";
    String shared = "4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742";

    Check("x25519-alice-public", HexOf(X25519.GetPublicKey(alice)), alicePublic);
    Check("x25519-bob-public", HexOf(X25519.GetPublicKey(bob)), bobPublic);
    Check("x25519-alice-shared", HexOf(X25519.DeriveSharedSecret(alice, Hex(bobPublic))), shared);
    Check("x25519-bob-shared", HexOf(X25519.DeriveSharedSecret(bob, Hex(alicePublic))), shared);

    // Points of order 1, 4 and 8: the secret is zero whatever the private key.
    String[] lowOrder = [
        "0000000000000000000000000000000000000000000000000000000000000000",
        "0100000000000000000000000000000000000000000000000000000000000000",
        "e0eb7a7c3b41b8ae1656e3faf19fc46ada098deb9c32b1fd866205165f49b800",
    ];
    for (nuint i = 0u; i < lowOrder.Length; i++)
    {
        var refused = X25519.DeriveSharedSecret(alice, Hex(lowOrder[i]));
        Console.WriteLine(!refused.Ok && refused.Error == CryptoError.InvalidKey
            ? "x25519-low-order refused" : "x25519-low-order WRONG");
    }

    var stunted = X25519.DeriveSharedSecret(Hex("0102"), Hex(bobPublic));
    Console.WriteLine(!stunted.Ok && stunted.Error == CryptoError.KeyLength
        ? "x25519-short-key refused" : "x25519-short-key WRONG");

    byte[] mine = X25519.GeneratePrivateKey();
    byte[] theirs = X25519.GeneratePrivateKey();
    byte[] minePublic = X25519.GetPublicKey(mine).GetValueOrDefault(new byte[32u]);
    byte[] theirsPublic = X25519.GetPublicKey(theirs).GetValueOrDefault(new byte[32u]);
    String forward = HexOf(X25519.DeriveSharedSecret(mine, theirsPublic));
    String backward = HexOf(X25519.DeriveSharedSecret(theirs, minePublic));
    CheckTrue("x25519-generated-agree", forward == backward && forward != "failed");
}

// ----------------------------------------------------------------- Ed25519

void CheckVector(String name, String secretKey, String publicKey, String message,
                 String signature)
{
    byte[] secret = Hex(secretKey);
    byte[] body = Hex(message);
    Check(name + "-public", HexOf(Ed25519.GetPublicKey(secret)), publicKey);
    Check(name + "-sign", HexOf(Ed25519.Sign(secret, body)), signature);
    CheckTrue(name + "-verify", Ed25519.Verify(Hex(publicKey), body, Hex(signature)));
}

void Signatures()
{
    CheckVector("ed25519-1",
                "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60",
                "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a",
                "",
                "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155" +
                "5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b");

    CheckVector("ed25519-2",
                "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb",
                "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c",
                "72",
                "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da" +
                "085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00");

    CheckVector("ed25519-3",
                "c5aa8df43f9f837bedb7442f31dcb7b166d38535076f094b85ce3a2e0b4458f7",
                "fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025",
                "af82",
                "6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac" +
                "18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a");

    CheckVector("ed25519-1024",
                "f5e5767cf153319517630f226876b86c8160cc583bc013744c6bf255f5cc0ee5",
                "278117fc144c72340f67d0f2316e8386ceffbf2b2428c9c51fef7c597f1d426e",
                "08b8b2b733424243760fe426a4b54908632110a66c2f6591eabd3345e3e4eb98" +
                "fa6e264bf09efe12ee50f8f54e9f77b1e355f6c50544e23fb1433ddf73be84d8" +
                "79de7c0046dc4996d9e773f4bc9efe5738829adb26c81b37c93a1b270b20329d" +
                "658675fc6ea534e0810a4432826bf58c941efb65d57a338bbd2e26640f89ffbc" +
                "1a858efcb8550ee3a5e1998bd177e93a7363c344fe6b199ee5d02e82d522c4fe" +
                "ba15452f80288a821a579116ec6dad2b3b310da903401aa62100ab5d1a36553e" +
                "06203b33890cc9b832f79ef80560ccb9a39ce767967ed628c6ad573cb116dbef" +
                "efd75499da96bd68a8a97b928a8bbc103b6621fcde2beca1231d206be6cd9ec7" +
                "aff6f6c94fcd7204ed3455c68c83f4a41da4af2b74ef5c53f1d8ac70bdcb7ed1" +
                "85ce81bd84359d44254d95629e9855a94a7c1958d1f8ada5d0532ed8a5aa3fb2" +
                "d17ba70eb6248e594e1a2297acbbb39d502f1a8c6eb6f1ce22b3de1a1f40cc24" +
                "554119a831a9aad6079cad88425de6bde1a9187ebb6092cf67bf2b13fd65f270" +
                "88d78b7e883c8759d2c4f5c65adb7553878ad575f9fad878e80a0c9ba63bcbcc" +
                "2732e69485bbc9c90bfbd62481d9089beccf80cfe2df16a2cf65bd92dd597b07" +
                "07e0917af48bbb75fed413d238f5555a7a569d80c3414a8d0859dc65a46128ba" +
                "b27af87a71314f318c782b23ebfe808b82b0ce26401d2e22f04d83d1255dc51a" +
                "ddd3b75a2b1ae0784504df543af8969be3ea7082ff7fc9888c144da2af58429e" +
                "c96031dbcad3dad9af0dcbaaaf268cb8fcffead94f3c7ca495e056a9b47acdb7" +
                "51fb73e666c6c655ade8297297d07ad1ba5e43f1bca32301651339e22904cc8c" +
                "42f58c30c04aafdb038dda0847dd988dcda6f3bfd15c4b4c4525004aa06eeff8" +
                "ca61783aacec57fb3d1f92b0fe2fd1a85f6724517b65e614ad6808d6f6ee34df" +
                "f7310fdc82aebfd904b01e1dc54b2927094b2db68d6f903b68401adebf5a7e08" +
                "d78ff4ef5d63653a65040cf9bfd4aca7984a74d37145986780fc0b16ac451649" +
                "de6188a7dbdf191f64b5fc5e2ab47b57f7f7276cd419c17a3ca8e1b939ae49e4" +
                "88acba6b965610b5480109c8b17b80e1b7b750dfc7598d5d5011fd2dcc5600a3" +
                "2ef5b52a1ecc820e308aa342721aac0943bf6686b64b2579376504ccc493d97e" +
                "6aed3fb0f9cd71a43dd497f01f17c0e2cb3797aa2a2f256656168e6c496afc5f" +
                "b93246f6b1116398a346f1a641f3b041e989f7914f90cc2c7fff357876e506b5" +
                "0d334ba77c225bc307ba537152f3f1610e4eafe595f6d9d90d11faa933a15ef1" +
                "369546868a7f3a45a96768d40fd9d03412c091c6315cf4fde7cb68606937380d" +
                "b2eaaa707b4c4185c32eddcdd306705e4dc1ffc872eeee475a64dfac86aba41c" +
                "0618983f8741c5ef68d3a101e8a3b8cac60c905c15fc910840b94c00a0b9d0",
                "0aab4c900501b3e24d7cdf4663326a3a87df5e4843b2cbdb67cbf6e460fec350" +
                "aa5371b1508f9f4528ecea23c436d94b5e8fcd4f681e30a6ac00a9704a188a03");

    CheckVector("ed25519-sha-abc",
                "833fe62409237b9d62ec77587520911e9a759cec1d19755b7da901b96dca3d42",
                "ec172b93ad5e563bf4932c70e1245034c35467ef2efd4d64ebf819683467e2bf",
                "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a" +
                "2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f",
                "dc2a4459e7369633a52b1bf277839a00201009a3efbf3ecb69bea2186c26b589" +
                "09351fc9ac90b3ecfdfbc7c66431e0303dca179c138ac17ad9bef1177331a704");

    // TEST 2, altered.
    byte[] publicKey = Hex("3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c");
    byte[] message = Hex("72");
    byte[] signature = Hex("92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da" +
                           "085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00");

    CheckRefused("ed25519-flipped-r", Ed25519.Verify(publicKey, message, FlipBit(signature, 3u)));
    CheckRefused("ed25519-flipped-s", Ed25519.Verify(publicKey, message, FlipBit(signature, 300u)));
    CheckRefused("ed25519-flipped-message",
                 Ed25519.Verify(publicKey, FlipBit(message, 0u), signature));
    CheckRefused("ed25519-flipped-key", Ed25519.Verify(FlipBit(publicKey, 9u), message, signature));

    // S + L satisfies the same equation as S, since L times B is the
    // identity. Only the range check on S refuses it.
    byte[] order = Hex("edd3f55c1a631258d69cf7a2def9de1400000000000000000000000000000010");
    byte[] widened = new byte[64u];
    uint carry = 0u;
    for (nuint i = 0u; i < 32u; i++)
    {
        widened[i] = signature[i];
        uint sum = (uint)signature[32u + i] + (uint)order[i] + carry;
        widened[32u + i] = (byte)(sum & 0xFFu);
        carry = sum >> 8;
    }
    CheckRefused("ed25519-s-not-reduced", Ed25519.Verify(publicKey, message, widened));

    // The identity has two encodings, y = 1 and y = p + 1. R = B and S = 1
    // is a signature of anything under it, since [1]B = B + [k]O. Both are
    // refused: the canonical one as a key of small order, the other as a
    // non-canonical encoding.
    byte[] forged = Hex("5866666666666666666666666666666666666666666666666666666666666666" +
                        "0100000000000000000000000000000000000000000000000000000000000000");
    byte[] identity = Hex("0100000000000000000000000000000000000000000000000000000000000000");
    byte[] identityAgain = Hex("eeffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f");
    CheckRefused("ed25519-identity-key", Ed25519.Verify(identity, message, forged));
    CheckRefused("ed25519-non-canonical-key", Ed25519.Verify(identityAgain, message, forged));

    // Points of order 2, 4 and 8. The same forgery holds under one of them
    // whenever the order divides k, which one message in eight or more
    // manages; across 64 messages at least one would get through.
    CheckRefused("ed25519-order-2-key", AcceptsForgery(
        Hex("ecffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f"), forged));
    CheckRefused("ed25519-order-4-key", AcceptsForgery(
        Hex("0000000000000000000000000000000000000000000000000000000000000000"), forged));
    CheckRefused("ed25519-order-8-key", AcceptsForgery(
        Hex("c7176a703d4dd84fba3c0b760d10670f2a2053fa2c39ccc64ec7fd7792ac037a"), forged));

    // y = 2 has no x on the curve.
    byte[] offCurve = Hex("0200000000000000000000000000000000000000000000000000000000000000");
    CheckRefused("ed25519-off-curve-key", Ed25519.Verify(offCurve, message, signature));

    CheckRefused("ed25519-short-signature",
                 Ed25519.Verify(publicKey, message, Hex("92a009a9f0d4cab8")));

    var stunted = Ed25519.Sign(Hex("0102"), message);
    Console.WriteLine(!stunted.Ok && stunted.Error == CryptoError.KeyLength
        ? "ed25519-short-key refused" : "ed25519-short-key WRONG");

    byte[] privateKey = Ed25519.GeneratePrivateKey();
    byte[] generatedPublic = Ed25519.GetPublicKey(privateKey).GetValueOrDefault(new byte[32u]);
    byte[] generatedSignature = Ed25519.Sign(privateKey, message).GetValueOrDefault(new byte[64u]);
    CheckTrue("ed25519-generated", Ed25519.Verify(generatedPublic, message, generatedSignature));
}

int Main()
{
    KeyAgreement();
    Signatures();
    return 0;
}
