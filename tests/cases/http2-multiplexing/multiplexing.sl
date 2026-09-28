// SPDX-License-Identifier: 0BSD
// Several requests on one HTTP/2 connection: six threads at once, a server
// that allows one stream at a time, a GOAWAY that leaves a request
// unprocessed, a stream the server resets or refuses, one that times out
// while others carry on, a streamed body held back by flow control, and a
// PING. That the requests shared a connection is proven by the server's
// count of connections and by the streams it saw open together.
module Http2Multiplexing;

import Standard.Collections;
import Standard.Console;
import Standard.IO;
import Standard.Net.Http;
import Standard.Net.Security;
import Standard.Security.Cryptography;
import Standard.Text;
import Standard.Threading;
import Standard.Time;

[Embed("ed25519.crt.pem")] static readonly byte[] ServerCertificate;
[Embed("ed25519.key.pem")] static readonly byte[] ServerKey;

String ConvertToText(byte[] bytes) => Text.FromBytes(&bytes[0u], bytes.Length);

TlsServerOptions? CreateServerOptions()
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
    options.ApplicationProtocols.Add("h2");
    return options;
}

/// What a route needs to know about the server it runs in, which does not
/// exist until the route has been handed to it.
class Scene
{
    public Http2TestServer? Server = null;
    public AtomicInt Refusals = new AtomicInt(0);

    public int StreamsSeen => Server is Http2TestServer server ? server.StreamsSeen : 0;
}

Http2TestReply RouteStreams(Http2TestRequest request, Scene scene)
{
    String where = "conn " + Text.FromInteger((long)request.Connection) + ", stream " +
                   Text.FromInteger((long)request.Stream);
    if (request.Path.StartsWith("/together/"))
    {
        return Http2TestReply.CreateText(200, request.Path + " on conn " + Text.FromInteger((long)request.Connection))
                             .WaitUntil(() => scene.StreamsSeen >= 3, 5000);
    }
    if (request.Path.StartsWith("/hold/"))
    {
        return Http2TestReply.CreateText(200, request.Path + " on conn " + Text.FromInteger((long)request.Connection))
                             .WaitUntil(() => scene.StreamsSeen >= 6, 5000);
    }
    switch (request.Path)
    {
        case "/slow":
            return Http2TestReply.CreateText(200, "slow on conn " + Text.FromInteger((long)request.Connection))
                                 .Pause(150);
        case "/first":
            return Http2TestReply.CreateText(200, "first on " + where)
                                 .WaitUntil(() => scene.StreamsSeen >= 2, 5000);
        case "/second":
            if (request.Connection == 1)
                return new Http2TestReply().SendGoAway(request.Stream - 2u);
            return Http2TestReply.CreateText(200, request.Method + " " + request.BodyText + " on " + where);
        case "/reset":
            return new Http2TestReply().ResetStream(2u);
        case "/refuse-once":
            if (scene.Refusals.Increment() == 1)
                return new Http2TestReply().ResetStream(7u);
            return Http2TestReply.CreateText(200, "accepted on " + where);
        case "/silent":
            return new Http2TestReply().StaySilent();
        case "/big":
        {
            var body = new byte[1048576u];
            for (nuint i = 0u; i < body.Length; i++)
                body[i] = (byte)(i % 251u);
            return new Http2TestReply().SetBody(body);
        }
    }
    return Http2TestReply.CreateText(200, "quick on " + where);
}

HttpClient CreateHttp2Client(int windowSize, TimeSpan timeout)
{
    var handler = new HttpClientHandler();
    handler.ServerCertificateCustomValidationCallback = HttpClientHandler.DangerousAcceptAnyServerCertificateValidator;
    handler.InitialHttp2StreamWindowSize = windowSize;
    var client = new HttpClient(handler);
    client.Timeout = timeout;
    client.DefaultRequestVersion = HttpVersion.Version20;
    client.DefaultVersionPolicy = HttpVersionPolicy.RequestVersionExact;
    return client;
}

String DescribeOutcome(Result<HttpResponseMessage, HttpError> sent, HttpFailure failure)
{
    if (!sent.Ok)
    {
        String code = failure.ProtocolErrorCode != 0 ? ", code " + Text.FromInteger(failure.ProtocolErrorCode) : "";
        return $"{sent.Error}" + code + " (" + failure.Message + ")";
    }
    HttpResponseMessage response = sent.Value;
    var body = response.Content.ReadAsString();
    return Text.FromInteger((long)(int)response.StatusCode) + " " +
           (body.Ok ? body.Value : "the body failed: " + $"{body.Error}");
}

String FetchText(HttpClient client, String uri)
{
    var request = new HttpRequestMessage(HttpMethod.Get, uri);
    request.Version = HttpVersion.Version20;
    request.VersionPolicy = HttpVersionPolicy.RequestVersionExact;
    var sent = client.Send(request, HttpCompletionOption.ResponseContentRead, out HttpFailure failure);
    return DescribeOutcome(sent, failure);
}

/// Waits up to five seconds for `condition`.
bool AwaitCondition(Http2TestCondition condition)
{
    for (int waited = 0; waited < 5000; waited += 5)
    {
        if (condition())
            return true;
        Sleep(5u);
    }
    return false;
}

void ShowConcurrent(String origin, Http2TestServer server)
{
    Console.WriteLine("-- six threads, one connection");
    HttpClient client = CreateHttp2Client(1048576, TimeSpan.FromSeconds(8));
    var results = new String[6u];
    var threads = new List<Thread>();
    for (nuint i = 0u; i < 6u; i++)
    {
        nuint index = i;
        threads.Add(new Thread(() => results[index] = FetchText(client, origin + "/hold/" +
                                                                 Text.FromInteger((long)index))));
    }
    foreach (var thread in threads)
        thread.Join();
    for (nuint i = 0u; i < 6u; i++)
        Console.WriteLine("  thread " + Text.FromInteger((long)i) + ": " + results[i]);
    Console.WriteLine("connections: " + Text.FromInteger((long)server.Accepts));
    Console.WriteLine("streams open at once, at most: " + Text.FromInteger((long)server.MostOpenStreams));
    Console.WriteLine("PING answered: " + Text.FromBool(server.HasLogged("PING answered with \"pingpong\"")));
    client.Dispose();
}

void ShowSerialised(String origin, Http2TestServer server)
{
    Console.WriteLine("-- MAX_CONCURRENT_STREAMS 1");
    HttpClient client = CreateHttp2Client(1048576, TimeSpan.FromSeconds(8));
    var results = new String[3u];
    var threads = new List<Thread>();
    for (nuint i = 0u; i < 3u; i++)
    {
        nuint index = i;
        threads.Add(new Thread(() => results[index] = FetchText(client, origin + "/slow")));
    }
    foreach (var thread in threads)
        thread.Join();
    for (nuint i = 0u; i < 3u; i++)
        Console.WriteLine("  thread " + Text.FromInteger((long)i) + ": " + results[i]);
    Console.WriteLine("connections: " + Text.FromInteger((long)server.Accepts));
    Console.WriteLine("streams open at once, at most: " + Text.FromInteger((long)server.MostOpenStreams));
    client.Dispose();
}

void ShowMultipleConnections(String origin, Http2TestServer server)
{
    Console.WriteLine("-- MAX_CONCURRENT_STREAMS 1, with EnableMultipleHttp2Connections");
    HttpClient client = CreateHttp2Client(1048576, TimeSpan.FromSeconds(8));
    client.Handler.EnableMultipleHttp2Connections = true;
    var results = new String[3u];
    var threads = new List<Thread>();
    for (nuint i = 0u; i < 3u; i++)
    {
        nuint index = i;
        threads.Add(new Thread(() => results[index] = FetchText(client, origin + "/together/" +
                                                                 Text.FromInteger((long)index))));
    }
    foreach (var thread in threads)
        thread.Join();
    for (nuint i = 0u; i < 3u; i++)
        Console.WriteLine("  thread " + Text.FromInteger((long)i) + ": " + (results[i].StartsWith("200 /together/")
                                                                            ? "200, together" : results[i]));
    Console.WriteLine("connections: " + Text.FromInteger((long)server.Accepts));
    client.Dispose();
}

void ShowGoAway(String origin, Http2TestServer server)
{
    Console.WriteLine("-- GOAWAY with a request unprocessed");
    HttpClient client = CreateHttp2Client(1048576, TimeSpan.FromSeconds(8));
    var results = new String[1u];
    var first = new Thread(() => results[0u] = FetchText(client, origin + "/first"));
    AwaitCondition(() => server.StreamsSeen >= 1);
    var request = new HttpRequestMessage(HttpMethod.Post, origin + "/second");
    request.Version = HttpVersion.Version20;
    request.VersionPolicy = HttpVersionPolicy.RequestVersionExact;
    request.Content = new StringContent("a POST");
    var sent = client.Send(request, HttpCompletionOption.ResponseContentRead, out HttpFailure failure);
    first.Join();
    Console.WriteLine("  the first request: " + results[0u]);
    Console.WriteLine("  the second, sent again: " + DescribeOutcome(sent, failure));
    Console.WriteLine("connections: " + Text.FromInteger((long)server.Accepts));
    client.Dispose();
}

void ShowResets(String origin, Http2TestServer server)
{
    Console.WriteLine("-- streams the server resets");
    HttpClient client = CreateHttp2Client(1048576, TimeSpan.FromSeconds(8));
    Console.WriteLine("  RST_STREAM INTERNAL_ERROR: " + FetchText(client, origin + "/reset"));
    Console.WriteLine("  REFUSED_STREAM, then: " + FetchText(client, origin + "/refuse-once"));
    Console.WriteLine("  the connection after: " + FetchText(client, origin + "/quick"));
    Console.WriteLine("connections: " + Text.FromInteger((long)server.Accepts));
    client.Dispose();
}

void ShowTimeout(String origin, Http2TestServer server)
{
    Console.WriteLine("-- one stream times out, the others carry on");
    HttpClient client = CreateHttp2Client(1048576, TimeSpan.FromSeconds(1));
    var results = new String[1u];
    var silent = new Thread(() => results[0u] = FetchText(client, origin + "/silent"));
    AwaitCondition(() => server.StreamsSeen >= 1);
    Console.WriteLine("  alongside it: " + FetchText(client, origin + "/quick"));
    silent.Join();
    Console.WriteLine("  the silent one: " + results[0u]);
    AwaitCondition(() => server.HasLogged("CANCEL"));
    Console.WriteLine("  the server saw RST_STREAM CANCEL: " + Text.FromBool(server.HasLogged(", CANCEL")));
    Console.WriteLine("  after it: " + FetchText(client, origin + "/quick"));
    Console.WriteLine("connections: " + Text.FromInteger((long)server.Accepts));
    client.Dispose();
}

void ShowBackpressure(String origin, Http2TestServer server)
{
    Console.WriteLine("-- a streamed body held back by a 65 535-byte window");
    HttpClient client = CreateHttp2Client(65535, TimeSpan.FromSeconds(8));
    var request = new HttpRequestMessage(HttpMethod.Get, origin + "/big");
    request.Version = HttpVersion.Version20;
    request.VersionPolicy = HttpVersionPolicy.RequestVersionExact;
    var sent = client.Send(request, HttpCompletionOption.ResponseHeadersRead, out HttpFailure failure);
    if (!sent.Ok)
    {
        Console.WriteLine("  " + $"{sent.Error}" + " (" + failure.Message + ")");
        return;
    }
    HttpResponseMessage response = sent.Value;
    var opened = response.Content.ReadAsStream();
    if (!opened.Ok)
        return;
    IStream body = opened.Value;
    var block = new byte[10000u];
    nuint read = 0u;
    while (read < 10000u)
    {
        nuint got = body.Read(block, read, 10000u - read);
        if (got == 0u)
            break;
        read += got;
    }
    AwaitCondition(() => server.HasLogged("waited for window"));
    Sleep(200u);
    Console.WriteLine("  read " + Text.FromInteger((long)read) + " bytes; the server " +
                      (server.HasLogged("waited for window after 65535 bytes") ? "stopped at 65 535" : "did not stop"));
    response.Dispose();
    AwaitCondition(() => server.HasLogged(", CANCEL"));
    Console.WriteLine("  closed early, the server saw RST_STREAM CANCEL: " +
                      Text.FromBool(server.HasLogged(", CANCEL")));
    Console.WriteLine("  the connection after: " + FetchText(client, origin + "/quick"));
    Console.WriteLine("connections: " + Text.FromInteger((long)server.Accepts));
    client.Dispose();
}

Http2TestServer? StartScene(Scene scene, TlsServerOptions tls, uint maxStreams, bool pings)
{
    var settings = new Http2TestSettings();
    settings.MaxConcurrentStreams = maxStreams;
    settings.SendsPing = pings;
    Http2TestServer? started = Http2TestServer.StartServing((request) => RouteStreams(request, scene), tls, settings);
    scene.Server = started;
    return started;
}

int Main()
{
    TlsServerOptions? options = CreateServerOptions();
    if (options == null)
        return 1;
    TlsServerOptions tls = options;

    var scenes = new List<Scene>();
    var servers = new List<Http2TestServer>();
    for (int i = 0; i < 7; i++)
    {
        var scene = new Scene();
        Http2TestServer? started = StartScene(scene, tls, i == 1 || i == 6 ? 1u : 0u, i == 0);
        if (started == null)
            return 1;
        scenes.Add(scene);
        servers.Add(started);
    }

    ShowConcurrent(servers[0u].Origin, servers[0u]);
    ShowSerialised(servers[1u].Origin, servers[1u]);
    ShowMultipleConnections(servers[6u].Origin, servers[6u]);
    ShowGoAway(servers[2u].Origin, servers[2u]);
    ShowResets(servers[3u].Origin, servers[3u]);
    ShowTimeout(servers[4u].Origin, servers[4u]);
    ShowBackpressure(servers[5u].Origin, servers[5u]);

    foreach (var server in servers)
        server.StopServing();
    foreach (var scene in scenes)
        scene.Server = null;
    return 0;
}
