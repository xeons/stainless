// SPDX-License-Identifier: 0BSD
// What TLS 1.3 refuses, and the alert each refusal sends.
//
// Some of these are the real client and server disagreeing: a certificate
// the validator will not have, no suite or group in common, a Finished that
// is wrong. The rest are a fake peer on the loopback writing bytes by hand
// — a Finished where a ServerHello belongs, a record cut short, one longer
// than the protocol allows — and reading back the alert it is sent.
module Tls13Refusals;

import Standard.Collections;
import Standard.Console;
import Standard.Convert;
import Standard.IO;
import Standard.Net;
import Standard.Net.Security;
import Standard.Security.Cryptography;
import Standard.Text;
import Standard.Threading;

[Embed("ed25519.crt.pem")]
static readonly byte[] Ed25519Certificate;
[Embed("ed25519.key.pem")]
static readonly byte[] Ed25519Key;

String ConvertToText(byte[] bytes) => Text.FromBytes(&bytes[0u], bytes.Length);

byte[] ReadCertificateDer()
{
    var block = PemEncoding.Find(ConvertToText(Ed25519Certificate));
    return block.Some ? block.Value.Data : new byte[0u];
}

TlsServerOptions CreateServerOptions()
{
    var options = new TlsServerOptions();
    options.CertificateChain.Add(ReadCertificateDer());
    var key = TlsSigningKey.ImportFromPem(ConvertToText(Ed25519Key));
    if (key.Ok)
        options.PrivateKey = key.Value;
    return options;
}

TlsError AcceptAnyCertificate(List<byte[]> chain, String targetHost) => TlsError.None;

TlsError RefuseEveryCertificate(List<byte[]> chain, String targetHost) =>
    TlsError.CertificateRefused;

TlsClientOptions CreateClientOptions()
{
    var options = new TlsClientOptions();
    options.TargetHost = "localhost";
    options.CertificateValidator = AcceptAnyCertificate;
    return options;
}

/// What the server end saw.
class ServerView
{
    public String Outcome = "not run";
    public String Alert = "";
    public String ReadError = "";
}

/// A real server on a thread: it handshakes, then reads once and says how
/// the read ended.
Thread StartServer(TcpListener listener, TlsServerOptions options, ServerView view)
{
    return new Thread(() =>
    {
        var accepted = TlsSocket.Accept(listener, options, out TlsAlertDescription alert);
        if (!accepted.Ok)
        {
            view.Outcome = DescribeTlsError(accepted.Error);
            view.Alert = $"{alert}";
            return;
        }
        TlsSocket socket = accepted.Value;
        view.Outcome = "ok";
        var buffer = new byte[65536u];
        while (socket.Read(buffer, 0u, buffer.Length) > 0u)
        {
        }
        view.ReadError = DescribeTlsError(socket.TlsErrorCode);
        socket.Close();
    });
}

void Report(
    String what, Result<TlsSocket, TlsError> client, TlsAlertDescription alert, ServerView view)
{
    Console.WriteLine(what + ":");
    String outcome = client.Ok
        ? "connected"
        : DescribeTlsError(client.Error) + ", alert " + $"{alert}";
    Console.WriteLine("  client: " + outcome);
    String alertSeen = view.Alert.ByteLength() > 0u ? ", alert " + view.Alert : "";
    Console.WriteLine("  server: " + view.Outcome + alertSeen);
}

void CheckRealPeers(String what, TlsServerOptions serverOptions, TlsClientOptions clientOptions)
{
    var listening = TcpListener.Listen("127.0.0.1", 0u);
    if (!listening.Ok)
        return;
    TcpListener listener = listening.Value;
    var view = new ServerView();
    Thread server = StartServer(listener, serverOptions, view);
    var client = TlsSocket.Connect("127.0.0.1", listener.LocalEndPoint.Port, clientOptions,
                                   out TlsAlertDescription alert);
    if (client.Ok)
        client.Value.Close();
    server.Join();
    listener.Close();
    Report(what, client, alert, view);
}

// ------------------------------------------------------------- a bad record

/// Passes everything through, and once armed flips a bit in the next write.
class TamperingStream : IStream
{
    private TcpClient _inner;
    public bool Armed = false;

    public TamperingStream(TcpClient inner) => _inner = inner;

    public bool CanRead => _inner.CanRead;
    public bool CanWrite => _inner.CanWrite;
    public bool CanSeek => false;
    public nuint Read(byte[] buffer, nuint offset, nuint count) =>
        _inner.Read(buffer, offset, count);

    public nuint Write(byte[] buffer, nuint offset, nuint count)
    {
        if (Armed && count > 10u)
        {
            buffer[offset + 10u] ^= 0x01;
            Armed = false;
        }
        return _inner.Write(buffer, offset, count);
    }

    public long Position => -1;
    public long Length => -1;
    public bool Seek(long offset, SeekOrigin origin) => false;
    public void Flush() { }
    public void Close() => _inner.Close();
    public IOError Error => _inner.Error;
}

void CheckTamperedRecord()
{
    var listening = TcpListener.Listen("127.0.0.1", 0u);
    if (!listening.Ok)
        return;
    TcpListener listener = listening.Value;
    var view = new ServerView();
    Thread server = StartServer(listener, CreateServerOptions(), view);

    var tcp = TcpClient.Connect("127.0.0.1", listener.LocalEndPoint.Port);
    if (!tcp.Ok)
        return;
    var tampering = new TamperingStream(tcp.Value);
    var client = TlsStream.AuthenticateAsClient(tampering, CreateClientOptions());
    if (!client.Ok)
        return;
    TlsStream tls = client.Value;
    tampering.Armed = true;
    byte[] data = "a record that will not arrive intact".ToBytes();
    tls.Write(data, 0u, data.Length);
    var buffer = new byte[64u];
    nuint got = tls.Read(buffer, 0u, buffer.Length);
    server.Join();
    Console.WriteLine("tampered record:");
    Console.WriteLine("  server read: " + view.ReadError);
    Console.WriteLine("  client read " + Text.FromInteger((long)got) + ": " +
                      DescribeTlsError(tls.TlsErrorCode) +
                      ", alert " + $"{tls.AlertDescription}");
    tls.Close();
    listener.Close();
}

// ---------------------------------------------------------- a wrong Finished

void CheckWrongFinished()
{
    var listening = TcpListener.Listen("127.0.0.1", 0u);
    if (!listening.Ok)
        return;
    TcpListener listener = listening.Value;
    var view = new ServerView();
    Thread server = StartServer(listener, CreateServerOptions(), view);
    var tcp = TcpClient.Connect("127.0.0.1", listener.LocalEndPoint.Port);
    if (!tcp.Ok)
        return;
    Console.WriteLine("wrong client Finished:");
    TlsError ended = RunTlsClientWithWrongFinished(tcp.Value, CreateClientOptions());
    server.Join();
    Console.WriteLine("  client: " + DescribeTlsError(ended));
    Console.WriteLine("  server: " + view.Outcome);
    tcp.Value.Close();
    listener.Close();
}

// ------------------------------------------------------------ a fake server

/// Accepts one connection, waits for the ClientHello, writes `reply`, and
/// reports the alert that comes back, if any.
class FakeServerView
{
    public String Heard = "nothing";
}

Thread StartFakeServer(TcpListener listener, byte[] reply, FakeServerView view)
{
    return new Thread(() =>
    {
        TcpClient peer = listener.Accept();
        var received = new List<byte>();
        var buffer = new byte[4096u];

        // The ClientHello: one record, whose length is in its header.
        while (received.Count < 5u ||
               received.Count < 5u + (((nuint)received[3u] << 8) | (nuint)received[4u]))
        {
            nuint got = peer.Read(buffer, 0u, buffer.Length);
            if (got == 0u)
                break;
            for (nuint i = 0u; i < got; i++)
                received.Add(buffer[i]);
        }
        nuint helloLength = 5u + (((nuint)received[3u] << 8) | (nuint)received[4u]);
        peer.Write(reply, 0u, reply.Length);

        // Nothing more is coming, which is what makes a record cut short
        // look cut short rather than slow.
        peer.Underlying.Shutdown(SocketShutdown.Send);

        while (true)
        {
            nuint got = peer.Read(buffer, 0u, buffer.Length);
            if (got == 0u)
                break;
            for (nuint i = 0u; i < got; i++)
                received.Add(buffer[i]);
        }

        // A plaintext alert: 21, the version, a length of 2, a level and a
        // description. What follows a ClientHello here can be nothing else.
        if (received.Count >= helloLength + 7u && received[helloLength] == 21)
        {
            view.Heard = "alert " + Text.FromInteger((long)received[helloLength + 6u]) +
                         (received[helloLength + 5u] == 2 ? ", fatal" : ", warning");
        }
        peer.Close();
    });
}

byte[] Bytes(String hex) => Convert.FromHexString(hex).GetValueOrDefault(new byte[0u]);

void CheckFakeServer(String what, byte[] reply) =>
    CheckFakeServer(what, reply, CreateClientOptions());

void CheckFakeServer(String what, byte[] reply, TlsClientOptions options)
{
    var listening = TcpListener.Listen("127.0.0.1", 0u);
    if (!listening.Ok)
        return;
    TcpListener listener = listening.Value;
    var view = new FakeServerView();
    Thread server = StartFakeServer(listener, reply, view);
    var client = TlsSocket.Connect("127.0.0.1", listener.LocalEndPoint.Port, options,
                                   out TlsAlertDescription alert);
    server.Join();
    listener.Close();
    Console.WriteLine(what + ":");
    Console.WriteLine("  client: " + (client.Ok ? "connected" : DescribeTlsError(client.Error)));
    Console.WriteLine("  fake server heard: " + view.Heard);
}

/// A ServerHello for TLS 1.2 — no supported_versions — whose random ends
/// with `tail`.
byte[] BuildLegacyServerHello(String tail)
{
    String random = "000102030405060708090a0b0c0d0e0f1011121314151617" + tail;
    String body = "0303" + random + "00" + "c02f" + "00";
    return Bytes("160303002a" + "02000026" + body);
}

void CheckFakeServers()
{
    CheckFakeServer("Finished before ServerHello",
                    Bytes("1603030024" + "14000020" +
                          "0000000000000000000000000000000000000000000000000000000000000000"));
    CheckFakeServer("record cut short", Bytes("1603030050" + "0200004c0303"));
    CheckFakeServer("plaintext record over 2^14", Bytes("1603034001" + "02"));
    CheckFakeServer("empty handshake record", Bytes("1603030000"));
    CheckFakeServer("unknown record type", Bytes("1803030001" + "00"));
    CheckFakeServer("change_cipher_spec of the wrong value", Bytes("1403030001" + "02"));
    TlsClientOptions tls13Only = CreateClientOptions();
    tls13Only.EnabledProtocols = TlsProtocolVersion.Tls13;
    CheckFakeServer("TLS 1.2 ServerHello to a TLS 1.3 client",
                    BuildLegacyServerHello("0000000000000000"), tls13Only);
    CheckFakeServer("TLS 1.2 ServerHello with the downgrade sentinel",
                    BuildLegacyServerHello("444f574e47524401"));
    // encrypt_then_mac, which a client of AEAD suites alone never offers.
    CheckFakeServer("ServerHello with an extension never offered",
                    Bytes("1603030036" + "02000032" + "0303" +
                          "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f" +
                          "00" + "1301" + "00" + "000a" + "002b00020304" + "0016" + "0000"));
}

// ------------------------------------------------------------ a fake client

/// Connects, writes `bytes` by hand to a real server, and reads what comes
/// back, which should be an alert.
void CheckFakeClient(String what, byte[] bytes) =>
    CheckFakeClient(what, bytes, CreateServerOptions());

void CheckFakeClient(String what, byte[] bytes, TlsServerOptions options)
{
    var listening = TcpListener.Listen("127.0.0.1", 0u);
    if (!listening.Ok)
        return;
    TcpListener listener = listening.Value;
    var view = new ServerView();
    Thread server = StartServer(listener, options, view);
    var tcp = TcpClient.Connect("127.0.0.1", listener.LocalEndPoint.Port);
    if (!tcp.Ok)
        return;
    TcpClient peer = tcp.Value;
    peer.Write(bytes, 0u, bytes.Length);
    var reply = new byte[7u];
    nuint got = peer.Read(reply, 0u, reply.Length);
    server.Join();
    Console.WriteLine(what + ":");
    Console.WriteLine("  server: " + view.Outcome);
    String heard = got == 7u && reply[0u] == 21
        ? "alert " + Text.FromInteger((long)reply[6u])
        : Text.FromInteger((long)got) + " bytes";
    Console.WriteLine("  fake client heard: " + heard);
    peer.Close();
    listener.Close();
}

void CheckFakeClients()
{
    // A ClientHello with no extensions: TLS 1.2 at most.
    TlsServerOptions tls13Only = CreateServerOptions();
    tls13Only.EnabledProtocols = TlsProtocolVersion.Tls13;
    CheckFakeClient("TLS 1.2 ClientHello to a TLS 1.3 server",
                    Bytes("160301002d" + "01000029" + "0303" +
                          "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f" +
                          "00" + "0002c02f" + "0100"),
                    tls13Only);
    CheckFakeClient("change_cipher_spec before a ClientHello", Bytes("1403030001" + "01"));
    CheckFakeClient("application data before a handshake", Bytes("1703030005" + "0102030405"));
}

// ------------------------------------------ a record over 2^14 + 256, sealed

void CheckOversizedProtectedRecord()
{
    var listening = TcpListener.Listen("127.0.0.1", 0u);
    if (!listening.Ok)
        return;
    TcpListener listener = listening.Value;
    var view = new ServerView();
    Thread server = StartServer(listener, CreateServerOptions(), view);
    var tcp = TcpClient.Connect("127.0.0.1", listener.LocalEndPoint.Port);
    if (!tcp.Ok)
        return;
    var options = CreateClientOptions();
    options.LeaveInnerStreamOpen = true;
    var client = TlsStream.AuthenticateAsClient(tcp.Value, options);
    if (!client.Ok)
        return;

    // Past the TLS stream, straight onto the connection: a header claiming
    // 2^14 + 257 bytes of ciphertext.
    var huge = new byte[5u + 16641u];
    huge[0u] = 23;
    huge[1u] = 3;
    huge[2u] = 3;
    huge[3u] = 0x41;
    huge[4u] = 0x01;
    tcp.Value.SendAll(huge);
    var buffer = new byte[64u];
    nuint got = client.Value.Read(buffer, 0u, buffer.Length);
    server.Join();
    Console.WriteLine("protected record over 2^14 + 256:");
    Console.WriteLine("  server read: " + view.ReadError);
    Console.WriteLine("  client read " + Text.FromInteger((long)got) + ": " +
                      DescribeTlsError(client.Value.TlsErrorCode) + ", alert " +
                      $"{client.Value.AlertDescription}");
    tcp.Value.Close();
    listener.Close();
}

int Main()
{
    TlsClientOptions refusing = CreateClientOptions();
    refusing.CertificateValidator = RefuseEveryCertificate;
    CheckRealPeers("certificate refused", CreateServerOptions(), refusing);

    TlsClientOptions defaulted = CreateClientOptions();
    defaulted.CertificateValidator = ValidateTlsCertificateChainByDefault;
    CheckRealPeers("default validator", CreateServerOptions(), defaulted);

    TlsServerOptions chachaOnly = CreateServerOptions();
    chachaOnly.CipherSuites.Clear();
    chachaOnly.CipherSuites.Add(TlsCipherSuite.TlsChaCha20Poly1305Sha256);
    TlsClientOptions aesOnly = CreateClientOptions();
    aesOnly.CipherSuites.Clear();
    aesOnly.CipherSuites.Add(TlsCipherSuite.TlsAes256GcmSha384);
    CheckRealPeers("no common suite", chachaOnly, aesOnly);

    TlsServerOptions x25519Only = CreateServerOptions();
    x25519Only.KeyExchangeGroups.Clear();
    x25519Only.KeyExchangeGroups.Add(TlsNamedGroup.X25519);
    TlsClientOptions p384Only = CreateClientOptions();
    p384Only.KeyExchangeGroups.Clear();
    p384Only.KeyExchangeGroups.Add(TlsNamedGroup.Secp384r1);
    p384Only.KeyShareGroups.Clear();
    p384Only.KeyShareGroups.Add(TlsNamedGroup.Secp384r1);
    CheckRealPeers("no common group", x25519Only, p384Only);

    CheckTamperedRecord();
    CheckWrongFinished();
    CheckFakeServers();
    CheckFakeClients();
    CheckOversizedProtectedRecord();
    return 0;
}
