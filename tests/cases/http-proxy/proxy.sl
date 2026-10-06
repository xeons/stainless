// SPDX-License-Identifier: 0BSD
// Proxies: a request for http sent to the proxy in absolute form, a CONNECT
// tunnel carrying TLS to an https origin, Basic credentials, a 407, hosts
// that go around the proxy, and how the environment's variables are read.
//
// The proxy is a small one written here: a thread per connection, which
// forwards one absolute-form request to its origin and relays the answer, or
// answers CONNECT and relays bytes both ways until either side closes.
module HttpProxy;

import Standard.Collections;
import Standard.Console;
import Standard.Convert;
import Standard.IO;
import Standard.Net;
import Standard.Net.Http;
import Standard.Net.Security;
import Standard.Security.Cryptography;
import Standard.Security.Cryptography.X509Certificates;
import Standard.Text;
import Standard.Threading;
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

// ---------------------------------------------------------------- the proxy

/// A proxy on the loopback. When `RequiredCredentials` is not empty, it
/// answers 407 to anything without exactly that `Proxy-Authorization`.
class TestProxy
{
    private TcpListener _listener;
    private AtomicBool _stopping = new AtomicBool(false);
    private Mutex<List<String>> _log = new Mutex<List<String>>(new List<String>());
    private List<Thread> _workers = new List<Thread>();
    private Thread? _acceptor;
    public String RequiredCredentials = "";

    public TestProxy(TcpListener listener) => _listener = listener;

    public ushort Port => _listener.LocalEndPoint.Port;

    public String Address => "http://127.0.0.1:" + Text.FromInteger((long)Port);

    public void StartProxying() => _acceptor = new Thread(() => this.AcceptProxyConnections());

    public void StopProxying()
    {
        _stopping.Write(true);
        if (_acceptor is Thread acceptor)
            acceptor.Join();
        foreach (var worker in _workers)
            worker.Join();
        _listener.Close();
    }

    /// What the proxy did, in order.
    public List<String> TakeProxyLog()
    {
        var held = _log.Enter();
        var copy = new List<String>();
        foreach (var line in held.Value)
            copy.Add(line);
        held.Value.Clear();
        return copy;
    }

    private void NoteProxyEvent(String line)
    {
        var held = this._log.Enter();
        held.Value.Add(line);
    }

    private void AcceptProxyConnections()
    {
        while (!this._stopping.Read())
        {
            if (!this._listener.Pending(10))
                continue;
            TcpClient client = this._listener.Accept();
            client.Underlying.SetReceiveTimeout(5000);
            this._workers.Add(new Thread(() => this.ServeProxyConnection(client)));
        }
    }

    private void ServeProxyConnection(TcpClient client)
    {
        String head = ReadProxyHead(client);
        if (head.IsEmpty)
        {
            client.Close();
            return;
        }
        String[] lines = head.Split("\r\n");
        String[] requestLine = lines[0u].Split(' ');
        String authorization = FindProxyField(lines, "proxy-authorization");
        String shownAuthorization = authorization.IsEmpty ? "" : " with " + authorization;

        if (!this.RequiredCredentials.IsEmpty && authorization != this.RequiredCredentials)
        {
            this.NoteProxyEvent("407 for " + requestLine[0u] + shownAuthorization);
            client.SendText("HTTP/1.1 407 Proxy Authentication Required\r\n" +
                            "Proxy-Authenticate: Basic realm=\"test\"\r\nContent-Length: 0\r\n" +
                            "Connection: close\r\n\r\n");
            client.Close();
            return;
        }

        if (requestLine[0u] == "CONNECT")
        {
            this.NoteProxyEvent("CONNECT " + HideTestPort(requestLine[1u]) + shownAuthorization);
            String[] hostPort = requestLine[1u].Split(':');
            var origin = TcpClient.Connect(hostPort[0u], (ushort)ParseTestDecimal(hostPort[1u]));
            if (!origin.Ok)
            {
                client.SendText("HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\n\r\n");
                client.Close();
                return;
            }
            client.SendText("HTTP/1.1 200 Connection Established\r\n\r\n");
            this.RelayProxyBytes(client, origin.Value);
            return;
        }

        // Absolute form: http://host:port/path.
        String target = requestLine[1u];
        this.NoteProxyEvent(requestLine[0u] + " " + HideTestPort(target) + shownAuthorization);
        String rest = target.Substring(7u);
        long slash = rest.IndexOf('/');
        String authority = rest.Substring(0u, (nuint)slash);
        String path = rest.Substring((nuint)slash);
        String[] hostPort = authority.Split(':');
        var upstream = TcpClient.Connect(hostPort[0u], (ushort)ParseTestDecimal(hostPort[1u]));
        if (!upstream.Ok)
        {
            client.Close();
            return;
        }
        TcpClient origin = upstream.Value;
        var forwarded = new StringBuilder();
        forwarded.Append(requestLine[0u] + " " + path + " HTTP/1.1\r\n");
        for (nuint i = 1u; i < lines.Length; i++)
        {
            String lower = lines[i].ToLowerAscii();
            if (lines[i].IsEmpty || lower.StartsWith("proxy-authorization:") || lower.StartsWith("connection:"))
                continue;
            forwarded.Append(lines[i] + "\r\n");
        }
        forwarded.Append("Connection: close\r\n\r\n");
        origin.SendText(forwarded.ToText());
        this.RelayProxyBytes(client, origin);
    }

    /// Copies bytes each way until either side ends, then closes both.
    private void RelayProxyBytes(TcpClient client, TcpClient origin)
    {
        var block = new byte[16384u];
        bool open = true;
        while (open && !this._stopping.Read())
        {
            bool moved = false;
            if (client.WaitToRead(0))
            {
                nuint got = client.Read(block, 0u, block.Length);
                if (got == 0u)
                    open = false;
                else
                    origin.SendAll(block[:got].ToArray());
                moved = true;
            }
            if (open && origin.WaitToRead(0))
            {
                nuint got = origin.Read(block, 0u, block.Length);
                if (got == 0u)
                    open = false;
                else
                    client.SendAll(block[:got].ToArray());
                moved = true;
            }
            if (!moved)
                Sleep(1u);
        }
        origin.Close();
        client.Close();
    }
}

/// The head of a request, up to its empty line, or empty when it ends first.
String ReadProxyHead(TcpClient client)
{
    var bytes = new List<byte>();
    var one = new byte[1u];
    while (true)
    {
        if (client.Read(one, 0u, 1u) == 0u)
            return "";
        bytes.Add(one[0u]);
        nuint count = bytes.Count;
        if (count >= 4u && bytes[count - 4u] == (byte)'\r' && bytes[count - 3u] == (byte)'\n' &&
            bytes[count - 2u] == (byte)'\r' && bytes[count - 1u] == (byte)'\n')
        {
            byte[] all = bytes.ToArray();
            return Text.FromBytes(&all[0u], count - 4u);
        }
    }
}

String FindProxyField(String[] lines, String name)
{
    foreach (var line in lines)
    {
        if (line.ToLowerAscii().StartsWith(name + ":"))
            return line.Substring(name.ByteLength() + 1u).Trim();
    }
    return "";
}

/// `127.0.0.1:NNNNN` with the port hidden, since the system chose it.
String HideTestPort(String text)
{
    long at = text.IndexOf("127.0.0.1:");
    if (at < 0)
        return text;
    nuint start = (nuint)at + 10u;
    nuint end = start;
    while (end < text.ByteLength() && text.GetByteAt(end) >= (byte)'0' && text.GetByteAt(end) <= (byte)'9')
        end++;
    return text.Substring(0u, start) + "PORT" + text.Substring(end);
}

TestProxy? StartTestProxy()
{
    var listening = TcpListener.Listen("127.0.0.1", 0u);
    if (!listening.Ok)
        return null;
    var proxy = new TestProxy(listening.Value);
    proxy.StartProxying();
    return proxy;
}

// --------------------------------------------------------------- the client

HttpTestReply RouteOrigin(HttpTestRequest request)
{
    String sent = request.HasField("Proxy-Authorization") ? "leaked credentials" : "no credentials";
    return HttpTestReply.CreateText(200, "OK", "", "origin served " + request.Target + ", " + sent);
}

void ShowFetched(String label, HttpClient client, String uri, TestProxy proxy)
{
    var sent = client.Send(new HttpRequestMessage(HttpMethod.Get, uri),
                           HttpCompletionOption.ResponseContentRead, out HttpFailure failure);
    if (sent.Ok)
    {
        Console.WriteLine(label + ": " + sent.Value.Content.ReadAsString().GetValueOrDefault("body failed"));
    }
    else
    {
        String status = failure.StatusCode is Some code ? " " + Text.FromInteger((long)(int)code.Value) : "";
        Console.WriteLine(label + ": " + $"{sent.Error}" + status + " (" + failure.Message + ")");
    }
    foreach (var line in proxy.TakeProxyLog())
        Console.WriteLine("  proxy: " + line);
}

bool AcceptPinned(HttpRequestMessage request, X509Certificate2? certificate, List<byte[]> chain,
                  TlsError defaultVerdict)
{
    byte[] expected = ReadCertificateDer(ServerCertificate);
    if (chain.Count == 0u || chain[0u].Length != expected.Length)
        return false;
    for (nuint i = 0u; i < expected.Length; i++)
    {
        if (chain[0u][i] != expected[i])
            return false;
    }
    return true;
}

HttpClient CreateProxiedClient(IWebProxy? proxy, bool useProxy)
{
    var handler = new HttpClientHandler();
    handler.Proxy = proxy;
    handler.UseProxy = useProxy;
    handler.ServerCertificateCustomValidationCallback = AcceptPinned;
    var client = new HttpClient(handler);
    client.Timeout = TimeSpan.FromSeconds(8);
    return client;
}

// ----------------------------------------------------------- the environment

void ShowEnvironment(String label, Dictionary<String, String> variables)
{
    IWebProxy? found = HttpEnvironmentProxy.FromEnvironment((String name) =>
    {
        if (variables.TryGetValue(name) is Some value)
            return value.Value;
        return null;
    });
    if (found == null)
    {
        Console.WriteLine(label + ": no proxy");
        return;
    }
    IWebProxy proxy = found;
    var http = proxy.GetProxy(new Uri("http://far.example/"));
    var https = proxy.GetProxy(new Uri("https://far.example/"));
    Console.WriteLine(label + ": http via " + (http is Uri a ? a.ToString() : "none") +
                      ", https via " + (https is Uri b ? b.ToString() : "none"));
}

void ShowBypass(IWebProxy proxy, String uri)
{
    Console.WriteLine("  " + uri + " " + (proxy.IsBypassed(new Uri(uri)) ? "direct" : "proxied"));
}

Dictionary<String, String> CreateVariables(String name, String value)
{
    var variables = new Dictionary<String, String>();
    variables.SetValue(name, value);
    return variables;
}

int Main()
{
    var tls = new TlsServerOptions();
    tls.CertificateChain.Add(ReadCertificateDer(ServerCertificate));
    var key = TlsSigningKey.ImportFromPem(ConvertToText(ServerKey));
    if (!key.Ok)
        return 1;
    tls.PrivateKey = key.Value;

    HttpTestServer? plainStarted = HttpTestServer.StartServing(RouteOrigin);
    HttpTestServer? secureStarted = HttpTestServer.StartServing(RouteOrigin, tls);
    TestProxy? proxyStarted = StartTestProxy();
    TestProxy? guardedStarted = StartTestProxy();
    if (plainStarted == null || secureStarted == null || proxyStarted == null || guardedStarted == null)
        return 1;
    HttpTestServer plain = plainStarted;
    HttpTestServer secure = secureStarted;
    TestProxy proxy = proxyStarted;
    TestProxy guarded = guardedStarted;
    guarded.RequiredCredentials = "Basic " + Convert.ToBase64String("user:secret");

    Console.WriteLine("-- through the proxy");
    var webProxy = new WebProxy(proxy.Address);
    var client = CreateProxiedClient(webProxy, true);
    ShowFetched("http", client, plain.Origin + "/page?x=1", proxy);
    ShowFetched("https", client, secure.Origin + "/secret", proxy);
    ShowFetched("https again, same tunnel", client, secure.Origin + "/again", proxy);
    client.Dispose();

    Console.WriteLine("-- credentials");
    var withCredentials = new WebProxy(guarded.Address);
    withCredentials.Credentials = new NetworkCredential("user", "secret");
    client = CreateProxiedClient(withCredentials, true);
    ShowFetched("http", client, plain.Origin + "/guarded", guarded);
    ShowFetched("https", client, secure.Origin + "/guarded", guarded);
    client.Dispose();
    var inAddress = new WebProxy("http://user:secret@127.0.0.1:" + Text.FromInteger((long)guarded.Port));
    client = CreateProxiedClient(inAddress, true);
    ShowFetched("from the proxy's URI", client, plain.Origin + "/userinfo", guarded);
    client.Dispose();
    client = CreateProxiedClient(new WebProxy(guarded.Address), true);
    ShowFetched("none, http", client, plain.Origin + "/refused", guarded);
    ShowFetched("none, https", client, secure.Origin + "/refused", guarded);
    client.Dispose();

    Console.WriteLine("-- around the proxy");
    var bypassing = new WebProxy(proxy.Address, false, ["127.0.0.*"]);
    client = CreateProxiedClient(bypassing, true);
    ShowFetched("bypass list", client, plain.Origin + "/direct", proxy);
    client.Dispose();
    client = CreateProxiedClient(new WebProxy(proxy.Address, true), true);
    ShowFetched("bypass on local", client, plain.Origin + "/direct", proxy);
    client.Dispose();
    client = CreateProxiedClient(webProxy, false);
    ShowFetched("UseProxy off", client, plain.Origin + "/direct", proxy);
    client.Dispose();
    HttpClient.DefaultProxy = new WebProxy(proxy.Address);
    client = CreateProxiedClient(null, true);
    ShowFetched("DefaultProxy", client, plain.Origin + "/default", proxy);
    client.Dispose();
    HttpClient.DefaultProxy = new WebProxy();
    client = CreateProxiedClient(null, true);
    ShowFetched("DefaultProxy that is none", client, plain.Origin + "/default", proxy);
    client.Dispose();

    proxy.StopProxying();
    guarded.StopProxying();
    plain.StopServing();
    secure.StopServing();
    Console.WriteLine("-- the TLS origin saw");
    foreach (var line in secure.Log)
        Console.WriteLine(line);

    Console.WriteLine("-- the environment");
    ShowEnvironment("nothing set", new Dictionary<String, String>());
    ShowEnvironment("http_proxy", CreateVariables("http_proxy", "http://proxy.example:3128"));
    ShowEnvironment("no scheme", CreateVariables("https_proxy", "proxy.example:8080"));
    var both = CreateVariables("http_proxy", "http://lower.example:1");
    both.SetValue("HTTP_PROXY", "http://upper.example:2");
    ShowEnvironment("lower case first", both);
    ShowEnvironment("upper case alone", CreateVariables("HTTP_PROXY", "http://upper.example:2"));
    var cgi = CreateVariables("HTTP_PROXY", "http://upper.example:2");
    cgi.SetValue("REQUEST_METHOD", "GET");
    ShowEnvironment("upper case under CGI", cgi);
    var all = CreateVariables("ALL_PROXY", "http://all.example:9");
    all.SetValue("https_proxy", "http://secure.example:3");
    ShowEnvironment("all_proxy as the fallback", all);
    ShowEnvironment("empty", CreateVariables("http_proxy", ""));
    ShowEnvironment("socks", CreateVariables("https_proxy", "socks5://socks.example:1080"));

    Console.WriteLine("-- no_proxy");
    var listed = CreateVariables("http_proxy", "http://proxy.example:3128");
    listed.SetValue("no_proxy", "example.com, .internal, *.wild.org, 10.0.0.0/8, 192.168.1.1, [fd00::1], host.test:8080");
    IWebProxy? parsed = HttpEnvironmentProxy.FromEnvironment((String name) =>
    {
        if (listed.TryGetValue(name) is Some value)
            return value.Value;
        return null;
    });
    if (parsed != null)
    {
        IWebProxy exceptions = parsed;
        ShowBypass(exceptions, "http://example.com/");
        ShowBypass(exceptions, "http://www.example.com/");
        ShowBypass(exceptions, "http://notexample.com/");
        ShowBypass(exceptions, "http://a.internal/");
        ShowBypass(exceptions, "http://internal/");
        ShowBypass(exceptions, "http://x.wild.org/");
        ShowBypass(exceptions, "http://wild.org/");
        ShowBypass(exceptions, "http://10.20.30.40/");
        ShowBypass(exceptions, "http://11.0.0.1/");
        ShowBypass(exceptions, "http://192.168.1.1/");
        ShowBypass(exceptions, "http://192.168.1.2/");
        ShowBypass(exceptions, "http://[fd00::1]/");
        ShowBypass(exceptions, "http://host.test:8080/");
        ShowBypass(exceptions, "http://host.test:9090/");
        ShowBypass(exceptions, "http://localhost/");
        ShowBypass(exceptions, "http://127.0.0.1:8080/");
    }
    var everything = CreateVariables("http_proxy", "http://proxy.example:3128");
    everything.SetValue("NO_PROXY", "*");
    IWebProxy? star = HttpEnvironmentProxy.FromEnvironment((String name) =>
    {
        if (everything.TryGetValue(name) is Some value)
            return value.Value;
        return null;
    });
    if (star != null)
        ShowBypass(star, "http://anything.example/");
    return 0;
}
