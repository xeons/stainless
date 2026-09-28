// SPDX-License-Identifier: 0BSD
module ChaChaVectors;

import Standard.Console;
import Standard.Convert;
import Standard.Encoding;
import Standard.Text;
import Standard.Security.Cryptography;

// Every answer here is from RFC 8439: the ChaCha20 block of §2.3.2 and the five
// of A.1, the encryptions of §2.4.2 and A.2, the Poly1305 tags of §2.5.2 and
// the eleven of A.3, the key generation of §2.6.2 and A.4, the AEAD of §2.8.2,
// and the AEAD decryption of A.5. A number that changes here is a broken
// implementation rather than a changed convention.

byte[] Bytes(String text) => Encoding.CreateUtf8().GetBytes(text);

byte[] Hex(String text) => Convert.FromHexString(text).GetValueOrDefault(new byte[0u]);

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

String ApplyChaCha(String key, String nonce, uint counter, byte[] input)
{
    var cipher = ChaCha20.FromKey(Hex(key));
    if (!cipher.Ok)
        return "key refused";

    var output = cipher.Value.ApplyKeystream(Hex(nonce), counter, input);
    if (!output.Ok)
        return "refused";
    return Convert.ToHexString(output.Value);
}

String ComputeTag(String key, byte[] message)
{
    var tag = Poly1305.ComputeTag(Hex(key), message);
    if (!tag.Ok)
        return "key refused";
    return Convert.ToHexString(tag.Value);
}

byte[] CreateSunscreenText() =>
    Bytes("Ladies and Gentlemen of the class of '99: If I could offer " +
          "you only one tip for the future, sunscreen would be it.");

byte[] CreateContributionText() =>
    Bytes("Any submission to the IETF intended by the Contributor for " +
          "publication as all or part of an IETF Internet-Draft or RFC " +
          "and any statement made within the context of an IETF " +
          "activity is considered an \"IETF Contribution\". Such " +
          "statements include oral statements in IETF sessions, as well " +
          "as written and electronic communications made at any time or " +
          "place, which are addressed to");

byte[] CreateJabberwockyText() =>
    Bytes("'Twas brillig, and the slithy toves\nDid gyre and gimble in " +
          "the wabe:\nAll mimsy were the borogoves,\nAnd the mome raths " +
          "outgrabe.");

void CheckBlockFunction()
{
    // Each is one block of keystream, which is what enciphering 64 zero bytes
    // gives back.
    Check("block-2.3.2",
          ApplyChaCha("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f",
                      "000000090000004a00000000", 1u, new byte[64u]),
          "10f1e7e4d13b5915500fdd1fa32071c4c7d1f4c733c068030422aa9ac3d46c4e" +
          "d2826446079faa0914c2d705d98b02a2b5129cd1de164eb9cbd083e8a2503c4e");
    Check("block-a.1.1",
          ApplyChaCha("0000000000000000000000000000000000000000000000000000000000000000",
                      "000000000000000000000000", 0u, new byte[64u]),
          "76b8e0ada0f13d90405d6ae55386bd28bdd219b8a08ded1aa836efcc8b770dc7" +
          "da41597c5157488d7724e03fb8d84a376a43b8f41518a11cc387b669b2ee6586");
    Check("block-a.1.2",
          ApplyChaCha("0000000000000000000000000000000000000000000000000000000000000000",
                      "000000000000000000000000", 1u, new byte[64u]),
          "9f07e7be5551387a98ba977c732d080dcb0f29a048e3656912c6533e32ee7aed" +
          "29b721769ce64e43d57133b074d839d531ed1f28510afb45ace10a1f4b794d6f");
    Check("block-a.1.3",
          ApplyChaCha("0000000000000000000000000000000000000000000000000000000000000001",
                      "000000000000000000000000", 1u, new byte[64u]),
          "3aeb5224ecf849929b9d828db1ced4dd832025e8018b8160b82284f3c949aa5a" +
          "8eca00bbb4a73bdad192b5c42f73f2fd4e273644c8b36125a64addeb006c13a0");
    Check("block-a.1.4",
          ApplyChaCha("00ff000000000000000000000000000000000000000000000000000000000000",
                      "000000000000000000000000", 2u, new byte[64u]),
          "72d54dfbf12ec44b362692df94137f328fea8da73990265ec1bbbea1ae9af0ca" +
          "13b25aa26cb4a648cb9b9d1be65b2c0924a66c54d545ec1b7374f4872e99f096");
    Check("block-a.1.5",
          ApplyChaCha("0000000000000000000000000000000000000000000000000000000000000000",
                      "000000000000000000000002", 0u, new byte[64u]),
          "c2c64d378cd536374ae204b9ef933fcd1a8b2288b3dfa49672ab765b54ee27c7" +
          "8a970e0e955c14f3a88e741b97c286f75f8fc299e8148362fa198a39531bed6d");
}

void CheckEncryption()
{
    Check("encrypt-2.4.2",
          ApplyChaCha("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f",
                      "000000000000004a00000000", 1u, CreateSunscreenText()),
          "6e2e359a2568f98041ba0728dd0d6981e97e7aec1d4360c20a27afccfd9fae0b" +
          "f91b65c5524733ab8f593dabcd62b3571639d624e65152ab8f530c359f0861d8" +
          "07ca0dbf500d6a6156a38e088a22b65e52bc514d16ccf806818ce91ab7793736" +
          "5af90bbf74a35be6b40b8eedf2785e42874d");
    Check("encrypt-a.2.1",
          ApplyChaCha("0000000000000000000000000000000000000000000000000000000000000000",
                      "000000000000000000000000", 0u, new byte[64u]),
          "76b8e0ada0f13d90405d6ae55386bd28bdd219b8a08ded1aa836efcc8b770dc7" +
          "da41597c5157488d7724e03fb8d84a376a43b8f41518a11cc387b669b2ee6586");
    Check("encrypt-a.2.2",
          ApplyChaCha("0000000000000000000000000000000000000000000000000000000000000001",
                      "000000000000000000000002", 1u, CreateContributionText()),
          "a3fbf07df3fa2fde4f376ca23e82737041605d9f4f4f57bd8cff2c1d4b7955ec" +
          "2a97948bd3722915c8f3d337f7d370050e9e96d647b7c39f56e031ca5eb6250d" +
          "4042e02785ececfa4b4bb5e8ead0440e20b6e8db09d881a7c6132f420e527950" +
          "42bdfa7773d8a9051447b3291ce1411c680465552aa6c405b7764d5e87bea85a" +
          "d00f8449ed8f72d0d662ab052691ca66424bc86d2df80ea41f43abf937d3259d" +
          "c4b2d0dfb48a6c9139ddd7f76966e928e635553ba76c5c879d7b35d49eb2e62b" +
          "0871cdac638939e25e8a1e0ef9d5280fa8ca328b351c3c765989cbcf3daa8b6c" +
          "cc3aaf9f3979c92b3720fc88dc95ed84a1be059c6499b9fda236e7e818b04b0b" +
          "c39c1e876b193bfe5569753f88128cc08aaa9b63d1a16f80ef2554d7189c411f" +
          "5869ca52c5b83fa36ff216b9c1d30062bebcfd2dc5bce0911934fda79a86f6e6" +
          "98ced759c3ff9b6477338f3da4f9cd8514ea9982ccafb341b2384dd902f3d1ab" +
          "7ac61dd29c6f21ba5b862f3730e37cfdc4fd806c22f221");
    Check("encrypt-a.2.3",
          ApplyChaCha("1c9240a5eb55d38af333888604f6b5f0473917c1402b80099dca5cbc207075c0",
                      "000000000000000000000002", 42u, CreateJabberwockyText()),
          "62e6347f95ed87a45ffae7426f27a1df5fb69110044c0d73118effa95b01e5cf" +
          "166d3df2d721caf9b21e5fb14c616871fd84c54f9d65b283196c7fe4f60553eb" +
          "f39c6402c42234e32a356b3e764312a61a5532055716ead6962568f87d3f3f77" +
          "04c6a8d1bcd1bf4d50d6154b6da731b187b58dfd728afa36757a797ac188d1");
}

void CheckAuthenticator()
{
    // A.3.5 to A.3.11 are the edge cases of the reduction modulo 2^130 - 5.
    Check("poly1305-2.5.2",
          ComputeTag("85d6be7857556d337f4452fe42d506a80103808afb0db2fd4abff6af4149f51b",
                     Bytes("Cryptographic Forum Research Group")),
          "a8061dc1305136c6c22b8baf0c0127a9");
    Check("poly1305-a.3.1",
          ComputeTag("0000000000000000000000000000000000000000000000000000000000000000",
                     new byte[64u]),
          "00000000000000000000000000000000");
    Check("poly1305-a.3.2",
          ComputeTag("0000000000000000000000000000000036e5f6b5c5e06070f0efca96227a863e",
                     CreateContributionText()),
          "36e5f6b5c5e06070f0efca96227a863e");
    Check("poly1305-a.3.3",
          ComputeTag("36e5f6b5c5e06070f0efca96227a863e00000000000000000000000000000000",
                     CreateContributionText()),
          "f3477e7cd95417af89a6b8794c310cf0");
    Check("poly1305-a.3.4",
          ComputeTag("1c9240a5eb55d38af333888604f6b5f0473917c1402b80099dca5cbc207075c0",
                     CreateJabberwockyText()),
          "4541669a7eaaee61e708dc7cbcc5eb62");
    Check("poly1305-a.3.5",
          ComputeTag("0200000000000000000000000000000000000000000000000000000000000000",
                     Hex("ffffffffffffffffffffffffffffffff")),
          "03000000000000000000000000000000");
    Check("poly1305-a.3.6",
          ComputeTag("02000000000000000000000000000000ffffffffffffffffffffffffffffffff",
                     Hex("02000000000000000000000000000000")),
          "03000000000000000000000000000000");
    Check("poly1305-a.3.7",
          ComputeTag("0100000000000000000000000000000000000000000000000000000000000000",
                     Hex("fffffffffffffffffffffffffffffffff0ffffffffffffffffffffffffffffff" +
                         "11000000000000000000000000000000")),
          "05000000000000000000000000000000");
    Check("poly1305-a.3.8",
          ComputeTag("0100000000000000000000000000000000000000000000000000000000000000",
                     Hex("fffffffffffffffffffffffffffffffffbfefefefefefefefefefefefefefefe" +
                         "01010101010101010101010101010101")),
          "00000000000000000000000000000000");
    Check("poly1305-a.3.9",
          ComputeTag("0200000000000000000000000000000000000000000000000000000000000000",
                     Hex("fdffffffffffffffffffffffffffffff")),
          "faffffffffffffffffffffffffffffff");
    Check("poly1305-a.3.10",
          ComputeTag("0100000000000000040000000000000000000000000000000000000000000000",
                     Hex("e33594d7505e43b900000000000000003394d7505e4379cd0100000000000000" +
                         "0000000000000000000000000000000001000000000000000000000000000000")),
          "14000000000000005500000000000000");
    Check("poly1305-a.3.11",
          ComputeTag("0100000000000000040000000000000000000000000000000000000000000000",
                     Hex("e33594d7505e43b900000000000000003394d7505e4379cd0100000000000000" +
                         "00000000000000000000000000000000")),
          "13000000000000000000000000000000");
}

void CheckKeyGeneration()
{
    // The one-time Poly1305 key is the first 32 bytes of block zero.
    Check("keygen-2.6.2",
          ApplyChaCha("808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f",
                      "000000000001020304050607", 0u, new byte[32u]),
          "8ad5a08b905f81cc815040274ab29471a833b637e3fd0da508dbb8e2fdd1a646");
    Check("keygen-a.4.1",
          ApplyChaCha("0000000000000000000000000000000000000000000000000000000000000000",
                      "000000000000000000000000", 0u, new byte[32u]),
          "76b8e0ada0f13d90405d6ae55386bd28bdd219b8a08ded1aa836efcc8b770dc7");
    Check("keygen-a.4.2",
          ApplyChaCha("0000000000000000000000000000000000000000000000000000000000000001",
                      "000000000000000000000002", 0u, new byte[32u]),
          "ecfa254f845f647473d3cb140da9e87606cb33066c447b87bc2666dde3fbb739");
    Check("keygen-a.4.3",
          ApplyChaCha("1c9240a5eb55d38af333888604f6b5f0473917c1402b80099dca5cbc207075c0",
                      "000000000000000000000002", 0u, new byte[32u]),
          "965e3bc6f9ec7ed9560808f4d229f94b137ff275ca9b3fcbdd59deaad23310ae");
}

void CheckSealed()
{
    var made = ChaCha20Poly1305.FromKey(Hex("808182838485868788898a8b8c8d8e8f" +
                                            "909192939495969798999a9b9c9d9e9f"));
    if (!made.Ok)
    {
        Console.WriteLine("aead key WRONG");
        return;
    }

    // §2.8.2: the nonce is a 32-bit sender id, 7, before the eight-byte IV.
    var box = made.Value;
    byte[] nonce = Hex("070000004041424344454647");
    byte[] associated = Hex("50515253c0c1c2c3c4c5c6c7");
    byte[] tag = new byte[16u];
    var sealedText = box.Encrypt(nonce, CreateSunscreenText(), associated, tag);

    Check("aead-2.8.2-ciphertext", Convert.ToHexString(sealedText.GetValueOrDefault(new byte[0u])),
          "d31a8d34648e60db7b86afbc53ef7ec2a4aded51296e08fea9e2b5a736ee62d6" +
          "3dbea45e8ca9671282fafb69da92728b1a71de0a9e060b2905d6a5b67ecd3b36" +
          "92ddbd7f2d778b8c9803aee328091b58fab324e4fad675945585808b4831d7bc" +
          "3ff4def08e4b7a9de576d26586cec64b6116");
    Check("aead-2.8.2-tag", Convert.ToHexString(tag), "1ae10b594f09e26a7e902ecbd0600691");

    var opened = box.Decrypt(nonce, sealedText.GetValueOrDefault(new byte[0u]), associated, tag);
    Check("aead-2.8.2-round-trip", Convert.ToHexString(opened.GetValueOrDefault(new byte[0u])),
          Convert.ToHexString(CreateSunscreenText()));

    // A.5 is the other direction: a received message, checked and opened.
    var received = ChaCha20Poly1305.FromKey(Hex("1c9240a5eb55d38af333888604f6b5f0" +
                                                "473917c1402b80099dca5cbc207075c0"));
    byte[] receivedNonce = Hex("000000000102030405060708");
    byte[] receivedAssociated = Hex("f33388860000000000004e91");
    byte[] receivedTag = Hex("eead9d67890cbb22392336fea1851f38");
    byte[] receivedText = Hex("64a0861575861af460f062c79be643bd5e805cfd345cf389f108670ac76c8cb2" +
                              "4c6cfc18755d43eea09ee94e382d26b0bdb7b73c321b0100d4f03b7f355894cf" +
                              "332f830e710b97ce98c8a84abd0b948114ad176e008d33bd60f982b1ff37c855" +
                              "9797a06ef4f0ef61c186324e2b3506383606907b6a7c02b0f9f6157b53c867e4" +
                              "b9166c767b804d46a59b5216cde7a4e99040c5a40433225ee282a1b0a06c523e" +
                              "af4534d7f83fa1155b0047718cbc546a0d072b04b3564eea1b422273f548271a" +
                              "0bb2316053fa76991955ebd63159434ecebb4e466dae5a1073a6727627097a10" +
                              "49e617d91d361094fa68f0ff77987130305beaba2eda04df997b714d6c6f2c29" +
                              "a6ad5cb4022b02709b");
    if (!received.Ok)
    {
        Console.WriteLine("aead-a.5 key WRONG");
        return;
    }

    var decrypted = received.Value.Decrypt(receivedNonce, receivedText, receivedAssociated,
                                           receivedTag);
    Check("aead-a.5", Convert.ToHexString(decrypted.GetValueOrDefault(new byte[0u])),
          "496e7465726e65742d4472616674732061726520647261667420646f63756d65" +
          "6e74732076616c696420666f722061206d6178696d756d206f6620736978206d" +
          "6f6e74687320616e64206d617920626520757064617465642c207265706c6163" +
          "65642c206f72206f62736f6c65746564206279206f7468657220646f63756d65" +
          "6e747320617420616e792074696d652e20497420697320696e617070726f7072" +
          "6961746520746f2075736520496e7465726e65742d4472616674732061732072" +
          "65666572656e6365206d6174657269616c206f7220746f206369746520746865" +
          "6d206f74686572207468616e206173202fe2809c776f726b20696e2070726f67" +
          "726573732e2fe2809d");

    // Re-encrypting A.5's plaintext has to give back the tag that was sent.
    byte[] resealedTag = new byte[16u];
    received.Value.Encrypt(receivedNonce, decrypted.GetValueOrDefault(new byte[0u]),
                           receivedAssociated, resealedTag);
    Check("aead-a.5-tag", Convert.ToHexString(resealedTag), "eead9d67890cbb22392336fea1851f38");
}

void CheckRefusals()
{
    var made = ChaCha20Poly1305.FromKey(new byte[32u]);
    if (!made.Ok)
    {
        Console.WriteLine("aead zero key WRONG");
        return;
    }

    var box = made.Value;
    byte[] nonce = new byte[12u];
    byte[] tag = new byte[16u];
    var sealedText = box.Encrypt(nonce, Bytes("attack at dawn"), Bytes("header"), tag);
    byte[] ciphertext = sealedText.GetValueOrDefault(new byte[0u]);

    var honest = box.Decrypt(nonce, ciphertext, Bytes("header"), tag);
    Check("aead-honest", Encoding.CreateUtf8().GetString(honest.GetValueOrDefault(new byte[0u])),
          "attack at dawn");

    // A flipped bit anywhere — tag, ciphertext or associated data — is a
    // forgery, and a forgery answers nothing but the failure.
    byte[] forgedTag = Hex(Convert.ToHexString(tag));
    forgedTag[15u] = (byte)(forgedTag[15u] ^ 0x80u);
    var forged = box.Decrypt(nonce, ciphertext, Bytes("header"), forgedTag);
    Console.WriteLine(forged.Ok ? "aead-forged-tag opened" : "aead-forged-tag refused");

    byte[] altered = Hex(Convert.ToHexString(ciphertext));
    altered[0u] = (byte)(altered[0u] ^ 1u);
    var tampered = box.Decrypt(nonce, altered, Bytes("header"), tag);
    Console.WriteLine(tampered.Ok ? "aead-altered-ciphertext opened"
                                  : "aead-altered-ciphertext refused");

    var moved = box.Decrypt(nonce, ciphertext, Bytes("headed"), tag);
    Console.WriteLine(moved.Ok ? "aead-altered-header opened" : "aead-altered-header refused");

    // Twelve bytes and nothing else: GCM's hashing of other lengths has no
    // counterpart here.
    var shortNonce = box.Encrypt(new byte[8u], Bytes("x"), new byte[0u], tag);
    Console.WriteLine(!shortNonce.Ok && shortNonce.Error == CryptoError.NonceLength
        ? "aead-short-nonce refused" : "aead-short-nonce WRONG");

    var longNonce = box.Decrypt(new byte[16u], ciphertext, Bytes("header"), tag);
    Console.WriteLine(!longNonce.Ok && longNonce.Error == CryptoError.NonceLength
        ? "aead-long-nonce refused" : "aead-long-nonce WRONG");

    var shortTag = box.Decrypt(nonce, ciphertext, Bytes("header"), new byte[12u]);
    Console.WriteLine(!shortTag.Ok && shortTag.Error == CryptoError.TagLength
        ? "aead-short-tag refused" : "aead-short-tag WRONG");

    var shortKey = ChaCha20Poly1305.FromKey(new byte[16u]);
    Console.WriteLine(!shortKey.Ok && shortKey.Error == CryptoError.KeyLength
        ? "aead-short-key refused" : "aead-short-key WRONG");

    String zeroKey = "0000000000000000000000000000000000000000000000000000000000000000";
    Check("chacha-short-nonce", ApplyChaCha(zeroKey, "0000000000000000", 0u, new byte[1u]),
          "refused");
    Check("chacha-short-key", ApplyChaCha("00", "000000000000000000000000", 0u, new byte[1u]),
          "key refused");

    // The counter is 32 bits and MUST NOT wrap: the last block is usable,
    // and one byte past it is not.
    String last = ApplyChaCha(zeroKey, "000000000000000000000000", 0xFFFFFFFFu, new byte[64u]);
    Console.WriteLine(last == "refused" ? "chacha-last-block WRONG" : "chacha-last-block ok");
    Check("chacha-counter-wrap", ApplyChaCha(zeroKey, "000000000000000000000000", 0xFFFFFFFFu,
                                             new byte[65u]),
          "refused");

    Check("poly1305-short-key", ComputeTag("00", new byte[0u]), "key refused");

    // Appended in pieces that straddle the sixteen-byte blocks, the tag is
    // the one-shot tag.
    var made1305 = Poly1305.FromKey(Hex("85d6be7857556d337f4452fe42d506a8" +
                                        "0103808afb0db2fd4abff6af4149f51b"));
    if (!made1305.Ok)
    {
        Console.WriteLine("poly1305 key WRONG");
        return;
    }

    var pieces = made1305.Value;
    pieces.AppendData(Bytes("Cryptographic"));
    pieces.AppendData(Bytes(" Forum Research"));
    pieces.AppendData(Bytes(" Group"));
    Check("poly1305-incremental", Convert.ToHexString(pieces.GetTag()),
          "a8061dc1305136c6c22b8baf0c0127a9");
}

int Main()
{
    CheckBlockFunction();
    CheckEncryption();
    CheckAuthenticator();
    CheckKeyGeneration();
    CheckSealed();
    CheckRefusals();
    return 0;
}
