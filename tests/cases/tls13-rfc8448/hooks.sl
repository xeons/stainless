// SPDX-License-Identifier: 0BSD
// The test's way into the module: this file joins Standard.Net.Security, so
// it reaches the key schedule, the record cipher and the options' fixed
// randomness, and hands them on as public members the test can call.
module Standard.Net.Security;

import Standard.Security.Cryptography;

public class TlsTestKeySchedule
{
    private TlsKeySchedule _schedule;

    public TlsTestKeySchedule() => _schedule = new TlsKeySchedule(HashAlgorithmName.Sha256);

    public byte[] EarlySecret => _schedule._earlySecret;
    public byte[] HandshakeSecret => _schedule._handshakeSecret;
    public byte[] ClientHandshakeTraffic => _schedule._clientHandshakeTrafficSecret;
    public byte[] ServerHandshakeTraffic => _schedule._serverHandshakeTrafficSecret;
    public byte[] MasterSecret => _schedule._masterSecret;
    public byte[] ClientApplicationTraffic => _schedule._clientApplicationTrafficSecret;
    public byte[] ServerApplicationTraffic => _schedule._serverApplicationTrafficSecret;
    public byte[] ExporterMaster => _schedule._exporterMasterSecret;
    public byte[] ResumptionMaster => _schedule._resumptionMasterSecret;

    public byte[] HashTranscript(byte[] messages) => _schedule.HashTlsBytes(messages);

    public void DeriveHandshake(byte[] shared, byte[] helloHash) =>
        _schedule.DeriveHandshakeSecrets(shared, helloHash);

    public void DeriveApplication(byte[] serverFinishedHash) =>
        _schedule.DeriveApplicationSecrets(serverFinishedHash);

    public void DeriveResumption(byte[] clientFinishedHash) =>
        _schedule.DeriveResumptionSecret(clientFinishedHash);

    public byte[] ExpandLabel(byte[] secret, String label, nuint length) =>
        _schedule.ExpandTlsLabel(secret, label, new byte[0u], length);

    public byte[] ComputeFinished(byte[] baseSecret, byte[] transcriptHash) =>
        _schedule.ComputeTlsFinished(baseSecret, transcriptHash);

    public byte[] DeriveResumptionKey(byte[] nonce) => _schedule.DeriveTlsResumptionKey(nonce);
}

/// Seals `content` of `type` as the first record under a traffic secret.
public byte[] SealTlsTestRecord(byte[] trafficSecret, byte type, byte[] content)
{
    var cipher = CreateTlsTestCipher(trafficSecret);
    if (!cipher.Ok)
        return new byte[0u];
    var inner = new byte[content.Length + 1u];
    for (nuint i = 0u; i < content.Length; i++)
        inner[i] = content[i];
    inner[content.Length] = type;
    var record = cipher.Value.SealTlsRecord(inner, inner.Length);
    return record.Ok ? record.Value : new byte[0u];
}

/// Opens the first record under a traffic secret, answering the inner
/// plaintext with its type byte still on the end, or nothing.
public byte[] OpenTlsTestRecord(byte[] trafficSecret, byte[] record)
{
    var cipher = CreateTlsTestCipher(trafficSecret);
    if (!cipher.Ok)
        return new byte[0u];
    var opened = cipher.Value.OpenTlsRecord(record, 0u, record.Length - 5u);
    return opened.Ok ? opened.Value : new byte[0u];
}

Result<TlsRecordCipher, TlsError> CreateTlsTestCipher(byte[] trafficSecret)
{
    var schedule = new TlsKeySchedule(HashAlgorithmName.Sha256);
    return schedule.CreateTlsRecordCipher(TlsCipherSuite.TlsAes128GcmSha256, trafficSecret);
}

public void FixTlsTestClientHello(TlsClientOptions options, byte[] clientHello, byte[] x25519PrivateKey)
{
    options._fixedClientHello = clientHello;
    options._fixedX25519PrivateKey = x25519PrivateKey;
}

public void FixTlsTestServerRandom(TlsServerOptions options, byte[] random, byte[] x25519PrivateKey)
{
    options._fixedRandom = random;
    options._fixedX25519PrivateKey = x25519PrivateKey;
}
