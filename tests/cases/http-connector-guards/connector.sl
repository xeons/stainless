// SPDX-License-Identifier: 0BSD
//
// What the HTTP connector guarantees before a request is written: every
// address a name resolves to is tried, `Timeout` bounds a TLS handshake and a
// proxy's CONNECT answer however slowly the peer trickles bytes, and a host
// that would split the request line never reaches the wire.
module HttpConnectorGuards;

import Standard.Console;
import Standard.Net;
import Standard.Net.Http;
import Standard.Text;
import Standard.Threading;
import Standard.Time;

// Accepts `count` connections and answers each with a tiny response.
void AnswerConnections(TcpListener listener, int count)
{
    for (int i = 0; i < count; i++)
    {
        if (!listener.Pending(15000))
            return;
        TcpClient client = listener.Accept();
        client.Underlying.SetReceiveTimeout(5000);
        client.Read(new byte[4096], 0u, 4096u);
        client.SendText("HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok");
        client.Close();
    }
}

// Accepts one connection, reads what the client sends first, and then sends
// `payload` a byte every 200 ms, each well inside any per-read timeout.
void TrickleToOneClient(TcpListener listener, byte[] payload)
{
    if (!listener.Pending(15000))
        return;
    TcpClient client = listener.Accept();
    client.Underlying.SetReceiveTimeout(5000);
    client.Read(new byte[4096], 0u, 4096u);
    for (nuint i = 0u; i < payload.Length; i++)
    {
        Sleep(200u);
        client.Underlying.Send(payload, i, 1u, out SocketError error);
        if (error != SocketError.None)
            break;
    }
    client.Close();
}

TcpListener? ListenOnLoopback()
{
    var opened = TcpListener.Listen("127.0.0.1", 0u);
    if (!opened.Ok)
        return null;
    return opened.Value;
}

String FormatLoopbackOrigin(String host, TcpListener listener) =>
    "http://" + host + ":" + Text.FromInteger((long)listener.LocalEndPoint.Port);

void ShowLocalhost()
{
    TcpListener listener = ListenOnLoopback()!;
    var server = new Thread(() => AnswerConnections(listener, 2));
    String uri = FormatLoopbackOrigin("localhost", listener) + "/";

    var bounded = new HttpClient();
    bounded.Timeout = TimeSpan.FromSeconds(10);
    var first = bounded.GetString(uri);
    Console.WriteLine("localhost within 10 s: " + (first.Ok ? first.Value : DescribeHttpError(first.Error)));

    var unbounded = new HttpClient();
    unbounded.Timeout = TimeSpan.FromSeconds(0);
    var second = unbounded.GetString(uri);
    Console.WriteLine("localhost, no limit: " + (second.Ok ? second.Value : DescribeHttpError(second.Error)));

    server.Join();
    bounded.Dispose();
    unbounded.Dispose();
}

void ShowTrickleBounded(String label, byte[] payload, bool throughProxy)
{
    TcpListener listener = ListenOnLoopback()!;
    var server = new Thread(() => TrickleToOneClient(listener, payload));

    var handler = new HttpClientHandler();
    String uri = "https://127.0.0.1:" + Text.FromInteger((long)listener.LocalEndPoint.Port) + "/";
    if (throughProxy)
    {
        handler.Proxy = new WebProxy(FormatLoopbackOrigin("127.0.0.1", listener));
        uri = "https://origin.invalid/";
    }
    var client = new HttpClient(handler);
    client.Timeout = TimeSpan.FromMilliseconds(1000);

    var clock = new Stopwatch();
    var sent = client.Send(new HttpRequestMessage(HttpMethod.Get, uri),
                           HttpCompletionOption.ResponseContentRead, out HttpFailure failure);
    long elapsed = clock.Elapsed.Nanoseconds / 1000000;
    Console.WriteLine(label + ": " + (sent.Ok ? "ok" : $"{sent.Error}") +
                      ", within the limit: " + Text.FromBool(elapsed < 3000));

    client.Dispose();
    server.Join();
}

void ShowUnwritableHostRefused()
{
    TcpListener listener = ListenOnLoopback()!;
    var handler = new HttpClientHandler();
    handler.Proxy = new WebProxy(FormatLoopbackOrigin("127.0.0.1", listener));
    var client = new HttpClient(handler);
    client.Timeout = TimeSpan.FromSeconds(5);

    String[] uris = [
        "https://victim.example\r\nX-Injected: 1\r\nX-End: 1:443/",
        "http://victim.example\r\nX-Injected: 1\r\nX-End: 1/"
    ];
    foreach (String uri in uris)
    {
        var request = new HttpRequestMessage(HttpMethod.Get, uri);
        request.Headers.Host = "victim.example";
        var sent = client.Send(request, HttpCompletionOption.ResponseContentRead, out HttpFailure failure);
        Console.WriteLine("CR LF in the host: " + (sent.Ok ? "sent" : "refused") +
                          ", proxy reached: " + Text.FromBool(listener.Pending(0)));
    }
    client.Dispose();
}

int Main()
{
    ShowLocalhost();

    // A TLS record header announcing a ServerHello, then its body, slowly.
    var hello = new byte[40];
    hello[0] = 0x16;
    hello[1] = 0x03;
    hello[2] = 0x03;
    hello[3] = 0x00;
    hello[4] = 0x40;
    hello[5] = 0x02;
    ShowTrickleBounded("TLS handshake trickled", hello, false);

    String established = "HTTP/1.1 200 Connection established\r\n\r\n";
    var answer = new byte[established.ByteLength()];
    for (nuint i = 0u; i < answer.Length; i++)
        answer[i] = established.GetByteAt(i);
    ShowTrickleBounded("CONNECT answer trickled", answer, true);

    ShowUnwritableHostRefused();
    return 0;
}
