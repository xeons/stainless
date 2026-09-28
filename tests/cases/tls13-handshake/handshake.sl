// SPDX-License-Identifier: 0BSD
// TLS 1.3 between this library's client and its server, over the loopback.
//
// Every suite with every group, against a server holding each kind of key;
// a transfer of many records each way; ALPN agreed and refused; the name a
// client asks for, as the server sees it; a HelloRetryRequest in each
// direction; a KeyUpdate halfway through a transfer; a client certificate;
// exported keying material; and close_notify.
//
// Each exchange has a server on a thread of its own and the client in main.
// The server writes nothing while it runs: it keeps what it saw in a
// ServerView, which main prints after joining it, so the output does not
// depend on how the two threads interleave.
module Tls13Handshake;

import Standard.Collections;
import Standard.Console;
import Standard.IO;
import Standard.Net;
import Standard.Net.Security;
import Standard.Security.Cryptography;
import Standard.Text;
import Standard.Threading;

[Embed("ed25519.crt.pem")] static readonly byte[] Ed25519Certificate;
[Embed("ed25519.key.pem")] static readonly byte[] Ed25519Key;
[Embed("p256.crt.pem")] static readonly byte[] P256Certificate;
[Embed("p256.key.pem")] static readonly byte[] P256Key;
[Embed("p384.crt.pem")] static readonly byte[] P384Certificate;
[Embed("p384.key.pem")] static readonly byte[] P384Key;
[Embed("rsa.crt.pem")] static readonly byte[] RsaCertificate;
[Embed("rsa.key.pem")] static readonly byte[] RsaKey;
[Embed("rsapss.crt.pem")] static readonly byte[] RsaPssCertificate;
[Embed("rsapss.key.pem")] static readonly byte[] RsaPssKey;
[Embed("client.crt.pem")] static readonly byte[] ClientCertificate;
[Embed("client.key.pem")] static readonly byte[] ClientKey;

String ConvertToText(byte[] bytes) => Text.FromBytes(&bytes[0u], bytes.Length);

byte[] ReadCertificateDer(byte[] pem)
{
    var block = PemEncoding.Find(ConvertToText(pem));
    return block.Some ? block.Value.Data : new byte[0u];
}

TlsSigningKey? ReadSigningKey(byte[] pem)
{
    var key = TlsSigningKey.ImportFromPem(ConvertToText(pem));
    if (!key.Ok)
    {
        Console.WriteLine("key did not load: " + $"{key.Error}");
        return null;
    }
    return key.Value;
}

/// A test's certificate check: the peer's leaf MUST be the one expected.
class PinnedCertificate
{
    private byte[] _expected;

    public PinnedCertificate(byte[] expected) => _expected = expected;

    public TlsError CheckChain(List<byte[]> chain, String targetHost)
    {
        if (chain.Count == 0u || !AreSame(chain[0u], _expected))
            return TlsError.CertificateRefused;
        return TlsError.None;
    }
}

bool AreSame(byte[] left, byte[] right)
{
    if (left.Length != right.Length)
        return false;
    for (nuint i = 0u; i < left.Length; i++)
    {
        if (left[i] != right[i])
            return false;
    }
    return true;
}

/// Bytes whose value says where they are, so a record out of place shows.
byte[] CreatePattern(nuint length, uint seed)
{
    var bytes = new byte[length];
    for (nuint i = 0u; i < length; i++)
        bytes[i] = (byte)(((uint)i * 31u + seed + ((uint)i >> 11)) & 0xFFu);
    return bytes;
}

/// Reads exactly `length` bytes, or as many as arrive before the end.
byte[] ReadExactly(IStream stream, nuint length)
{
    var bytes = new byte[length];
    nuint done = 0u;
    while (done < length)
    {
        nuint got = stream.Read(bytes, done, length - done);
        if (got == 0u)
            break;
        done += got;
    }
    if (done == length)
        return bytes;
    var part = new byte[done];
    for (nuint i = 0u; i < done; i++)
        part[i] = bytes[i];
    return part;
}

/// What the server saw, for main to print once the server has finished.
class ServerView
{
    public String Outcome = "not run";
    public String Host = "";
    public String Protocol = "";
    public nuint Received = 0u;
    public bool Echoed = false;
    public bool SawEnd = false;
    public bool Mutual = false;
    public String ClientLeaf = "";
    public byte[] Exported = new byte[0u];
}

/// How the server echoes: it reads `expect` bytes, writes them back, and
/// then reads once more, which returns zero at the client's close_notify.
Thread StartEchoServer(
    TcpListener listener, TlsServerOptions options, nuint expect, ServerView view)
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
        view.Host = socket.TargetHostName;
        var protocol = socket.NegotiatedApplicationProtocol;
        view.Protocol = protocol == null ? "none" : protocol;
        view.Mutual = socket.Stream.IsMutuallyAuthenticated;
        view.ClientLeaf = socket.RemoteCertificate.Length > 0u ? "client leaf" : "no client leaf";
        view.Exported = socket.Stream.ExportKeyingMaterial("EXPORTER-test", "context"u8, 32u)
                                     .GetValueOrDefault(new byte[0u]);

        byte[] data = ReadExactly(socket, expect);
        view.Received = data.Length;
        view.Echoed = socket.Write(data, 0u, data.Length) == data.Length || data.Length == 0u;

        var rest = new byte[16u];
        nuint after = socket.Read(rest, 0u, rest.Length);
        view.SawEnd = after == 0u && socket.TlsErrorCode == TlsError.None;
        socket.Close();
    });
}

TlsServerOptions CreateServerOptions(byte[] certificatePem, byte[] keyPem)
{
    var options = new TlsServerOptions();
    options.CertificateChain.Add(ReadCertificateDer(certificatePem));
    options.PrivateKey = ReadSigningKey(keyPem);
    return options;
}

TlsClientOptions CreateClientOptions(byte[] certificatePem)
{
    var options = new TlsClientOptions();
    options.TargetHost = "localhost";
    var pin = new PinnedCertificate(ReadCertificateDer(certificatePem));
    options.CertificateValidator = pin.CheckChain;
    return options;
}

/// One connection: the server on a thread, the client here sending
/// `payload` and reading it back. Answers the client's socket, closed.
TlsSocket? Exchange(TlsServerOptions serverOptions, TlsClientOptions clientOptions, byte[] payload,
                    ServerView view)
{
    var listening = TcpListener.Listen("127.0.0.1", 0u);
    if (!listening.Ok)
        return null;
    TcpListener listener = listening.Value;
    Thread server = StartEchoServer(listener, serverOptions, payload.Length, view);

    var connected = TlsSocket.Connect("127.0.0.1", listener.LocalEndPoint.Port, clientOptions,
                                      out TlsAlertDescription alert);
    if (!connected.Ok)
    {
        Console.WriteLine(
            "  client: " + DescribeTlsError(connected.Error) + ", alert " + $"{alert}");
        server.Join();
        listener.Close();
        return null;
    }
    TlsSocket client = connected.Value;
    client.Write(payload, 0u, payload.Length);
    byte[] back = ReadExactly(client, payload.Length);
    // A client finishes its handshake before the server has judged its
    // certificate, so a refusal of it arrives here, on the first read.
    if (!AreSame(back, payload))
    {
        Console.WriteLine("  client read: " + DescribeTlsError(client.TlsErrorCode) + ", alert " +
                          $"{client.AlertDescription}");
    }
    client.Close();
    server.Join();
    listener.Close();
    return client;
}

String DescribeKey(int index)
{
    switch (index)
    {
        case 0: return "ed25519";
        case 1: return "p-256";
        case 2: return "p-384";
        case 3: return "rsa";
        default: return "rsa-pss";
    }
}

TlsServerOptions CreateServerOptionsForKey(int index)
{
    switch (index)
    {
        case 0: return CreateServerOptions(Ed25519Certificate, Ed25519Key);
        case 1: return CreateServerOptions(P256Certificate, P256Key);
        case 2: return CreateServerOptions(P384Certificate, P384Key);
        case 3: return CreateServerOptions(RsaCertificate, RsaKey);
        default: return CreateServerOptions(RsaPssCertificate, RsaPssKey);
    }
}

byte[] ChooseCertificateForKey(int index)
{
    switch (index)
    {
        case 0: return Ed25519Certificate;
        case 1: return P256Certificate;
        case 2: return P384Certificate;
        case 3: return RsaCertificate;
        default: return RsaPssCertificate;
    }
}

void CheckEverySuiteGroupAndKey()
{
    var suites = new List<TlsCipherSuite>();
    suites.Add(TlsCipherSuite.TlsAes128GcmSha256);
    suites.Add(TlsCipherSuite.TlsAes256GcmSha384);
    suites.Add(TlsCipherSuite.TlsChaCha20Poly1305Sha256);
    var groups = new List<TlsNamedGroup>();
    groups.Add(TlsNamedGroup.X25519);
    groups.Add(TlsNamedGroup.Secp256r1);
    groups.Add(TlsNamedGroup.Secp384r1);

    byte[] payload = CreatePattern(1000u, 7u);
    for (int key = 0; key < 5; key++)
    {
        for (nuint s = 0u; s < suites.Count; s++)
        {
            for (nuint g = 0u; g < groups.Count; g++)
            {
                TlsClientOptions client = CreateClientOptions(ChooseCertificateForKey(key));
                client.CipherSuites.Clear();
                client.CipherSuites.Add(suites[s]);
                client.KeyExchangeGroups.Clear();
                client.KeyExchangeGroups.Add(groups[g]);
                client.KeyShareGroups.Clear();
                client.KeyShareGroups.Add(groups[g]);

                var view = new ServerView();
                var socket = Exchange(CreateServerOptionsForKey(key), client, payload, view);
                String line = DescribeKey(key) + " " + $"{suites[s]}" + " " + $"{groups[g]}" + ": ";
                if (socket == null)
                {
                    Console.WriteLine(line + "failed, server " + view.Outcome);
                    continue;
                }
                bool agreed = socket.CipherSuite == suites[s] &&
                              socket.KeyExchangeGroup == groups[g];
                Console.WriteLine(line + (agreed && view.Echoed && view.SawEnd ? "ok " : "WRONG ") +
                                  $"{socket.SignatureScheme}");
            }
        }
    }
}

void CheckLargeTransferAndKeyUpdate()
{
    // 300 KiB is nineteen full records each way, with a KeyUpdate from the
    // client a third of the way in, which the server answers with its own
    // before it echoes.
    byte[] payload = CreatePattern(307200u, 3u);
    var listening = TcpListener.Listen("127.0.0.1", 0u);
    if (!listening.Ok)
        return;
    TcpListener listener = listening.Value;
    var view = new ServerView();
    Thread server = StartEchoServer(
        listener, CreateServerOptions(P256Certificate, P256Key), payload.Length, view);

    var connected = TlsSocket.Connect("127.0.0.1", listener.LocalEndPoint.Port,
                                      CreateClientOptions(P256Certificate));
    if (!connected.Ok)
    {
        Console.WriteLine("large: " + DescribeTlsError(connected.Error));
        server.Join();
        return;
    }
    TlsSocket client = connected.Value;
    client.Write(payload, 0u, 102400u);
    TlsError updated = client.Stream.UpdateTrafficKeys(true);
    client.Write(payload, 102400u, payload.Length - 102400u);
    byte[] back = ReadExactly(client, payload.Length);
    Console.WriteLine("key update: " + DescribeTlsError(updated));
    Console.WriteLine("large transfer: " + Text.FromInteger((long)view.Received) +
                      " bytes each way, " +
                      (AreSame(back, payload) ? "intact" : "CORRUPT"));
    client.Close();
    server.Join();
    Console.WriteLine("server saw close_notify: " + (view.SawEnd ? "yes" : "no"));
}

void CheckApplicationProtocols()
{
    TlsServerOptions server = CreateServerOptions(Ed25519Certificate, Ed25519Key);
    server.ApplicationProtocols.Add("http/1.1");
    server.ApplicationProtocols.Add("h2");
    TlsClientOptions client = CreateClientOptions(Ed25519Certificate);
    client.ApplicationProtocols.Add("h2");
    client.ApplicationProtocols.Add("http/1.1");
    var view = new ServerView();
    var socket = Exchange(server, client, CreatePattern(10u, 1u), view);
    if (socket != null)
    {
        var chosen = socket.NegotiatedApplicationProtocol;
        Console.WriteLine(
            "alpn: client " + (chosen == null ? "none" : chosen) + ", server " + view.Protocol);
    }

    TlsServerOptions picky = CreateServerOptions(Ed25519Certificate, Ed25519Key);
    picky.ApplicationProtocols.Add("spdy/3");
    TlsClientOptions other = CreateClientOptions(Ed25519Certificate);
    other.ApplicationProtocols.Add("h2");
    var refused = new ServerView();
    Console.WriteLine("alpn mismatch:");
    Exchange(picky, other, CreatePattern(10u, 1u), refused);
    Console.WriteLine("  server: " + refused.Outcome);

    TlsServerOptions quiet = CreateServerOptions(Ed25519Certificate, Ed25519Key);
    quiet.ApplicationProtocols.Add("h2");
    var none = new ServerView();
    var plain = Exchange(
        quiet, CreateClientOptions(Ed25519Certificate), CreatePattern(10u, 1u), none);
    Console.WriteLine("alpn offered by the server only: " + none.Protocol);
}

void CheckServerName()
{
    TlsClientOptions client = CreateClientOptions(Ed25519Certificate);
    client.TargetHost = "tls.example.test";
    var view = new ServerView();
    Exchange(
        CreateServerOptions(Ed25519Certificate, Ed25519Key), client, CreatePattern(10u, 1u), view);
    Console.WriteLine("server saw the name: " + view.Host);

    TlsClientOptions literal = CreateClientOptions(Ed25519Certificate);
    literal.TargetHost = "127.0.0.1";
    var unnamed = new ServerView();
    Exchange(
        CreateServerOptions(Ed25519Certificate, Ed25519Key), literal, CreatePattern(10u, 1u),
        unnamed);
    Console.WriteLine("an address is not sent as a name: '" + unnamed.Host + "'");
}

void CheckHelloRetry(TlsNamedGroup clientShare, TlsNamedGroup serverGroup)
{
    TlsServerOptions server = CreateServerOptions(Ed25519Certificate, Ed25519Key);
    server.KeyExchangeGroups.Clear();
    server.KeyExchangeGroups.Add(serverGroup);
    TlsClientOptions client = CreateClientOptions(Ed25519Certificate);
    client.KeyShareGroups.Clear();
    client.KeyShareGroups.Add(clientShare);
    var view = new ServerView();
    var socket = Exchange(server, client, CreatePattern(5000u, 9u), view);
    String line = "retry from " + $"{clientShare}" + " to " + $"{serverGroup}" + ": ";
    if (socket == null)
    {
        Console.WriteLine(line + "failed, server " + view.Outcome);
        return;
    }
    Console.WriteLine(line + $"{socket.KeyExchangeGroup}" + (view.Echoed ? ", echoed" : ""));
}

void CheckClientCertificate()
{
    TlsServerOptions server = CreateServerOptions(P384Certificate, P384Key);
    server.ClientCertificateRequired = true;
    var pin = new PinnedCertificate(ReadCertificateDer(ClientCertificate));
    server.ClientCertificateValidator = pin.CheckChain;
    TlsClientOptions client = CreateClientOptions(P384Certificate);
    client.ClientCertificateChain.Add(ReadCertificateDer(ClientCertificate));
    client.ClientPrivateKey = ReadSigningKey(ClientKey);
    var view = new ServerView();
    Exchange(server, client, CreatePattern(100u, 2u), view);
    Console.WriteLine("client certificate: " + view.Outcome + ", " + view.ClientLeaf +
                      (view.Mutual ? ", mutual" : ""));

    TlsServerOptions demanding = CreateServerOptions(P384Certificate, P384Key);
    demanding.ClientCertificateRequired = true;
    var refused = new ServerView();
    Console.WriteLine("no client certificate:");
    Exchange(demanding, CreateClientOptions(P384Certificate), CreatePattern(100u, 2u), refused);
    Console.WriteLine("  server: " + refused.Outcome);
}

void CheckExportedKeys()
{
    var listening = TcpListener.Listen("127.0.0.1", 0u);
    if (!listening.Ok)
        return;
    TcpListener listener = listening.Value;
    var view = new ServerView();
    Thread server = StartEchoServer(
        listener, CreateServerOptions(Ed25519Certificate, Ed25519Key), 0u, view);
    var connected = TlsSocket.Connect("127.0.0.1", listener.LocalEndPoint.Port,
                                      CreateClientOptions(Ed25519Certificate));
    if (connected.Ok)
    {
        TlsSocket client = connected.Value;
        var exported = client.Stream.ExportKeyingMaterial("EXPORTER-test", "context"u8, 32u);
        client.Close();
        server.Join();
        Console.WriteLine("exported keys agree: " +
                          (exported.Ok && AreSame(exported.Value, view.Exported) ? "yes" : "no"));
    }
}

int Main()
{
    CheckEverySuiteGroupAndKey();
    CheckLargeTransferAndKeyUpdate();
    CheckApplicationProtocols();
    CheckServerName();
    CheckHelloRetry(TlsNamedGroup.Secp256r1, TlsNamedGroup.X25519);
    CheckHelloRetry(TlsNamedGroup.X25519, TlsNamedGroup.Secp384r1);
    CheckClientCertificate();
    CheckExportedKeys();
    return 0;
}
