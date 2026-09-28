// SPDX-License-Identifier: 0BSD
// HTTP/1.1 against a scripted server on the loopback: the methods, fields
// both ways, every way a body is framed, interim responses, bodies that are
// absent by rule, a body streamed before it has all arrived, and
// EnsureSuccessStatusCode.
module HttpBasics;

import Standard.Collections;
import Standard.Console;
import Standard.IO;
import Standard.Net.Http;
import Standard.Text;
import Standard.Threading;
import Standard.Time;
import HttpTestServer;

/// What the route for a streamed body and main share: main releases the
/// rest of the body once it holds the response.
class StreamGate
{
    public AtomicBool Released = new AtomicBool(false);
    public AtomicBool ReleasedInTime = new AtomicBool(false);

    /// Whether main has released the body, noting that it did in time.
    public bool IsReleased()
    {
        if (!Released.Read())
            return false;
        ReleasedInTime.Write(true);
        return true;
    }
}

/// A stream with no length and no position, so that content over it is sent
/// chunked.
class OneWayStream : IStream
{
    private byte[] _data;
    private nuint _at = 0u;

    public OneWayStream(String text) => _data = text.ToBytes();

    public bool CanRead => true;
    public bool CanWrite => false;
    public bool CanSeek => false;

    public nuint Read(byte[] buffer, nuint offset, nuint count)
    {
        // A few bytes at a time, so that the body goes as several chunks.
        nuint part = _data.Length - _at;
        if (part > 7u)
            part = 7u;
        if (part > count)
            part = count;
        for (nuint i = 0u; i < part; i++)
            buffer[offset + i] = _data[_at + i];
        _at += part;
        return part;
    }

    public nuint Write(byte[] buffer, nuint offset, nuint count) => 0u;
    public long Position => -1;
    public long Length => -1;
    public bool Seek(long offset, SeekOrigin origin) => false;
    public void Flush() { }
    public void Close() { }
    public IOError Error => IOError.None;
}

HttpTestReply RouteBasics(HttpTestRequest request, StreamGate gate)
{
    switch (request.Target.SubstringBefore("?"))
    {
        case "/hello":
            return HttpTestReply.CreateText(200, "OK", "X-Test: yes\r\nContent-Type: text/plain\r\n", "hello, world");
        case "/echo":
            return HttpTestReply.CreateText(200, "OK", "", DescribeTestRequest(request));
        case "/head":
            return HttpTestReply.CreateRaw("HTTP/1.1 200 OK\r\nContent-Length: 100\r\n\r\n");
        case "/chunked":
            return HttpTestReply.CreateRaw(
                "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nTrailer: X-Checksum\r\n\r\n" +
                "5\r\nhello\r\n7;name=value\r\n, chunk\r\n1\r\ny\r\n0\r\nX-Checksum: 42\r\nX-Other: 7\r\n\r\n");
        case "/interim":
            return HttpTestReply.CreateRaw(
                "HTTP/1.1 100 Continue\r\n\r\nHTTP/1.1 103 Early Hints\r\nLink: </style.css>\r\n\r\n" +
                "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nfinal");
        case "/no-content":
            return HttpTestReply.CreateRaw("HTTP/1.1 204 No Content\r\nContent-Length: 0\r\n\r\n");
        case "/not-modified":
            return HttpTestReply.CreateRaw("HTTP/1.1 304 Not Modified\r\nContent-Length: 50\r\nETag: \"v1\"\r\n\r\n");
        case "/until-close":
            return new HttpTestReply()
                .SendText("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nread to ")
                .Pause(50)
                .SendText("the close")
                .CloseConnection();
        case "/http10":
            return new HttpTestReply()
                .SendText("HTTP/1.0 200 OK\r\nContent-Length: 4\r\n\r\nold!")
                .CloseConnection();
        case "/streamed":
            return new HttpTestReply()
                .SendText("HTTP/1.1 200 OK\r\nContent-Length: 12\r\n\r\nfirst")
                .WaitUntil(() => gate.IsReleased(), 5000)
                .SendText(" second");
        case "/missing":
            return HttpTestReply.CreateText(404, "Not Found", "", "no such thing");
        case "/upload":
            return HttpTestReply.CreateText(201, "Created", "Location: /upload/1\r\n",
                                            DescribeTestRequest(request));
    }
    return HttpTestReply.CreateText(500, "Internal Server Error", "", "no route for " + request.Target);
}

/// The request as the server saw it: method, target, the fields a test can
/// predict, and the body.
String DescribeTestRequest(HttpTestRequest request)
{
    var text = new StringBuilder();
    text.Append(request.Method + " " + request.Target + " " + request.Version + "\n");
    foreach (var field in request.Fields)
    {
        String lower = field.ToLowerAscii();
        if (lower.StartsWith("host:"))
            text.Append("Host: 127.0.0.1:PORT\n");
        else
            text.Append(field + "\n");
    }
    if (request.Chunked)
        text.Append("(chunked)\n");
    foreach (var trailer in request.Trailers)
        text.Append("trailer " + trailer + "\n");
    text.Append("body [" + request.BodyText + "]");
    return text.ToText();
}

void ShowResponse(String label, Result<HttpResponseMessage, HttpError> sent)
{
    Console.WriteLine("-- " + label);
    if (!sent.Ok)
    {
        Console.WriteLine("failed: " + DescribeHttpError(sent.Error));
        return;
    }
    HttpResponseMessage response = sent.Value;
    Console.WriteLine(response.ToString());
    foreach (var field in response.Headers)
        Console.WriteLine("  " + field.Key + ": " + ", ".Join(field.Value));
    foreach (var field in response.Content.Headers)
        Console.WriteLine("  (content) " + field.Key + ": " + ", ".Join(field.Value));
    var body = response.Content.ReadAsString();
    if (body.Ok)
        Console.WriteLine("[" + body.Value + "]");
    else
        Console.WriteLine("body failed: " + DescribeHttpError(body.Error));
    foreach (var field in response.TrailingHeaders)
        Console.WriteLine("  (trailer) " + field.Key + ": " + ", ".Join(field.Value));
}

int Main()
{
    var gate = new StreamGate();
    HttpTestServer? started = HttpTestServer.StartServing((request) => RouteBasics(request, gate));
    if (started == null)
        return 1;
    HttpTestServer server = started;
    String origin = server.Origin;

    var client = new HttpClient();
    client.Timeout = TimeSpan.FromSeconds(8);
    client.DefaultRequestHeaders.UserAgent = "stainless-test/1.0";

    ShowResponse("GET", client.Get(origin + "/hello"));

    var request = new HttpRequestMessage(HttpMethod.Get, origin + "/echo?x=1&y=two");
    request.Headers.Add("X-Custom", "one");
    request.Headers.Add("X-Custom", "two");
    request.Headers.Accept = "text/plain";
    ShowResponse("fields sent", client.Send(request));

    ShowResponse("POST", client.Post(origin + "/echo", new StringContent("a posted body")));
    ShowResponse("PUT", client.Put(origin + "/echo", new ByteArrayContent("put bytes".ToBytes())));
    ShowResponse("PATCH", client.Patch(origin + "/echo",
                                       new StringContent("{}", null, "application/json")));
    ShowResponse("DELETE", client.Delete(origin + "/echo"));
    ShowResponse("HEAD", client.Send(new HttpRequestMessage(HttpMethod.Head, origin + "/head")));
    ShowResponse("OPTIONS", client.Send(new HttpRequestMessage(HttpMethod.Options, origin + "/echo")));
    ShowResponse("custom method", client.Send(new HttpRequestMessage(new HttpMethod("PROPFIND"),
                                                                     origin + "/echo")));

    ShowResponse("chunked response with trailers", client.Get(origin + "/chunked"));

    var upload = new HttpRequestMessage(HttpMethod.Post, origin + "/upload");
    upload.Content = new StreamContent(new OneWayStream("a body of unknown length, sent in chunks"));
    ShowResponse("chunked upload", client.Send(upload));

    var continued = new HttpRequestMessage(HttpMethod.Post, origin + "/echo");
    continued.Headers.ExpectContinue = true;
    continued.Content = new StringContent("after the interim answer");
    ShowResponse("Expect: 100-continue", client.Send(continued));

    ShowResponse("1xx skipped", client.Get(origin + "/interim"));
    ShowResponse("204", client.Get(origin + "/no-content"));
    ShowResponse("304", client.Get(origin + "/not-modified"));
    ShowResponse("after 304, same connection", client.Get(origin + "/hello"));
    ShowResponse("read to the close", client.Get(origin + "/until-close"));
    ShowResponse("HTTP/1.0", client.Get(origin + "/http10"));

    Console.WriteLine("-- ResponseHeadersRead");
    var streamed = client.Get(origin + "/streamed", HttpCompletionOption.ResponseHeadersRead);
    if (streamed.Ok)
    {
        HttpResponseMessage response = streamed.Value;
        gate.Released.Write(true);
        var body = response.Content.ReadAsStream();
        if (body.Ok)
        {
            var all = IO.ReadTextToEnd(body.Value);
            Console.WriteLine("[" + all.GetValueOrDefault("read failed") + "]");
        }
        Console.WriteLine("headers came before the body: " + Text.FromBool(gate.ReleasedInTime.Read()));
    }
    else
    {
        gate.Released.Write(true);
        Console.WriteLine("failed: " + DescribeHttpError(streamed.Error));
    }

    Console.WriteLine("-- EnsureSuccessStatusCode");
    var missing = client.Get(origin + "/missing");
    if (missing.Ok)
    {
        HttpResponseMessage response = missing.Value;
        Console.WriteLine("success: " + Text.FromBool(response.IsSuccessStatusCode));
        var ensured = response.EnsureSuccessStatusCode(out HttpFailure failure);
        Console.WriteLine("ensured: " + Text.FromBool(ensured.Ok) + ", " + failure.ToString());
    }
    var found = client.Get(origin + "/hello");
    if (found.Ok)
        Console.WriteLine("ensured 200: " + Text.FromBool(found.Value.EnsureSuccessStatusCode().Ok));

    Console.WriteLine("-- convenience");
    client.BaseAddress = new Uri(origin + "/");
    Console.WriteLine("GetString: " + client.GetString("hello").GetValueOrDefault("failed"));
    var bytes = client.GetByteArray("hello");
    Console.WriteLine("GetByteArray: " + Text.FromInteger((long)bytes.GetValueOrDefault(new byte[0u]).Length));
    var stream = client.GetStream(new Uri(origin + "/hello"));
    if (stream.Ok)
        Console.WriteLine("GetStream: " + IO.ReadTextToEnd(stream.Value).GetValueOrDefault("failed"));
    var refused = client.GetString("missing");
    Console.WriteLine("GetString 404: " + (refused.Ok ? "ok" : DescribeHttpError(refused.Error)));

    client.Dispose();
    server.StopServing();
    Console.WriteLine("-- server");
    foreach (var line in server.Log)
        Console.WriteLine(line);
    return 0;
}
