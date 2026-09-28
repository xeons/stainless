// SPDX-License-Identifier: 0BSD
module KeyDerivation;

import Standard.Console;
import Standard.Convert;
import Standard.Encoding;
import Standard.Text;
import Standard.Security.Cryptography;

// Every answer here is a published test vector: RFC 7914 §12 for scrypt. A
// number that changes here is a broken implementation rather than a changed
// convention.
//
// RFC 7914's fourth vector, N = 2^20, fills 1 GiB and takes about two seconds.

byte[] Bytes(String text) => Encoding.CreateUtf8().GetBytes(text);

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

int Main()
{
    CheckScrypt();
    return 0;
}
