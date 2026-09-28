// SPDX-License-Identifier: 0BSD
module AesVectors;

import Standard.Console;
import Standard.Convert;
import Standard.Text;
import Standard.Security.Cryptography;

// The block vectors are FIPS-197's appendices B and C; the mode vectors are
// NIST SP 800-38A's appendix F, for all three key lengths; the GCM vectors are
// the eighteen test cases of McGrew and Viega's GCM specification. The sweeps
// hash every ciphertext of every length from 0 to 100 bytes, and their digests
// come from .NET's System.Security.Cryptography, which shares no code with
// this. A number that changes here is a broken implementation.

byte[] Hex(String text) => Convert.FromHexString(text).GetValueOrDefault(new byte[0u]);

String ToHex(Result<byte[], CryptoError> result)
{
    if (!result.Ok)
        return "refused";
    return Convert.ToHexString(result.Value);
}

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

void CheckBlock(String label, String key, String plain, String expected)
{
    var cipher = Cipher(Hex(key));
    byte[] block = Hex(plain);
    cipher.EncryptBlock(block, 0u);
    Check(label, Convert.ToHexString(block), expected);
    cipher.DecryptBlock(block, 0u);
    Check(label + "-back", Convert.ToHexString(block), plain);
}

void CheckBlocks()
{
    CheckBlock("fips-b", "2b7e151628aed2a6abf7158809cf4f3c", "3243f6a8885a308d313198a2e0370734",
               "3925841d02dc09fbdc118597196a0b32");
    CheckBlock("fips-c1", "000102030405060708090a0b0c0d0e0f", "00112233445566778899aabbccddeeff",
               "69c4e0d86a7b0430d8cdb78070b4c55a");
    CheckBlock("fips-c2", "000102030405060708090a0b0c0d0e0f1011121314151617",
               "00112233445566778899aabbccddeeff", "dda97ca4864cdfe06eaf70a0ec0d7191");
    CheckBlock("fips-c3", "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f",
               "00112233445566778899aabbccddeeff", "8ea2b7ca516745bfeafc49904b496089");

    // One block in the middle of a buffer, which is all a single-block call
    // may touch although a pass carries four.
    byte[] buffer = new byte[48u];
    byte[] plain = Hex("00112233445566778899aabbccddeeff");
    for (nuint i = 0u; i < 16u; i++)
        buffer[16u + i] = plain[i];
    Cipher(Hex("000102030405060708090a0b0c0d0e0f")).EncryptBlock(buffer, 16u);
    Check("fips-c1-offset", Convert.ToHexString(buffer),
          "00000000000000000000000000000000" + "69c4e0d86a7b0430d8cdb78070b4c55a" +
          "00000000000000000000000000000000");
}

void CheckModes(String bits, String key, String ecb, String cbc, String cfb, String ctr)
{
    byte[] plain = Hex("6bc1bee22e409f96e93d7e117393172a" + "ae2d8a571e03ac9c9eb76fac45af8e51" +
                       "30c81c46a35ce411e5fbc1191a0a52ef" + "f69f2445df4f9b17ad2b417be66c3710");
    byte[] iv = Hex("000102030405060708090a0b0c0d0e0f");
    byte[] counter = Hex("f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff");
    String expected = Convert.ToHexString(plain);
    var cipher = Cipher(Hex(key));

    Check("ecb-" + bits, ToHex(cipher.EncryptEcb(plain, PaddingMode.None)), ecb);
    Check("ecb-" + bits + "-back", ToHex(cipher.DecryptEcb(Hex(ecb), PaddingMode.None)), expected);
    Check("cbc-" + bits, ToHex(cipher.EncryptCbc(plain, iv, PaddingMode.None)), cbc);
    Check("cbc-" + bits + "-back", ToHex(cipher.DecryptCbc(Hex(cbc), iv, PaddingMode.None)), expected);
    Check("cfb-" + bits, ToHex(cipher.EncryptCfb(plain, iv)), cfb);
    Check("cfb-" + bits + "-back", ToHex(cipher.DecryptCfb(Hex(cfb), iv)), expected);
    Check("ctr-" + bits, ToHex(cipher.ApplyCtr(plain, counter)), ctr);
    Check("ctr-" + bits + "-back", ToHex(cipher.ApplyCtr(Hex(ctr), counter)), expected);
}

void CheckGcm(String label, String key, String nonce, String plain, String associated,
              String ciphertext, String tag)
{
    var made = AesGcm.FromKey(Hex(key));
    if (!made.Ok)
    {
        Console.WriteLine(label + " key refused");
        return;
    }

    var box = made.Value;
    byte[] computed = new byte[16u];
    var sealedText = box.Encrypt(Hex(nonce), Hex(plain), Hex(associated), computed);
    if (!sealedText.Ok)
    {
        Console.WriteLine(label + " refused");
        return;
    }

    Check(label, Convert.ToHexString(sealedText.Value), ciphertext);
    Check(label + "-tag", Convert.ToHexString(computed), tag);
    Check(label + "-open", ToHex(box.Decrypt(Hex(nonce), sealedText.Value, Hex(associated), computed)),
          plain);
}

void CheckGcmCases()
{
    String plain = "d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a72" +
                   "1c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b391aafd255";
    String truncated = "d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a72" +
                       "1c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39";
    String associated = "feedfacedeadbeeffeedfacedeadbeefabaddad2";
    String nonce = "cafebabefacedbaddecaf888";
    String nonce64 = "cafebabefacedbad";
    String nonce480 = "9313225df88406e555909c5aff5269aa6a7a9538534f7da1e4c303d2a318a728" +
                      "c3c0c95156809539fcf0e2429a6b525416aedbf5a0de6a57a637b39b";
    String zeros = "000000000000000000000000";
    String block = "00000000000000000000000000000000";
    String key128 = "feffe9928665731c6d6a8f9467308308";
    String key192 = "feffe9928665731c6d6a8f9467308308feffe9928665731c";
    String key256 = "feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308";

    CheckGcm("gcm-1", block, zeros, "", "", "", "58e2fccefa7e3061367f1d57a4e7455a");
    CheckGcm("gcm-2", block, zeros, block, "", "0388dace60b6a392f328c2b971b2fe78",
             "ab6e47d42cec13bdf53a67b21257bddf");
    CheckGcm("gcm-3", key128, nonce, plain, "",
             "42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e" +
             "21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e091473f5985",
             "4d5c2af327cd64a62cf35abd2ba6fab4");
    CheckGcm("gcm-4", key128, nonce, truncated, associated,
             "42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e" +
             "21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e091",
             "5bc94fbc3221a5db94fae95ae7121a47");
    CheckGcm("gcm-5", key128, nonce64, truncated, associated,
             "61353b4c2806934a777ff51fa22a4755699b2a714fcdc6f83766e5f97b6c7423" +
             "73806900e49f24b22b097544d4896b424989b5e1ebac0f07c23f4598",
             "3612d2e79e3b0785561be14aaca2fccb");
    CheckGcm("gcm-6", key128, nonce480, truncated, associated,
             "8ce24998625615b603a033aca13fb894be9112a5c3a211a8ba262a3cca7e2ca7" +
             "01e4a9a4fba43c90ccdcb281d48c7c6fd62875d2aca417034c34aee5",
             "619cc5aefffe0bfa462af43c1699d050");

    String block192 = "000000000000000000000000000000000000000000000000";
    CheckGcm("gcm-7", block192, zeros, "", "", "", "cd33b28ac773f74ba00ed1f312572435");
    CheckGcm("gcm-8", block192, zeros, block, "", "98e7247c07f0fe411c267e4384b0f600",
             "2ff58d80033927ab8ef4d4587514f0fb");
    CheckGcm("gcm-9", key192, nonce, plain, "",
             "3980ca0b3c00e841eb06fac4872a2757859e1ceaa6efd984628593b40ca1e19c" +
             "7d773d00c144c525ac619d18c84a3f4718e2448b2fe324d9ccda2710acade256",
             "9924a7c8587336bfb118024db8674a14");
    CheckGcm("gcm-10", key192, nonce, truncated, associated,
             "3980ca0b3c00e841eb06fac4872a2757859e1ceaa6efd984628593b40ca1e19c" +
             "7d773d00c144c525ac619d18c84a3f4718e2448b2fe324d9ccda2710",
             "2519498e80f1478f37ba55bd6d27618c");
    CheckGcm("gcm-11", key192, nonce64, truncated, associated,
             "0f10f599ae14a154ed24b36e25324db8c566632ef2bbb34f8347280fc4507057" +
             "fddc29df9a471f75c66541d4d4dad1c9e93a19a58e8b473fa0f062f7",
             "65dcc57fcf623a24094fcca40d3533f8");
    CheckGcm("gcm-12", key192, nonce480, truncated, associated,
             "d27e88681ce3243c4830165a8fdcf9ff1de9a1d8e6b447ef6ef7b79828666e45" +
             "81e79012af34ddd9e2f037589b292db3e67c036745fa22e7e9b7373b",
             "dcf566ff291c25bbb8568fc3d376a6d9");

    String block256 = block + block;
    CheckGcm("gcm-13", block256, zeros, "", "", "", "530f8afbc74536b9a963b4f1c4cb738b");
    CheckGcm("gcm-14", block256, zeros, block, "", "cea7403d4d606b6e074ec5d3baf39d18",
             "d0d1c8a799996bf0265b98b5d48ab919");
    CheckGcm("gcm-15", key256, nonce, plain, "",
             "522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa" +
             "8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f662898015ad",
             "b094dac5d93471bdec1a502270e3cc6c");
    CheckGcm("gcm-16", key256, nonce, truncated, associated,
             "522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa" +
             "8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f662",
             "76fc6ece0f4e1768cddf8853bb2d551b");
    CheckGcm("gcm-17", key256, nonce64, truncated, associated,
             "c3762df1ca787d32ae47c13bf19844cbaf1ae14d0b976afac52ff7d79bba9de0" +
             "feb582d33934a4f0954cc2363bc73f7862ac430e64abe499f47c9b1f",
             "3a337dbf46a792c45e454913fe2ea8f2");
    CheckGcm("gcm-18", key256, nonce480, truncated, associated,
             "5a8def2f0c9e53f1f75d7853659e2a20eeb2b22aafde6419a058ab4f6f746bf4" +
             "0fc0c3b780f244452da3ebf1c5d82cdea2418997200ef82e44ae7e3f",
             "a44a8266ee1c8eb0c8b5d4cf5ae9f19a");
}

byte[] MakeBytes(nuint length, nuint step, nuint start)
{
    byte[] data = new byte[length];
    for (nuint i = 0u; i < length; i++)
        data[i] = (byte)(i * step + start);
    return data;
}

bool IsSame(Result<byte[], CryptoError> result, byte[] expected)
{
    if (!result.Ok)
        return false;
    return CryptographicOperations.FixedTimeEquals(result.Value, expected);
}

// Every length from 0 to 100 bytes, so every count of blocks in a pass and
// every ragged tail is reached, in every mode, checked two ways: the digest
// of all the ciphertexts against .NET's, and each decryption against the
// plaintext it came from.
void CheckSweep(nuint keyLength, String ecb, String cbc, String cfb, String ctr, String gcm)
{
    byte[] key = MakeBytes(keyLength, 11u, keyLength);
    byte[] iv = MakeBytes(16u, 1u, 0xA0u);
    byte[] nonce = MakeBytes(12u, 1u, 0x50u);
    var cipher = Cipher(key);
    var made = AesGcm.FromKey(key);
    if (!made.Ok)
        return;
    var box = made.Value;

    var ecbHash = new Sha256();
    var cbcHash = new Sha256();
    var cfbHash = new Sha256();
    var ctrHash = new Sha256();
    var gcmHash = new Sha256();
    nuint failures = 0u;

    for (nuint length = 0u; length <= 100u; length++)
    {
        byte[] plain = MakeBytes(length, 37u, length);
        byte[] associated = MakeBytes(length % 23u, 3u, 1u);

        byte[] sealedEcb = cipher.EncryptEcb(plain, PaddingMode.Pkcs7).GetValueOrDefault(new byte[0u]);
        ecbHash.AppendData(sealedEcb);
        if (!IsSame(cipher.DecryptEcb(sealedEcb, PaddingMode.Pkcs7), plain))
            failures++;

        byte[] sealedCbc = cipher.EncryptCbc(plain, iv, PaddingMode.Pkcs7).GetValueOrDefault(new byte[0u]);
        cbcHash.AppendData(sealedCbc);
        if (!IsSame(cipher.DecryptCbc(sealedCbc, iv, PaddingMode.Pkcs7), plain))
            failures++;

        byte[] sealedCfb = cipher.EncryptCfb(plain, iv).GetValueOrDefault(new byte[0u]);
        cfbHash.AppendData(sealedCfb);
        if (!IsSame(cipher.DecryptCfb(sealedCfb, iv), plain))
            failures++;

        byte[] sealedCtr = cipher.ApplyCtr(plain, iv).GetValueOrDefault(new byte[0u]);
        ctrHash.AppendData(sealedCtr);
        if (!IsSame(cipher.ApplyCtr(sealedCtr, iv), plain))
            failures++;

        byte[] tag = new byte[16u];
        byte[] sealedGcm = box.Encrypt(nonce, plain, associated, tag).GetValueOrDefault(new byte[0u]);
        gcmHash.AppendData(sealedGcm);
        gcmHash.AppendData(tag);
        if (!IsSame(box.Decrypt(nonce, sealedGcm, associated, tag), plain))
            failures++;
    }

    String bits = Text.FromInteger((long)(keyLength * 8u));
    Check("sweep-ecb-" + bits, Convert.ToHexString(ecbHash.GetHashAndReset()), ecb);
    Check("sweep-cbc-" + bits, Convert.ToHexString(cbcHash.GetHashAndReset()), cbc);
    Check("sweep-cfb-" + bits, Convert.ToHexString(cfbHash.GetHashAndReset()), cfb);
    Check("sweep-ctr-" + bits, Convert.ToHexString(ctrHash.GetHashAndReset()), ctr);
    Check("sweep-gcm-" + bits, Convert.ToHexString(gcmHash.GetHashAndReset()), gcm);
    Console.WriteLine("round-trips-" + bits + " failed " + Text.FromInteger((long)failures));
}

void CheckEdges()
{
    // A counter whose increment carries through nine bytes inside one pass.
    var cipher = Cipher(MakeBytes(16u, 11u, 16u));
    Check("ctr-carry",
          ToHex(cipher.ApplyCtr(MakeBytes(64u, 37u, 64u), Hex("00000000000000fffffffffffffffffe"))),
          "913a230ea8a938f0e3f54001a5296f6f4ca5ad4c8d6145220824a386c7a2956b" +
          "40b4babba0ebc34915edbb1a67e92760a46689bc1a382a0a510450aa3df2a417");

    byte[] iv = new byte[16u];
    Check("cbc-short-iv", ToHex(cipher.EncryptCbc(new byte[16u], new byte[15u], PaddingMode.None)),
          "refused");
    Check("ecb-empty", ToHex(cipher.DecryptEcb(new byte[0u], PaddingMode.None)), "refused");
    Check("cbc-ragged", ToHex(cipher.DecryptCbc(new byte[17u], iv, PaddingMode.None)), "refused");
    Check("cfb-empty", ToHex(cipher.EncryptCfb(new byte[0u], iv)), "");
    Check("cfb-empty-back", ToHex(cipher.DecryptCfb(new byte[0u], iv)), "");
    Check("ctr-empty", ToHex(cipher.ApplyCtr(new byte[0u], iv)), "");
}

int Main()
{
    CheckBlocks();

    CheckModes("128", "2b7e151628aed2a6abf7158809cf4f3c",
               "3ad77bb40d7a3660a89ecaf32466ef97f5d3d58503b9699de785895a96fdbaaf" +
               "43b1cd7f598ece23881b00e3ed0306887b0c785e27e8ad3f8223207104725dd4",
               "7649abac8119b246cee98e9b12e9197d5086cb9b507219ee95db113a917678b2" +
               "73bed6b8e3c1743b7116e69e222295163ff1caa1681fac09120eca307586e1a7",
               "3b3fd92eb72dad20333449f8e83cfb4ac8a64537a0b3a93fcde3cdad9f1ce58b" +
               "26751f67a3cbb140b1808cf187a4f4dfc04b05357c5d1c0eeac4c66f9ff7f2e6",
               "874d6191b620e3261bef6864990db6ce9806f66b7970fdff8617187bb9fffdff" +
               "5ae4df3edbd5d35e5b4f09020db03eab1e031dda2fbe03d1792170a0f3009cee");
    CheckModes("192", "8e73b0f7da0e6452c810f32b809079e562f8ead2522c6b7b",
               "bd334f1d6e45f25ff712a214571fa5cc974104846d0ad3ad7734ecb3ecee4eef" +
               "ef7afd2270e2e60adce0ba2face6444e9a4b41ba738d6c72fb16691603c18e0e",
               "4f021db243bc633d7178183a9fa071e8b4d9ada9ad7dedf4e5e738763f69145a" +
               "571b242012fb7ae07fa9baac3df102e008b0e27988598881d920a9e64f5615cd",
               "cdc80d6fddf18cab34c25909c99a417467ce7f7f81173621961a2b70171d3d7a" +
               "2e1e8a1dd59b88b1c8e60fed1efac4c9c05f9f9ca9834fa042ae8fba584b09ff",
               "1abc932417521ca24f2b0459fe7e6e0b090339ec0aa6faefd5ccc2c6f4ce8e94" +
               "1e36b26bd1ebc670d1bd1d665620abf74f78a7f6d29809585a97daec58c6b050");
    CheckModes("256", "603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4",
               "f3eed1bdb5d2a03c064b5a7e3db181f8591ccb10d410ed26dc5ba74a31362870" +
               "b6ed21b99ca6f4f9f153e7b1beafed1d23304b7a39f9f3ff067d8d8f9e24ecc7",
               "f58c4c04d6e5f1ba779eabfb5f7bfbd69cfc4e967edb808d679f777bc6702c7d" +
               "39f23369a9d9bacfa530e26304231461b2eb05e2c39be9fcda6c19078c6a9d1b",
               "dc7e84bfda79164b7ecd8486985d386039ffed143b28b1c832113c6331e5407b" +
               "df10132415e54b92a13ed0a8267ae2f975a385741ab9cef82031623d55b1e471",
               "601ec313775789a5b7a7f504bbf3d228f443e3ca4d62b59aca84e990cacaf5c5" +
               "2b0930daa23de94ce87017ba2d84988ddfc9c58db67aada613c2dd08457941a6");

    CheckGcmCases();

    CheckSweep(16u,
               "5a149f540879fe11d6efc130159c19145a7a58907e32451a4725685594dff538",
               "bfb642d4650d4494d8da6354be0eb4fa49562e53ae8e242ed7106ab39be8e028",
               "5a5a7025fb4dfc398421ad2cdfa775ff22b9f95613035d40bc6d3de15d7f0b35",
               "54bfd5821997d505bfcbf7e1a139ed4b553abb8c46d8add6c6b3132c1569d83d",
               "dbb9370c843f0f9c893a9b84b74148f768ef0690d1cd68fa8fa234f6d594332c");
    CheckSweep(24u,
               "cf6bb9e57bf5a1c2aaa4adbde62b668bf2dd7cbfb0bc3a14782dbc2b816eb480",
               "2e82dfe76ca214abbde26365259d87b38c402204e8d65cff217042ab04a7ed60",
               "7e9ff417df0676e12278ad7e49826ff3a9023c5e4c8489fd2045718729d28439",
               "68f5dc5bb13aa42482886d26e51fb7919a842c568073acd2271060393b3f430d",
               "9421c08c7504b8d5798a18a4f912ebc572078af26faa2e8bfba94cb9342abd3e");
    CheckSweep(32u,
               "69f27574caeca3ac7a80c749fdfd258943bf9548e74713bedda0d0df6e4eaae2",
               "382d03023539bea41968e24bd684e47ce23e2cc9925973b2142badcedf27d1d0",
               "d9a8e2104ea9f9d1d66805687bf65a3442682faddbfb0f8f7f0cee57a9266b5f",
               "f00472e66765d448cf35cdc69e340f7d6d9bfcbc371d9d8591c72fd4cb6468d7",
               "f50f596df81bb603655ab2a886c8da1288aaebc694f7db550dfd6754a8cc90ff");

    CheckEdges();
    return 0;
}
