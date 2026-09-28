// SPDX-License-Identifier: 0BSD
// TLS 1.2's PRF, key schedule and record protection, against known answers.
//
// The PRF vectors are the ones widely published for P_SHA256 and P_SHA384
// with the label "test label". The rest were computed independently, with
// Python's hmac and the cryptography package's AESGCM and ChaCha20Poly1305,
// from fixed randoms, a fixed premaster secret and fixed transcript hashes:
// the extended master secret, the key block for each IV length, a client
// Finished, and the first two records sealed in a direction, which pins the
// explicit nonce, the XOR nonce and the 13 bytes of additional data.
module Tls12Prf;

import Standard.Console;
import Standard.Convert;
import Standard.Security.Cryptography;
import Standard.Net.Security;
import Standard.Text;

byte[] Hex(String text) => Convert.FromHexString(text).GetValueOrDefault(new byte[0u]);

void Check(String name, byte[] actual, String expected)
{
    String got = Convert.ToHexString(actual);
    Console.WriteLine(name + ": " + (got == expected ? "ok" : "WRONG " + got));
}

byte[] CreateRange(uint first, nuint count)
{
    var bytes = new byte[count];
    for (nuint i = 0u; i < count; i++)
        bytes[i] = (byte)(first + (uint)i);
    return bytes;
}

byte[] HashText(String text) => Sha256.HashData(text.ToBytes());

int Main()
{
    Check("prf sha256",
          ComputeTls12TestPrf(false, Hex("9bbe436ba940f017b17652849a71db35"), "test label",
                              Hex("a0ba9f936cda311827a6f796ffd5198c"), 100u),
          "e3f229ba727be17b8d122620557cd453c2aab21d07c3d495329b52d4e61edb5a" +
          "6b301791e90d35c9c9a46b4e14baf9af0fa022f7077def17abfd3797c0564bab" +
          "4fbc91666e9def9b97fce34f796789baa48082d122ee42c5a72e5a5110fff701" +
          "87347b66");
    Check("prf sha384",
          ComputeTls12TestPrf(true, Hex("b80b733d6ceefcdc71566ea48e5567df"), "test label",
                              Hex("cd665cf6a8447dd6ff8b27555edb7465"), 148u),
          "7b0c18e9ced410ed1804f2cfa34a336a1c14dffb4900bb5fd7942107e81c83cd" +
          "e9ca0faa60be9fe34f82b1233c9146a0e534cb400fed2700884f9dc236f80edd" +
          "8bfa961144c9e8d792eca722a7b32fc3d416d473ebc2c5fd4abfdad05d918425" +
          "9b5bf8cd4d90fa0d31e2dec479e4f1a26066f2eea9a69236a3e52655c9e9aee6" +
          "91c8f3a26854308d5eaa3be85e0990703d73e56f");

    var schedule = new Tls12TestKeySchedule(CreateRange(0x00u, 32u), CreateRange(0x70u, 32u));
    schedule.DeriveMasterSecret(CreateRange(0x40u, 32u), HashText("the handshake"));
    Check("extended master secret", schedule.MasterSecret,
          "12ee48c23344d164d22124ac9ff2ca33633c339954374b7a2b4dafde350453b8" +
          "943e05dd7c8c78205a3ac637a48fc14f");
    Check("key block, AES-128-GCM", schedule.ComputeKeyBlock(false),
          "5b7309ca146fcd2b080e8f33fad9a52362b04fd57ce7a00cb4f4f5b81a958dd5" +
          "56f0d893fd12bac9");
    Check("key block, ChaCha20-Poly1305", schedule.ComputeKeyBlock(true),
          "5b7309ca146fcd2b080e8f33fad9a52362b04fd57ce7a00cb4f4f5b81a958dd5" +
          "56f0d893fd12bac94dd8f5fd5dc03c05f36a692ffe1d2eaf7a63492bd70c1fed" +
          "afdb4294edb34e59084d6b1fdac5e7a7d49cac3347d436de");
    Check("client finished", schedule.ComputeClientFinished(HashText("the transcript")),
          "6e6f1c3d2f572f63f6472994");

    byte[] content = "hello, TLS 1.2".ToBytes();
    String gcm0 = "17030300260000000000000000e5d2f1888e71a83eb3e0d9169eb0fe75f915126774" +
                  "3f28d41fa7df83a3fe";
    String gcm1 = "170303002600000000000000015ca37fff708379cdc0919bf27b4698757dafe3aeb5" +
                  "d0da3eec79450ba62d";
    String chaCha0 = "170303001e0d56b6c76ab0b3fad7274aea7828c86d47dc08bc81f8b7bf0a1d1579a956";
    String chaCha1 = "170303001e10c047a85d81cc5ddd76b0202cab1b7f6f871d87ef088f4aad4d2e67dbea";
    Check("AES-GCM client record 0", schedule.SealRecords(false, true, content, 1), gcm0);
    Check("AES-GCM client record 1", schedule.SealRecords(false, true, content, 2), gcm1);
    Check("ChaCha20 server record 0", schedule.SealRecords(true, false, content, 1), chaCha0);
    Check("ChaCha20 server record 1", schedule.SealRecords(true, false, content, 2), chaCha1);
    Check("AES-GCM client records open",
          schedule.OpenRecords(false, true, Hex(gcm0), Hex(gcm1)), "68656c6c6f2c20544c5320312e32");
    Check("ChaCha20 server records open",
          schedule.OpenRecords(true, false, Hex(chaCha0), Hex(chaCha1)),
          "68656c6c6f2c20544c5320312e32");

    byte[] tampered = Hex(gcm1);
    tampered[20u] ^= 0x01;
    Check("AES-GCM tampered record refused",
          schedule.OpenRecords(false, true, Hex(gcm0), tampered), "");
    Check("records out of order refused",
          schedule.OpenRecords(true, false, Hex(chaCha1), Hex(chaCha0)), "");
    return 0;
}
