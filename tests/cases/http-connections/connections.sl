// SPDX-License-Identifier: 0BSD
// What happens to connections: kept alive and reused, closed by either end,
// dropped after sitting idle, held to a limit per server, retried when a
// pooled one turns out to be dead, and given up on when the server is slow.
//
// Reuse is proven by the server counting the connections it accepted, which
// is the one number a client that quietly reconnected could not fake.
module HttpConnections;

import Standard.Console;
import Standard.Net.Http;
import Standard.Text;
import Standard.Threading;
import Standard.Time;
import HttpTestServer;

class Gate
{
    public AtomicBool Released = new AtomicBool(false);

    public bool IsReleased() => Released.Read();
}

HttpTestReply RouteConnections(HttpTestRequest request, Gate gate)
{
    String path = request.Target;
    if (path.StartsWith("/drop") && request.Sequence >= 2)
        return new HttpTestReply().CloseConnection();
    switch (path)
    {
        case "/close":
            return HttpTestReply.CreateText(200, "OK", "Connection: close\r\n", "closing")
                                .CloseConnection();
        case "/held":
            return new HttpTestReply()
                .SendText("HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\nheld")
                .WaitUntil(() => gate.IsReleased(), 5000)
                .SendText(" rest!");
        case "/slow-head":
            return new HttpTestReply()
                .Pause(1000)
                .SendText("HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\nlate");
        case "/slow-body":
            return new HttpTestReply()
                .SendText("HTTP/1.1 200 OK\r\nContent-Length: 9\r\n\r\nstart")
                .Pause(1000)
                .SendText(" end");
    }
    return HttpTestReply.CreateText(200, "OK", "", "served " + path + " as request " +
                                    Text.FromInteger((long)request.Sequence) + " of its connection");
}

void ShowOutcome(String label, Result<HttpResponseMessage, HttpError> sent, HttpFailure failure)
{
    if (!sent.Ok)
    {
        Console.WriteLine(label + ": " + $"{sent.Error}" + " (" + failure.Message + ")");
        return;
    }
    var body = sent.Value.Content.ReadAsString();
    Console.WriteLine(label + ": " + (body.Ok ? body.Value : "body failed: " + $"{body.Error}"));
}

void ShowGet(String label, HttpClient client, String uri)
{
    var request = new HttpRequestMessage(HttpMethod.Get, uri);
    ShowOutcome(label, client.Send(request, HttpCompletionOption.ResponseContentRead, out HttpFailure failure),
                failure);
}

int Main()
{
    var gate = new Gate();
    HttpTestServer? started = HttpTestServer.StartServing((request) => RouteConnections(request, gate));
    if (started == null)
        return 1;
    HttpTestServer server = started;
    String origin = server.Origin;

    Console.WriteLine("-- keep-alive");
    var client = new HttpClient();
    client.Timeout = TimeSpan.FromSeconds(8);
    ShowGet("first", client, origin + "/a");
    ShowGet("second", client, origin + "/b");
    ShowGet("third", client, origin + "/c");
    Console.WriteLine("accepted: " + Text.FromInteger((long)server.Accepts));

    Console.WriteLine("-- Connection: close from the server");
    ShowGet("closing", client, origin + "/close");
    ShowGet("after", client, origin + "/d");
    Console.WriteLine("accepted: " + Text.FromInteger((long)server.Accepts));

    Console.WriteLine("-- Connection: close from the client");
    var closing = new HttpRequestMessage(HttpMethod.Get, origin + "/e");
    closing.Headers.ConnectionClose = true;
    ShowOutcome("asked to close", client.Send(closing, HttpCompletionOption.ResponseContentRead,
                                              out HttpFailure closeFailure), closeFailure);
    ShowGet("after", client, origin + "/f");
    Console.WriteLine("accepted: " + Text.FromInteger((long)server.Accepts));

    Console.WriteLine("-- a dead pooled connection");
    ShowGet("GET before", client, origin + "/drop-get");
    ShowGet("GET retried", client, origin + "/drop-get");
    Console.WriteLine("accepted: " + Text.FromInteger((long)server.Accepts));
    ShowGet("POST before", client, origin + "/drop-post");
    var post = new HttpRequestMessage(HttpMethod.Post, origin + "/drop-post");
    post.Content = new StringContent("not idempotent");
    ShowOutcome("POST not retried", client.Send(post, HttpCompletionOption.ResponseContentRead,
                                                out HttpFailure postFailure), postFailure);
    Console.WriteLine("accepted: " + Text.FromInteger((long)server.Accepts));
    client.Dispose();

    Console.WriteLine("-- idle timeout");
    var idleHandler = new HttpClientHandler();
    idleHandler.PooledConnectionIdleTimeout = TimeSpan.FromMilliseconds(300);
    var idle = new HttpClient(idleHandler);
    int before = server.Accepts;
    ShowGet("first", idle, origin + "/g");
    ShowGet("at once", idle, origin + "/h");
    Sleep(700u);
    ShowGet("after idling", idle, origin + "/i");
    Console.WriteLine("new connections: " + Text.FromInteger((long)(server.Accepts - before)));
    idle.Dispose();

    Console.WriteLine("-- one connection per server");
    var limitedHandler = new HttpClientHandler();
    limitedHandler.MaxConnectionsPerServer = 1;
    var limited = new HttpClient(limitedHandler);
    limited.Timeout = TimeSpan.FromMilliseconds(700);
    before = server.Accepts;
    var held = limited.Get(origin + "/held", HttpCompletionOption.ResponseHeadersRead);
    Console.WriteLine("held: " + Text.FromBool(held.Ok));
    ShowGet("while held", limited, origin + "/j");
    gate.Released.Write(true);
    if (held.Ok)
    {
        var rest = held.Value.Content.ReadAsString();
        Console.WriteLine("held body: " + rest.GetValueOrDefault("failed"));
    }
    ShowGet("once free", limited, origin + "/k");
    Console.WriteLine("new connections: " + Text.FromInteger((long)(server.Accepts - before)));
    limited.Dispose();

    Console.WriteLine("-- timeouts");
    var impatient = new HttpClient();
    impatient.Timeout = TimeSpan.FromMilliseconds(500);
    ShowGet("slow body", impatient, origin + "/slow-body");
    ShowGet("slow head", impatient, origin + "/slow-head");
    impatient.Dispose();

    Console.WriteLine("-- nobody listening");
    ushort closedPort = server.Port;
    server.StopServing();
    var refused = new HttpClient();
    refused.Timeout = TimeSpan.FromSeconds(8);
    var nobody = refused.Get("http://127.0.0.1:" + Text.FromInteger((long)closedPort) + "/");
    Console.WriteLine("refused: " + (nobody.Ok ? "answered" : $"{nobody.Error}"));
    refused.Dispose();
    return 0;
}
