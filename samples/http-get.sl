// SPDX-License-Identifier: 0BSD
//
// `http-get`: fetch a URL and say what came back — the status line, the
// fields, and how long the body was.
//
//   stainless run samples/http-get.sl -- http://example.com/
//   stainless run samples/http-get.sl -- --gzip https://example.com/
//   stainless run samples/http-get.sl -- --http2 https://example.com/
//
// `--http2` asks for HTTP/2 and takes HTTP/1.1 when the server will not agree
// to h2 in ALPN; `--http2-only` takes nothing else, and speaks h2 with prior
// knowledge to an http URL.
//
// An https URL is trusted by the TLS module's validator, so it reaches a real
// site once that validator checks X.509 chains against the platform's roots;
// until then every certificate is refused, and the sample says so.
module HttpGet;

import Standard.Console;
import Standard.Net.Http;
import Standard.Text;
import Standard.Time;

int Main(String[] args)
{
    bool gzip = false;
    Version version = HttpVersion.Version11;
    HttpVersionPolicy policy = HttpVersionPolicy.RequestVersionOrLower;
    String url = "";
    foreach (var argument in args)
    {
        switch (argument)
        {
            case "--gzip":
                gzip = true;
                break;
            case "--http2":
                version = HttpVersion.Version20;
                break;
            case "--http2-only":
                version = HttpVersion.Version20;
                policy = HttpVersionPolicy.RequestVersionExact;
                break;
            default:
                url = argument;
                break;
        }
    }
    if (url.IsEmpty)
    {
        Console.WriteError("usage: http-get [--gzip] [--http2 | --http2-only] <url>");
        return 2;
    }

    var handler = new HttpClientHandler();
    if (gzip)
        handler.AutomaticDecompression = DecompressionMethods.All;
    var client = new HttpClient(handler);
    client.Timeout = TimeSpan.FromSeconds(30);
    client.DefaultRequestHeaders.UserAgent = "stainless-http-get/1.0";

    var request = new HttpRequestMessage(HttpMethod.Get, url);
    request.Version = version;
    request.VersionPolicy = policy;
    var sent = client.Send(request, HttpCompletionOption.ResponseContentRead, out HttpFailure failure);
    if (!sent.Ok)
    {
        Console.WriteError("http-get: " + failure.ToString());
        return 1;
    }

    HttpResponseMessage response = sent.Value;
    Console.WriteLine(response.ToString());
    foreach (var field in response.Headers)
        Console.WriteLine(field.Key + ": " + ", ".Join(field.Value));
    foreach (var field in response.Content.Headers)
        Console.WriteLine(field.Key + ": " + ", ".Join(field.Value));

    var body = response.Content.ReadAsByteArray();
    if (!body.Ok)
    {
        Console.WriteError("http-get: the body could not be read: " + DescribeHttpError(body.Error));
        return 1;
    }
    Console.WriteLine("");
    Console.WriteLine("body: " + Text.FromInteger((long)body.Value.Length) + " bytes");
    if (response.RequestMessage is HttpRequestMessage last && last.RequestUri is Uri final)
        Console.WriteLine("from: " + final.ToString());
    client.Dispose();
    return response.IsSuccessStatusCode ? 0 : 1;
}
