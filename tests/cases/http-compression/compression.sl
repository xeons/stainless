// SPDX-License-Identifier: 0BSD
// Content-Encoding undone as it arrives: gzip, deflate in both of the forms
// servers send it in, gzip inside chunks, a corrupt body, a body read as a
// stream, and what Accept-Encoding asks for.
module HttpCompression;

import Standard.Console;
import Standard.IO;
import Standard.IO.Compression;
import Standard.Net.Http;
import Standard.Text;
import Standard.Time;
import HttpTestServer;

/// Text long and repetitive enough that compressing it is worth it.
String CreateCompressibleText()
{
    var text = new StringBuilder();
    for (int i = 0; i < 200; i++)
        text.Append("line " + Text.FromInteger((long)i) + " of a body that compresses well\n");
    return text.ToText();
}

HttpTestReply CreateEncoded(String coding, byte[] body)
{
    String head = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Encoding: " + coding +
                  "\r\nContent-Length: " + Text.FromInteger((long)body.Length) + "\r\n\r\n";
    return new HttpTestReply().SendText(head).SendBytes(body);
}

/// `body` in chunks of at most `size` bytes.
HttpTestReply CreateChunkedEncoded(String coding, byte[] body, nuint size)
{
    var reply = new HttpTestReply().SendText(
        "HTTP/1.1 200 OK\r\nContent-Encoding: " + coding + "\r\nTransfer-Encoding: chunked\r\n\r\n");
    nuint at = 0u;
    while (at < body.Length)
    {
        nuint part = body.Length - at;
        if (part > size)
            part = size;
        var chunk = new byte[part];
        for (nuint i = 0u; i < part; i++)
            chunk[i] = body[at + i];
        reply.SendText(FormatTestHexadecimal(part) + "\r\n").SendBytes(chunk).SendText("\r\n");
        at += part;
    }
    return reply.SendText("0\r\n\r\n");
}

String FormatTestHexadecimal(nuint value)
{
    String digits = "";
    nuint left = value;
    while (left > 0u)
    {
        digits = "0123456789abcdef".Substring(left % 16u, 1u) + digits;
        left = left / 16u;
    }
    return digits.IsEmpty ? "0" : digits;
}

HttpTestReply RouteCompression(HttpTestRequest request, String text)
{
    byte[] plain = text.ToBytes();
    switch (request.Target)
    {
        case "/gzip":
            return CreateEncoded("gzip", Compression.CompressGZip(plain));
        case "/zlib":
            return CreateEncoded("deflate", Compression.CompressZLib(plain));
        case "/raw-deflate":
            return CreateEncoded("deflate", Compression.CompressDeflate(plain));
        case "/chunked-gzip":
            return CreateChunkedEncoded("gzip", Compression.CompressGZip(plain), 100u);
        case "/corrupt":
        {
            byte[] packed = Compression.CompressGZip(plain);
            for (nuint i = 20u; i < 40u; i++)
                packed[i] = (byte)(packed[i] ^ 0x5A);
            return CreateEncoded("gzip", packed);
        }
        case "/brotli":
            return CreateEncoded("br", "not really brotli".ToBytes());
        case "/accept":
        {
            String asked = request.HasField("Accept-Encoding") ? request.GetField("Accept-Encoding") : "(none)";
            return HttpTestReply.CreateText(200, "OK", "", "Accept-Encoding: " + asked);
        }
    }
    return HttpTestReply.CreateText(404, "Not Found", "", "no route");
}

void ShowDecoded(String label, HttpClient client, String uri, String expected)
{
    var sent = client.Get(uri);
    if (!sent.Ok)
    {
        Console.WriteLine(label + ": " + $"{sent.Error}");
        return;
    }
    HttpResponseMessage response = sent.Value;
    String coding = ", ".Join(response.Content.Headers.ContentEncoding);
    bool hasLength = response.Content.Headers.Contains("Content-Length");
    var body = response.Content.ReadAsString();
    String outcome = body.Ok ? (body.Value == expected ? "matches" : "differs") : $"{body.Error}";
    Console.WriteLine(label + ": " + outcome + "; Content-Encoding [" + coding + "]; Content-Length " +
                      (hasLength ? "kept" : "removed"));
}

int Main()
{
    String text = CreateCompressibleText();
    HttpTestServer? started = HttpTestServer.StartServing((request) => RouteCompression(request, text));
    if (started == null)
        return 1;
    HttpTestServer server = started;
    String origin = server.Origin;

    var handler = new HttpClientHandler();
    handler.AutomaticDecompression = DecompressionMethods.All;
    var client = new HttpClient(handler);
    client.Timeout = TimeSpan.FromSeconds(8);

    Console.WriteLine("-- decoded");
    Console.WriteLine(client.GetString(origin + "/accept").GetValueOrDefault("failed"));
    ShowDecoded("gzip", client, origin + "/gzip", text);
    ShowDecoded("deflate as zlib", client, origin + "/zlib", text);
    ShowDecoded("deflate as raw deflate", client, origin + "/raw-deflate", text);
    ShowDecoded("gzip in chunks", client, origin + "/chunked-gzip", text);
    ShowDecoded("a coding not asked for", client, origin + "/brotli", "not really brotli");

    var failed = client.Send(new HttpRequestMessage(HttpMethod.Get, origin + "/corrupt"),
                             HttpCompletionOption.ResponseContentRead, out HttpFailure failure);
    Console.WriteLine("corrupt: " + (failed.Ok ? "decoded" : $"{failed.Error}") + ", with a reason: " +
                      Text.FromBool(failure.CompressionErrorCode != CompressionError.None));

    var streamed = client.Get(origin + "/chunked-gzip", HttpCompletionOption.ResponseHeadersRead);
    if (streamed.Ok)
    {
        var stream = streamed.Value.Content.ReadAsStream();
        if (stream.Ok)
        {
            var read = IO.ReadTextToEnd(stream.Value);
            Console.WriteLine("streamed: " + (read.Ok && read.Value == text ? "matches" : "differs"));
        }
    }
    int before = server.Accepts;
    Console.WriteLine("after a streamed body: " + client.GetString(origin + "/accept").GetValueOrDefault("failed"));
    Console.WriteLine("its connection reused: " + Text.FromBool(server.Accepts == before));

    Console.WriteLine("-- gzip only");
    var gzipHandler = new HttpClientHandler();
    gzipHandler.AutomaticDecompression = DecompressionMethods.GZip;
    var gzipOnly = new HttpClient(gzipHandler);
    Console.WriteLine(gzipOnly.GetString(origin + "/accept").GetValueOrDefault("failed"));
    ShowDecoded("deflate left alone", gzipOnly, origin + "/zlib", text);
    var custom = new HttpRequestMessage(HttpMethod.Get, origin + "/accept");
    custom.Headers.AcceptEncoding = "identity";
    var customSent = gzipOnly.Send(custom);
    if (customSent.Ok)
        Console.WriteLine("asked for itself: " + customSent.Value.Content.ReadAsString().GetValueOrDefault("failed"));
    gzipOnly.Dispose();

    Console.WriteLine("-- not decoded");
    var plain = new HttpClient();
    Console.WriteLine(plain.GetString(origin + "/accept").GetValueOrDefault("failed"));
    var raw = plain.GetByteArray(origin + "/gzip");
    if (raw.Ok)
    {
        var unpacked = Compression.DecompressGZip(raw.Value);
        Console.WriteLine("left as gzip, which unpacks by hand: " +
                          Text.FromBool(unpacked.Ok && unpacked.Value.Length == text.ByteLength()));
    }
    plain.Dispose();

    client.Dispose();
    server.StopServing();
    return 0;
}
