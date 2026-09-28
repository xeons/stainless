// SPDX-License-Identifier: 0BSD
// Responses a strict HTTP/1.1 client refuses: malformed status lines, folded
// and malformed fields, heads over their limits, chunk sizes that are not
// sizes, and the framings one message is smuggled inside another with. Each
// is refused with the reason, and none of them is read as something else.
module HttpParsingRefusals;

import Standard.Collections;
import Standard.Console;
import Standard.Net.Http;
import Standard.Text;
import Standard.Time;
import HttpTestServer;

/// The raw response for each case, by path.
Dictionary<String, String> CreateCases()
{
    var cases = new Dictionary<String, String>();
    cases.SetValue("/no-space", "HTTP/1.1 200OK\r\nContent-Length: 0\r\n\r\n");
    cases.SetValue("/version-2", "HTTP/2.0 200 OK\r\nContent-Length: 0\r\n\r\n");
    cases.SetValue("/letters", "HTTP/1.1 2x0 OK\r\nContent-Length: 0\r\n\r\n");
    cases.SetValue("/below-100", "HTTP/1.1 099 Low\r\nContent-Length: 0\r\n\r\n");
    cases.SetValue("/not-http", "ICY 200 OK\r\nContent-Length: 0\r\n\r\n");
    cases.SetValue("/control-reason", "HTTP/1.1 200 O\x01K\r\nContent-Length: 0\r\n\r\n");
    cases.SetValue("/folded", "HTTP/1.1 200 OK\r\nX-Long: first\r\n second\r\nContent-Length: 0\r\n\r\n");
    cases.SetValue("/no-colon", "HTTP/1.1 200 OK\r\nNo colon here\r\nContent-Length: 0\r\n\r\n");
    cases.SetValue("/space-before-colon", "HTTP/1.1 200 OK\r\nX-Spaced : 1\r\nContent-Length: 0\r\n\r\n");
    cases.SetValue("/control-value", "HTTP/1.1 200 OK\r\nX-Bad: a\x01b\r\nContent-Length: 0\r\n\r\n");
    cases.SetValue("/bare-cr", "HTTP/1.1 200 OK\r\nX-Bad: a\rb\r\nContent-Length: 0\r\n\r\n");
    cases.SetValue("/long-line", "HTTP/1.1 200 OK\r\nX-Long: " + "x".Repeat(17000u) + "\r\nContent-Length: 0\r\n\r\n");
    var many = new StringBuilder();
    many.Append("HTTP/1.1 200 OK\r\n");
    for (int i = 0; i < 300; i++)
        many.Append("X-Field-" + Text.FromInteger((long)i) + ": v\r\n");
    many.Append("Content-Length: 0\r\n\r\n");
    cases.SetValue("/many-fields", many.ToText());
    var big = new StringBuilder();
    big.Append("HTTP/1.1 200 OK\r\n");
    for (int i = 0; i < 40; i++)
        big.Append("X-Big-" + Text.FromInteger((long)i) + ": " + "y".Repeat(100u) + "\r\n");
    big.Append("Content-Length: 0\r\n\r\n");
    cases.SetValue("/big-head", big.ToText());
    cases.SetValue("/bad-chunk", "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nzz\r\nhello\r\n0\r\n\r\n");
    cases.SetValue("/huge-chunk", "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nffffffffffffffffff\r\nhello\r\n");
    cases.SetValue("/negative-chunk", "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n-5\r\nhello\r\n0\r\n\r\n");
    cases.SetValue("/overlong-chunk", "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nhello\r\n0\r\n\r\n");
    cases.SetValue("/two-lengths", "HTTP/1.1 200 OK\r\nContent-Length: 5\r\nContent-Length: 6\r\n\r\nhello!");
    cases.SetValue("/length-list", "HTTP/1.1 200 OK\r\nContent-Length: 5, 6\r\n\r\nhello!");
    cases.SetValue("/same-lengths", "HTTP/1.1 200 OK\r\nContent-Length: 5\r\nContent-Length: 5\r\n\r\nhello");
    cases.SetValue("/negative-length", "HTTP/1.1 200 OK\r\nContent-Length: -1\r\n\r\nhello");
    cases.SetValue("/signed-length", "HTTP/1.1 200 OK\r\nContent-Length: +5\r\n\r\nhello");
    cases.SetValue("/length-and-chunked",
                   "HTTP/1.1 200 OK\r\nContent-Length: 5\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n0\r\n\r\n");
    cases.SetValue("/gzip-coding", "HTTP/1.1 200 OK\r\nTransfer-Encoding: gzip, chunked\r\n\r\n0\r\n\r\n");
    cases.SetValue("/chunked-twice", "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked, chunked\r\n\r\n0\r\n\r\n");
    cases.SetValue("/folded-trailer",
                   "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n0\r\nX-T: 1\r\n more\r\n\r\n");
    cases.SetValue("/switching", "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n\r\n");
    cases.SetValue("/short-body", "HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\nshort");
    cases.SetValue("/nothing", "");
    cases.SetValue("/half-head", "HTTP/1.1 200 OK\r\nContent-Le");
    return cases;
}

HttpTestReply RouteRefusals(HttpTestRequest request, Dictionary<String, String> cases)
{
    String raw = cases.GetValueOrDefault(request.Target, "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n");
    return HttpTestReply.CreateRaw(raw).CloseConnection();
}

void ShowRefusal(HttpClient client, String origin, String path)
{
    var sent = client.Send(new HttpRequestMessage(HttpMethod.Get, origin + path),
                           HttpCompletionOption.ResponseContentRead, out HttpFailure failure);
    if (sent.Ok)
    {
        var body = sent.Value.Content.ReadAsString();
        Console.WriteLine(path + ": accepted, " + Text.FromInteger((long)(int)sent.Value.StatusCode) +
                          " [" + body.GetValueOrDefault("") + "]");
        return;
    }
    Console.WriteLine(path + ": " + $"{sent.Error}" + " (" + failure.Message + ")");
}

int Main()
{
    var cases = CreateCases();
    HttpTestServer? started = HttpTestServer.StartServing((request) => RouteRefusals(request, cases));
    if (started == null)
        return 1;
    HttpTestServer server = started;

    var client = new HttpClient();
    client.Timeout = TimeSpan.FromSeconds(8);
    foreach (var path in ["/no-space", "/version-2", "/letters", "/below-100", "/not-http",
                          "/control-reason", "/folded", "/no-colon", "/space-before-colon",
                          "/control-value", "/bare-cr", "/long-line", "/many-fields",
                          "/bad-chunk", "/huge-chunk", "/negative-chunk", "/overlong-chunk",
                          "/two-lengths", "/length-list", "/same-lengths", "/negative-length",
                          "/signed-length", "/length-and-chunked", "/gzip-coding", "/chunked-twice",
                          "/folded-trailer", "/switching", "/short-body", "/nothing", "/half-head"])
        ShowRefusal(client, server.Origin, path);

    Console.WriteLine("-- a smaller limit on the head");
    var smallHandler = new HttpClientHandler();
    smallHandler.MaxResponseHeadersLength = 2;
    var small = new HttpClient(smallHandler);
    ShowRefusal(small, server.Origin, "/big-head");
    ShowRefusal(client, server.Origin, "/big-head");
    small.Dispose();

    Console.WriteLine("-- a smaller limit on the body");
    client.MaxResponseContentBufferSize = 4;
    ShowRefusal(client, server.Origin, "/same-lengths");
    client.Dispose();

    server.StopServing();
    return 0;
}
