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

import Standard.IO;
import Standard.Threading;
import Standard.Time;

/// Sends requests and receives responses: .NET's `HttpClient`, blocking.
///
///     var client = new HttpClient();
///     client.BaseAddress = new Uri("https://api.example.com/");
///     client.DefaultRequestHeaders.Accept = "application/json";
///     var response = try client.Get("items/42");
///     String body = try response.Content.ReadAsString();
///
/// One client is meant to be made once and used for many requests, so that
/// its handler's connections are reused. `Timeout` covers each request
/// whole: connecting, TLS, sending, redirects, and reading the body unless
/// the body is streamed, each read of the socket given what is left of it.
public class HttpClient : IDisposable
{
    // Mutable rather than readonly, so that what it holds is released at exit.
    private static Mutex<HttpDefaultProxySlot> s_defaultProxy =
        new Mutex<HttpDefaultProxySlot>(new HttpDefaultProxySlot());

    private HttpClientHandler _handler;
    private bool _disposeHandler;
    private HttpRequestHeaders _defaultRequestHeaders = new HttpRequestHeaders();
    private bool _disposed = false;

    /// A client with a handler of its own.
    public HttpClient() : this(new HttpClientHandler(), true) { }

    /// A client sending through `handler`, which it disposes with itself.
    public HttpClient(HttpClientHandler handler) : this(handler, true) { }

    /// A client sending through `handler`, disposing it with itself when
    /// `disposeHandler`.
    public HttpClient(HttpClientHandler handler, bool disposeHandler)
    {
        _handler = handler;
        _disposeHandler = disposeHandler;
    }

    /// The proxy a handler uses when its own `Proxy` is null: the one the
    /// environment names (see `HttpEnvironmentProxy`), read the first time it
    /// is asked for, or one that sends everything direct.
    public static IWebProxy DefaultProxy
    {
        get
        {
            var held = s_defaultProxy.Enter();
            HttpDefaultProxySlot slot = held.Value;
            IWebProxy? known = slot.Proxy;
            if (known != null)
                return known;
            IWebProxy? found = HttpEnvironmentProxy.FromEnvironment();
            IWebProxy chosen = found != null ? found : new WebProxy();
            slot.Proxy = chosen;
            return chosen;
        }
        set
        {
            var held = s_defaultProxy.Enter();
            held.Value.Proxy = value;
        }
    }

    /// The URI a relative request URI is resolved against.
    public Uri? BaseAddress { get; set; }

    /// Fields sent with every request, where the request does not name them
    /// itself.
    public HttpRequestHeaders DefaultRequestHeaders => _defaultRequestHeaders;

    /// How long a request may take, 100 seconds unless set. Zero or negative
    /// is no limit.
    public TimeSpan Timeout { get; set; } = TimeSpan.FromSeconds(100);

    /// The longest body read into memory, 2 GiB unless set.
    public long MaxResponseContentBufferSize { get; set; } = 2147483647;

    /// The handler requests go through.
    public HttpClientHandler Handler => _handler;

    /// The version the methods that make their own request ask for — `Get`,
    /// `Post`, `GetString` and the rest. HTTP/1.1 unless set, as .NET's is;
    /// a request made by the caller keeps its own.
    public Version DefaultRequestVersion { get; set; } = HttpVersion.Version11;

    /// The policy those requests are made with.
    public HttpVersionPolicy DefaultVersionPolicy { get; set; } = HttpVersionPolicy.RequestVersionOrLower;

    // ------------------------------------------------------------- sending

    /// Sends `request` and reads the whole response.
    ///
    /// @failure HttpError.Timeout           `Timeout` ran out
    /// @failure HttpError.ConnectFailure    no connection could be made
    /// @failure HttpError.InvalidResponse   the response was malformed
    /// @failure HttpError.InvalidRequest    the request has no absolute URI
    ///                                      and there is no `BaseAddress`
    public Result<HttpResponseMessage, HttpError> Send(HttpRequestMessage request) =>
        Send(request, HttpCompletionOption.ResponseContentRead, out HttpFailure failure);

    /// Sends `request`, returning when `completionOption` says.
    ///
    /// @failure HttpError.Timeout  `Timeout` ran out
    public Result<HttpResponseMessage, HttpError> Send(HttpRequestMessage request,
                                                      HttpCompletionOption completionOption) =>
        Send(request, completionOption, out HttpFailure failure);

    /// Sends `request`, returning when `completionOption` says, and says what
    /// went wrong in `failure` when it fails.
    ///
    /// @param request           what to send; a followed redirect changes it
    /// @param completionOption  whether to read the body before returning
    /// @param failure           the detail of a failure, or `None`
    /// @failure HttpError.Timeout            `Timeout` ran out
    /// @failure HttpError.TlsFailure         the TLS handshake failed
    /// @failure HttpError.TooManyRedirects   more than the handler allows
    /// @failure HttpError.ResponseTooLarge   past `MaxResponseContentBufferSize`
    public Result<HttpResponseMessage, HttpError> Send(HttpRequestMessage request,
                                                      HttpCompletionOption completionOption,
                                                      out HttpFailure failure)
    {
        failure = new HttpFailure();
        if (_disposed)
            return Fail(failure.RecordHttpFailure(HttpError.Disposed, "the client has been disposed"));

        var given = request.RequestUri;
        Uri? resolved = null;
        if (given is Uri uri && uri.IsAbsoluteUri)
        {
            resolved = uri;
        }
        else if (BaseAddress is Uri baseAddress && baseAddress.IsAbsoluteUri)
        {
            if (given is Uri relative)
            {
                if (Uri.TryCreate(baseAddress, relative.OriginalString) is Ok joined)
                    resolved = joined.Value;
            }
            else
            {
                resolved = baseAddress;
            }
        }
        if (resolved is not Uri absolute)
        {
            return Fail(failure.RecordHttpFailure(HttpError.InvalidRequest,
                "the request has no absolute URI and the client no BaseAddress"));
        }
        request.RequestUri = absolute;
        failure.RequestUri = absolute;

        var deadline = new HttpDeadline(Timeout);
        return _handler.SendHttpRequest(request, completionOption, deadline, failure,
                                        _defaultRequestHeaders, MaxResponseContentBufferSize);
    }

    /// `GET` of `requestUri`, with the whole body read.
    public Result<HttpResponseMessage, HttpError> Get(String requestUri) =>
        Send(CreateHttpRequest(HttpMethod.Get, requestUri, null));

    /// `GET` of `requestUri`, with the whole body read.
    public Result<HttpResponseMessage, HttpError> Get(Uri requestUri) =>
        Send(CreateHttpRequest(HttpMethod.Get, requestUri, null));

    /// `GET` of `requestUri`, returning when `completionOption` says.
    public Result<HttpResponseMessage, HttpError> Get(String requestUri, HttpCompletionOption completionOption) =>
        Send(CreateHttpRequest(HttpMethod.Get, requestUri, null), completionOption);

    /// `GET` of `requestUri`, returning when `completionOption` says.
    public Result<HttpResponseMessage, HttpError> Get(Uri requestUri, HttpCompletionOption completionOption) =>
        Send(CreateHttpRequest(HttpMethod.Get, requestUri, null), completionOption);

    /// The body of a `GET` as text.
    ///
    /// @failure HttpError.UnsuccessfulStatusCode  the status was not 2xx
    public Result<String, HttpError> GetString(String requestUri) =>
        ReadHttpSuccessString(Get(requestUri));

    /// The body of a `GET` as text.
    ///
    /// @failure HttpError.UnsuccessfulStatusCode  the status was not 2xx
    public Result<String, HttpError> GetString(Uri requestUri) =>
        ReadHttpSuccessString(Get(requestUri));

    /// The body of a `GET` as bytes.
    ///
    /// @failure HttpError.UnsuccessfulStatusCode  the status was not 2xx
    public Result<byte[], HttpError> GetByteArray(String requestUri) =>
        ReadHttpSuccessBytes(Get(requestUri));

    /// The body of a `GET` as bytes.
    ///
    /// @failure HttpError.UnsuccessfulStatusCode  the status was not 2xx
    public Result<byte[], HttpError> GetByteArray(Uri requestUri) =>
        ReadHttpSuccessBytes(Get(requestUri));

    /// The body of a `GET` as a stream, read from the connection as it
    /// arrives.
    ///
    /// @failure HttpError.UnsuccessfulStatusCode  the status was not 2xx
    public Result<IStream, HttpError> GetStream(String requestUri) =>
        ReadHttpSuccessStream(Get(requestUri, HttpCompletionOption.ResponseHeadersRead));

    /// The body of a `GET` as a stream, read from the connection as it
    /// arrives.
    ///
    /// @failure HttpError.UnsuccessfulStatusCode  the status was not 2xx
    public Result<IStream, HttpError> GetStream(Uri requestUri) =>
        ReadHttpSuccessStream(Get(requestUri, HttpCompletionOption.ResponseHeadersRead));

    /// `POST` of `content` to `requestUri`.
    public Result<HttpResponseMessage, HttpError> Post(String requestUri, HttpContent? content) =>
        Send(CreateHttpRequest(HttpMethod.Post, requestUri, content));

    /// `POST` of `content` to `requestUri`.
    public Result<HttpResponseMessage, HttpError> Post(Uri requestUri, HttpContent? content) =>
        Send(CreateHttpRequest(HttpMethod.Post, requestUri, content));

    /// `PUT` of `content` to `requestUri`.
    public Result<HttpResponseMessage, HttpError> Put(String requestUri, HttpContent? content) =>
        Send(CreateHttpRequest(HttpMethod.Put, requestUri, content));

    /// `PUT` of `content` to `requestUri`.
    public Result<HttpResponseMessage, HttpError> Put(Uri requestUri, HttpContent? content) =>
        Send(CreateHttpRequest(HttpMethod.Put, requestUri, content));

    /// `PATCH` of `content` to `requestUri`.
    public Result<HttpResponseMessage, HttpError> Patch(String requestUri, HttpContent? content) =>
        Send(CreateHttpRequest(HttpMethod.Patch, requestUri, content));

    /// `PATCH` of `content` to `requestUri`.
    public Result<HttpResponseMessage, HttpError> Patch(Uri requestUri, HttpContent? content) =>
        Send(CreateHttpRequest(HttpMethod.Patch, requestUri, content));

    /// `DELETE` of `requestUri`.
    public Result<HttpResponseMessage, HttpError> Delete(String requestUri) =>
        Send(CreateHttpRequest(HttpMethod.Delete, requestUri, null));

    /// `DELETE` of `requestUri`.
    public Result<HttpResponseMessage, HttpError> Delete(Uri requestUri) =>
        Send(CreateHttpRequest(HttpMethod.Delete, requestUri, null));

    /// Refuses further requests, and disposes the handler unless it was made
    /// to be shared.
    public void Dispose()
    {
        if (_disposed)
            return;
        _disposed = true;
        if (_disposeHandler)
            _handler.Dispose();
    }

    /// A request for one of the methods that make their own, with the
    /// default version and policy.
    private HttpRequestMessage CreateHttpRequest(HttpMethod method, String requestUri, HttpContent? content)
    {
        var request = new HttpRequestMessage(method, requestUri);
        request.Content = content;
        request.Version = DefaultRequestVersion;
        request.VersionPolicy = DefaultVersionPolicy;
        return request;
    }

    private HttpRequestMessage CreateHttpRequest(HttpMethod method, Uri requestUri, HttpContent? content)
    {
        var request = new HttpRequestMessage(method, requestUri);
        request.Content = content;
        request.Version = DefaultRequestVersion;
        request.VersionPolicy = DefaultVersionPolicy;
        return request;
    }
}

/// Where `HttpClient.DefaultProxy` keeps its answer once it has one.
internal sealed class HttpDefaultProxySlot
{
    internal IWebProxy? Proxy = null;

    internal HttpDefaultProxySlot() { }
}

internal Result<String, HttpError> ReadHttpSuccessString(Result<HttpResponseMessage, HttpError> sent)
{
    if (!sent.Ok)
        return Fail(sent.Error);
    HttpResponseMessage response = sent.Value;
    if (!response.IsSuccessStatusCode)
    {
        response.Dispose();
        return Fail(HttpError.UnsuccessfulStatusCode);
    }
    return response.Content.ReadAsString();
}

internal Result<byte[], HttpError> ReadHttpSuccessBytes(Result<HttpResponseMessage, HttpError> sent)
{
    if (!sent.Ok)
        return Fail(sent.Error);
    HttpResponseMessage response = sent.Value;
    if (!response.IsSuccessStatusCode)
    {
        response.Dispose();
        return Fail(HttpError.UnsuccessfulStatusCode);
    }
    return response.Content.ReadAsByteArray();
}

internal Result<IStream, HttpError> ReadHttpSuccessStream(Result<HttpResponseMessage, HttpError> sent)
{
    if (!sent.Ok)
        return Fail(sent.Error);
    HttpResponseMessage response = sent.Value;
    if (!response.IsSuccessStatusCode)
    {
        response.Dispose();
        return Fail(HttpError.UnsuccessfulStatusCode);
    }
    return response.Content.ReadAsStream();
}
