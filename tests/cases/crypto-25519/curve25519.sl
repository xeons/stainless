// SPDX-License-Identifier: 0BSD
module Curve25519;

import Standard.Console;
import Standard.Convert;
import Standard.Security.Cryptography;

// Every answer here is a published test vector: RFC 7748 §5.2 for the two
// X25519 pairs and the iterated test, and RFC 7748 §6.1 for the
// Diffie-Hellman example. The refused inputs are the low-order points every
// X25519 implementation is expected to catch.

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

int Main()
{
    KeyAgreement();
    return 0;
}
