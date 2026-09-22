// SPDX-License-Identifier: 0BSD
module Cryptography;

import Standard.Console;
import Standard.Convert;
import Standard.Encoding;
import Standard.Text;
import Standard.Security.Cryptography;

// Every answer here is a published test vector: FIPS-180 and RFC 1321 for the
// digests, RFC 2202 and 4231 for HMAC, RFC 6070 for PBKDF2, RFC 5869 for HKDF,
// FIPS-197 appendix C for the AES blocks, NIST SP 800-38A F.5 for CTR and the
// GCM specification's own test case 3. A number that changes here is a broken
// implementation rather than a changed convention.

byte[] Bytes(String text) => Encoding.CreateUtf8().GetBytes(text);

byte[] Hex(String text) => Convert.FromHex(text).GetValueOrDefault(new byte[0u]);

byte[] Repeat(byte value, nuint count)
{
    byte[] data = new byte[count];
    for (nuint i = 0u; i < count; i++)
        data[i] = value;
    return data;
}

// The cipher factories report a bad key length, and every key here is a good
// one; `GetValueOrDefault` supplies a cipher that is never reached.
Aes Cipher(byte[] key) => Aes.FromKey(key).GetValueOrDefault(Aes.Create());

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

void Digests()
{
    byte[] abc = Bytes("abc");

    Check("md5", Convert.ToHex(Md5.HashData(abc)), "900150983cd24fb0d6963f7d28e17f72");
    Check("sha1", Convert.ToHex(Sha1.HashData(abc)),
          "a9993e364706816aba3e25717850c26c9cd0d89d");
    Check("sha256", Convert.ToHex(Sha256.HashData(abc)),
          "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
    Check("sha384", Convert.ToHex(Sha384.HashData(abc)),
          "cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed" +
          "8086072ba1e7cc2358baeca134c825a7");
    Check("sha512", Convert.ToHex(Sha512.HashData(abc)),
          "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a" +
          "2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f");

    // The empty input is the one that exercises the padding on its own: the
    // block it hashes is nothing but the terminator, the zeros and the length.
    Check("sha256-empty", Convert.ToHex(Sha256.HashData(new byte[0u])),
          "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");

    // A message that crosses a block boundary, and the same message appended
    // in three pieces: the buffering has to give the same answer as the
    // one-shot, and the split is chosen to land inside a block.
    byte[] long448 = Bytes("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq");
    Check("sha256-multiblock", Convert.ToHex(Sha256.HashData(long448)),
          "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1");

    var incremental = new Sha256();
    incremental.Append(Bytes("abcdbcdecdefdefgefghfghi"));
    incremental.Append(Bytes("ghijhijkijkl"));
    incremental.Append(Bytes("jklmklmnlmnomnopnopq"));
    Check("sha256-incremental", Convert.ToHex(incremental.GetHashAndReset()),
          "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1");

    // And the reset that `GetHashAndReset` promises.
    Check("sha256-reset", Convert.ToHex(incremental.GetHashAndReset()),
          "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
}

void Macs()
{
    byte[] key = Repeat((byte)0x0B, 20u);
    byte[] data = Bytes("Hi There");

    // RFC 2202's MD5 cases use a sixteen-byte key where RFC 4231's SHA cases
    // use twenty, which is the only reason this line differs from the rest.
    Check("hmac-md5", Convert.ToHex(HmacMd5.HashData(Repeat((byte)0x0B, 16u), data)),
          "9294727a3638bb1c13f48ef8158bfc9d");
    Check("hmac-sha1", Convert.ToHex(HmacSha1.HashData(key, data)),
          "b617318655057264e28bc0b6fb378c8ef146be00");
    Check("hmac-sha256", Convert.ToHex(HmacSha256.HashData(Repeat((byte)0x0B, 20u), data)),
          "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7");
    Check("hmac-sha384", Convert.ToHex(HmacSha384.HashData(Repeat((byte)0x0B, 20u), data)),
          "afd03944d84895626b0825f4ab46907f15f9dadbe4101ec682aa034c7cebc59c" +
          "faea9ea9076ede7f4af152e8b2fa9cb6");
    Check("hmac-sha512", Convert.ToHex(HmacSha512.HashData(Repeat((byte)0x0B, 20u), data)),
          "87aa7cdea5ef619d4ff0b4241a1d6cb02379f4e2ce4ec2787ad0b30545e17cde" +
          "daa833b7d6b8a702038b274eaea3f4e4be9d914eeb61f1702e696c203a126854");

    // A key longer than the block, which is hashed down before it is used --
    // RFC 4231 test case 6.
    Check("hmac-long-key",
          Convert.ToHex(HmacSha256.HashData(Repeat((byte)0xAA, 131u),
              Bytes("Test Using Larger Than Block-Size Key - Hash Key First"))),
          "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54");
}

void Derivation()
{
    byte[] password = Bytes("password");
    byte[] salt = Bytes("salt");

    var once = Rfc2898DeriveBytes.Pbkdf2(password, salt, 1u, new Sha1(), 20u);
    Check("pbkdf2-1", Convert.ToHex(once.GetValueOrDefault(new byte[0u])),
          "0c60c80f961f0e71f3a9b524af6012062fe037a6");

    var twice = Rfc2898DeriveBytes.Pbkdf2(password, salt, 2u, new Sha1(), 20u);
    Check("pbkdf2-2", Convert.ToHex(twice.GetValueOrDefault(new byte[0u])),
          "ea6c014dc72d6f8ccd1ed92ace1d41f0d8de8957");

    var many = Rfc2898DeriveBytes.Pbkdf2(password, salt, 4096u, new Sha1(), 20u);
    Check("pbkdf2-4096", Convert.ToHex(many.GetValueOrDefault(new byte[0u])),
          "4b007901b765489abead49d926f721d065a429c1");

    var wide = Rfc2898DeriveBytes.Pbkdf2(password, salt, 1u, new Sha256(), 32u);
    Check("pbkdf2-sha256", Convert.ToHex(wide.GetValueOrDefault(new byte[0u])),
          "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b");

    var refused = Rfc2898DeriveBytes.Pbkdf2(password, salt, 0u, new Sha256(), 32u);
    Console.WriteLine(refused.Ok ? "pbkdf2-zero WRONG" : "pbkdf2-zero refused");

    var derived = Hkdf.DeriveKey(new Sha256(), Repeat((byte)0x0B, 22u),
                                 Hex("000102030405060708090a0b0c"),
                                 Hex("f0f1f2f3f4f5f6f7f8f9"), 42u);
    Check("hkdf", Convert.ToHex(derived.GetValueOrDefault(new byte[0u])),
          "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf" +
          "34007208d5b887185865");
}

void Blocks()
{
    String plain = "00112233445566778899aabbccddeeff";

    byte[] block = Hex(plain);
    Cipher(Hex("000102030405060708090a0b0c0d0e0f")).EncryptBlock(block, 0u);
    Check("aes-128", Convert.ToHex(block), "69c4e0d86a7b0430d8cdb78070b4c55a");
    Cipher(Hex("000102030405060708090a0b0c0d0e0f")).DecryptBlock(block, 0u);
    Check("aes-128-back", Convert.ToHex(block), plain);

    block = Hex(plain);
    Cipher(Hex("000102030405060708090a0b0c0d0e0f1011121314151617")).EncryptBlock(block, 0u);
    Check("aes-192", Convert.ToHex(block), "dda97ca4864cdfe06eaf70a0ec0d7191");

    block = Hex(plain);
    var wide = Cipher(Hex("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"));
    wide.EncryptBlock(block, 0u);
    Check("aes-256", Convert.ToHex(block), "8ea2b7ca516745bfeafc49904b496089");
    wide.DecryptBlock(block, 0u);
    Check("aes-256-back", Convert.ToHex(block), plain);

    var stunted = Aes.FromKey(new byte[10u]);
    Console.WriteLine(stunted.Ok ? "aes-short-key WRONG" : "aes-short-key refused");
}

void Modes()
{
    // SP 800-38A F.1.1 and F.2.1, whose plaintext is four named blocks.
    byte[] key = Hex("2b7e151628aed2a6abf7158809cf4f3c");
    byte[] iv = Hex("000102030405060708090a0b0c0d0e0f");
    byte[] plain = Hex("6bc1bee22e409f96e93d7e117393172a" +
                       "ae2d8a571e03ac9c9eb76fac45af8e51");
    var cipher = Cipher(key);

    var ecb = cipher.EncryptEcb(plain, PaddingMode.None);
    Check("ecb", Convert.ToHex(ecb.GetValueOrDefault(new byte[0u])),
          "3ad77bb40d7a3660a89ecaf32466ef97f5d3d58503b9699de785895a96fdbaaf");

    var cbc = cipher.EncryptCbc(plain, iv, PaddingMode.None);
    Check("cbc", Convert.ToHex(cbc.GetValueOrDefault(new byte[0u])),
          "7649abac8119b246cee98e9b12e9197d5086cb9b507219ee95db113a917678b2");

    // F.5.1: the counter runs from a named start rather than from an IV.
    var ctr = cipher.ApplyCtr(plain, Hex("f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff"));
    Check("ctr", Convert.ToHex(ctr.GetValueOrDefault(new byte[0u])),
          "874d6191b620e3261bef6864990db6ce9806f66b7970fdff8617187bb9fffdff");

    // CTR is its own inverse, which is the whole of why it needs no padding.
    var back = cipher.ApplyCtr(ctr.GetValueOrDefault(new byte[0u]),
                               Hex("f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff"));
    Check("ctr-inverse", Convert.ToHex(back.GetValueOrDefault(new byte[0u])), Convert.ToHex(plain));

    // The padding, which is what a message that is not a whole block needs.
    byte[] message = Bytes("the quick brown fox");
    var padded = cipher.EncryptCbc(message, iv, PaddingMode.Pkcs7);
    Console.WriteLine("pkcs7 grows to " + Text.FromInteger((long)padded.GetValueOrDefault(new byte[0u]).Length));

    var opened = cipher.DecryptCbc(padded.GetValueOrDefault(new byte[0u]), iv, PaddingMode.Pkcs7);
    Check("cbc-round-trip", Encoding.CreateUtf8().GetString(opened.GetValueOrDefault(new byte[0u])),
          "the quick brown fox");

    // A wrong key is a padding failure far more often than it is a wrong
    // plaintext, and that is what a caller sees.
    var wrong = Cipher(Hex("00000000000000000000000000000000"))
        .DecryptCbc(padded.GetValueOrDefault(new byte[0u]), iv, PaddingMode.Pkcs7);
    Console.WriteLine(wrong.Ok ? "cbc-wrong-key opened" : "cbc-wrong-key refused");

    var ragged = cipher.EncryptCbc(message, iv, PaddingMode.None);
    Console.WriteLine(ragged.Ok ? "cbc-no-padding WRONG" : "cbc-no-padding refused");

    var cfb = cipher.EncryptCfb(message, iv);
    var cfbBack = cipher.DecryptCfb(cfb.GetValueOrDefault(new byte[0u]), iv);
    Check("cfb-round-trip", Encoding.CreateUtf8().GetString(cfbBack.GetValueOrDefault(new byte[0u])),
          "the quick brown fox");
}

void Authenticated()
{
    // The GCM specification's test case 3: a 64-byte message, no associated
    // data, and the twelve-byte nonce everything uses.
    byte[] nonce = Hex("cafebabefacedbaddecaf888");
    byte[] plain = Hex("d9313225f88406e5a55909c5aff5269a86a7a9531534f7da" +
                       "2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525" +
                       "b16aedf5aa0de657ba637b391aafd255");

    var made = AesGcm.FromKey(Hex("feffe9928665731c6d6a8f9467308308"));
    if (!made.Ok)
    {
        Console.WriteLine("gcm key WRONG");
        return;
    }

    var box = made.Value;
    byte[] tag = new byte[16u];
    var sealedText = box.Encrypt(nonce, plain, new byte[0u], tag);

    Check("gcm-ciphertext", Convert.ToHex(sealedText.GetValueOrDefault(new byte[0u])),
          "42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e" +
          "21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e091473f5985");
    Check("gcm-tag", Convert.ToHex(tag), "4d5c2af327cd64a62cf35abd2ba6fab4");

    var opened = box.Decrypt(nonce, sealedText.GetValueOrDefault(new byte[0u]), new byte[0u], tag);
    Check("gcm-round-trip", Convert.ToHex(opened.GetValueOrDefault(new byte[0u])), Convert.ToHex(plain));

    // Associated data is authenticated and not encrypted, so changing it after
    // the fact is a forgery like any other.
    byte[] header = Bytes("record 7");
    byte[] boundTag = new byte[16u];
    var bound = box.Encrypt(nonce, Bytes("secret"), header, boundTag);
    var rightHeader = box.Decrypt(nonce, bound.GetValueOrDefault(new byte[0u]), header, boundTag);
    Check("gcm-associated", Encoding.CreateUtf8().GetString(rightHeader.GetValueOrDefault(new byte[0u])), "secret");

    var wrongHeader = box.Decrypt(nonce, bound.GetValueOrDefault(new byte[0u]), Bytes("record 8"), boundTag);
    Console.WriteLine(wrongHeader.Ok ? "gcm-associated-changed opened" : "gcm-associated-changed refused");

    tag[0u] = (byte)(tag[0u] ^ 1u);
    var forged = box.Decrypt(nonce, sealedText.GetValueOrDefault(new byte[0u]), new byte[0u], tag);
    Console.WriteLine(forged.Ok ? "gcm-forgery opened" : "gcm-forgery refused");
}

void Discipline()
{
    byte[] left = Hex("0011223344556677");
    byte[] right = Hex("0011223344556677");
    byte[] other = Hex("0011223344556678");

    Console.WriteLine(CryptographicOperations.FixedTimeEquals(left, right)
        ? "equal ok" : "equal WRONG");
    Console.WriteLine(CryptographicOperations.FixedTimeEquals(left, other)
        ? "unequal WRONG" : "unequal ok");
    Console.WriteLine(CryptographicOperations.FixedTimeEquals(left, Hex("00112233"))
        ? "lengths WRONG" : "lengths ok");

    CryptographicOperations.ZeroMemory(left);
    Console.WriteLine("zeroed " + Convert.ToHex(left));

    // Entropy is not reproducible, so what is checked is that it arrives and
    // that two draws differ -- which a stuck generator would fail.
    byte[] first = RandomNumberGenerator.GetBytes(32u);
    byte[] second = RandomNumberGenerator.GetBytes(32u);
    Console.WriteLine("entropy " + Text.FromInteger((long)first.Length) + " bytes, distinct " +
        (CryptographicOperations.FixedTimeEquals(first, second) ? "no" : "yes"));

    int drawn = RandomNumberGenerator.GetInt32(10, 20);
    Console.WriteLine(drawn >= 10 && drawn < 20 ? "range ok" : "range WRONG");
}

int Main()
{
    Digests();
    Macs();
    Derivation();
    Blocks();
    Modes();
    Authenticated();
    Discipline();
    return 0;
}
