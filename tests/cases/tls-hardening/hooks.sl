// SPDX-License-Identifier: 0BSD
// Peers that misbehave in ways the real ones never do: this file joins
// Standard.Net.Security so that it can parse a ClientHello built by hand,
// write raw records under a connection's key, and run a TLS 1.2 server a step
// at a time.
module Standard.Net.Security;

import Standard.Collections;
import Standard.IO;

/// A ClientHello offering TLS 1.3 with `extensions`, each already laid out as
/// a type, a length and its data.
public byte[] BuildTlsTestClientHello(byte[] extensions)
{
    var message = new TlsBuffer(extensions.Length + 128u);
    nuint body = BeginTlsHandshakeMessage(message, TlsHandshakeType.ClientHello);
    message.WriteUInt16(0x0303u);
    message.WriteBytes(new byte[32u]);
    message.WriteByte(0u);
    message.WriteUInt16(2u);
    message.WriteUInt16(0x1301u);
    message.WriteByte(1u);
    message.WriteByte(0u);
    nuint extensionsAt = message.BeginVector(2u);
    message.WriteBytes(extensions);
    message.EndVector(extensionsAt, 2u);
    EndTlsHandshakeMessage(message, body);
    return message.ToArray();
}

/// `count` distinct empty extensions of types from `first` up, then a repeat
/// of the first when `repeatFirst`.
public byte[] BuildTlsTestExtensions(uint first, nuint count, bool repeatFirst)
{
    var extensions = new TlsBuffer(4u * count + 4u);
    for (nuint i = 0u; i < count; i++)
    {
        extensions.WriteUInt16(first + (uint)i);
        extensions.WriteUInt16(0u);
    }
    if (repeatFirst)
    {
        extensions.WriteUInt16(first);
        extensions.WriteUInt16(0u);
    }
    return extensions.ToArray();
}

/// supported_groups naming `supported`, and a key_share with a 32-byte share
/// in each of `shared`.
public byte[] BuildTlsTestKeyShareExtensions(List<uint> supported, List<uint> shared)
{
    var extensions = new TlsBuffer(256u);
    nuint groupsAt = BeginTlsExtension(extensions, TlsExtensionType.SupportedGroups);
    nuint groupListAt = extensions.BeginVector(2u);
    for (nuint i = 0u; i < supported.Count; i++)
        extensions.WriteUInt16(supported[i]);
    extensions.EndVector(groupListAt, 2u);
    EndTlsExtension(extensions, groupsAt);

    nuint sharesAt = BeginTlsExtension(extensions, TlsExtensionType.KeyShare);
    nuint shareListAt = extensions.BeginVector(2u);
    for (nuint i = 0u; i < shared.Count; i++)
    {
        extensions.WriteUInt16(shared[i]);
        nuint keyAt = extensions.BeginVector(2u);
        extensions.WriteBytes(new byte[32u]);
        extensions.EndVector(keyAt, 2u);
    }
    extensions.EndVector(shareListAt, 2u);
    EndTlsExtension(extensions, sharesAt);
    return extensions.ToArray();
}

/// What parsing `message` as a ClientHello answers.
public TlsError ParseTlsTestClientHello(byte[] message)
{
    var parsed = TlsClientHello.ParseTlsClientHello(message);
    return parsed.Ok ? TlsError.None : parsed.Error;
}

/// One end of a connection whose handshake has finished, which can also
/// write records the real one never would.
public class TlsTestPeer
{
    private TlsConnection _connection;
    private TlsStream _stream;

    internal TlsTestPeer(TlsConnection connection)
    {
        _connection = connection;
        _stream = TlsStream.WrapTlsConnection(connection);
    }

    public TlsStream Stream => _stream;

    /// Writes an alert of `level` and `description` under the current key.
    public TlsError SendRawAlert(byte level, byte description)
    {
        var alert = new byte[2u];
        alert[0u] = level;
        alert[1u] = description;
        return _connection._records.WriteTlsRecords(TlsContentType.Alert, alert, 0u, 2u);
    }

    /// Writes a record of application data with nothing in it.
    public TlsError SendEmptyRecord()
    {
        var nothing = new byte[1u];
        return _connection._records.WriteTlsRecord(
            TlsContentType.ApplicationData, nothing, 0u, 0u);
    }
}

public Result<TlsTestPeer, TlsError> AcceptTlsTestPeer(IStream inner, TlsServerOptions options)
{
    var connection = new TlsConnection(inner, true, false);
    var handshake = new TlsServerHandshake(connection, options);
    TlsError failed = handshake.RunTlsServerHandshake();
    if (failed != TlsError.None)
    {
        connection.AbandonTls(failed);
        return Fail(failed);
    }
    return Ok(new TlsTestPeer(connection));
}

/// A TLS 1.2 server that sends a HelloRequest between reading the client's
/// Finished and sending its own change_cipher_spec, and then `data`.
public TlsError ServeTls12WithHelloRequest(IStream inner, TlsServerOptions options, byte[] data)
{
    var key = options.PrivateKey;
    if (key == null)
        return TlsError.InternalError;
    var connection = new TlsConnection(inner, true, false);
    var read = connection.ReadTlsHandshakeMessage();
    if (!read.Ok)
        return read.Error;
    byte[] first = read.Value;
    var parsed = TlsClientHello.ParseTlsClientHello(first);
    if (!parsed.Ok)
        return parsed.Error;
    connection.SelectTls12();

    var legacy = new Tls12ServerHandshake(connection, options, parsed.Value, key);
    TlsError step = legacy.ChooseTls12Parameters();
    if (step == TlsError.None)
    {
        legacy._transcript.AddTlsMessage(first);
        step = legacy.SendTls12ServerFlight(false);
    }
    if (step == TlsError.None)
        step = legacy.ReadTls12ClientFlight();
    if (step == TlsError.None)
    {
        // No write key yet, so it goes in plaintext.
        connection.QueueTlsHandshakeMessage(new byte[4u]);
        step = connection.FlushTlsHandshake();
    }
    if (step == TlsError.None)
        step = legacy.SendTls12ServerFinished();
    if (step != TlsError.None)
    {
        connection.AbandonTls(step);
        return step;
    }

    var stream = TlsStream.WrapTlsConnection(connection);
    stream.Write(data, 0u, data.Length);
    var buffer = new byte[16u];
    stream.Read(buffer, 0u, buffer.Length);
    stream.Close();
    return TlsError.None;
}
