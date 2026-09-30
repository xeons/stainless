// SPDX-License-Identifier: 0BSD
// What a client MUST NOT let through or be talked into: a body past its
// Content-Length, a head trickled past the timeout, an interim response
// taken as final, a method changed or a field carried across a redirect it
// was not meant for, a host that would split a request line, httpoxy under
// CGI, and a cookie jar without bounds.
module HttpHardening;

import Standard.Collections;
import Standard.Console;
import Standard.Env;
import Standard.IO;
import Standard.Net;
import Standard.Net.Http;
import Standard.Text;
import Standard.Threading;
import Standard.Time;
import HttpRawServer;

String DescribeSent(Result<HttpResponseMessage, HttpError> sent, HttpFailure failure)
{
    if (!sent.Ok)
        return $"{sent.Error}" + " (" + failure.Message + ")";
    HttpResponseMessage response = sent.Value;
    String body = response.Content.ReadAsString().GetValueOrDefault("body failed");
    return Text.FromInteger((long)(int)response.StatusCode) + " [" + body + "]";
}

/// A request line and the fields a redirect might carry, with the ports of
/// the two servers named rather than numbered.
String DescribeRedirectedHead(String head, String first, String second)
{
    String host = FindRawField(head, "Host").Replace(first, "first").Replace(second, "second");
    return FindRawRequestLine(head) + "; Host " + host + "; Cookie " + FindRawField(head, "Cookie") +
           "; Authorization " + FindRawField(head, "Authorization") +
           "; Proxy-Authorization " + FindRawField(head, "Proxy-Authorization");
}

void TestOverlongBodies()
{
    Console.WriteLine("-- a body longer than its Content-Length");
    var log = new RawLog();
    RawServer server = RawServer.StartRawServer((connection, index) =>
    {
        String head = ReadRawHead(connection);
        String rest = ReadRawBytes(connection, 1000000u);
        String line = head.IsEmpty ? "(nothing)" : FindRawRequestLine(head);
        log.AddLine("  server: " + line + ", declared " + FindRawField(head, "Content-Length") +
                    ", within it: " + (rest.ByteLength() <= 20000u ? "yes" : "no") +
                    ", smuggled request seen: " + (rest.Contains("GET /admin") ? "yes" : "no"));
        connection.Close();
    })!;

    var client = new HttpClient();
    client.Timeout = TimeSpan.FromSeconds(5);
    String hidden = "GET /admin HTTP/1.1\r\nHost: internal\r\n\r\n";

    // One write, all of it past the limit.
    var small = new HttpRequestMessage(HttpMethod.Post, server.Origin + "/small");
    var smallContent = new StringContent("a".Repeat(100u) + hidden + "b".Repeat(40000u));
    smallContent.Headers.ContentLength = 100;
    small.Content = smallContent;
    var sent = client.Send(small, HttpCompletionOption.ResponseContentRead, out HttpFailure smallFailure);
    Console.WriteLine("small: " + DescribeSent(sent, smallFailure));

    // Blocks of a stream, the first within the limit and a later one past it.
    var large = new HttpRequestMessage(HttpMethod.Post, server.Origin + "/large");
    var largeContent = new StreamContent(new MemoryStream(("c".Repeat(20000u) + hidden + "d".Repeat(60000u)).ToBytes()));
    largeContent.Headers.ContentLength = 20000;
    large.Content = largeContent;
    sent = client.Send(large, HttpCompletionOption.ResponseContentRead, out HttpFailure largeFailure);
    Console.WriteLine("large: " + DescribeSent(sent, largeFailure));

    client.Dispose();
    server.StopRawServer();
    // The two connections end in either order.
    List<String> lines = log.CopyLines();
    lines.Sort();
    foreach (var line in lines)
        Console.WriteLine(line);
}

void TestTrickledHead()
{
    Console.WriteLine("-- a head sent a byte at a time");
    RawServer server = RawServer.StartRawServer((connection, index) =>
    {
        ReadRawHead(connection);
        connection.SendText("HTTP/1.1 200 OK\r\n");
        String field = "X-Slow: abcdefgh\r\n";
        for (nuint i = 0u; i < 12u; i++)
        {
            Sleep(150u);
            connection.SendText(field.Substring(i, 1u));
        }
        connection.SendText(field.Substring(12u) + "Content-Length: 2\r\n\r\nok");
        connection.Close();
    })!;

    var client = new HttpClient();
    client.Timeout = TimeSpan.FromMilliseconds(700);
    var clock = new Stopwatch();
    var sent = client.Send(new HttpRequestMessage(HttpMethod.Get, server.Origin + "/"),
                           HttpCompletionOption.ResponseContentRead, out HttpFailure failure);
    long elapsed = clock.Elapsed.Nanoseconds / 1000000;
    Console.WriteLine("700 ms timeout: " + (sent.Ok ? "answered" : $"{sent.Error}") +
                      ", within 1500 ms: " + (elapsed < 1500 ? "yes" : "no"));
    client.Dispose();
    server.StopRawServer();
}

void TestEarlyHints()
{
    Console.WriteLine("-- 103 while waiting for 100 (Continue)");
    var log = new RawLog();
    RawServer server = RawServer.StartRawServer((connection, index) =>
    {
        ReadRawHead(connection);
        connection.SendText("HTTP/1.1 103 Early Hints\r\nLink: </style.css>; rel=preload\r\n\r\n");
        String body = ReadRawBytes(connection, 20u);
        log.AddLine("  server got the body: [" + body + "]");
        connection.SendText("HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nfinal");
        connection.Close();
    })!;

    var client = new HttpClient();
    client.Timeout = TimeSpan.FromSeconds(3);
    var request = new HttpRequestMessage(HttpMethod.Post, server.Origin + "/upload");
    request.Headers.ExpectContinue = true;
    request.Content = new StringContent("0123456789abcdefghij");
    var sent = client.Send(request, HttpCompletionOption.ResponseContentRead, out HttpFailure failure);
    Console.WriteLine("client: " + DescribeSent(sent, failure));
    client.Dispose();
    server.StopRawServer();
    foreach (var line in log.CopyLines())
        Console.WriteLine(line);
}

void TestRedirects()
{
    Console.WriteLine("-- redirects");
    var log = new RawLog();
    RawServer second = RawServer.StartRawServer((connection, index) =>
    {
        while (true)
        {
            String head = ReadRawHead(connection);
            if (head.IsEmpty)
                break;
            String declared = FindRawField(head, "Content-Length");
            String body = declared == "(none)" ? "" : ReadRawBytes(connection, ParseRawDecimal(declared));
            log.AddLine("second|" + head + "|" + body);
            connection.SendText("HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n");
        }
        connection.Close();
    })!;
    String secondOrigin = second.Origin;
    RawServer first = RawServer.StartRawServer((connection, index) =>
    {
        while (true)
        {
            String head = ReadRawHead(connection);
            if (head.IsEmpty)
                break;
            String declared = FindRawField(head, "Content-Length");
            if (declared != "(none)")
                ReadRawBytes(connection, ParseRawDecimal(declared));
            String target = FindRawRequestLine(head).Split(' ')[1u];
            String status = target.Substring(1u, 3u);
            String location = target.Contains("away") ? secondOrigin + "/landed" : "//bad host:1:2/";
            log.AddLine("first|" + head + "|");
            connection.SendText("HTTP/1.1 " + status + " Moved\r\nLocation: " + location +
                                "\r\nContent-Length: 0\r\n\r\n");
        }
        connection.Close();
    })!;

    var client = new HttpClient();
    client.Timeout = TimeSpan.FromSeconds(5);
    foreach (var method in [HttpMethod.Delete, HttpMethod.Put, HttpMethod.Post, HttpMethod.Head])
    {
        foreach (var status in ["301", "302", "303"])
        {
            var request = new HttpRequestMessage(method, first.Origin + "/" + status + "/away");
            if (method.Method == "PUT" || method.Method == "POST")
                request.Content = new StringContent("payload");
            var sent = client.Send(request, HttpCompletionOption.ResponseContentRead, out HttpFailure failure);
            String ended = "?";
            if (sent.Ok && sent.Value.RequestMessage is HttpRequestMessage last)
                ended = last.Method.Method;
            Console.WriteLine(method.Method + " through " + status + ": " + ended);
        }
    }

    var carried = new HttpRequestMessage(HttpMethod.Get, first.Origin + "/302/away");
    carried.Headers.Add("Cookie", "session=for-first");
    carried.Headers.Authorization = "Bearer for-first";
    carried.Headers.Host = "first.example";
    carried.Headers.TryAddWithoutValidation("Proxy-Authorization", "Basic Zm9yOmZpcnN0");
    var sentCarried = client.Send(carried, HttpCompletionOption.ResponseContentRead, out HttpFailure carriedFailure);
    Console.WriteLine("fields set by hand: " + DescribeSent(sentCarried, carriedFailure));

    var broken = client.Send(new HttpRequestMessage(HttpMethod.Get, first.Origin + "/302/broken"),
                             HttpCompletionOption.ResponseContentRead, out HttpFailure brokenFailure);
    Console.WriteLine("a Location with a malformed host: " + DescribeSent(broken, brokenFailure));

    String firstAuthority = first.Origin.Substring(7u);
    String secondAuthority = secondOrigin.Substring(7u);
    client.Dispose();
    first.StopRawServer();
    second.StopRawServer();
    foreach (var entry in log.CopyLines())
    {
        String[] parts = entry.Split('|');
        if (!parts[1u].Contains("first.example") && !parts[1u].Contains("landed"))
            continue;
        Console.WriteLine("  " + parts[0u] + ": " + DescribeRedirectedHead(parts[1u], firstAuthority, secondAuthority) +
                          (parts[2u].IsEmpty ? "" : "; body [" + parts[2u] + "]"));
    }
}

void TestHosts()
{
    Console.WriteLine("-- hosts");
    foreach (var text in ["http://victim.example\r\nX-Injected:1/", "http://a b.example/", "http://a:b:80/",
                          "http://a\\b/", "http://[::1/", "http://x]y/", "http://tab\there/", "http://del\x7Fhere/",
                          "http://[::1]:8080/", "http://example.com:8080/", "http://user@example.com/"])
    {
        String shown = text.Replace("\r", "\\r").Replace("\n", "\\n").Replace("\t", "\\t").Replace("\x7F", "\\x7F");
        var parsed = Uri.TryCreate(text, UriKind.Absolute);
        Console.WriteLine(shown + ": " + (parsed is Ok made ? "host " + made.Value.Host : "refused"));
    }
    var based = Uri.TryCreate(new Uri("http://example.com/a/"), "//bad host/");
    Console.WriteLine("//bad host/ against http://example.com/a/: " + (based is Ok ? "resolved" : "refused"));
}

void TestMultipartFields()
{
    Console.WriteLine("-- a multipart part with CR LF in a field");
    var log = new RawLog();
    RawServer server = RawServer.StartRawServer((connection, index) =>
    {
        String head = ReadRawHead(connection);
        String rest = ReadRawBytes(connection, 100000u);
        log.AddLine("  server saw the injected field: " + (rest.Contains("Injected:") ? "yes" : "no"));
        connection.Close();
    })!;
    var client = new HttpClient();
    client.Timeout = TimeSpan.FromSeconds(5);
    var parts = new MultipartContent();
    var part = new StringContent("part");
    part.Headers.TryAddWithoutValidation("X-Part", "a\r\nInjected: 1");
    parts.Add(part);
    var request = new HttpRequestMessage(HttpMethod.Post, server.Origin + "/parts");
    request.Content = parts;
    var sent = client.Send(request, HttpCompletionOption.ResponseContentRead, out HttpFailure failure);
    Console.WriteLine("client: " + DescribeSent(sent, failure));
    client.Dispose();
    server.StopRawServer();
    foreach (var line in log.CopyLines())
        Console.WriteLine(line);
}

void TestEnvironment()
{
    Console.WriteLine("-- the environment");
    // Under CGI, HTTP_PROXY is the request's Proxy header. On Windows, where
    // names are not cased, asking for http_proxy finds it too.
    Env.RemoveEnvironmentVariable("http_proxy");
    Env.RemoveEnvironmentVariable("all_proxy");
    Env.RemoveEnvironmentVariable("no_proxy");
    Env.SetEnvironmentVariable("REQUEST_METHOD", "GET");
    Env.SetEnvironmentVariable("HTTP_PROXY", "http://attacker.example:1");
    Env.SetEnvironmentVariable("HTTPS_PROXY", "http://proxy.example:3128");
    if (HttpEnvironmentProxy.FromEnvironment() is HttpEnvironmentProxy cgi)
    {
        Uri? http = cgi.HttpProxy;
        Uri? https = cgi.HttpsProxy;
        Console.WriteLine("under CGI: http " + (http == null ? "direct" : http.ToString()) +
                          ", https " + (https == null ? "direct" : https.ToString()));
    }
    else
    {
        Console.WriteLine("under CGI: no proxy at all");
    }

    // A no_proxy port that cannot be read is no exception, not one for every
    // port.
    IWebProxy? read = HttpEnvironmentProxy.FromEnvironment((name) =>
    {
        switch (name)
        {
            case "http_proxy":
                return "http://proxy.example:3128";
            case "no_proxy":
                return "example.com:notaport, other.example:8080";
        }
        return null;
    });
    if (read is HttpEnvironmentProxy proxy)
    {
        Console.WriteLine("example.com with an unreadable port bypassed: " +
                          (proxy.IsBypassed(new Uri("http://example.com/")) ? "yes" : "no"));
        Console.WriteLine("other.example:8080 bypassed: " +
                          (proxy.IsBypassed(new Uri("http://other.example:8080/")) ? "yes" : "no"));
    }
}

void TestCookieLimits()
{
    Console.WriteLine("-- cookie limits");
    var uri = new Uri("https://www.example.com/");
    var jar = new CookieContainer();
    jar.SetCookies(uri, "millennium=1; Max-Age=31536000000");
    jar.SetCookies(uri, "huge=1; Max-Age=99999999999999999999999");
    foreach (var cookie in jar.GetCookies(uri))
    {
        long days = 0;
        if (cookie.Expires is Some at)
            days = (long)((at.Value - DateTimeOffset.UtcNow).TotalDays + 0.5);
        Console.WriteLine(cookie.Name + " expires in " + Text.FromInteger(days) + " days");
    }

    var many = new CookieContainer();
    for (int i = 0; i < 60; i++)
        many.SetCookies(uri, "c" + Text.FromInteger((long)i) + "=v");
    String header = many.GetCookieHeader(uri);
    Console.WriteLine("one host: " + Text.FromInteger((long)many.Count) + " held, oldest kept: " +
                      (header.Contains("c0=") ? "yes" : "no") + ", newest kept: " +
                      (header.Contains("c59=") ? "yes" : "no"));

    var wide = new CookieContainer();
    wide.Capacity = 100u;
    wide.PerDomainCapacity = 30u;
    for (int host = 0; host < 5; host++)
    {
        var at = new Uri("https://h" + Text.FromInteger((long)host) + ".example.com/");
        for (int i = 0; i < 30; i++)
            wide.SetCookies(at, "c" + Text.FromInteger((long)i) + "=v");
    }
    Console.WriteLine("five hosts, 100 in all: " + Text.FromInteger((long)wide.Count) + " held, first host keeps " +
                      Text.FromInteger((long)wide.GetCookies(new Uri("https://h0.example.com/")).Count) +
                      ", last keeps " + Text.FromInteger((long)wide.GetCookies(new Uri("https://h4.example.com/")).Count));
}

int Main()
{
    TestOverlongBodies();
    TestTrickledHead();
    TestEarlyHints();
    TestRedirects();
    TestHosts();
    TestMultipartFields();
    TestEnvironment();
    TestCookieLimits();
    return 0;
}
