// SPDX-License-Identifier: 0BSD
// What only the module's own hooks can reach: a HelloRetryRequest with a
// cookie and no key_share, 0-RTT data a server skips, a cookie too long to
// echo, a length prefix too short for its vector, a sequence number at its
// end, and the secrets a connection overwrites as it goes and at close.
module TlsHardeningInternals;

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

String ConvertToText(byte[] bytes) => Text.FromBytes(&bytes[0u], bytes.Length);

TlsServerOptions CreateServerOptions()
{
    var options = new TlsServerOptions();
    var block = PemEncoding.Find(ConvertToText(Ed25519Certificate));
    options.CertificateChain.Add(block.Some ? block.Value.Data : new byte[0u]);
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
    options.CertificateValidator = AcceptAnyCertificate;
    return options;
}

class ServerView
{
    public String Outcome = "not run";
    public String Protocol = "";
}

/// A real server on a thread, which handshakes, reads until the client
/// closes, and says how the handshake went.
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
        view.Outcome = "connected";
        var protocol = socket.Stream.NegotiatedApplicationProtocol;
        view.Protocol = protocol == null ? "none" : (String)protocol;
        var buffer = new byte[256u];
        while (socket.Read(buffer, 0u, buffer.Length) > 0u)
        {
        }
        socket.Close();
    });
}

void CheckCookieRetry()
{
    var listening = TcpListener.Listen("127.0.0.1", 0u);
    if (!listening.Ok)
        return;
    TcpListener listener = listening.Value;
    var serverOptions = CreateServerOptions();
    serverOptions.ApplicationProtocols.Add("h2");
    SetTlsTestCookieRetry(serverOptions);
    var view = new ServerView();
    Thread server = StartServer(listener, serverOptions, view);

    var options = CreateClientOptions();
    options.EnabledProtocols = TlsProtocolVersion.Tls13;
    options.ApplicationProtocols.Add("h2");
    var client = TlsSocket.Connect("127.0.0.1", listener.LocalEndPoint.Port, options);
    String outcome = client.Ok ? "connected" : DescribeTlsError(client.Error);
    if (client.Ok)
        client.Value.Close();
    server.Join();
    listener.Close();
    Console.WriteLine("HelloRetryRequest with a cookie alone:");
    Console.WriteLine("  client: " + outcome);
    Console.WriteLine("  server: " + view.Outcome + ", ALPN " + view.Protocol);
}

void CheckEarlyData(nuint earlyBytes)
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
    TlsError ended = RunTlsClientWithEarlyData(tcp.Value, CreateClientOptions(), earlyBytes);
    tcp.Value.Close();
    server.Join();
    listener.Close();
    Console.WriteLine("rejected 0-RTT data, " + Text.FromInteger((long)earlyBytes) + " bytes:");
    // A client the server refused ends however the reset reaches it first.
    if (view.Outcome == "connected")
        Console.WriteLine("  client: " + DescribeTlsError(ended));
    Console.WriteLine("  server: " + view.Outcome);
}

void CheckSecretsWiped(TlsProtocolVersion version, String what)
{
    var listening = TcpListener.Listen("127.0.0.1", 0u);
    if (!listening.Ok)
        return;
    TcpListener listener = listening.Value;
    var view = new ServerView();
    Thread server = StartServer(listener, CreateServerOptions(), view);
    var options = CreateClientOptions();
    options.EnabledProtocols = version;
    var client = TlsSocket.Connect("127.0.0.1", listener.LocalEndPoint.Port, options);
    if (!client.Ok)
        return;
    TlsStream stream = client.Value.Stream;
    Console.WriteLine(what + " secrets:");
    if (version == TlsProtocolVersion.Tls13)
    {
        Console.WriteLine("  handshake secrets wiped once connected: " +
                          $"{AreTlsTestHandshakeSecretsWiped(stream)}");
        stream.UpdateTrafficKeys(true);
    }
    Console.WriteLine("  all wiped before close: " + $"{AreTlsTestSecretsWiped(stream)}");
    client.Value.Close();
    Console.WriteLine("  all wiped after close: " + $"{AreTlsTestSecretsWiped(stream)}");
    server.Join();
    listener.Close();
}

int Main()
{
    CheckCookieRetry();
    CheckEarlyData(20000u);
    CheckEarlyData(40000u);

    var options = CreateClientOptions();
    options.EnabledProtocols = TlsProtocolVersion.Tls13;
    Console.WriteLine("second ClientHello echoing a cookie:");
    Console.WriteLine("  of 100 bytes: " +
                      DescribeTlsError(BuildTlsTestRetryWithCookie(options, 100u)));
    Console.WriteLine("  of 65533 bytes: " +
                      DescribeTlsError(BuildTlsTestRetryWithCookie(options, 65533u)));

    Console.WriteLine("length prefixes:");
    Console.WriteLine("  255 in one byte: " + $"{FitsTlsTestVector(1u, 255u)}");
    Console.WriteLine("  256 in one byte: " + $"{FitsTlsTestVector(1u, 256u)}");
    Console.WriteLine("  65535 in two bytes: " + $"{FitsTlsTestVector(2u, 65535u)}");
    Console.WriteLine("  65536 in two bytes: " + $"{FitsTlsTestVector(2u, 65536u)}");

    Console.WriteLine("sequence number at its end:");
    Console.WriteLine("  TLS 1.3: " + SealTlsTestRecordsAtSequenceEnd(false));
    Console.WriteLine("  TLS 1.2: " + SealTlsTestRecordsAtSequenceEnd(true));

    CheckSecretsWiped(TlsProtocolVersion.Tls13, "TLS 1.3");
    CheckSecretsWiped(TlsProtocolVersion.Tls12, "TLS 1.2");
    return 0;
}
