// SPDX-License-Identifier: 0BSD
// What TLS 1.2 refuses, and the alert each refusal sends.
//
// Some of these are the real client and server: a record tampered with on
// the way, a Finished that is wrong, and a renegotiation asked for from
// either side, which is answered with a no_renegotiation warning and nothing
// else. The rest are a fake peer on the loopback writing a hello by hand —
// one without the extended master secret, one offering only CBC suites or
// groups this library does not have, a ServerKeyExchange in a group never
// offered or with a signature that does not verify, and a ServerHello
// carrying the downgrade sentinel — and reading back the alert it is sent.
module Tls12Refusals;

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

TlsClientOptions CreateClientOptions()
{
    var options = new TlsClientOptions();
    options.TargetHost = "localhost";
    options.EnabledProtocols = TlsProtocolVersion.Tls12;
    options.CertificateValidator = AcceptAnyCertificate;
    return options;
}

/// What the server end saw.
class ServerView
{
    public String Outcome = "not run";
    public String ReadError = "";
}

/// A real server on a thread: it handshakes, then echoes what it reads
/// until the end, and says how the reading ended.
Thread StartServer(TcpListener listener, TlsServerOptions options, ServerView view)
{
    return new Thread(() =>
    {
        var accepted = TlsSocket.Accept(listener, options);
        if (!accepted.Ok)
        {
            view.Outcome = DescribeTlsError(accepted.Error);
            return;
        }
        TlsSocket socket = accepted.Value;
        view.Outcome = "ok";
        var buffer = new byte[65536u];
        while (true)
        {
            nuint got = socket.Read(buffer, 0u, buffer.Length);
            if (got == 0u)
                break;
            socket.Write(buffer, 0u, got);
        }
        view.ReadError = DescribeTlsError(socket.TlsErrorCode);
        socket.Close();
    });
}

// ------------------------------------------------------------- hex to hand

byte[] Bytes(String hex) => Convert.FromHexString(hex).GetValueOrDefault(new byte[0u]);

String FormatLength(nuint value, nuint size)
{
    var bytes = new byte[size];
    for (nuint i = 0u; i < size; i++)
        bytes[i] = (byte)((value >> (8u * (size - 1u - i))) & 0xFFu);
    return Convert.ToHexString(bytes);
}

/// `hex` behind a length of `size` bytes.
String PrefixLength(String hex, nuint size) => FormatLength(hex.ByteLength() / 2u, size) + hex;

String BuildExtension(String type, String body) => type + PrefixLength(body, 2u);

String BuildHandshake(String type, String body) => type + PrefixLength(body, 3u);

String BuildRecord(String type, String body) => type + "0303" + PrefixLength(body, 2u);

String FormatHelloRandom() =>
    "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f";

/// A TLS 1.2 ClientHello with `suites` and these extensions, as a record.
byte[] BuildClientHello(String suites, String extensions)
{
    String body = "0303" + FormatHelloRandom() + "00" + PrefixLength(suites, 2u) + "0100" +
                  PrefixLength(extensions, 2u);
    return Bytes(BuildRecord("16", BuildHandshake("01", body)));
}

String BuildGroupsX25519() => BuildExtension("000a", PrefixLength("001d", 2u));

String BuildPointFormats() => BuildExtension("000b", "0100");

String BuildSignatureEd25519() => BuildExtension("000d", PrefixLength("0807", 2u));

String BuildExtendedMasterSecret() => BuildExtension("0017", "");

String BuildRenegotiationInfo() => BuildExtension("ff01", "00");

// ------------------------------------------------------------ a fake client

/// Connects, writes `bytes` by hand to a real server, and reads what comes
/// back, which should be an alert.
void CheckFakeClient(String what, byte[] bytes)
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
    String groups = BuildGroupsX25519();
    String formats = BuildPointFormats();
    String signatures = BuildSignatureEd25519();
    String master = BuildExtendedMasterSecret();
    CheckFakeClient("ClientHello without the extended master secret",
                    BuildClientHello("c02b", groups + formats + signatures));
    // ECDHE-ECDSA with AES-128-CBC and AES-256-CBC, both with SHA-1.
    CheckFakeClient("ClientHello offering only CBC suites",
                    BuildClientHello("c009c00a", groups + formats + signatures + master +
                                                 BuildRenegotiationInfo()));
    // secp521r1 and ffdhe2048.
    CheckFakeClient("ClientHello offering only groups not implemented",
                    BuildClientHello("c02b", BuildExtension("000a", PrefixLength("00190100", 2u)) +
                                             formats + signatures + master));
    CheckFakeClient("ClientHello renegotiating from the start",
                    BuildClientHello("c02b", groups + formats + signatures + master +
                                             BuildExtension("ff01", PrefixLength("00112233", 1u))));
    CheckFakeClient("ClientHello without signature_algorithms",
                    BuildClientHello("c02b", groups + formats + master));
    CheckFakeClient("ClientHello with compressed points only",
                    BuildClientHello("c02b", groups + BuildExtension("000b", "0101") + signatures +
                                             master));
}

// ------------------------------------------------------------ a fake server

class FakeServerView
{
    public String Heard = "nothing";
}

/// Accepts one connection, waits for the ClientHello, writes `reply`, and
/// reports the alert that comes back, if any.
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
        peer.Underlying.Shutdown(SocketShutdown.Send);

        while (true)
        {
            nuint got = peer.Read(buffer, 0u, buffer.Length);
            if (got == 0u)
                break;
            for (nuint i = 0u; i < got; i++)
                received.Add(buffer[i]);
        }

        if (received.Count >= helloLength + 7u && received[helloLength] == 21)
        {
            view.Heard = "alert " + Text.FromInteger((long)received[helloLength + 6u]) +
                         (received[helloLength + 5u] == 2 ? ", fatal" : ", warning");
        }
        peer.Close();
    });
}

void CheckFakeServer(String what, String reply, TlsClientOptions options)
{
    var listening = TcpListener.Listen("127.0.0.1", 0u);
    if (!listening.Ok)
        return;
    TcpListener listener = listening.Value;
    var view = new FakeServerView();
    Thread server = StartFakeServer(listener, Bytes(reply), view);
    var client = TlsSocket.Connect("127.0.0.1", listener.LocalEndPoint.Port, options,
                                   out TlsAlertDescription alert);
    server.Join();
    listener.Close();
    Console.WriteLine(what + ":");
    Console.WriteLine("  client: " + (client.Ok ? "connected" : DescribeTlsError(client.Error)));
    Console.WriteLine("  fake server heard: " + view.Heard);
}

/// A TLS 1.2 ServerHello choosing ECDHE-ECDSA with AES-128-GCM, whose random
/// ends with `tail`.
String BuildServerHello(String tail, String extensions)
{
    String random = "707172737475767778797a7b7c7d7e7f8081828384858687" + tail;
    return BuildHandshake("02", "0303" + random + "00" + "c02b" + "00" +
                                PrefixLength(extensions, 2u));
}

String BuildCertificate()
{
    String leaf = Convert.ToHexString(ReadCertificateDer());
    return BuildHandshake("0b", PrefixLength(PrefixLength(leaf, 3u), 3u));
}

/// A ServerKeyExchange in `group` with an X25519-sized point, signed with
/// Ed25519 by nobody: 64 bytes of signature that verify against no key.
String BuildServerKeyExchange(String group)
{
    String point = "09" + "00000000000000000000000000000000000000000000000000000000000000";
    String signature = "00000000000000000000000000000000000000000000000000000000000000000000" +
                       "000000000000000000000000000000000000000000000000000000000000";
    return BuildHandshake("0c", "03" + group + PrefixLength(point, 1u) + "0807" +
                                PrefixLength(signature, 2u));
}

void CheckFakeServers()
{
    String extensions = BuildExtendedMasterSecret() + BuildRenegotiationInfo();
    TlsClientOptions tls12 = CreateClientOptions();
    TlsClientOptions both = CreateClientOptions();
    both.EnabledProtocols = TlsProtocolVersion.Tls12 | TlsProtocolVersion.Tls13;

    CheckFakeServer("ServerHello without the extended master secret",
                    BuildRecord("16", BuildServerHello("0000000000000000",
                                                       BuildRenegotiationInfo())),
                    tls12);
    CheckFakeServer("ServerKeyExchange in a group never offered",
                    BuildRecord("16", BuildServerHello("0000000000000000", extensions) +
                                      BuildCertificate() + BuildServerKeyExchange("0019")),
                    tls12);
    CheckFakeServer("ServerKeyExchange with a wrong signature",
                    BuildRecord("16", BuildServerHello("0000000000000000", extensions) +
                                      BuildCertificate() + BuildServerKeyExchange("001d")),
                    tls12);
    CheckFakeServer("downgrade sentinel to a client of TLS 1.3 too",
                    BuildRecord("16", BuildServerHello("444f574e47524401", extensions)), both);
    CheckFakeServer("downgrade sentinel to a client of TLS 1.2 alone",
                    BuildRecord("16", BuildServerHello("444f574e47524401", extensions)), tls12);
    CheckFakeServer("change_cipher_spec in place of a Certificate",
                    BuildRecord("16", BuildServerHello("0000000000000000", extensions)) +
                    "140303000101", tls12);
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
        if (Armed && count > 20u)
        {
            buffer[offset + 20u] ^= 0x01;
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
    TlsError ended = RunTls12ClientWithWrongFinished(tcp.Value, CreateClientOptions());
    server.Join();
    Console.WriteLine("  client: " + DescribeTlsError(ended));
    Console.WriteLine("  server: " + view.Outcome);
    tcp.Value.Close();
    listener.Close();
}

// ------------------------------------------------------------ renegotiation

/// A client that asks to renegotiate with a ClientHello under the
/// connection's keys, then goes on sending data to an echoing server.
void CheckClientRenegotiation()
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
    var connected = ConnectTls12TestPeer(tcp.Value, CreateClientOptions());
    if (!connected.Ok)
    {
        Console.WriteLine("renegotiation: " + DescribeTlsError(connected.Error));
        server.Join();
        return;
    }
    Tls12TestPeer client = connected.Value;
    byte[] hello = BuildClientHello("c02b", BuildGroupsX25519() + BuildPointFormats() +
                                            BuildSignatureEd25519() + BuildExtendedMasterSecret());
    TlsError sent = client.SendHandshakeMessage(hello[5u:].ToArray());
    byte[] data = "still here".ToBytes();
    client.Stream.Write(data, 0u, data.Length);
    var buffer = new byte[64u];
    nuint got = client.Stream.Read(buffer, 0u, buffer.Length);
    client.Stream.Close();
    server.Join();
    Console.WriteLine("client asks to renegotiate:");
    Console.WriteLine("  sent: " + DescribeTlsError(sent));
    Console.WriteLine("  server answered: " + $"{client.WarningReceived}");
    Console.WriteLine("  echo after: " + Text.FromInteger((long)got) + " bytes, " +
                      DescribeTlsError(client.Stream.TlsErrorCode));
    Console.WriteLine("  server: " + view.Outcome + ", read ended: " + view.ReadError);
    listener.Close();
}

/// A server that sends a HelloRequest after the handshake, then reads what
/// the client sends and answers it.
void CheckServerRenegotiation()
{
    var listening = TcpListener.Listen("127.0.0.1", 0u);
    if (!listening.Ok)
        return;
    TcpListener listener = listening.Value;
    var heard = new FakeServerView();
    Thread server = new Thread(() =>
    {
        TcpClient tcp = listener.Accept();
        var accepted = AcceptTls12TestPeer(tcp, CreateServerOptions());
        if (!accepted.Ok)
        {
            heard.Heard = DescribeTlsError(accepted.Error);
            return;
        }
        Tls12TestPeer peer = accepted.Value;
        peer.SendHandshakeMessage(Bytes("00000000"));
        var buffer = new byte[64u];
        nuint got = peer.Stream.Read(buffer, 0u, buffer.Length);
        peer.Stream.Write(buffer, 0u, got);
        peer.Stream.Read(buffer, 0u, buffer.Length);
        heard.Heard = $"{peer.WarningReceived}" + ", then " +
                      DescribeTlsError(peer.Stream.TlsErrorCode);
        peer.Stream.Close();
    });

    var client = TlsSocket.Connect("127.0.0.1", listener.LocalEndPoint.Port, CreateClientOptions());
    if (!client.Ok)
    {
        Console.WriteLine("HelloRequest: " + DescribeTlsError(client.Error));
        server.Join();
        return;
    }
    byte[] data = "ping".ToBytes();
    client.Value.Write(data, 0u, data.Length);
    var buffer = new byte[64u];
    nuint got = client.Value.Read(buffer, 0u, buffer.Length);
    Console.WriteLine("server asks to renegotiate:");
    Console.WriteLine("  client read " + Text.FromInteger((long)got) + " bytes, " +
                      DescribeTlsError(client.Value.TlsErrorCode));
    client.Value.Close();
    server.Join();
    Console.WriteLine("  server heard: " + heard.Heard);
    listener.Close();
}

int Main()
{
    CheckFakeClients();
    CheckFakeServers();
    CheckTamperedRecord();
    CheckWrongFinished();
    CheckClientRenegotiation();
    CheckServerRenegotiation();
    return 0;
}
