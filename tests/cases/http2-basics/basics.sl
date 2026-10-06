// SPDX-License-Identifier: 0BSD
// HTTP/2 over the loopback: h2 through TLS and ALPN, h2c with prior
// knowledge, GET, POST and HEAD, fields both ways, trailers, an interim
// response, bodies past the 65 535-byte window in both directions, and which
// version each combination of version and policy ends up in.
module Http2Basics;

import Standard.Collections;
import Standard.Console;
import Standard.Net;
import Standard.Net.Http;
import Standard.Net.Security;
import Standard.Security.Cryptography;
import Standard.Text;
import Standard.Threading;
import Standard.Time;

[Embed("ed25519.crt.pem")]
static readonly byte[] ServerCertificate;
[Embed("ed25519.key.pem")]
static readonly byte[] ServerKey;

String ConvertToText(byte[] bytes) => Text.FromBytes(&bytes[0u], bytes.Length);

TlsServerOptions? CreateServerOptions(bool offersHttp2)
{
    var options = new TlsServerOptions();
    var block = PemEncoding.Find(ConvertToText(ServerCertificate));
    if (!block.Some)
        return null;
    options.CertificateChain.Add(block.Value.Data);
    var key = TlsSigningKey.ImportFromPem(ConvertToText(ServerKey));
    if (!key.Ok)
        return null;
    options.PrivateKey = key.Value;
    if (offersHttp2)
        options.ApplicationProtocols.Add("h2");
    options.ApplicationProtocols.Add("http/1.1");
    return options;
}

byte[] CreatePattern(nuint length)
{
    var bytes = new byte[length];
    for (nuint i = 0u; i < length; i++)
        bytes[i] = (byte)((i * 7u + i / 251u) % 256u);
    return bytes;
}

ulong ComputeChecksum(byte[] bytes)
{
    ulong sum = 0u;
    for (nuint i = 0u; i < bytes.Length; i++)
        sum = (sum * 31u + (ulong)bytes[i]) % 1000000007u;
    return sum;
}

Http2TestReply RouteBasics(Http2TestRequest request)
{
    switch (request.Path)
    {
        case "/hello":
            return Http2TestReply.CreateText(200, "hello over " + request.Protocol)
                                 .AddField("set-cookie", "a=1")
                                 .AddField("set-cookie", "b=2");
        case "/echo":
            return Http2TestReply.CreateText(200, request.Method + " of " +
                                             Text.FromInteger((long)request.Body.Length) + " bytes, checksum " +
                                             Text.FromInteger((long)ComputeChecksum(request.Body)));
        case "/fields":
        {
            var shown = new StringBuilder();
            String authority = request.Authority.StartsWith("127.0.0.1:") ? "127.0.0.1 and its port" : request.Authority;
            shown.Append(":authority " + authority + ", :scheme " + request.Scheme);
            foreach (var field in request.Fields)
                shown.Append("\n  " + field);
            return Http2TestReply.CreateText(200, shown.ToText());
        }
        case "/trailers":
            return Http2TestReply.CreateText(200, "body before trailers")
                                 .AddTrailer("x-checksum", "12345")
                                 .AddTrailer("x-status", "done");
        case "/early":
            return Http2TestReply.CreateText(200, "after an interim response").AddInterim(103);
        case "/large":
            return new Http2TestReply().SetBody(CreatePattern(300000u));
        case "/head":
            return Http2TestReply.CreateText(200, "a body HEAD never sees");
        case "/empty":
            return new Http2TestReply().AddField("x-empty", "yes");
        case "/version":
            return Http2TestReply.CreateText(200, request.Protocol);
    }
    return Http2TestReply.CreateText(404, "no route");
}

String DescribeVersion(Version version) => "HTTP/" + version.ToString(2);

void ShowResponse(String label, Result<HttpResponseMessage, HttpError> sent, HttpFailure failure)
{
    if (!sent.Ok)
    {
        Console.WriteLine(label + ": " + $"{sent.Error}" + " (" + failure.Message + ")");
        return;
    }
    HttpResponseMessage response = sent.Value;
    var body = response.Content.ReadAsString();
    Console.WriteLine(label + ": " + Text.FromInteger((long)(int)response.StatusCode) + " in " +
                      DescribeVersion(response.Version) + ", " +
                      (body.Ok ? body.Value : "the body failed: " + $"{body.Error}"));
}

void SendAndShow(String label, HttpClient client, HttpRequestMessage request)
{
    var sent = client.Send(request, HttpCompletionOption.ResponseContentRead, out HttpFailure failure);
    ShowResponse(label, sent, failure);
}

HttpRequestMessage CreateVersioned(HttpMethod method, String uri, Version version, HttpVersionPolicy policy)
{
    var request = new HttpRequestMessage(method, uri);
    request.Version = version;
    request.VersionPolicy = policy;
    return request;
}

HttpClient CreateTrustingClient()
{
    var handler = new HttpClientHandler();
    handler.ServerCertificateCustomValidationCallback = HttpClientHandler.DangerousAcceptAnyServerCertificateValidator;
    var client = new HttpClient(handler);
    client.Timeout = TimeSpan.FromSeconds(8);
    return client;
}

void ShowMatrix(HttpClient client, String origin)
{
    var versions = new List<Version>();
    versions.Add(HttpVersion.Version11);
    versions.Add(HttpVersion.Version20);
    versions.Add(HttpVersion.Version30);
    var policies = new List<HttpVersionPolicy>();
    policies.Add(HttpVersionPolicy.RequestVersionOrLower);
    policies.Add(HttpVersionPolicy.RequestVersionOrHigher);
    policies.Add(HttpVersionPolicy.RequestVersionExact);
    foreach (var version in versions)
    {
        foreach (var policy in policies)
        {
            var request = CreateVersioned(HttpMethod.Get, origin + "/version", version, policy);
            var sent = client.Send(request, HttpCompletionOption.ResponseContentRead, out HttpFailure failure);
            String label = "  " + version.ToString(2) + " " + $"{policy}";
            if (!sent.Ok)
            {
                Console.WriteLine(label + ": " + $"{sent.Error}");
                continue;
            }
            var body = sent.Value.Content.ReadAsString();
            Console.WriteLine(label + ": " + DescribeVersion(sent.Value.Version) + ", the server saw " +
                              body.GetValueOrDefault("?"));
        }
    }
}

int Main()
{
    TlsServerOptions? tls = CreateServerOptions(true);
    TlsServerOptions? http11Only = CreateServerOptions(false);
    if (tls == null || http11Only == null)
        return 1;
    var settings = new Http2TestSettings();
    Http2TestServer? secureStarted = Http2TestServer.StartServing(RouteBasics, tls, settings);
    Http2TestServer? plainStarted = Http2TestServer.StartServing(RouteBasics, null, settings);
    Http2TestServer? refusingStarted = Http2TestServer.StartServing(RouteBasics, http11Only, settings);
    if (secureStarted == null || plainStarted == null || refusingStarted == null)
        return 1;
    Http2TestServer secure = secureStarted;
    Http2TestServer plain = plainStarted;
    Http2TestServer refusing = refusingStarted;

    Console.WriteLine("-- h2 through TLS");
    HttpClient client = CreateTrustingClient();
    client.DefaultRequestVersion = HttpVersion.Version20;
    ShowResponse("GET /hello", client.Get(secure.Origin + "/hello"), new HttpFailure());
    var cookies = client.Get(secure.Origin + "/hello");
    if (cookies.Ok)
    {
        Console.WriteLine("  set-cookie: " + " | ".Join(cookies.Value.Headers.GetValues("set-cookie")));
        Console.WriteLine("  content-type: " + " | ".Join(cookies.Value.Content.Headers.GetValues("content-type")));
    }
    ShowResponse("POST /echo", client.Post(secure.Origin + "/echo", new StringContent("twelve bytes")),
                 new HttpFailure());

    var head = client.Send(CreateVersioned(HttpMethod.Head, secure.Origin + "/head", HttpVersion.Version20,
                                           HttpVersionPolicy.RequestVersionOrLower));
    if (head.Ok)
    {
        var length = head.Value.Content.Headers.ContentLength;
        Console.WriteLine("HEAD /head: " + Text.FromInteger((long)(int)head.Value.StatusCode) + ", content-length " +
                          (length is Some known ? Text.FromInteger(known.Value) : "none") + ", body \"" +
                          head.Value.Content.ReadAsString().GetValueOrDefault("?") + "\"");
    }
    ShowResponse("GET /empty", client.Get(secure.Origin + "/empty"), new HttpFailure());

    var trailers = client.Get(secure.Origin + "/trailers");
    if (trailers.Ok)
    {
        Console.WriteLine("GET /trailers: " + trailers.Value.Content.ReadAsString().GetValueOrDefault("?"));
        Console.WriteLine("  trailers: x-checksum " +
                          ",".Join(trailers.Value.TrailingHeaders.GetValues("x-checksum")) + ", x-status " +
                          ",".Join(trailers.Value.TrailingHeaders.GetValues("x-status")));
    }
    ShowResponse("GET /early", client.Get(secure.Origin + "/early"), new HttpFailure());

    var fields = CreateVersioned(HttpMethod.Get, secure.Origin + "/fields", HttpVersion.Version20,
                                 HttpVersionPolicy.RequestVersionOrLower);
    fields.Headers.TryAddWithoutValidation("X-Mixed-Case", "Value");
    fields.Headers.TryAddWithoutValidation("Connection", "keep-alive");
    fields.Headers.TryAddWithoutValidation("Keep-Alive", "timeout=5");
    fields.Headers.TryAddWithoutValidation("Upgrade", "h2c");
    fields.Headers.TryAddWithoutValidation("TE", "trailers");
    fields.Headers.TryAddWithoutValidation("Cookie", "first=1; second=2");
    fields.Headers.TryAddWithoutValidation("Authorization", "Bearer secret");
    SendAndShow("GET /fields", client, fields);
    Console.WriteLine("connections to the TLS server: " + Text.FromInteger((long)secure.Accepts));

    Console.WriteLine("-- past the 65 535-byte window");
    var smallHandler = new HttpClientHandler();
    smallHandler.ServerCertificateCustomValidationCallback =
        HttpClientHandler.DangerousAcceptAnyServerCertificateValidator;
    smallHandler.InitialHttp2StreamWindowSize = 65535;
    var small = new HttpClient(smallHandler);
    small.Timeout = TimeSpan.FromSeconds(8);
    small.DefaultRequestVersion = HttpVersion.Version20;
    int updatesBefore = secure.WindowUpdates;
    var large = small.GetByteArray(secure.Origin + "/large");
    if (large.Ok)
    {
        byte[] expected = CreatePattern(300000u);
        Console.WriteLine("300 000 bytes down: " + Text.FromInteger((long)large.Value.Length) + " arrived, " +
                          (ComputeChecksum(large.Value) == ComputeChecksum(expected) ? "intact" : "corrupt"));
    }
    else
    {
        Console.WriteLine("300 000 bytes down: " + $"{large.Error}");
    }
    Console.WriteLine("  the client sent the stream WINDOW_UPDATE: " +
                      Text.FromBool(secure.WindowUpdates > updatesBefore));
    byte[] upload = CreatePattern(300000u);
    ShowResponse("300 000 bytes up", small.Post(secure.Origin + "/echo", new ByteArrayContent(upload)),
                 new HttpFailure());
    Console.WriteLine("  expected checksum " + Text.FromInteger((long)ComputeChecksum(upload)));
    Console.WriteLine("  the client overran a window: " + Text.FromBool(secure.HasLogged("sent past its window")));
    small.Dispose();

    Console.WriteLine("-- h2c with prior knowledge");
    var plainClient = new HttpClient();
    plainClient.Timeout = TimeSpan.FromSeconds(8);
    SendAndShow("2.0 exact", plainClient, CreateVersioned(HttpMethod.Get, plain.Origin + "/hello",
                                                          HttpVersion.Version20, HttpVersionPolicy.RequestVersionExact));
    SendAndShow("2.0 or higher", plainClient, CreateVersioned(HttpMethod.Get, plain.Origin + "/version",
                                                              HttpVersion.Version20,
                                                              HttpVersionPolicy.RequestVersionOrHigher));
    SendAndShow("2.0 or lower", plainClient, CreateVersioned(HttpMethod.Get, plain.Origin + "/version",
                                                             HttpVersion.Version20,
                                                             HttpVersionPolicy.RequestVersionOrLower));
    SendAndShow("1.1 or higher", plainClient, CreateVersioned(HttpMethod.Get, plain.Origin + "/version",
                                                              HttpVersion.Version11,
                                                              HttpVersionPolicy.RequestVersionOrHigher));
    SendAndShow("POST over h2c", plainClient, CreateEchoRequest(plain.Origin));
    plainClient.Dispose();

    Console.WriteLine("-- versions and policies, a server offering h2 and http/1.1");
    HttpClient matrix = CreateTrustingClient();
    ShowMatrix(matrix, secure.Origin);
    matrix.Dispose();

    Console.WriteLine("-- versions and policies, a server offering http/1.1 alone");
    HttpClient fallback = CreateTrustingClient();
    ShowMatrix(fallback, refusing.Origin);
    fallback.Dispose();

    Console.WriteLine("-- Expect: 100-continue");
    var expecting = CreateVersioned(HttpMethod.Post, secure.Origin + "/echo", HttpVersion.Version20,
                                    HttpVersionPolicy.RequestVersionExact);
    expecting.Headers.ExpectContinue = true;
    expecting.Content = new StringContent("after the go-ahead");
    SendAndShow("POST expecting 100", client, expecting);
    Console.WriteLine("  the server said 100 first: " + Text.FromBool(secure.HasLogged("sent 100")));

    Console.WriteLine("-- through a proxy");
    TunnelProxy? tunnelStarted = TunnelProxy.StartTunnelling();
    if (tunnelStarted == null)
        return 1;
    TunnelProxy tunnel = tunnelStarted;
    var proxiedHandler = new HttpClientHandler();
    proxiedHandler.ServerCertificateCustomValidationCallback =
        HttpClientHandler.DangerousAcceptAnyServerCertificateValidator;
    proxiedHandler.Proxy = new WebProxy(tunnel.Origin);
    var proxied = new HttpClient(proxiedHandler);
    proxied.Timeout = TimeSpan.FromSeconds(8);
    SendAndShow("https in a CONNECT tunnel", proxied,
                CreateVersioned(HttpMethod.Get, secure.Origin + "/version", HttpVersion.Version20,
                                HttpVersionPolicy.RequestVersionExact));
    SendAndShow("http in absolute form, 2.0 required", proxied,
                CreateVersioned(HttpMethod.Get, plain.Origin + "/version", HttpVersion.Version20,
                                HttpVersionPolicy.RequestVersionExact));
    proxied.Dispose();
    tunnel.StopTunnelling();
    foreach (var line in tunnel.Log)
        Console.WriteLine("  the proxy saw: " + line);

    Console.WriteLine("-- the default is HTTP/1.1, as .NET's is");
    HttpClient defaults = CreateTrustingClient();
    ShowResponse("GET with no version set", defaults.Get(secure.Origin + "/version"), new HttpFailure());
    defaults.Dispose();

    client.Dispose();
    secure.StopServing();
    plain.StopServing();
    refusing.StopServing();
    return 0;
}

/// A proxy that does nothing but CONNECT: it reads the request head, dials
/// the target, says 200, and copies both ways until either end stops.
class TunnelProxy
{
    private TcpListener _listener;
    private AtomicBool _stopping = new AtomicBool(false);
    private Mutex<int> _lock = new Mutex<int>(0);
    private List<TcpClient> _sockets = new List<TcpClient>();
    private List<Thread> _threads = new List<Thread>();
    private Thread? _acceptor;
    public List<String> Log = new List<String>();

    private TunnelProxy(TcpListener listener) => _listener = listener;

    public static TunnelProxy? StartTunnelling()
    {
        var listening = TcpListener.Listen("127.0.0.1", 0u);
        if (!listening.Ok)
            return null;
        var proxy = new TunnelProxy(listening.Value);
        proxy._acceptor = new Thread(() => proxy.AcceptTunnels());
        return proxy;
    }

    public String Origin => "http://127.0.0.1:" + Text.FromInteger((long)_listener.LocalEndPoint.Port);

    public void StopTunnelling()
    {
        _stopping.Write(true);
        if (_acceptor is Thread acceptor)
            acceptor.Join();
        {
            var held = _lock.Enter();
            foreach (var socket in _sockets)
                socket.Underlying.Shutdown(SocketShutdown.Both);
        }
        foreach (var thread in _threads)
            thread.Join();
        foreach (var socket in _sockets)
            socket.Close();
        _listener.Close();
    }

    private void AcceptTunnels()
    {
        while (!this._stopping.Read())
        {
            if (!this._listener.Pending(10))
                continue;
            TcpClient client = this._listener.Accept();
            this.KeepSocket(client);
            this._threads.Add(new Thread(() => this.ServeTunnel(client)));
        }
    }

    private void KeepSocket(TcpClient socket)
    {
        var held = this._lock.Enter();
        this._sockets.Add(socket);
    }

    private void ServeTunnel(TcpClient client)
    {
        var head = new StringBuilder();
        var one = new byte[1u];
        while (!head.ToText().EndsWith("\r\n\r\n"))
        {
            if (client.Read(one, 0u, 1u) == 0u)
                return;
            head.AppendByte(one[0u]);
        }
        String[] words = head.ToText().Split(' ');
        if (words.Length < 2u || words[0u] != "CONNECT")
            return;
        String target = words[1u];
        {
            var held = this._lock.Enter();
            this.Log.Add("CONNECT to the TLS server");
        }
        String[] parts = target.Split(':');
        if (parts.Length != 2u)
            return;
        var dialled = TcpClient.Connect(parts[0u], ParsePort(parts[1u]));
        if (!dialled.Ok)
            return;
        TcpClient server = dialled.Value;
        this.KeepSocket(server);
        client.SendText("HTTP/1.1 200 Connection Established\r\n\r\n");
        var upstream = new Thread(() => CopyTunnel(client, server));
        CopyTunnel(server, client);
        upstream.Join();
    }
}

ushort ParsePort(String text)
{
    uint value = 0u;
    for (nuint i = 0u; i < text.ByteLength(); i++)
        value = value * 10u + (uint)(text.GetByteAt(i) - (byte)'0');
    return (ushort)value;
}

/// Copies `from` into `to` until `from` ends, then ends `to`.
void CopyTunnel(TcpClient from, TcpClient to)
{
    var block = new byte[16384u];
    while (true)
    {
        nuint got = from.Read(block, 0u, block.Length);
        if (got == 0u)
            break;
        nuint at = 0u;
        while (at < got)
        {
            nuint wrote = to.Write(block, at, got - at);
            if (wrote == 0u)
                break;
            at += wrote;
        }
        if (at < got)
            break;
    }
    to.Underlying.Shutdown(SocketShutdown.Send);
}

HttpRequestMessage CreateEchoRequest(String origin)
{
    var request = CreateVersioned(HttpMethod.Post, origin + "/echo", HttpVersion.Version20,
                                  HttpVersionPolicy.RequestVersionExact);
    request.Content = new StringContent("sent in the clear");
    return request;
}

