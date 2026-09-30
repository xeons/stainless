// Stainless - an experimental general-purpose language.
// Copyright (C) 2026 Brandon Scott
//
// This file is part of the Stainless runtime library. It is free
// software: you can redistribute it and/or modify it under the terms of
// the GNU General Public License as published by the Free Software
// Foundation, either version 3 of the License, or (at your option) any
// later version.
//
// It is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
// for more details.
//
// As an additional permission under section 7 of that License, compiling
// a program with Stainless does not by itself place that program under
// the GNU General Public License. See LICENSE.RUNTIME.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

module Standard.Net.Http;

import Standard.Collections;
import Standard.IO;
import Standard.IO.Compression;
import Standard.Limits;
import Standard.Net.Security;
import Standard.Text;
import Standard.Threading;
import Standard.Time;

/// What a client does between a request and the wire: connections and their
/// pool, proxies, TLS, redirects, cookies and decompression.
///
///     var handler = new HttpClientHandler();
///     handler.AutomaticDecompression = DecompressionMethods.All;
///     handler.MaxConnectionsPerServer = 4;
///     var client = new HttpClient(handler);
///
/// .NET's `HttpClientHandler`, and its defaults. Its settings are read when
/// a request is sent; the pool is made with the ones in force at the first
/// request and keeps them.
public class HttpClientHandler
{
    private HttpConnectionPool? _pool;
    private Mutex<int> _poolLock = new Mutex<int>(0);
    private bool _disposed = false;
    private HttpServerCertificateValidator _certificateCallback = AcceptHttpCertificateByDefault;
    private bool _hasCertificateCallback = false;

    public HttpClientHandler() { }

    // The pool is emptied here rather than when it goes, since an HTTP/2
    // reader thread can hold the pool's last reference for a moment and MUST
    // NOT be the one to release the connections that join it.
    ~HttpClientHandler() { Dispose(); }

    /// Whether a `3xx` with a `Location` is followed. A 303 makes any method
    /// but HEAD a `GET` without a body; a 301 or a 302 does so to `POST`
    /// alone; a 307 or a 308 keeps the method and the body. Once a redirect
    /// leaves the first origin, `Authorization`, a `Cookie` set by hand and
    /// a `Host` override are not sent.
    public bool AllowAutoRedirect { get; set; } = true;

    /// How many redirects one request may follow before it fails with
    /// `TooManyRedirects`.
    public int MaxAutomaticRedirections { get; set; } = 50;

    /// Which codings are asked for with `Accept-Encoding` and undone.
    public DecompressionMethods AutomaticDecompression { get; set; } = DecompressionMethods.None;

    /// Whether `CookieContainer` is sent and filled.
    public bool UseCookies { get; set; } = true;

    /// The cookies sent and received.
    public CookieContainer CookieContainer { get; set; } = new CookieContainer();

    /// Whether a proxy is used at all.
    public bool UseProxy { get; set; } = true;

    /// The proxy, or null for `HttpClient.DefaultProxy`.
    public IWebProxy? Proxy { get; set; }

    /// Decides whether to trust a server's certificate, in place of the TLS
    /// module's validator, which it is told the answer of.
    public HttpServerCertificateValidator ServerCertificateCustomValidationCallback
    {
        get => _certificateCallback;
        set
        {
            _certificateCallback = value;
            _hasCertificateCallback = true;
        }
    }

    /// A callback that trusts every certificate. For a test against a server
    /// with a throwaway certificate, and nothing else: it makes TLS encryption
    /// without authentication, which a machine in the middle defeats.
    public static HttpServerCertificateValidator DangerousAcceptAnyServerCertificateValidator =>
        AcceptAnyHttpCertificate;

    /// The client's certificates, DER, leaf first, sent when a server asks.
    public List<byte[]> ClientCertificates { get; set; } = new List<byte[]>();

    /// The key of the client's leaf certificate.
    public TlsSigningKey? ClientCertificateKey { get; set; }

    /// The most connections open to one server at once. A request past it
    /// waits, within its timeout, for one to be free.
    public int MaxConnectionsPerServer { get; set; } = Limits.MaxInt;

    /// How long a connection may sit idle in the pool and still be reused.
    /// Zero pools nothing; negative keeps connections for ever.
    public TimeSpan PooledConnectionIdleTimeout { get; set; } = TimeSpan.FromMinutes(1);

    /// The most a response head may take, in KiB. HTTP/2 advertises it as
    /// `SETTINGS_MAX_HEADER_LIST_SIZE`.
    public int MaxResponseHeadersLength { get; set; } = 64;

    /// How much of a response body each HTTP/2 stream lets the server send
    /// before the reader has read it, in bytes: the flow-control window,
    /// between 65 535 and 2^31 − 1. .NET's starts at 65 535 and grows it as
    /// it measures the connection; this one is fixed, so its default is a
    /// window wide enough for a fast link, 1 MiB.
    public int InitialHttp2StreamWindowSize { get; set; } = 1048576;

    /// Whether a second HTTP/2 connection to a server is opened when every
    /// stream the first allows is busy. When false, as by default, a request
    /// waits for a stream to end.
    public bool EnableMultipleHttp2Connections { get; set; } = false;

    /// Closes every idle connection. A response still being read keeps its
    /// connection until it is done with it, and that one is then closed too.
    public void Dispose()
    {
        HttpConnectionPool? pool = null;
        {
            var held = _poolLock.Enter();
            _disposed = true;
            pool = _pool;
        }
        if (pool != null)
            pool.CloseAllHttpConnections();
    }

    internal TlsCertificateValidator CreateHttpCertificateValidator(HttpRequestMessage request)
    {
        if (!_hasCertificateCallback)
            return ValidateTlsCertificateChainByDefault;
        var check = new HttpCertificateCheck(request, _certificateCallback);
        return check.ValidateHttpCertificateChain;
    }

    /// The pool, made by the first request. Several threads MAY send the
    /// first requests at once, and they MUST all get the one pool.
    private HttpConnectionPool EnsureHttpPool()
    {
        var held = _poolLock.Enter();
        var existing = _pool;
        if (existing != null)
            return existing;
        int most = MaxConnectionsPerServer;
        var made = new HttpConnectionPool(most <= 0 ? 1u : (nuint)most, PooledConnectionIdleTimeout,
                                          EnableMultipleHttp2Connections);
        _pool = made;
        return made;
    }

    // ------------------------------------------------------------- sending

    /// Sends `request` to its absolute `RequestUri`, following redirects, and
    /// reads the body into memory unless `option` says to stream it.
    internal Result<HttpResponseMessage, HttpError> SendHttpRequest(
        HttpRequestMessage request, HttpCompletionOption option, HttpDeadline deadline,
        HttpFailure failure, HttpRequestHeaders defaults, long maxBufferSize)
    {
        if (_disposed)
            return Fail(failure.RecordHttpFailure(HttpError.Disposed, "the handler has been disposed"));
        HttpConnectionPool pool = EnsureHttpPool();

        Uri first = (Uri)request.RequestUri;
        nuint redirects = 0u;
        HttpResponseMessage response = new HttpResponseMessage();
        while (true)
        {
            Uri uri = (Uri)request.RequestUri;
            failure.RequestUri = uri;
            bool sameOrigin = IsHttpSameOrigin(first, uri);
            var sent = SendHttpRequestOnce(request, uri, sameOrigin, deadline, failure, defaults, pool);
            if (!sent.Ok)
                return Fail(sent.Error);
            response = sent.Value;
            response.RequestMessage = request;

            if (UseCookies)
            {
                var now = DateTimeOffset.UtcNow;
                foreach (var header in response.Headers.GetValues("set-cookie"))
                    CookieContainer.StoreHttpSetCookie(uri, header, now);
            }

            if (!AllowAutoRedirect)
                break;
            if (FindHttpRedirectTarget(response, uri) is not Uri target)
                break;

            int status = (int)response.StatusCode;
            HttpMethod method = request.Method;
            HttpContent? content = request.Content;
            // 303 makes anything but HEAD a GET; 301 and 302 do so to POST
            // alone, as browsers and .NET do. Every other method goes again
            // as it was, with its body.
            bool becomesGet = status == 303
                ? method.Method != "HEAD"
                : (status == 301 || status == 302) && method.Method == "POST";
            if (becomesGet)
            {
                method = HttpMethod.Get;
                content = null;
            }
            else if (content != null && !content.RewindHttpContent())
            {
                break;
            }

            redirects++;
            if (redirects > (nuint)MaxAutomaticRedirections || MaxAutomaticRedirections <= 0)
            {
                response.Dispose();
                return Fail(failure.RecordHttpFailure(HttpError.TooManyRedirects,
                    "more redirects than MaxAutomaticRedirections allows (" +
                    Text.FromInteger((long)MaxAutomaticRedirections) + ")"));
            }

            DiscardHttpResponseBody(response);
            request.RequestUri = target;
            request.Method = method;
            request.Content = content;
        }

        if (AutomaticDecompression != DecompressionMethods.None)
            DecodeHttpResponse(response);

        if (option == HttpCompletionOption.ResponseHeadersRead)
        {
            deadline.RemoveHttpDeadline();
            return Ok(response);
        }

        HttpError buffered = response.Content.LoadIntoBuffer(maxBufferSize);
        if (buffered != HttpError.None)
        {
            response.Dispose();
            if (buffered == HttpError.ResponseTooLarge)
            {
                failure.RecordHttpFailure(buffered, "the body was longer than " +
                                          Text.FromInteger(maxBufferSize) + " bytes");
            }
            else if (buffered == HttpError.DecompressionFailed && response.Content is HttpResponseContent decoded)
            {
                failure.CompressionErrorCode = decoded.HttpCompressionError;
                failure.RecordHttpFailure(buffered, "the body was not valid " +
                                          DescribeHttpContentCoding(response));
            }
            else if (failure.Error != buffered)
            {
                failure.RecordHttpFailure(buffered, "the body could not be read");
            }
            return Fail(buffered);
        }
        return Ok(response);
    }

    /// One hop: a route, a connection from the pool or a new one, and one
    /// retry on a new connection when a pooled one turns out to have been
    /// closed and the request may safely be sent again.
    private Result<HttpResponseMessage, HttpError> SendHttpRequestOnce(
        HttpRequestMessage request, Uri uri, bool sameOrigin, HttpDeadline deadline,
        HttpFailure failure, HttpRequestHeaders defaults, HttpConnectionPool pool)
    {
        var routed = ChooseHttpRoute(uri, failure);
        if (!routed.Ok)
            return Fail(routed.Error);
        HttpRoute route = routed.Value;

        var chosen = ChooseHttpVersions(request, route, failure);
        if (!chosen.Ok)
            return Fail(chosen.Error);
        HttpVersionChoice choice = chosen.Value;

        var built = BuildHttpWireRequest(request, uri, route, sameOrigin, defaults, failure);
        if (!built.Ok)
            return Fail(built.Error);
        HttpWireRequest wire = built.Value;

        nuint headerLimit = MaxResponseHeadersLength <= 0 ? 1024u : (nuint)MaxResponseHeadersLength * 1024u;
        var exchange = new HttpExchange(deadline, failure, headerLimit);
        String key = route.PoolKey;
        bool allowIdle = true;
        bool mayAddHttp2 = true;
        nuint attempt = 0u;
        while (true)
        {
            attempt++;
            HttpError reserved = pool.ReserveHttpConnection(key, deadline, choice, allowIdle, mayAddHttp2,
                                                            out IHttpConnection? found);
            if (reserved != HttpError.None)
            {
                String why = reserved == HttpError.Timeout
                    ? "the request timed out waiting for a connection"
                    : "the handler has been disposed";
                return Fail(failure.RecordHttpFailure(reserved, why));
            }

            IHttpConnection connection;
            if (found != null)
            {
                connection = found;
            }
            else
            {
                var opened = OpenHttpConnection(route, this, request, choice, exchange, pool);
                if (!opened.Ok)
                {
                    pool.CancelHttpReservation(key, choice);
                    return Fail(opened.Error);
                }
                connection = opened.Value;
                HttpError added = pool.AddHttpConnection(key, connection, choice, out bool streamReserved);
                if (added != HttpError.None)
                    return Fail(failure.RecordHttpFailure(added, "the handler has been disposed"));
                // A connection that came up with no stream free is waited on
                // like any other, and no more are opened for this request.
                if (!streamReserved && connection.IsMultiplexed)
                {
                    mayAddHttp2 = false;
                    continue;
                }
            }

            exchange.IsRetryable = false;
            exchange.IsUnprocessed = false;
            var result = connection.SendHttpRequest(wire, exchange);
            if (result.Ok)
            {
                HttpResponseMessage answered = result.Value;
                if (route.Proxy == null || route.IsHttps ||
                    answered.StatusCode != HttpStatusCode.ProxyAuthenticationRequired)
                    return result;
                DiscardHttpResponseBody(answered);
                failure.StatusCode = HttpStatusCode.ProxyAuthenticationRequired;
                return Fail(failure.RecordHttpFailure(HttpError.ProxyFailure,
                    "the proxy wants credentials: 407 " + answered.ReasonPhrase));
            }

            pool.ReleaseHttpConnection(connection, false);
            HttpContent? content = wire.Content;
            // A request the server never processed may go again whatever its
            // method; one that met a connection closed under it, only once
            // and only when it is idempotent.
            bool mayRetry = result.Error == HttpError.ConnectionClosed &&
                            ((exchange.IsUnprocessed && attempt <= 3u) ||
                             (attempt == 1u && exchange.IsRetryable && request.Method.IsIdempotent));
            if (!mayRetry || (content != null && !content.RewindHttpContent()))
                return Fail(result.Error);
            failure.ResetHttpFailure();
            failure.RequestUri = uri;
            allowIdle = false;
        }
    }

    /// Which protocols `request` may go in along `route`: its version, its
    /// policy, and what the route can carry. Plain http speaks HTTP/2 only
    /// when nothing else will do, and a plain proxy never.
    ///
    /// @failure HttpError.VersionNegotiationFailure  nothing the policy
    ///                                               allows can be used
    private Result<HttpVersionChoice, HttpError> ChooseHttpVersions(HttpRequestMessage request, HttpRoute route,
                                                                    HttpFailure failure)
    {
        int major = request.Version.Major;
        HttpVersionPolicy policy = request.VersionPolicy;
        bool http11 = false;
        bool http2 = false;
        if (major >= 3)
        {
            if (policy != HttpVersionPolicy.RequestVersionOrLower)
            {
                return Fail(failure.RecordHttpFailure(HttpError.VersionNegotiationFailure,
                    "HTTP/" + request.Version.ToString(2) + " is not spoken, and the policy allows nothing lower"));
            }
            http11 = true;
            http2 = true;
        }
        else if (major == 2)
        {
            http2 = true;
            http11 = policy == HttpVersionPolicy.RequestVersionOrLower;
        }
        else
        {
            http11 = true;
            http2 = policy == HttpVersionPolicy.RequestVersionOrHigher;
        }

        if (!route.IsHttps && http2 && (http11 || route.Proxy != null))
        {
            if (!http11)
            {
                return Fail(failure.RecordHttpFailure(HttpError.VersionNegotiationFailure,
                    "HTTP/2 was required, and a plain proxy is spoken to in HTTP/1.1"));
            }
            http2 = false;
        }
        return Ok(new HttpVersionChoice(http11, http2));
    }

    /// Direct, or through the proxy this handler or `HttpClient.DefaultProxy`
    /// names for `uri`.
    private Result<HttpRoute, HttpError> ChooseHttpRoute(Uri uri, HttpFailure failure)
    {
        String scheme = uri.Scheme;
        if (scheme != "http" && scheme != "https")
        {
            return Fail(failure.RecordHttpFailure(HttpError.InvalidRequest,
                "the scheme '" + scheme + "' is not http or https"));
        }
        String host = GetHttpBareHost(uri);
        int port = uri.Port;
        if (host.IsEmpty || port <= 0 || port > 65535)
            return Fail(failure.RecordHttpFailure(HttpError.InvalidRequest, "the URI names no host"));
        if (!IsHttpHostValid(uri.Host))
            return Fail(failure.RecordHttpFailure(HttpError.InvalidRequest, "the URI's host is malformed"));
        var route = new HttpRoute(scheme, host, (ushort)port);

        if (!UseProxy)
            return Ok(route);
        IWebProxy? chosen = Proxy;
        IWebProxy proxy = chosen != null ? chosen : HttpClient.DefaultProxy;
        if (proxy.IsBypassed(uri))
            return Ok(route);
        if (proxy.GetProxy(uri) is not Uri address || address.Equals(uri))
            return Ok(route);
        if (address.Scheme != "http")
        {
            return Fail(failure.RecordHttpFailure(HttpError.ProxyFailure,
                "the proxy '" + address.ToString() + "' is not an http proxy"));
        }
        route.Proxy = address;
        var fromAddress = ReadHttpProxyCredentials(address);
        route.ProxyCredentials = fromAddress != null ? fromAddress : proxy.Credentials;
        return Ok(route);
    }

    /// Every field the request is sent with, in the order it is sent.
    private Result<HttpWireRequest, HttpError> BuildHttpWireRequest(
        HttpRequestMessage request, Uri uri, HttpRoute route, bool sameOrigin,
        HttpRequestHeaders defaults, HttpFailure failure)
    {
        HttpMethod method = request.Method;
        if (!IsHttpToken(method.Method))
            return Fail(failure.RecordHttpFailure(HttpError.InvalidRequest, "the method is not a token"));

        String path = uri.PathAndQuery;
        if (path.IsEmpty)
            path = "/";
        String target = path;
        if (route.Proxy != null && !route.IsHttps)
            target = uri.Scheme + "://" + uri.Authority + path;

        var wire = new HttpWireRequest(method, target);
        wire.Scheme = uri.Scheme;
        wire.Authority = uri.Authority;
        wire.Path = path;
        HttpWireHeaders fields = wire.Fields;
        HttpRequestHeaders headers = request.Headers;
        // A Host override was meant for the first origin, not for another.
        String? host = sameOrigin ? headers.Host : null;
        fields.AppendHttpValue("Host", host != null ? host : uri.Authority);

        // A hand-set Proxy-Authorization goes only to a plain proxy of the
        // first origin that the handler has no credentials for; anywhere
        // else it would reach a server or another proxy.
        bool plainProxy = route.Proxy != null && !route.IsHttps;
        bool keepsProxyAuthorization = plainProxy && sameOrigin && route.ProxyCredentials == null;
        foreach (var field in defaults.Fields)
        {
            if (!headers.Contains(field.Name))
                AddHttpRequestField(fields, field, sameOrigin, keepsProxyAuthorization);
        }
        foreach (var field in headers.Fields)
            AddHttpRequestField(fields, field, sameOrigin, keepsProxyAuthorization);

        if (AutomaticDecompression != DecompressionMethods.None && !fields.Contains("Accept-Encoding"))
        {
            bool gzip = AutomaticDecompression.HasFlag(DecompressionMethods.GZip);
            bool deflate = AutomaticDecompression.HasFlag(DecompressionMethods.Deflate);
            fields.AppendHttpValue("Accept-Encoding", gzip && deflate ? "gzip, deflate" : gzip ? "gzip" : "deflate");
        }

        if (UseCookies)
        {
            String cookies = CookieContainer.GetCookieHeader(uri);
            if (!cookies.IsEmpty)
            {
                String? given = fields.GetJoinedHttpValue("cookie");
                fields.SetHttpValue("Cookie", given == null ? cookies : given + "; " + cookies);
            }
        }

        if (plainProxy && route.ProxyCredentials is NetworkCredential credentials)
            fields.AppendHttpValue("Proxy-Authorization", FormatHttpBasicCredentials(credentials));

        HttpContent? content = request.Content;
        if (content != null)
        {
            wire.Content = content;
            foreach (var field in content.Headers.Fields)
            {
                if (field.Key == "content-length")
                    continue;
                foreach (var value in field.Values)
                    fields.AppendHttpValue(field.Name, value);
            }
            var length = content.Headers.ContentLength;
            if (headers.TransferEncodingChunked || length is not Some known)
            {
                wire.IsChunked = true;
                fields.AppendHttpValue("Transfer-Encoding", "chunked");
            }
            else
            {
                wire.DeclaredLength = known.Value;
                fields.AppendHttpValue("Content-Length", Text.FromInteger(known.Value));
            }
            if (headers.ExpectContinue)
            {
                wire.ExpectContinue = true;
                fields.AppendHttpValue("Expect", "100-continue");
            }
        }
        else if (method.Method == "POST" || method.Method == "PUT" || method.Method == "PATCH")
        {
            fields.AppendHttpValue("Content-Length", "0");
        }

        foreach (var field in fields.Fields)
        {
            foreach (var value in field.Values)
            {
                if (!IsHttpFieldValue(value))
                {
                    return Fail(failure.RecordHttpFailure(HttpError.InvalidRequest,
                        "the field '" + field.Name + "' has a control character in it"));
                }
            }
        }
        return Ok(wire);
    }

    /// Copies one request field onto the wire, leaving out what this handler
    /// decides itself, `Authorization` and `Cookie` once a redirect has left
    /// the origin they were meant for, and `Proxy-Authorization` unless
    /// `keepsProxyAuthorization`.
    private void AddHttpRequestField(HttpWireHeaders fields, HttpHeaderField field, bool sameOrigin,
                                     bool keepsProxyAuthorization)
    {
        switch (field.Key)
        {
            case "host":
            case "transfer-encoding":
            case "content-length":
            case "expect":
                return;
            case "authorization":
            case "cookie":
                if (!sameOrigin)
                    return;
                break;
            case "proxy-authorization":
                if (!keepsProxyAuthorization)
                    return;
                break;
        }
        foreach (var value in field.Values)
            fields.AppendHttpValue(field.Name, value);
    }

    /// Replaces a response's body with the body decoded, when it was coded
    /// with one coding this handler was asked to undo.
    private void DecodeHttpResponse(HttpResponseMessage response)
    {
        if (response.Content is not HttpResponseContent content)
            return;
        String[] codings = content.Headers.ContentEncoding;
        if (codings.Length != 1u)
            return;
        String coding = codings[0u].ToLowerAscii();
        IStream raw = content.RawHttpBody;
        if ((coding == "gzip" || coding == "x-gzip") && AutomaticDecompression.HasFlag(DecompressionMethods.GZip))
            content.DecodeHttpContent(new GZipStream(raw, CompressionMode.Decompress));
        else if (coding == "deflate" && AutomaticDecompression.HasFlag(DecompressionMethods.Deflate))
            content.DecodeHttpContent(new HttpDeflateDecoder(raw));
        else
            return;
        content.Headers.Remove("Content-Encoding");
        content.Headers.Remove("Content-Length");
    }
}

/// The coding a response's content declared, for a message.
internal String DescribeHttpContentCoding(HttpResponseMessage response)
{
    String? coding = response.Content.Headers.GetFirstHttpValue("content-encoding");
    return coding == null ? "compressed data" : coding;
}

/// Whether `host`, as a URI has it, can go in a request line and a `Host`
/// field: no control byte, space or DEL, none of `/ ? # @ \`, and brackets
/// and colons only in a bracketed IPv6 literal.
internal bool IsHttpHostValid(String host)
{
    nuint length = host.ByteLength();
    bool bracketed = length >= 2u && host.GetByteAt(0u) == (byte)'[' &&
                     host.GetByteAt(length - 1u) == (byte)']';
    nuint start = bracketed ? 1u : 0u;
    nuint end = bracketed ? length - 1u : length;
    for (nuint i = start; i < end; i++)
    {
        byte c = host.GetByteAt(i);
        if (c <= (byte)' ' || c == 0x7F || "/?#@\\[]".Contains((char)c))
            return false;
        if (c == (byte)':' && !bracketed)
            return false;
    }
    return true;
}

/// Whether two URIs share a scheme, a host and a port.
internal bool IsHttpSameOrigin(Uri first, Uri second) =>
    first.Scheme == second.Scheme && first.Host == second.Host && first.Port == second.Port;

/// Where a response redirects to, resolved against `from`, or null when it is
/// not a redirect to follow: not a 301, 302, 303, 307 or 308, no `Location`,
/// a scheme other than http or https, or https to http.
internal Uri? FindHttpRedirectTarget(HttpResponseMessage response, Uri from)
{
    switch ((int)response.StatusCode)
    {
        case 301:
        case 302:
        case 303:
        case 307:
        case 308:
            break;
        default:
            return null;
    }
    String? location = response.Headers.GetFirstHttpValue("location");
    if (location == null)
        return null;
    if (Uri.TryCreate(from, location) is not Ok resolved)
        return null;
    Uri target = resolved.Value;
    String scheme = target.Scheme;
    if (scheme != "http" && scheme != "https")
        return null;
    if (from.Scheme == "https" && scheme == "http")
        return null;
    return target;
}

/// Reads and drops what is left of a body nobody wants, so that its
/// connection can be reused, then releases it.
internal void DiscardHttpResponseBody(HttpResponseMessage response)
{
    if (response.Content is HttpResponseContent content)
        DrainHttpBody(content.RawHttpBody);
    response.Dispose();
}
