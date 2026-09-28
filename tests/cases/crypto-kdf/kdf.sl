// SPDX-License-Identifier: 0BSD
module KeyDerivation;

import Standard.Console;
import Standard.Convert;
import Standard.Encoding;
import Standard.Text;
import Standard.Security.Cryptography;

// Every answer here is a published test vector: RFC 7914 §12 for scrypt,
// RFC 7693 Appendix A for BLAKE2b-512 and RFC 9106 §5.3 for Argon2id. The
// other BLAKE2b answers are the reference implementation's, the keyed one
// from the BLAKE2 known-answer file, and the second Argon2id answer is from
// the test.c of the Argon2 reference implementation. A number that changes
// here is a broken implementation rather than a changed convention.
//
// RFC 7914's fourth vector, N = 2^20, fills 1 GiB and takes about two seconds.

byte[] Bytes(String text) => Encoding.CreateUtf8().GetBytes(text);

byte[] Hex(String text) => Convert.FromHexString(text).GetValueOrDefault(new byte[0u]);

byte[] Repeat(byte value, nuint count)
{
    byte[] data = new byte[count];
    for (nuint i = 0u; i < count; i++)
        data[i] = value;
    return data;
}

byte[] CountUpTo(nuint count)
{
    byte[] data = new byte[count];
    for (nuint i = 0u; i < count; i++)
        data[i] = (byte)i;
    return data;
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

String DeriveScryptKey(String password, String salt, nuint cost, nuint blockSize, nuint parallelism,
                       nuint length)
{
    var derived = Scrypt.DeriveKey(Bytes(password), Bytes(salt), cost, blockSize, parallelism,
                                   length);
    if (!derived.Ok)
        return "refused";
    return Convert.ToHexString(derived.Value);
}

void CheckScrypt()
{
    Check("scrypt-16", DeriveScryptKey("", "", 16u, 1u, 1u, 64u),
          "77d6576238657b203b19ca42c18a0497f16b4844e3074ae8dfdffa3fede21442" +
          "fcd0069ded0948f8326a753a0fc81f17e8d3e0fb2e0d3628cf35e20c38d18906");
    Check("scrypt-1024", DeriveScryptKey("password", "NaCl", 1024u, 8u, 16u, 64u),
          "fdbabe1c9d3472007856e7190d01e9fe7c6ad7cbc8237830e77376634b373162" +
          "2eaf30d92e22a3886ff109279d9830dac727afb94a83ee6d8360cbdfa2cc0640");
    Check("scrypt-16384", DeriveScryptKey("pleaseletmein", "SodiumChloride", 16384u, 8u, 1u, 64u),
          "7023bdcb3afd7348461c06cd81fd38ebfda8fbba904f8e3ea9b543f6545da1f2" +
          "d5432955613f0fcf62d49705242a9af9e61e85dc0d651e40dfcf017b45575887");
    Check("scrypt-1048576",
          DeriveScryptKey("pleaseletmein", "SodiumChloride", 1048576u, 8u, 1u, 64u),
          "2101cb9b6a511aaeaddbbe09cf70f881ec568d574a2ffd4dabe5ee9820adaa47" +
          "8e56fd8f4ba5d09ffa1c6d927c40f4c337304049e8a952fbcbf45c6fa77a41a4");

    // The output is PBKDF2 over the mixed blocks, so a shorter request is a
    // prefix of a longer one.
    Check("scrypt-short", DeriveScryptKey("", "", 16u, 1u, 1u, 16u),
          "77d6576238657b203b19ca42c18a0497");

    Check("scrypt-cost-odd", DeriveScryptKey("p", "s", 1000u, 8u, 1u, 32u), "refused");
    Check("scrypt-cost-one", DeriveScryptKey("p", "s", 1u, 8u, 1u, 32u), "refused");
    Check("scrypt-block-zero", DeriveScryptKey("p", "s", 16u, 0u, 1u, 32u), "refused");
    Check("scrypt-parallel-zero", DeriveScryptKey("p", "s", 16u, 1u, 0u, 32u), "refused");
    Check("scrypt-length-zero", DeriveScryptKey("p", "s", 16u, 1u, 1u, 0u), "refused");
    Check("scrypt-width", DeriveScryptKey("p", "s", 16u, 0x8000u, 0x8000u, 32u), "refused");
    Check("scrypt-cost-for-width", DeriveScryptKey("p", "s", 65536u, 1u, 1u, 32u), "refused");
    Check("scrypt-memory", DeriveScryptKey("p", "s", 8388608u, 8u, 1u, 32u), "refused");
}

String HashKeyed(byte[] key, nuint hashSize, byte[] data)
{
    var made = Blake2b.FromKey(key, hashSize);
    if (!made.Ok)
        return "refused";

    var hash = made.Value;
    hash.AppendData(data);
    return Convert.ToHexString(hash.GetHashAndReset());
}

void CheckBlake2b()
{
    Check("blake2b-abc", Convert.ToHexString(Blake2b.HashData(Bytes("abc"))),
          "ba80a53f981c4d0d6a2797b69f12f6e94c212f14685ac4b74b12bb6fdbffa2d1" +
          "7d87c5392aab792dc252d5de4533cc9518d38aa8dbf1925ab92386edd4009923");
    Check("blake2b-empty", Convert.ToHexString(Blake2b.HashData(new byte[0u])),
          "786a02f742015903c6c6fd852552d272912f4740e15847618a86e217f71f5419" +
          "d25e1031afee585313896444934eb04b903a685b1448b755d56f701afe9be2ce");

    // Exactly one block is the case the held-back last block exists for: it
    // has to be compressed as the final one, not as a middle one.
    Check("blake2b-one-block", Convert.ToHexString(Blake2b.HashData(CountUpTo(128u))),
          "2319e3789c47e2daa5fe807f61bec2a1a6537fa03f19ff32e87eecbfd64b7e0e" +
          "8ccff439ac333b040f19b0c4ddd11a61e24ac1fe0f10a039806c5dcc0da3d115");

    // A shorter digest is its own function rather than a prefix, and the
    // pieces straddle the block boundary.
    var made = Blake2b.FromKey(new byte[0u], 32u);
    if (made.Ok)
    {
        var pieces = made.Value;
        byte[] data = CountUpTo(200u);
        pieces.AppendData(data[:100u]);
        pieces.AppendData(data[100u:130u]);
        pieces.AppendData(data[130u:]);
        Check("blake2b-256-pieces", Convert.ToHexString(pieces.GetHashAndReset()),
              "63c3d97a9f8894d5e043a707b0fee7f7ec4c049a23bbf1079df20b4165f9e22d");
        Check("blake2b-name", pieces.Name, "BLAKE2b-256");
    }

    Check("blake2b-keyed-empty", HashKeyed(CountUpTo(64u), 64u, new byte[0u]),
          "10ebb67700b1868efb4417987acf4690ae9d972fb7a590c2f02871799aaa4786" +
          "b5e996e8f0f4eb981fc214b005f42d2ff4233499391653df7aefcbc13fc51568");
    Check("blake2b-keyed-160", HashKeyed(CountUpTo(64u), 20u, CountUpTo(3u)),
          "1da6545578fa6ff5068e1a183ce781e61f68fb51");

    Check("blake2b-long-key", HashKeyed(new byte[65u], 64u, new byte[0u]), "refused");
    Check("blake2b-no-size", HashKeyed(new byte[0u], 0u, new byte[0u]), "refused");
    Check("blake2b-wide", HashKeyed(new byte[0u], 65u, new byte[0u]), "refused");
}

String DeriveArgonKey(nuint iterations, nuint memoryKiB, nuint parallelism, nuint length,
                      byte[] salt)
{
    var derived = Argon2id.DeriveKey(Repeat((byte)1, 32u), salt, iterations, memoryKiB,
                                     parallelism, length, Repeat((byte)3, 8u),
                                     Repeat((byte)4, 12u));
    if (!derived.Ok)
        return "refused";
    return Convert.ToHexString(derived.Value);
}

void CheckArgon2id()
{
    // RFC 9106 §5.3: four lanes, three passes, 32 KiB, with a secret and
    // associated data.
    byte[] salt = Repeat((byte)2, 16u);
    Check("argon2id-9106", DeriveArgonKey(3u, 32u, 4u, 32u, salt),
          "0d640df58d78766c08c037a34a8b53c9d01ef0452d75b65eb52520e96b01e659");

    // One lane, two passes and 64 MiB, with no secret and no associated data.
    var bare = Argon2id.DeriveKey(Bytes("password"), Bytes("somesalt"), 2u, 65536u, 1u, 32u);
    Check("argon2id-64-mib", Convert.ToHexString(bare.GetValueOrDefault(new byte[0u])),
          "09316115d5cf24ed5a15a31a3ba326e5cf32edc24702987c02b6566f61913cf7");

    // The short form is the long one with the two left empty.
    var empty = Argon2id.DeriveKey(Bytes("password"), Bytes("somesalt"), 2u, 65536u, 1u, 32u,
                                   new byte[0u], new byte[0u]);
    Check("argon2id-overload", Convert.ToHexString(empty.GetValueOrDefault(new byte[0u])),
          "09316115d5cf24ed5a15a31a3ba326e5cf32edc24702987c02b6566f61913cf7");

    // A tag longer than one BLAKE2b digest is chained from several.
    Console.WriteLine(DeriveArgonKey(1u, 37u, 2u, 100u, salt).ByteLength() == 200u
        ? "argon2id-long-tag ok" : "argon2id-long-tag WRONG");

    Check("argon2id-no-passes", DeriveArgonKey(0u, 32u, 4u, 32u, salt), "refused");
    Check("argon2id-short-memory", DeriveArgonKey(1u, 31u, 4u, 32u, salt), "refused");
    Check("argon2id-no-lanes", DeriveArgonKey(1u, 32u, 0u, 32u, salt), "refused");
    Check("argon2id-short-tag", DeriveArgonKey(1u, 32u, 4u, 3u, salt), "refused");
    Check("argon2id-short-salt", DeriveArgonKey(1u, 32u, 4u, 32u, Repeat((byte)2, 7u)), "refused");
    Check("argon2id-memory", DeriveArgonKey(1u, 8388608u, 1u, 32u, salt), "refused");
}

int Main()
{
    CheckScrypt();
    CheckBlake2b();
    CheckArgon2id();
    return 0;
}
