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
import Standard.IO;
import Standard.Net;
import Standard.Net.Security;
import Standard.Text;

/// Where a request goes and how: its origin, and the proxy between, if any.
internal sealed class HttpRoute
{
    internal String Scheme;

    /// The host, without the brackets an IPv6 literal has in a URI.
    internal String Host;

    internal ushort Port;

    /// An HTTP proxy, or null to go direct.
    internal Uri? Proxy;

    internal NetworkCredential? ProxyCredentials;

    internal HttpRoute(String scheme, String host, ushort port)
    {
        Scheme = scheme;
        Host = host;
        Port = port;
    }

    internal bool IsHttps => Scheme == "https";

    /// The pool's key: everything that makes one connection unlike another.
    internal String PoolKey
    {
        get
        {
            String key = Scheme + "://" + FormatHttpAuthority(Host, Port);
            if (Proxy is Uri proxy)
                key += " via " + proxy.Host + ":" + Text.FromInteger((long)proxy.Port);
            return key;
        }
    }
}

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

/// Opens a TCP connection within the deadline: resolves the name, then
/// connects without blocking and waits for the connect to finish.
///
/// @failure HttpError.NameResolutionFailure  the name did not resolve
/// @failure HttpError.ConnectFailure         the connect was refused or failed
/// @failure HttpError.Timeout                the deadline ran out first
internal Result<TcpClient, HttpError> ConnectHttpSocket(String host, ushort port, HttpExchange exchange)
{
    HttpFailure failure = exchange.Failure;
    HttpDeadline deadline = exchange.Deadline;

    var resolved = Net.ResolveHost(host);
    if (!resolved.Ok)
    {
        failure.SocketErrorCode = resolved.Error;
        return Fail(failure.RecordHttpFailure(HttpError.NameResolutionFailure,
            "the name '" + host + "' did not resolve"));
    }
    String address = resolved.Value;
    AddressFamily family = address.Contains(':') ? AddressFamily.IPv6 : AddressFamily.IPv4;

    var opened = Socket.Open(family, SocketType.Stream);
    if (!opened.Ok)
    {
        failure.SocketErrorCode = opened.Error;
        return Fail(failure.RecordHttpFailure(HttpError.ConnectFailure, "no socket could be opened"));
    }
    Socket socket = opened.Value;
    String where = FormatHttpAuthority(host, port);

    if (deadline.HasExpired)
        return Fail(failure.RecordHttpFailure(HttpError.Timeout, "the request timed out before connecting"));

    if (!deadline.IsBounded)
    {
        SocketError direct = socket.Connect(address, port);
        if (direct != SocketError.None)
        {
            failure.SocketErrorCode = direct;
            return Fail(failure.RecordHttpFailure(HttpError.ConnectFailure,
                "connecting to " + where + " failed: " + DescribeSocketError(direct)));
        }
        return Ok(new TcpClient(socket));
    }

    socket.SetBlocking(false);
    SocketError started = socket.Connect(address, port);
    if (started == SocketError.WouldBlock)
    {
        if (!socket.WaitToWrite(deadline.WaitMilliseconds))
        {
            SocketError waited = socket.Error;
            socket.Close();
            if (waited == SocketError.None || waited == SocketError.TimedOut)
            {
                failure.SocketErrorCode = SocketError.TimedOut;
                return Fail(failure.RecordHttpFailure(HttpError.Timeout,
                    "connecting to " + where + " timed out"));
            }
            failure.SocketErrorCode = waited;
            return Fail(failure.RecordHttpFailure(HttpError.ConnectFailure,
                "connecting to " + where + " failed: " + DescribeSocketError(waited)));
        }
    }
    else if (started != SocketError.None)
    {
        socket.Close();
        failure.SocketErrorCode = started;
        return Fail(failure.RecordHttpFailure(HttpError.ConnectFailure,
            "connecting to " + where + " failed: " + DescribeSocketError(started)));
    }
    socket.SetBlocking(true);
    return Ok(new TcpClient(socket));
}

/// Opens a connection along `route`: TCP, a `CONNECT` tunnel through the
/// proxy for https, and TLS for https, offering the ALPN names of the
/// protocols this module speaks.
internal Result<IHttpConnection, HttpError> OpenHttpConnection(
    HttpRoute route, HttpClientHandler handler, HttpRequestMessage request, HttpExchange exchange,
    HttpConnectionPool pool)
{
    HttpFailure failure = exchange.Failure;
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
        return Ok(new Http11Connection(route.PoolKey, tcp, tcp, null, pool));

    ApplyHttpSocketDeadline(tcp, exchange.Deadline);
    var options = new TlsClientOptions();
    options.TargetHost = route.Host;
    options.ApplicationProtocols = CreateHttpApplicationProtocols();
    options.CertificateValidator = handler.CreateHttpCertificateValidator(request);
    options.ClientCertificateChain = handler.ClientCertificates;
    options.ClientPrivateKey = handler.ClientCertificateKey;

    var secured = TlsStream.AuthenticateAsClient(tcp, options, out TlsAlertDescription alert);
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
        return Fail(failure.RecordHttpFailure(HttpError.TlsFailure,
            "the TLS handshake with " + route.Host + " failed: " + DescribeTlsError(secured.Error)));
    }
    TlsStream tls = secured.Value;

    // The protocol ALPN agreed on decides the connection; h2 will be a second
    // case here.
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

    ApplyHttpSocketDeadline(tcp, exchange.Deadline);
    if (!WriteHttpText(tcp, request.ToText()))
        return FailHttpTunnel(tcp, exchange, "the proxy closed the connection");

    var reader = new HttpBufferedReader(tcp, 4096u);
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
