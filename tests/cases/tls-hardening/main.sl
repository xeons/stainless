// SPDX-License-Identifier: 0BSD
// Limits and refusals of both TLS versions that a well-behaved peer never
// meets: a client with no name to check, a refused certificate whose
// signature is wrong as well, a ClientHello of thousands of extensions,
// exporters asked for more than they can give, fatal and endless alerts,
// runs of empty records, and a HelloRequest where a TLS 1.2 client does not
// expect one.
module TlsHardening;

import Standard.Collections;
import Standard.Console;
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
[Embed("other.key.pem")]
static readonly byte[] OtherKey;

String ConvertToText(byte[] bytes) => Text.FromBytes(&bytes[0u], bytes.Length);

byte[] ReadCertificateDer()
{
    var block = PemEncoding.Find(ConvertToText(Ed25519Certificate));
    return block.Some ? block.Value.Data : new byte[0u];
}

TlsSigningKey? ReadSigningKey(byte[] pem)
{
    var key = TlsSigningKey.ImportFromPem(ConvertToText(pem));
    return key.Ok ? key.Value : null;
}

TlsServerOptions CreateServerOptions()
{
    var options = new TlsServerOptions();
    options.CertificateChain.Add(ReadCertificateDer());
    options.PrivateKey = ReadSigningKey(Ed25519Key);
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
    public String Host = "";
}

String DescribeClient(Result<TlsStream, TlsError> client) =>
    client.Ok ? "connected" : DescribeTlsError(client.Error);

// ------------------------------------------------------ an empty TargetHost

/// Whatever a validator was handed, for the report.
class HostSeen
{
    public String Host = "not asked";

    public TlsError AcceptAndRecord(List<byte[]> chain, String targetHost)
    {
        Host = "'" + targetHost + "'";
        return TlsError.None;
    }
}

void CheckEmptyTargetHost()
{
    Console.WriteLine("empty TargetHost:");
    Console.WriteLine("  default validator on its own: " +
                      DescribeTlsError(ValidateTlsCertificateChainByDefault(
                          CreateChain(), "")));

    var defaulted = new TlsClientOptions();
    Console.WriteLine("  client, default validator: " + RunEmptyHostClient(defaulted, null));

    var seen = new HostSeen();
    var custom = new TlsClientOptions();
    custom.CertificateValidator = seen.AcceptAndRecord;
    Console.WriteLine("  client, own validator: " + RunEmptyHostClient(custom, seen));
}

List<byte[]> CreateChain()
{
    var chain = new List<byte[]>();
    chain.Add(ReadCertificateDer());
    return chain;
}

String RunEmptyHostClient(TlsClientOptions options, HostSeen? seen)
{
    var listening = TcpListener.Listen("127.0.0.1", 0u);
    if (!listening.Ok)
        return "no listener";
    TcpListener listener = listening.Value;
    var server = new Thread(() =>
    {
        var accepted = TlsSocket.Accept(listener, CreateServerOptions());
        if (accepted.Ok)
            accepted.Value.Close();
    });
    var tcp = TcpClient.Connect("127.0.0.1", listener.LocalEndPoint.Port);
    if (!tcp.Ok)
        return "no connection";
    var client = TlsStream.AuthenticateAsClient(tcp.Value, options);
    if (client.Ok)
        client.Value.Close();
    server.Join();
    listener.Close();
    String outcome = DescribeClient(client);
    if (seen != null)
        outcome = outcome + ", validator saw " + seen.Host;
    return outcome;
}

// ------------------------------- a refused certificate with a bad signature

/// A client that presents the server's own certificate and signs with a key
/// that is not its, to a server that refuses every client certificate.
void CheckRefusedCertificateBadSignature(String what, TlsProtocolVersion version)
{
    var listening = TcpListener.Listen("127.0.0.1", 0u);
    if (!listening.Ok)
        return;
    TcpListener listener = listening.Value;
    var serverOptions = CreateServerOptions();
    serverOptions.ClientCertificateRequested = true;
    serverOptions.ClientCertificateValidator = RefuseEveryCertificate;
    var view = new ServerView();
    var server = new Thread(() =>
    {
        var accepted = TlsSocket.Accept(listener, serverOptions);
        view.Outcome = accepted.Ok ? "connected" : DescribeTlsError(accepted.Error);
        if (accepted.Ok)
            accepted.Value.Close();
    });

    var options = CreateClientOptions();
    options.EnabledProtocols = version;
    options.ClientCertificateChain.Add(ReadCertificateDer());
    options.ClientPrivateKey = ReadSigningKey(OtherKey);
    var tcp = TcpClient.Connect("127.0.0.1", listener.LocalEndPoint.Port);
    if (!tcp.Ok)
        return;
    var client = TlsStream.AuthenticateAsClient(tcp.Value, options);
    if (client.Ok)
    {
        var buffer = new byte[16u];
        client.Value.Read(buffer, 0u, buffer.Length);
        client.Value.Close();
    }
    server.Join();
    listener.Close();
    Console.WriteLine(what + ":");
    Console.WriteLine("  server: " + view.Outcome);
}

// -------------------------------------------------------- ClientHello limits

void CheckClientHellos()
{
    Console.WriteLine("ClientHello:");
    byte[] repeated = BuildTlsTestClientHello(BuildTlsTestExtensions(1000u, 3u, true));
    Console.WriteLine("  an extension twice: " +
                      DescribeTlsError(ParseTlsTestClientHello(repeated)));

    byte[] many = BuildTlsTestClientHello(BuildTlsTestExtensions(1000u, 16383u, false));
    Console.WriteLine("  " + Text.FromInteger((long)many.Length) + " bytes of " +
                      "16383 extensions: " + DescribeTlsError(ParseTlsTestClientHello(many)));

    byte[] manyRepeated = BuildTlsTestClientHello(BuildTlsTestExtensions(1000u, 16382u, true));
    Console.WriteLine("  16382 extensions and the first again: " +
                      DescribeTlsError(ParseTlsTestClientHello(manyRepeated)));

    var x25519 = new List<uint>();
    x25519.Add(29u);
    var twice = new List<uint>();
    twice.Add(29u);
    twice.Add(29u);
    var p256 = new List<uint>();
    p256.Add(23u);
    Console.WriteLine("  a key share group twice: " +
                      DescribeTlsError(ParseTlsTestClientHello(BuildTlsTestClientHello(
                          BuildTlsTestKeyShareExtensions(x25519, twice)))));
    Console.WriteLine("  a key share in a group not supported: " +
                      DescribeTlsError(ParseTlsTestClientHello(BuildTlsTestClientHello(
                          BuildTlsTestKeyShareExtensions(p256, x25519)))));
    Console.WriteLine("  one key share in a group supported: " +
                      DescribeTlsError(ParseTlsTestClientHello(BuildTlsTestClientHello(
                          BuildTlsTestKeyShareExtensions(x25519, x25519)))));
}

// ------------------------------------------------------------- the exporters

String DescribeExport(Result<byte[], TlsError> exported)
{
    if (!exported.Ok)
        return DescribeTlsError(exported.Error);
    return Text.FromInteger((long)exported.Value.Length) + " bytes";
}

void CheckExporters(String what, TlsProtocolVersion version)
{
    var listening = TcpListener.Listen("127.0.0.1", 0u);
    if (!listening.Ok)
        return;
    TcpListener listener = listening.Value;
    var server = new Thread(() =>
    {
        var accepted = TlsSocket.Accept(listener, CreateServerOptions());
        if (!accepted.Ok)
            return;
        var buffer = new byte[16u];
        accepted.Value.Read(buffer, 0u, buffer.Length);
        accepted.Value.Close();
    });
    var options = CreateClientOptions();
    options.EnabledProtocols = version;
    var client = TlsSocket.Connect("127.0.0.1", listener.LocalEndPoint.Port, options);
    if (!client.Ok)
        return;
    TlsStream stream = client.Value.Stream;

    Console.WriteLine(what + " exporter:");
    Console.WriteLine("  32 bytes: " +
                      DescribeExport(stream.ExportKeyingMaterial("EXPORTER-test", "c"u8, 32u)));
    if (version == TlsProtocolVersion.Tls13)
    {
        // SHA-256 gives at most 255 digests: 8160 bytes.
        Console.WriteLine("  8160 bytes: " + DescribeExport(
            stream.ExportKeyingMaterial("EXPORTER-test", "c"u8, 8160u)));
        Console.WriteLine("  8161 bytes: " + DescribeExport(
            stream.ExportKeyingMaterial("EXPORTER-test", "c"u8, 8161u)));
        var label = new StringBuilder();
        for (int i = 0; i < 250; i++)
            label.Append("x");
        Console.WriteLine("  a label of 250 bytes: " + DescribeExport(
            stream.ExportKeyingMaterial(label.ToText(), "c"u8, 32u)));
    }
    else
    {
        Console.WriteLine("  a context of 65535 bytes: " + DescribeExport(
            stream.ExportKeyingMaterial("EXPORTER-test", new byte[65535u], 32u)));
        Console.WriteLine("  a context of 65536 bytes: " + DescribeExport(
            stream.ExportKeyingMaterial("EXPORTER-test", new byte[65536u], 32u)));
    }
    client.Value.Close();
    server.Join();
    listener.Close();
}

// ---------------------------------------------------- records that say nothing

/// A server that handshakes, writes `count` raw alerts or empty records, then
/// a line of data; the client reads once and says how it ended.
void CheckRawRecords(String what, TlsProtocolVersion version, int count, bool alerts,
                     byte level, byte description)
{
    var listening = TcpListener.Listen("127.0.0.1", 0u);
    if (!listening.Ok)
        return;
    TcpListener listener = listening.Value;
    var server = new Thread(() =>
    {
        TcpClient tcp = listener.Accept();
        var accepted = AcceptTlsTestPeer(tcp, CreateServerOptions());
        if (!accepted.Ok)
            return;
        TlsTestPeer peer = accepted.Value;
        for (int i = 0; i < count; i++)
        {
            if (alerts)
            {
                peer.SendRawAlert(level, description);
            }
            else
            {
                peer.SendEmptyRecord();
            }
        }
        byte[] data = "data".ToBytes();
        peer.Stream.Write(data, 0u, data.Length);
        var buffer = new byte[16u];
        peer.Stream.Read(buffer, 0u, buffer.Length);
        peer.Stream.Close();
    });

    var tcp = TcpClient.Connect("127.0.0.1", listener.LocalEndPoint.Port);
    if (!tcp.Ok)
        return;
    var options = CreateClientOptions();
    options.EnabledProtocols = version;
    var client = TlsStream.AuthenticateAsClient(tcp.Value, options);
    if (!client.Ok)
        return;
    TlsStream tls = client.Value;
    var buffer = new byte[64u];
    nuint got = tls.Read(buffer, 0u, buffer.Length);
    Console.WriteLine(what + ":");
    String alert = tls.TlsErrorCode == TlsError.AlertReceived
        ? ", alert " + $"{tls.AlertDescription}"
        : "";
    Console.WriteLine("  client read " + Text.FromInteger((long)got) + " bytes, " +
                      DescribeTlsError(tls.TlsErrorCode) + alert);
    tls.Close();
    server.Join();
    listener.Close();
}

// ------------------------------------------ a HelloRequest before the Finished

void CheckHelloRequestBeforeChangeCipherSpec()
{
    var listening = TcpListener.Listen("127.0.0.1", 0u);
    if (!listening.Ok)
        return;
    TcpListener listener = listening.Value;
    var view = new ServerView();
    var server = new Thread(() =>
    {
        TcpClient tcp = listener.Accept();
        TlsError served = ServeTls12WithHelloRequest(tcp, CreateServerOptions(), "data".ToBytes());
        view.Outcome = DescribeTlsError(served);
    });
    var tcp = TcpClient.Connect("127.0.0.1", listener.LocalEndPoint.Port);
    if (!tcp.Ok)
        return;
    var options = CreateClientOptions();
    options.EnabledProtocols = TlsProtocolVersion.Tls12;
    var client = TlsStream.AuthenticateAsClient(tcp.Value, options);
    String read = "";
    if (client.Ok)
    {
        var buffer = new byte[64u];
        nuint got = client.Value.Read(buffer, 0u, buffer.Length);
        read = ", read " + Text.FromBytes(&buffer[0u], got);
        client.Value.Close();
    }
    server.Join();
    listener.Close();
    Console.WriteLine("TLS 1.2 HelloRequest before the server's change_cipher_spec:");
    Console.WriteLine("  client: " + DescribeClient(client) + read);
    Console.WriteLine("  server: " + view.Outcome);
}

int Main()
{
    CheckEmptyTargetHost();
    CheckRefusedCertificateBadSignature(
        "TLS 1.3 refused client certificate, wrong signature", TlsProtocolVersion.Tls13);
    CheckRefusedCertificateBadSignature(
        "TLS 1.2 refused client certificate, wrong signature", TlsProtocolVersion.Tls12);
    CheckClientHellos();
    CheckExporters("TLS 1.3", TlsProtocolVersion.Tls13);
    CheckExporters("TLS 1.2", TlsProtocolVersion.Tls12);

    // user_canceled is 90; a level of 2 is fatal.
    CheckRawRecords("TLS 1.2 fatal user_canceled, then data", TlsProtocolVersion.Tls12, 1,
                    true, 2, 90);
    CheckRawRecords("TLS 1.2 warning user_canceled, then data", TlsProtocolVersion.Tls12, 1,
                    true, 1, 90);
    CheckRawRecords("TLS 1.3 32 warnings, then data", TlsProtocolVersion.Tls13, 32, true, 1, 90);
    CheckRawRecords("TLS 1.3 33 warnings, then data", TlsProtocolVersion.Tls13, 33, true, 1, 90);
    CheckRawRecords("TLS 1.3 32 empty records, then data", TlsProtocolVersion.Tls13, 32, false,
                    0, 0);
    CheckRawRecords("TLS 1.3 33 empty records, then data", TlsProtocolVersion.Tls13, 33, false,
                    0, 0);
    CheckRawRecords("TLS 1.2 33 empty records, then data", TlsProtocolVersion.Tls12, 33, false,
                    0, 0);
    CheckHelloRequestBeforeChangeCipherSpec();
    return 0;
}
