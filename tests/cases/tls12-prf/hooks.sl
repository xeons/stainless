// SPDX-License-Identifier: 0BSD
// The test's way into the module: this file joins Standard.Net.Security, so
// it reaches TLS 1.2's PRF, key schedule and record cipher.
module Standard.Net.Security;

import Standard.Security.Cryptography;

public byte[] ComputeTls12TestPrf(bool sha384, byte[] secret, String label, byte[] seed,
                                  nuint length)
{
    HashAlgorithmName hash = sha384 ? HashAlgorithmName.Sha384 : HashAlgorithmName.Sha256;
    return ComputeTls12Prf(hash, secret, label, seed, length);
}

public class Tls12TestKeySchedule
{
    private Tls12KeySchedule _schedule;

    public Tls12TestKeySchedule(byte[] clientRandom, byte[] serverRandom) =>
        _schedule = new Tls12KeySchedule(HashAlgorithmName.Sha256, clientRandom, serverRandom);

    public byte[] MasterSecret => _schedule._masterSecret;

    public void DeriveMasterSecret(byte[] premaster, byte[] sessionHash) =>
        _schedule.DeriveTlsExtendedMasterSecret(premaster, sessionHash);

    public byte[] ComputeKeyBlock(bool chaCha) => _schedule.ComputeTlsKeyBlock(
        chaCha ? TlsCipherSuite.TlsEcdheRsaWithChaCha20Poly1305Sha256
               : TlsCipherSuite.TlsEcdheRsaWithAes128GcmSha256);

    public byte[] ComputeClientFinished(byte[] transcriptHash) =>
        _schedule.ComputeTls12Finished(true, transcriptHash);

    /// Seals `count` records of application data holding `content`, in the
    /// direction asked, and answers the last.
    public byte[] SealRecords(bool chaCha, bool forClient, byte[] content, int count)
    {
        var suite = chaCha ? TlsCipherSuite.TlsEcdheEcdsaWithChaCha20Poly1305Sha256
                           : TlsCipherSuite.TlsEcdheEcdsaWithAes128GcmSha256;
        var cipher = _schedule.CreateTls12RecordCipher(suite, forClient);
        if (!cipher.Ok)
            return new byte[0u];
        byte[] last = new byte[0u];
        for (int i = 0; i < count; i++)
        {
            var sealedRecord = cipher.Value.SealTls12Record(
                TlsContentType.ApplicationData, content, 0u, content.Length);
            last = sealedRecord.GetValueOrDefault(new byte[0u]);
        }
        return last;
    }

    /// Opens `first` and then `second` as the first two records in a
    /// direction, and answers the second's plaintext, or nothing.
    public byte[] OpenRecords(bool chaCha, bool forClient, byte[] first, byte[] second)
    {
        var suite = chaCha ? TlsCipherSuite.TlsEcdheEcdsaWithChaCha20Poly1305Sha256
                           : TlsCipherSuite.TlsEcdheEcdsaWithAes128GcmSha256;
        var cipher = _schedule.CreateTls12RecordCipher(suite, forClient);
        if (!cipher.Ok)
            return new byte[0u];
        if (!cipher.Value.OpenTls12Record(first, 0u, first.Length - 5u).Ok)
            return new byte[0u];
        var opened = cipher.Value.OpenTls12Record(second, 0u, second.Length - 5u);
        return opened.GetValueOrDefault(new byte[0u]);
    }
}
