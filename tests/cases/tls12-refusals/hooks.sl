// SPDX-License-Identifier: 0BSD
// Misbehaving peers built from the real ones' steps: this file joins
// Standard.Net.Security so that it can run a TLS 1.2 client's handshake a
// step at a time and send a Finished that is wrong, and send a handshake
// message after the handshake, where only a renegotiation would put one.
module Standard.Net.Security;

import Standard.Console;
import Standard.IO;

/// Runs a TLS 1.2 client handshake that sends a Finished with one bit set
/// that should not be, and answers how the server's reply ended it.
public TlsError RunTls12ClientWithWrongFinished(IStream inner, TlsClientOptions options)
{
    var connection = new TlsConnection(inner, false, true);
    var handshake = new TlsClientHandshake(connection, options, options.TargetHost);
    TlsError step = handshake.SendTlsClientHello();
    if (step == TlsError.None)
        step = handshake.ReadTlsServerHello();
    var legacy = handshake._tls12;
    if (step != TlsError.None || legacy == null)
        return step == TlsError.None ? TlsError.ProtocolVersion : step;
    step = legacy.ReadTls12ServerFlight();
    var schedule = legacy._schedule;
    if (step != TlsError.None || schedule == null)
        return step;

    var share = TlsKeyShare.GenerateTlsKeyShare(legacy._group);
    if (!share.Ok)
        return share.Error;
    var premaster = share.Value.DeriveTlsSharedSecret(legacy._serverPoint);
    if (!premaster.Ok)
        return premaster.Error;
    var exchange = new TlsBuffer(128u);
    nuint body = BeginTlsHandshakeMessage(exchange, TlsHandshakeType.ClientKeyExchange);
    nuint pointAt = exchange.BeginVector(1u);
    exchange.WriteBytes(share.Value.PublicKey);
    exchange.EndVector(pointAt, 1u);
    EndTlsHandshakeMessage(exchange, body);
    legacy.QueueTls12ClientMessage(exchange.ToArray());
    schedule.DeriveTlsExtendedMasterSecret(
        premaster.Value, legacy._transcript.ComputeTls12TranscriptHash(schedule));
    connection.FlushTlsHandshake();
    connection.WriteTlsChangeCipherSpec();
    var writing = schedule.CreateTls12RecordCipher(legacy._suite, true);
    if (!writing.Ok)
        return writing.Error;
    connection.InstallTlsWriteCipher(writing.Value);

    byte[] wrong = schedule.ComputeTls12Finished(
        true, legacy._transcript.ComputeTls12TranscriptHash(schedule));
    wrong[0u] ^= 0x01;
    connection.QueueTlsHandshakeMessage(BuildTlsFinished(wrong));
    connection.FlushTlsHandshake();

    // The server has no write key yet, so its alert comes in plaintext,
    // where its change_cipher_spec would have.
    TlsError reply = connection.ReadTlsChangeCipherSpec();
    if (reply == TlsError.AlertReceived)
        Console.WriteLine("  client heard: " + $"{connection._alertReceived}");
    return reply;
}

/// One end of a connection whose handshake has finished, which can also
/// send a bare handshake message under the current key.
public class Tls12TestPeer
{
    private TlsConnection _connection;
    private TlsStream _stream;

    internal Tls12TestPeer(TlsConnection connection)
    {
        _connection = connection;
        _stream = TlsStream.WrapTlsConnection(connection);
    }

    public TlsStream Stream => _stream;

    /// The last warning the peer sent that was passed over.
    public TlsAlertDescription WarningReceived => _connection._warningReceived;

    public TlsError SendHandshakeMessage(byte[] message)
    {
        _connection.QueueTlsHandshakeMessage(message);
        return _connection.FlushTlsHandshake();
    }
}

public Result<Tls12TestPeer, TlsError> ConnectTls12TestPeer(IStream inner, TlsClientOptions options)
{
    var connection = new TlsConnection(inner, false, false);
    var handshake = new TlsClientHandshake(connection, options, options.TargetHost);
    TlsError failed = handshake.RunTlsClientHandshake();
    if (failed != TlsError.None)
    {
        connection.AbandonTls(failed);
        return Fail(failed);
    }
    return Ok(new Tls12TestPeer(connection));
}

public Result<Tls12TestPeer, TlsError> AcceptTls12TestPeer(IStream inner, TlsServerOptions options)
{
    var connection = new TlsConnection(inner, true, false);
    var handshake = new TlsServerHandshake(connection, options);
    TlsError failed = handshake.RunTlsServerHandshake();
    if (failed != TlsError.None)
    {
        connection.AbandonTls(failed);
        return Fail(failed);
    }
    return Ok(new Tls12TestPeer(connection));
}

/// The last warning a stream's peer sent that was passed over.
public TlsAlertDescription GetTls12TestWarning(TlsStream stream) =>
    stream._connection._warningReceived;
