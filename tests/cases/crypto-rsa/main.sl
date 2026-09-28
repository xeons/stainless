// SPDX-License-Identifier: 0BSD
module RsaCase;

import Standard.Console;
import Standard.Security.Cryptography;

// The known answers, then one key made here. A generated key has nothing to
// compare against, so it is asked to sign and verify, encrypt and decrypt,
// and to survive its own export and import.

void CheckKeyGeneration()
{
    Check("key size 1000", DescribeKey(Rsa.Create(1000)), "KeyLength");
    Check("key size 256", DescribeKey(Rsa.Create(256)), "KeyLength");

    var created = Rsa.Create(2048);
    if (!created.Ok)
    {
        Console.WriteLine("generate refused");
        return;
    }
    Rsa key = created.Value;
    byte[] message = Bytes("made here");

    var signature = key.SignData(message, HashAlgorithmName.Sha256, RsaSignaturePadding.Pss);
    bool signs = signature.Ok &&
                 key.VerifyData(message, signature.Value, HashAlgorithmName.Sha256,
                                RsaSignaturePadding.Pss);

    var encrypted = key.Encrypt(message, RsaEncryptionPadding.OaepSha256);
    bool decrypts = encrypted.Ok &&
                    DescribeBytes(key.Decrypt(encrypted.Value, RsaEncryptionPadding.OaepSha256)) ==
                    ToHex(message);

    var exported = key.ExportPkcs8PrivateKey();
    bool survives = exported.Ok && Rsa.ImportPkcs8PrivateKey(exported.Value).Ok;

    CheckTrue("generated 2048", key.KeySize == 2048 && signs && decrypts && survives);
}

int Main()
{
    CheckRsaVectors();
    CheckKeyGeneration();
    return 0;
}
