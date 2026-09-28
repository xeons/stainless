// SPDX-License-Identifier: 0BSD
// Redirects: which statuses are followed, what each does to the method and
// the body, a Location relative to the request, Authorization kept within an
// origin and dropped outside it, a loop, and a redirect that is not
// followed.
module HttpRedirects;

import Standard.Collections;
import Standard.Console;
import Standard.IO;
import Standard.Net.Http;
import Standard.Text;
import Standard.Time;
import HttpTestServer;

/// A stream that can be read once, so its content cannot survive a 307.
class OnceStream : IStream
{
    private byte[] _data;
    private bool _read = false;

    public OnceStream(String text) => _data = text.ToBytes();

    public bool CanRead => !_read;
    public bool CanWrite => false;
    public bool CanSeek => false;

    public nuint Read(byte[] buffer, nuint offset, nuint count)
    {
        if (_read)
            return 0u;
        _read = true;
        for (nuint i = 0u; i < _data.Length; i++)
            buffer[offset + i] = _data[i];
        return _data.Length;
    }

    public nuint Write(byte[] buffer, nuint offset, nuint count) => 0u;
    public long Position => -1;
    public long Length => -1;
    public bool Seek(long offset, SeekOrigin origin) => false;
    public void Flush() { }
    public void Close() { }
    public IOError Error => IOError.None;
}

HttpTestReply CreateRedirect(int status, String location)
{
    return HttpTestReply.CreateText(status, "Redirect", "Location: " + location + "\r\n",
                                    "moved to " + location);
}

HttpTestReply RouteRedirects(HttpTestRequest request, String otherOrigin)
{
    String path = request.Target.SubstringBefore("?");
    if (path.StartsWith("/status/"))
    {
        // /status/NNN redirects with NNN to /landing.
        int status = (int)ParseTestDecimal(path.Substring(8u));
        return CreateRedirect(status, "/landing");
    }
    switch (path)
    {
        case "/landing":
        case "/docs/b":
        case "/absolute":
            return HttpTestReply.CreateText(200, "OK", "", DescribeRedirectedRequest(request));
        case "/docs/a/relative":
            return CreateRedirect(302, "../b?from=relative");
        case "/to-root":
            return CreateRedirect(301, "/absolute");
        case "/chain":
            return CreateRedirect(302, "/to-root");
        case "/to-other":
            return CreateRedirect(302, otherOrigin + "/landing");
        case "/loop":
            return CreateRedirect(302, "/loop");
        case "/nowhere":
            return HttpTestReply.CreateText(302, "Found", "", "no Location");
        case "/ftp":
            return CreateRedirect(302, "ftp://example.com/file");
    }
    return HttpTestReply.CreateText(404, "Not Found", "", "no route for " + path);
}

String DescribeRedirectedRequest(HttpTestRequest request)
{
    String authorization = request.HasField("Authorization") ? request.GetField("Authorization") : "none";
    String length = request.HasField("Content-Length") ? request.GetField("Content-Length") : "none";
    return request.Method + " " + request.Target + ", Authorization " + authorization +
           ", Content-Length " + length + ", body [" + request.BodyText + "]";
}

void ShowRedirected(String label, HttpClient client, HttpRequestMessage request)
{
    var sent = client.Send(request, HttpCompletionOption.ResponseContentRead, out HttpFailure failure);
    if (!sent.Ok)
    {
        Console.WriteLine(label + ": " + $"{sent.Error}" + " (" + failure.Message + ")");
        return;
    }
    HttpResponseMessage response = sent.Value;
    String body = response.Content.ReadAsString().GetValueOrDefault("body failed");
    String finalPath = "";
    if (response.RequestMessage is HttpRequestMessage last && last.RequestUri is Uri uri)
        finalPath = last.Method.Method + " " + uri.PathAndQuery;
    Console.WriteLine(label + ": " + Text.FromInteger((long)(int)response.StatusCode) + ", ended at " +
                      finalPath + ": " + body);
}

HttpRequestMessage CreatePost(String uri, String body)
{
    var request = new HttpRequestMessage(HttpMethod.Post, uri);
    request.Content = new StringContent(body);
    return request;
}

int Main()
{
    HttpTestServer? otherStarted = HttpTestServer.StartServing((request) => RouteRedirects(request, ""));
    if (otherStarted == null)
        return 1;
    HttpTestServer other = otherStarted;
    String otherOrigin = other.Origin;

    HttpTestServer? started = HttpTestServer.StartServing((request) => RouteRedirects(request, otherOrigin));
    if (started == null)
        return 1;
    HttpTestServer server = started;
    String origin = server.Origin;

    var client = new HttpClient();
    client.Timeout = TimeSpan.FromSeconds(8);

    Console.WriteLine("-- POST through each status");
    foreach (var status in [301, 302, 303, 307, 308])
    {
        String code = Text.FromInteger((long)status);
        ShowRedirected(code, client, CreatePost(origin + "/status/" + code, "the body"));
    }

    Console.WriteLine("-- HEAD through each status");
    foreach (var status in [301, 302, 303, 307, 308])
    {
        String code = Text.FromInteger((long)status);
        ShowRedirected(code, client, new HttpRequestMessage(HttpMethod.Head, origin + "/status/" + code));
    }

    Console.WriteLine("-- PUT through 303 and 307");
    var put = new HttpRequestMessage(HttpMethod.Put, origin + "/status/303");
    put.Content = new StringContent("put body");
    ShowRedirected("303", client, put);
    put = new HttpRequestMessage(HttpMethod.Put, origin + "/status/307");
    put.Content = new StringContent("put body");
    ShowRedirected("307", client, put);

    Console.WriteLine("-- a body that cannot be sent twice");
    var once = new HttpRequestMessage(HttpMethod.Post, origin + "/status/307");
    once.Content = new StreamContent(new OnceStream("only once"));
    ShowRedirected("307", client, once);

    Console.WriteLine("-- Locations");
    ShowRedirected("relative", client, new HttpRequestMessage(HttpMethod.Get, origin + "/docs/a/relative"));
    ShowRedirected("rooted", client, new HttpRequestMessage(HttpMethod.Get, origin + "/to-root"));
    ShowRedirected("no Location", client, new HttpRequestMessage(HttpMethod.Get, origin + "/nowhere"));
    ShowRedirected("ftp", client, new HttpRequestMessage(HttpMethod.Get, origin + "/ftp"));

    Console.WriteLine("-- Authorization");
    var same = new HttpRequestMessage(HttpMethod.Get, origin + "/to-root");
    same.Headers.Authorization = "Bearer secret";
    ShowRedirected("same origin", client, same);
    var away = new HttpRequestMessage(HttpMethod.Get, origin + "/to-other");
    away.Headers.Authorization = "Bearer secret";
    ShowRedirected("other origin", client, away);

    Console.WriteLine("-- limits");
    ShowRedirected("loop", client, new HttpRequestMessage(HttpMethod.Get, origin + "/loop"));
    var fewHandler = new HttpClientHandler();
    fewHandler.MaxAutomaticRedirections = 1;
    var few = new HttpClient(fewHandler);
    ShowRedirected("one allowed, one taken", few, new HttpRequestMessage(HttpMethod.Get, origin + "/to-root"));
    ShowRedirected("one allowed, two needed", few, new HttpRequestMessage(HttpMethod.Get, origin + "/chain"));
    few.Dispose();
    var noneHandler = new HttpClientHandler();
    noneHandler.AllowAutoRedirect = false;
    var none = new HttpClient(noneHandler);
    ShowRedirected("not following", none, new HttpRequestMessage(HttpMethod.Get, origin + "/to-root"));
    none.Dispose();

    client.Dispose();
    server.StopServing();
    other.StopServing();
    Console.WriteLine("-- the other origin saw");
    foreach (var line in other.Log)
        Console.WriteLine(line);
    return 0;
}
