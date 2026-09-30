// SPDX-License-Identifier: 0BSD
// The test's way into the module: this file joins Standard.Net.Security to
// run a client that sends 0-RTT data a server never accepted, to set a
// server's retry to a cookie alone, and to read a record cipher's sequence
// number, a buffer's overflow and a connection's secrets.
module Standard.Net.Security;

import Standard.IO;
import Standard.Security.Cryptography;

/// Makes `options` send a HelloRetryRequest with a cookie and no key_share.
public void SetTlsTestCookieRetry(TlsServerOptions options) =>
    options._retryWithCookieAlone = true;

/// `hello` with an empty extension of `type` added at the end.
byte[] AddTlsTestExtension(byte[] hello, uint type)
{
    nuint at = 4u + 2u + 32u;
    at += 1u + (nuint)hello[at];
    at += 2u + (((nuint)hello[at] << 8) | (nuint)hello[at + 1u]);
    at += 1u + (nuint)hello[at];

    var patched = new byte[hello.Length + 4u];
    for (nuint i = 0u; i < hello.Length; i++)
        patched[i] = hello[i];
    patched[hello.Length] = (byte)(type >> 8);
    patched[hello.Length + 1u] = (byte)(type & 0xFFu);

    nuint body = hello.Length - 4u + 4u;
    patched[1u] = (byte)(body >> 16);
    patched[2u] = (byte)((body >> 8) & 0xFFu);
    patched[3u] = (byte)(body & 0xFFu);
    nuint extensions = (((nuint)hello[at] << 8) | (nuint)hello[at + 1u]) + 4u;
    patched[at] = (byte)(extensions >> 8);
    patched[at + 1u] = (byte)(extensions & 0xFFu);
    return patched;
}

/// A TLS 1.3 client that offers early_data and sends `earlyBytes` of it in
/// records of 1000 bytes, which the server cannot open, before going on
/// with the handshake as usual.
public TlsError RunTlsClientWithEarlyData(IStream inner, TlsClientOptions options,
                                          nuint earlyBytes)
{
    options.EnabledProtocols = TlsProtocolVersion.Tls13;
    options._fixedX25519PrivateKey = X25519.GeneratePrivateKey();
    var connection = new TlsConnection(inner, false, true);
    var builder = new TlsClientHandshake(connection, options, options.TargetHost);
    TlsError step = builder.GenerateTlsKeyShares();
    if (step != TlsError.None)
        return step;
    var built = builder.BuildTlsClientHello();
    if (!built.Ok)
        return built.Error;
    options._fixedClientHello = AddTlsTestExtension(
        built.Value, (uint)TlsExtensionType.EarlyData);

    var handshake = new TlsClientHandshake(connection, options, options.TargetHost);
    step = handshake.SendTlsClientHello();
    var junk = new byte[1000u];
    for (nuint sent = 0u; sent < earlyBytes && step == TlsError.None; sent += 1000u)
        step = connection._records.WriteTlsRecord(TlsContentType.ApplicationData, junk, 0u, 1000u);
    if (step == TlsError.None)
        step = handshake.ReadTlsServerHello();
    if (step == TlsError.None)
        step = handshake.ReadTlsEncryptedExtensions();
    if (step == TlsError.None)
        step = handshake.ReadTlsServerAuthentication();
    if (step == TlsError.None)
        step = handshake.SendTlsClientFinished();
    if (step != TlsError.None)
    {
        connection.AbandonTls(step);
        return step;
    }
    connection.CloseTls();
    return TlsError.None;
}

/// What a second ClientHello answers when the cookie it echoes is `size`
/// bytes: one near the most a HelloRetryRequest can carry does not fit
/// beside the rest.
public TlsError BuildTlsTestRetryWithCookie(TlsClientOptions options, nuint size)
{
    var connection = new TlsConnection(new MemoryStream(), false, true);
    var handshake = new TlsClientHandshake(connection, options, options.TargetHost);
    TlsError step = handshake.GenerateTlsKeyShares();
    if (step != TlsError.None)
        return step;
    handshake._retried = true;
    handshake._offered._hasCookie = true;
    handshake._offered._cookie = new byte[size];
    var built = handshake.BuildTlsClientHello();
    return built.Ok ? TlsError.None : built.Error;
}

/// Whether a length prefix of `prefixSize` bytes holds `size`.
public bool FitsTlsTestVector(nuint prefixSize, nuint size)
{
    var buffer = new TlsBuffer(16u);
    nuint at = buffer.BeginVector(prefixSize);
    buffer.WriteBytes(new byte[size]);
    buffer.EndVector(at, prefixSize);
    return !buffer.HasOverflowed;
}

/// Seals two records with a cipher whose sequence number starts two short of
/// the end, and answers what each gave.
public String SealTlsTestRecordsAtSequenceEnd(bool tls12)
{
    Result<TlsRecordCipher, TlsError> created = Fail(TlsError.InternalError);
    if (tls12)
    {
        created = TlsRecordCipher.CreateTls12(
            TlsCipherSuite.TlsEcdheEcdsaWithAes128GcmSha256, new byte[16u], new byte[4u]);
    }
    else
    {
        created = TlsRecordCipher.Create(
            TlsCipherSuite.TlsAes128GcmSha256, new byte[16u], new byte[12u]);
    }
    if (!created.Ok)
        return "no cipher";
    TlsRecordCipher cipher = created.Value;
    cipher.SetTlsSequence(0xFFFFFFFFFFFFFFFDul);

    String outcome = "";
    for (int i = 0; i < 3; i++)
    {
        var data = new byte[5u];
        Result<byte[], TlsError> sealedRecord = tls12
            ? cipher.SealTls12Record(TlsContentType.ApplicationData, data, 0u, 4u)
            : cipher.SealTlsRecord(data, 5u);
        outcome = outcome + (i == 0 ? "" : ", ") +
                  (sealedRecord.Ok ? "sealed" : DescribeTlsError(sealedRecord.Error));
    }
    return outcome;
}

/// Whether every secret the connection under `stream` holds is zeros.
public bool AreTlsTestSecretsWiped(TlsStream stream)
{
    TlsConnection connection = stream._connection;
    bool wiped = IsTlsTestZero(connection._readTrafficSecret) &&
                 IsTlsTestZero(connection._writeTrafficSecret);
    var schedule = connection._schedule;
    if (schedule != null)
    {
        wiped = wiped && IsTlsTestZero(schedule._exporterMasterSecret) &&
                IsTlsTestZero(schedule._resumptionMasterSecret) &&
                IsTlsTestZero(schedule._handshakeSecret);
    }
    var legacy = connection._tls12Schedule;
    if (legacy != null)
        wiped = wiped && IsTlsTestZero(legacy._masterSecret);
    return wiped;
}

/// Whether the handshake-only secrets of the TLS 1.3 connection under
/// `stream` are zeros, while the exporter secret is not.
public bool AreTlsTestHandshakeSecretsWiped(TlsStream stream)
{
    var schedule = stream._connection._schedule;
    if (schedule == null)
        return false;
    return IsTlsTestZero(schedule._handshakeSecret) &&
           IsTlsTestZero(schedule._clientHandshakeTrafficSecret) &&
           IsTlsTestZero(schedule._serverHandshakeTrafficSecret) &&
           IsTlsTestZero(schedule._masterSecret) &&
           !IsTlsTestZero(schedule._exporterMasterSecret);
}

bool IsTlsTestZero(byte[] bytes)
{
    for (nuint i = 0u; i < bytes.Length; i++)
    {
        if (bytes[i] != 0)
            return false;
    }
    return true;
}
