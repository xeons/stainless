// SPDX-License-Identifier: 0BSD
// HTTPS over the loopback: TLS 1.3 to a server holding a throwaway
// certificate, trusted by pinning it in ServerCertificateCustomValidationCallback,
// refused without the pin, reused while kept alive, ALPN offered, and a
// redirect from https to http not followed.
module HttpsBasics;

import Standard.Collections;
import Standard.Console;
import Standard.Net.Http;
import Standard.Net.Security;
import Standard.Security.Cryptography;
import Standard.Security.Cryptography.X509Certificates;
import Standard.Text;
import Standard.Time;
import HttpTestServer;

[Embed("ed25519.crt.pem")]
static readonly byte[] ServerCertificate;
[Embed("ed25519.key.pem")]
static readonly byte[] ServerKey;

String ConvertToText(byte[] bytes) => Text.FromBytes(&bytes[0u], bytes.Length);

byte[] ReadCertificateDer(byte[] pem)
{
    var block = PemEncoding.Find(ConvertToText(pem));
    return block.Some ? block.Value.Data : new byte[0u];
}

bool AreSame(byte[] left, byte[] right)
{
    if (left.Length != right.Length)
        return false;
    for (nuint i = 0u; i < left.Length; i++)
    {
        if (left[i] != right[i])
            return false;
    }
    return true;
}

/// Trusts the one certificate it was made with, and notes what it was shown.
class PinnedCertificate
{
    private byte[] _expected;
    public String Seen = "";

    public PinnedCertificate(byte[] expected) => _expected = expected;

    public bool CheckCertificate(HttpRequestMessage request, X509Certificate2? certificate,
                                 List<byte[]> chain, TlsError defaultVerdict)
    {
        String subject = certificate == null ? "(unparsed)" : certificate.Subject;
        String path = request.RequestUri is Uri uri ? uri.AbsolutePath : "?";
        Seen = "for " + path + ": " + subject + ", " + Text.FromInteger((long)chain.Count) +
               " in the chain, the default would trust it: " + Text.FromBool(defaultVerdict == TlsError.None);
        return chain.Count > 0u && AreSame(chain[0u], _expected);
    }
}

bool RefuseEveryCertificate(HttpRequestMessage request, X509Certificate2? certificate,
                            List<byte[]> chain, TlsError defaultVerdict) => false;

HttpTestReply RouteHttps(HttpTestRequest request, String plainOrigin)
{
    switch (request.Target)
    {
        case "/secure":
            return HttpTestReply.CreateText(200, "OK", "", "over TLS, request " +
                                            Text.FromInteger((long)request.Sequence) + " of its connection");
        case "/downgrade":
            return HttpTestReply.CreateText(302, "Found", "Location: " + plainOrigin + "/plain\r\n", "go plain");
        case "/upgrade":
            return HttpTestReply.CreateText(200, "OK", "", "reached over https");
    }
    return HttpTestReply.CreateText(404, "Not Found", "", "no route");
}

HttpTestReply RoutePlain(HttpTestRequest request, String secureOrigin)
{
    if (request.Target == "/to-https")
        return HttpTestReply.CreateText(301, "Moved", "Location: " + secureOrigin + "/upgrade\r\n", "go secure");
    return HttpTestReply.CreateText(200, "OK", "", "plain");
}

void ShowFetched(String label, HttpClient client, String uri)
{
    var sent = client.Send(new HttpRequestMessage(HttpMethod.Get, uri),
                           HttpCompletionOption.ResponseContentRead, out HttpFailure failure);
    if (!sent.Ok)
    {
        Console.WriteLine(label + ": " + $"{sent.Error}");
        return;
    }
    HttpResponseMessage response = sent.Value;
    Console.WriteLine(label + ": " + Text.FromInteger((long)(int)response.StatusCode) + " " +
                      response.Content.ReadAsString().GetValueOrDefault("body failed"));
}

int Main()
{
    var serverOptions = new TlsServerOptions();
    serverOptions.CertificateChain.Add(ReadCertificateDer(ServerCertificate));
    var key = TlsSigningKey.ImportFromPem(ConvertToText(ServerKey));
    if (!key.Ok)
        return 1;
    serverOptions.PrivateKey = key.Value;
    serverOptions.ApplicationProtocols.Add("h2");
    serverOptions.ApplicationProtocols.Add("http/1.1");

    // The plain server's origin is not known until it is listening, and the
    // TLS server's is needed by it; each route reads the other's from here.
    var origins = new List<String>();
    origins.Add("");
    origins.Add("");
    HttpTestServer? secureStarted = HttpTestServer.StartServing((request) => RouteHttps(request, origins[1u]),
                                                                serverOptions);
    HttpTestServer? plainStarted = HttpTestServer.StartServing((request) => RoutePlain(request, origins[0u]));
    if (secureStarted == null || plainStarted == null)
        return 1;
    HttpTestServer secure = secureStarted;
    HttpTestServer plain = plainStarted;
    origins[0u] = secure.Origin;
    origins[1u] = plain.Origin;
    String origin = secure.Origin;

    Console.WriteLine("-- pinned");
    var pin = new PinnedCertificate(ReadCertificateDer(ServerCertificate));
    var handler = new HttpClientHandler();
    handler.ServerCertificateCustomValidationCallback = pin.CheckCertificate;
    var client = new HttpClient(handler);
    client.Timeout = TimeSpan.FromSeconds(8);
    ShowFetched("first", client, origin + "/secure");
    Console.WriteLine("callback: " + pin.Seen);
    ShowFetched("second", client, origin + "/secure");
    Console.WriteLine("connections: " + Text.FromInteger((long)secure.Accepts));

    Console.WriteLine("-- redirects between schemes");
    ShowFetched("https to http", client, origin + "/downgrade");
    ShowFetched("http to https", client, plain.Origin + "/to-https");
    client.Dispose();

    Console.WriteLine("-- not trusted");
    var strict = new HttpClient();
    strict.Timeout = TimeSpan.FromSeconds(8);
    var refused = strict.Send(new HttpRequestMessage(HttpMethod.Get, origin + "/secure"),
                              HttpCompletionOption.ResponseContentRead, out HttpFailure failure);
    Console.WriteLine("no callback: " + (refused.Ok ? "trusted" : $"{refused.Error}") +
                      ", a TLS error given: " + Text.FromBool(failure.TlsErrorCode != TlsError.None));
    strict.Dispose();

    var refusingHandler = new HttpClientHandler();
    refusingHandler.ServerCertificateCustomValidationCallback = RefuseEveryCertificate;
    var refusing = new HttpClient(refusingHandler);
    var declined = refusing.Send(new HttpRequestMessage(HttpMethod.Get, origin + "/secure"),
                                 HttpCompletionOption.ResponseContentRead, out HttpFailure declinedFailure);
    Console.WriteLine("callback refuses: " + (declined.Ok ? "trusted" : $"{declined.Error}") +
                      ", a TLS error given: " + Text.FromBool(declinedFailure.TlsErrorCode != TlsError.None));
    refusing.Dispose();

    var anyHandler = new HttpClientHandler();
    anyHandler.ServerCertificateCustomValidationCallback =
        HttpClientHandler.DangerousAcceptAnyServerCertificateValidator;
    var anything = new HttpClient(anyHandler);
    ShowFetched("accepting anything", anything, origin + "/secure");
    anything.Dispose();

    secure.StopServing();
    plain.StopServing();
    Console.WriteLine("-- the TLS server saw");
    foreach (var line in secure.Log)
        Console.WriteLine(line);
    return 0;
}
