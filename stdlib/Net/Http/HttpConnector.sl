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
import Standard.Convert;
import Standard.Net;
import Standard.Net.Security;
import Standard.Text;

/// `host:port`, with an IPv6 literal in brackets.
internal String FormatHttpAuthority(String host, ushort port)
{
    String written = host.Contains(':') ? "[" + host + "]" : host;
    return written + ":" + Text.FromInteger((long)port);
}

/// A URI's host without the brackets of an IPv6 literal.
internal String GetHttpBareHost(Uri uri)
{
    String host = uri.Host;
    if (host.StartsWith("[") && host.EndsWith("]"))
        return host.Substring(1u, host.ByteLength() - 2u);
    return host;
}

/// `Basic` credentials for a `Proxy-Authorization` or `Authorization` field.
internal String FormatHttpBasicCredentials(NetworkCredential credentials) =>
    "Basic " + Convert.ToBase64String(credentials.UserName + ":" + credentials.Password);

/// Opens a TCP connection within the deadline, trying every address the name
/// resolves to until one connects.
///
/// @failure HttpError.NameResolutionFailure  the name did not resolve
/// @failure HttpError.ConnectFailure         the connect was refused or failed
/// @failure HttpError.Timeout                the deadline ran out first
internal Result<TcpClient, HttpError> ConnectHttpSocket(String host, ushort port, HttpExchange exchange)
{
    HttpFailure failure = exchange.Failure;
    HttpDeadline deadline = exchange.Deadline;
    String where = FormatHttpAuthority(host, port);

    if (deadline.HasExpired)
        return Fail(failure.RecordHttpFailure(HttpError.Timeout, "the request timed out before connecting"));

    var opened = Socket.OpenConnected(host, port, AddressFamily.Any, SocketType.Stream,
                                      deadline.WaitMilliseconds);
    if (opened.Ok)
        return Ok(new TcpClient(opened.Value));

    SocketError error = opened.Error;
    failure.SocketErrorCode = error;
    switch (error)
    {
        case SocketError.NoName:
        case SocketError.TryAgain:
            return Fail(failure.RecordHttpFailure(HttpError.NameResolutionFailure,
                "the name '" + host + "' did not resolve"));

        case SocketError.TimedOut:
            if (deadline.IsBounded)
            {
                return Fail(failure.RecordHttpFailure(HttpError.Timeout,
                    "connecting to " + where + " timed out"));
            }
            break;
    }
    return Fail(failure.RecordHttpFailure(HttpError.ConnectFailure,
        "connecting to " + where + " failed: " + DescribeSocketError(error)));
}

/// Whether `host` can be written into a request line or a `CONNECT`
/// authority as it is. A control byte, a space, or a delimiter of another URI
/// part would end the host early or start a header.
internal bool IsHttpHostWritable(String host)
{
    if (host.IsEmpty)
        return false;
    for (nuint i = 0u; i < host.ByteLength(); i++)
    {
        byte b = host.GetByteAt(i);
        if (b <= 0x20 || b == 0x7F)
            return false;
        switch (b)
        {
            case 0x23:      // #
            case 0x2F:      // /
            case 0x3F:      // ?
            case 0x40:      // @
            case 0x5C:      // backslash
                return false;
        }
    }
    return true;
}

/// Opens a connection along `route`: TCP, a `CONNECT` tunnel through the
/// proxy for https, and TLS for https, offering the ALPN names of the
/// protocols `choice` allows. Plain http is HTTP/2 only when `choice`
/// allows nothing else, and then with prior knowledge (RFC 9113 §3.3).
///
/// @failure HttpError.VersionNegotiationFailure  HTTP/2 was required and
///                                               ALPN chose otherwise
internal Result<IHttpConnection, HttpError> OpenHttpConnection(
    HttpRoute route, HttpClientHandler handler, HttpRequestMessage request, HttpVersionChoice choice,
    HttpExchange exchange, HttpConnectionPool pool)
{
    HttpFailure failure = exchange.Failure;
    if (!IsHttpHostWritable(route.Host))
    {
        return Fail(failure.RecordHttpFailure(HttpError.InvalidRequest,
            "the host holds a byte that cannot be written into a request"));
    }

    String connectHost = route.Host;
    ushort connectPort = route.Port;
    if (route.Proxy is Uri proxy)
    {
        connectHost = GetHttpBareHost(proxy);
        connectPort = (ushort)proxy.Port;
    }

    var connected = ConnectHttpSocket(connectHost, connectPort, exchange);
    if (!connected.Ok)
    {
        if (route.Proxy != null && connected.Error != HttpError.Timeout)
        {
            return Fail(failure.RecordHttpFailure(HttpError.ProxyFailure,
                "the proxy could not be reached: " + failure.Message));
        }
        return Fail(connected.Error);
    }
    TcpClient tcp = connected.Value;
    tcp.Underlying.SetNoDelay(true);

    if (route.Proxy != null && route.IsHttps)
    {
        HttpError tunnel = EstablishHttpTunnel(tcp, route, exchange);
        if (tunnel != HttpError.None)
        {
            tcp.Close();
            return Fail(tunnel);
        }
    }

    if (!route.IsHttps)
    {
        if (choice.AllowsHttp2 && !choice.AllowsHttp11)
            return StartHttp2Connection(route.PoolKey, tcp, tcp, null, handler, exchange, pool);
        return Ok(new Http11Connection(route.PoolKey, tcp, tcp, null, pool));
    }

    var bounded = new HttpDeadlineStream(tcp, exchange.Deadline);
    var options = new TlsClientOptions();
    options.TargetHost = route.Host;
    options.ApplicationProtocols = CreateHttpApplicationProtocols(choice);
    options.CertificateValidator = handler.CreateHttpCertificateValidator(request);
    options.ClientCertificateChain = handler.ClientCertificates;
    options.ClientPrivateKey = handler.ClientCertificateKey;

    var secured = TlsStream.AuthenticateAsClient(bounded, options, out TlsAlertDescription alert);
    bounded.ReleaseHttpDeadline();
    if (!secured.Ok)
    {
        SocketError socketError = tcp.SocketErrorCode;
        tcp.Close();
        if (exchange.Deadline.HasExpired || socketError == SocketError.TimedOut ||
            socketError == SocketError.WouldBlock)
        {
            failure.SocketErrorCode = SocketError.TimedOut;
            return Fail(failure.RecordHttpFailure(HttpError.Timeout, "the TLS handshake timed out"));
        }
        failure.TlsErrorCode = secured.Error;
        failure.TlsAlert = alert;
        failure.SocketErrorCode = socketError;
        if (secured.Error == TlsError.AlertReceived && alert == TlsAlertDescription.NoApplicationProtocol)
        {
            return Fail(failure.RecordHttpFailure(HttpError.VersionNegotiationFailure,
                route.Host + " speaks none of the protocols offered in ALPN"));
        }
        return Fail(failure.RecordHttpFailure(HttpError.TlsFailure,
            "the TLS handshake with " + route.Host + " failed: " + DescribeTlsError(secured.Error)));
    }
    TlsStream tls = secured.Value;

    String? negotiated = tls.NegotiatedApplicationProtocol;
    String agreed = negotiated ?? "";
    if (agreed == "h2" && choice.AllowsHttp2)
        return StartHttp2Connection(route.PoolKey, tcp, tls, tls, handler, exchange, pool);
    if (!choice.AllowsHttp11)
    {
        tls.Close();
        return Fail(failure.RecordHttpFailure(HttpError.VersionNegotiationFailure,
            "HTTP/2 was required, and " + route.Host + " chose " +
            (agreed.IsEmpty ? "no protocol" : agreed) + " in ALPN"));
    }
    return Ok(new Http11Connection(route.PoolKey, tcp, tls, tls, pool));
}

/// Sets both of a socket's timeouts to what the deadline has left.
internal void ApplyHttpSocketDeadline(TcpClient tcp, HttpDeadline deadline)
{
    int timeout = deadline.SocketTimeoutMilliseconds;
    tcp.Underlying.SetReceiveTimeout(timeout);
    tcp.Underlying.SetSendTimeout(timeout);
}

/// Asks the proxy for a tunnel to the origin with `CONNECT`, and reads its
/// answer: any 2xx opens the tunnel, and anything else is a refusal.
///
/// @failure HttpError.ProxyFailure  the proxy refused, `407` among the
///                                  refusals, or broke off
/// @failure HttpError.Timeout       the deadline ran out first
internal HttpError EstablishHttpTunnel(TcpClient tcp, HttpRoute route, HttpExchange exchange)
{
    HttpFailure failure = exchange.Failure;
    String authority = FormatHttpAuthority(route.Host, route.Port);
    var request = new StringBuilder();
    request.Append("CONNECT ");
    request.Append(authority);
    request.Append(" HTTP/1.1\r\nHost: ");
    request.Append(authority);
    request.Append("\r\n");
    if (route.ProxyCredentials is NetworkCredential credentials)
    {
        request.Append("Proxy-Authorization: ");
        request.Append(FormatHttpBasicCredentials(credentials));
        request.Append("\r\n");
    }
    request.Append("\r\n");

    var bounded = new HttpDeadlineStream(tcp, exchange.Deadline);
    if (!WriteHttpText(bounded, request.ToText()))
        return FailHttpTunnel(tcp, exchange, "the proxy closed the connection");

    var reader = new HttpBufferedReader(bounded, 4096u);
    while (true)
    {
        HttpLineStatus status = reader.ReadHttpLine(HttpMaxLineLength, out String line);
        if (status != HttpLineStatus.Line)
            return FailHttpTunnel(tcp, exchange, "the proxy did not answer CONNECT");
        var head = new Http11Head();
        if (!ParseHttpStatusLine(line, head))
        {
            return failure.RecordHttpFailure(HttpError.ProxyFailure,
                "the proxy's answer to CONNECT was malformed: " + DescribeHttpLine(line));
        }
        HttpLineStatus fieldStatus = HttpLineStatus.Line;
        HttpError fields = ReadHttpFieldLines(reader, head.Fields, exchange.MaxHeaderBytes, failure,
                                              "in the proxy's answer", out fieldStatus);
        if (fields != HttpError.None)
        {
            if (fieldStatus != HttpLineStatus.Line)
                return FailHttpTunnel(tcp, exchange, "the proxy's answer to CONNECT ended early");
            return failure.RecordHttpFailure(HttpError.ProxyFailure, failure.Message);
        }
        if (head.Status < 200)
            continue;
        if (head.Status >= 300)
        {
            failure.StatusCode = (HttpStatusCode)head.Status;
            String why = head.Status == 407 ? "the proxy wants credentials" : "the proxy refused the tunnel";
            return failure.RecordHttpFailure(HttpError.ProxyFailure,
                why + ": " + Text.FromInteger((long)head.Status) + " " + head.Reason);
        }
        if (reader.BufferedCount != 0u)
        {
            return failure.RecordHttpFailure(HttpError.ProxyFailure,
                "the proxy sent bytes through the tunnel before it was used");
        }
        return HttpError.None;
    }
}

internal HttpError FailHttpTunnel(TcpClient tcp, HttpExchange exchange, String message)
{
    HttpFailure failure = exchange.Failure;
    SocketError socketError = tcp.SocketErrorCode;
    failure.SocketErrorCode = socketError;
    if (exchange.Deadline.HasExpired || socketError == SocketError.TimedOut ||
        socketError == SocketError.WouldBlock)
        return failure.RecordHttpFailure(HttpError.Timeout, "the request timed out waiting for the proxy");
    return failure.RecordHttpFailure(HttpError.ProxyFailure, message);
}

/// Reads field lines up to the empty line that ends them, into `into`.
/// A line that could not be read at all leaves its status in `failedLine` and
/// answers `ConnectionClosed` for the caller to explain; a line that was
/// malformed or over a limit is recorded here.
internal HttpError ReadHttpFieldLines(HttpBufferedReader reader, HttpHeaders into, nuint budget,
                                      HttpFailure failure, String where, out HttpLineStatus failedLine)
{
    failedLine = HttpLineStatus.Line;
    nuint used = 0u;
    nuint count = 0u;
    while (true)
    {
        HttpLineStatus status = reader.ReadHttpLine(HttpMaxLineLength, out String line);
        if (status != HttpLineStatus.Line)
        {
            failedLine = status;
            return HttpError.ConnectionClosed;
        }
        if (line.IsEmpty)
            return HttpError.None;

        used += line.ByteLength() + 2u;
        count++;
        if (used > budget || count > HttpMaxHeaderCount)
            return failure.RecordHttpFailure(HttpError.ResponseTooLarge, "too many or too long fields " + where);
        if (IsHttpWhitespace(line.GetByteAt(0u)))
            return failure.RecordHttpFailure(HttpError.InvalidResponse, "a folded field line " + where);

        long colon = line.IndexOf(':');
        if (colon <= 0)
        {
            return failure.RecordHttpFailure(HttpError.InvalidResponse,
                "a field line without a name " + where + ": " + DescribeHttpLine(line));
        }
        String name = line.Substring(0u, (nuint)colon);
        String value = TrimHttpWhitespace(line.Substring((nuint)colon + 1u));
        if (!IsHttpToken(name) || !IsHttpFieldValue(value))
        {
            return failure.RecordHttpFailure(HttpError.InvalidResponse,
                "a malformed field " + where + ": " + DescribeHttpLine(line));
        }
        into.AppendHttpValue(name, value);
    }
}
