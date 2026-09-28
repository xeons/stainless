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
import Standard.Net;
import Standard.Net.Security;
import Standard.Threading;
import Standard.Time;

/// An HTTP/2 connection (RFC 9113): many requests at once, each on a stream
/// of its own, over one socket.
///
/// **One reader thread per connection.** It reads every frame and applies
/// it to its stream; a thread sending a request writes its own frames and
/// then waits on its stream. The reader holds the multiplexer and not this
/// object, so dropping the last reference to this ends the connection and
/// joins the thread, and the thread never outlives it.
internal sealed class Http2Connection : IHttpConnection
{
    private Http2Multiplexer _multiplexer;
    private Thread? _reader = null;
    private bool _finished = false;

    internal Http2Connection(Http2Multiplexer multiplexer) => _multiplexer = multiplexer;

    ~Http2Connection() { FinishHttp2Connection(); }

    internal Http2Multiplexer Multiplexer => _multiplexer;

    public Version ProtocolVersion => HttpVersion.Version20;

    public String PoolKey => _multiplexer.PoolKey;

    public bool HasCarriedRequest => _multiplexer.HasCarriedHttp2Stream;

    public bool IsMultiplexed => true;

    public bool IsHttpConnectionAlive() => _multiplexer.IsHttp2Open;

    public bool TryReserveHttpStream() => _multiplexer.TryReserveHttp2Stream();

    public bool HasHttpIdleTimeoutPassed(TimeSpan now, TimeSpan timeout) =>
        _multiplexer.HasHttp2IdleTimeoutPassed(now, timeout);

    /// Sends GOAWAY and takes no new stream; the streams open finish first.
    public void CloseHttpConnection() => _multiplexer.BeginHttp2Shutdown();

    /// Starts the reader thread.
    internal void StartHttp2Reader()
    {
        Http2Multiplexer multiplexer = _multiplexer;
        _reader = new Thread(() => multiplexer.RunHttp2Reader());
    }

    /// Ends the connection now, joins the reader, and closes the socket.
    internal void FinishHttp2Connection()
    {
        if (_finished)
            return;
        _finished = true;
        _multiplexer.AbortHttp2Connection();
        if (_reader is Thread reader)
            reader.Join();
        _multiplexer.CloseHttp2Transport();
    }

    // ------------------------------------------------------------- sending

    public Result<HttpResponseMessage, HttpError> SendHttpRequest(HttpWireRequest request,
                                                                 HttpExchange exchange)
    {
        HttpFailure failure = exchange.Failure;
        var fields = new List<String>();
        String problem = BuildHttp2RequestFields(request, fields);
        if (!problem.IsEmpty)
        {
            _multiplexer.CancelHttp2Reservation();
            return Fail(failure.RecordHttpFailure(HttpError.InvalidRequest, problem));
        }
        if (exchange.Deadline.HasExpired)
        {
            _multiplexer.CancelHttp2Reservation();
            return Fail(failure.RecordHttpFailure(HttpError.Timeout, "the request timed out before it was sent"));
        }

        HttpContent? content = request.Content;
        var stream = new Http2Stream(request.Method.Method == "HEAD");
        if (!_multiplexer.OpenHttp2Stream(stream, fields, content == null))
            return Fail(_multiplexer.ReportHttp2StreamFailure(stream, exchange));

        if (content != null)
        {
            HttpError sent = SendHttp2RequestBody(request, content, stream, exchange);
            if (sent != HttpError.None)
                return Fail(sent);
        }

        HttpError headed = _multiplexer.WaitForHttp2Head(stream, exchange);
        if (headed != HttpError.None)
            return Fail(headed);
        return Ok(CreateHttp2Response(request, stream, exchange));
    }

    /// Sends the body, after waiting for 100 (Continue) when asked to. A body
    /// cut short by the stream's end is not a failure here: the response, or
    /// the stream's own failure, says what happened.
    private HttpError SendHttp2RequestBody(HttpWireRequest request, HttpContent content, Http2Stream stream,
                                           HttpExchange exchange)
    {
        HttpFailure failure = exchange.Failure;
        if (request.ExpectContinue)
        {
            _multiplexer.WaitForHttp2Continue(stream, ComputeHttpContinueMilliseconds(exchange.Deadline));
            if (_multiplexer.HasHttp2FinalHead(stream))
                return HttpError.None;
        }

        var body = new Http2RequestBody(_multiplexer, stream, exchange);
        var counted = new HttpCountingStream(body);
        HttpError written = content.WriteHttpContent(counted);
        if (body.HasFailed)
            return HttpError.None;
        if (written != HttpError.None)
        {
            _multiplexer.CancelHttp2Stream(stream, "the request content could not be read");
            return failure.RecordHttpFailure(written, "the request content could not be read");
        }
        if (!request.IsChunked && request.DeclaredLength != counted.CountedBytes)
        {
            _multiplexer.CancelHttp2Stream(stream, "the request content was not the length it declared");
            return failure.RecordHttpFailure(HttpError.ContentFailure,
                "the request content was not the length it declared");
        }
        _multiplexer.EndHttp2RequestBody(stream);
        return HttpError.None;
    }

    /// The response from the stream's final head. Its fields and status are
    /// settled once the head has arrived, so they are read without the lock.
    private HttpResponseMessage CreateHttp2Response(HttpWireRequest request, Http2Stream stream,
                                                    HttpExchange exchange)
    {
        var response = new HttpResponseMessage((HttpStatusCode)stream.Status);
        response.Version = HttpVersion.Version20;
        bool hasBody = !stream.IsHeadRequest && stream.Status != 204 && stream.Status != 304;

        HttpContent content = new HttpEmptyContent();
        if (hasBody)
        {
            var body = new Http2ResponseBody(this, stream, exchange, response.TrailingHeaders);
            content = new HttpResponseContent(body, body);
        }
        else
        {
            _multiplexer.CancelHttp2Stream(stream, "the response has no body");
        }
        foreach (var field in stream.Head.Fields)
        {
            foreach (var value in field.Values)
            {
                if (IsHttpContentHeaderKey(field.Key))
                    content.Headers.AppendHttpValue(field.Name, value);
                else
                    response.Headers.AppendHttpValue(field.Name, value);
            }
        }
        response.Content = content;
        return response;
    }
}

/// Opens HTTP/2 over a transport already connected, and secured if it is to
/// be: the preface, SETTINGS, the reader thread, and the wait for the peer's
/// SETTINGS.
internal Result<IHttpConnection, HttpError> StartHttp2Connection(
    String key, TcpClient tcp, IStream stream, TlsStream? tls, HttpClientHandler handler, HttpExchange exchange,
    HttpConnectionPool pool)
{
    HttpFailure failure = exchange.Failure;
    long window = (long)handler.InitialHttp2StreamWindowSize;
    if (window < Http2DefaultWindowSize)
        window = Http2DefaultWindowSize;
    if (window > Http2MaxWindowSize)
        window = Http2MaxWindowSize;
    var multiplexer = new Http2Multiplexer(key, tcp, stream, tls, pool, window, exchange.MaxHeaderBytes);

    ApplyHttpSocketDeadline(tcp, exchange.Deadline);
    if (!multiplexer.SendHttp2Preface())
    {
        SocketError socketError = tcp.SocketErrorCode;
        multiplexer.CloseHttp2Transport();
        failure.SocketErrorCode = socketError;
        if (exchange.Deadline.HasExpired || socketError == SocketError.TimedOut)
            return Fail(failure.RecordHttpFailure(HttpError.Timeout, "the request timed out sending the HTTP/2 preface"));
        return Fail(failure.RecordHttpFailure(HttpError.ConnectionClosed,
            "the connection closed before the HTTP/2 preface was sent"));
    }
    // The reader blocks for as long as the connection lives; each request
    // keeps its own deadline instead.
    tcp.Underlying.SetReceiveTimeout(0);
    tcp.Underlying.SetSendTimeout(0);

    var connection = new Http2Connection(multiplexer);
    connection.StartHttp2Reader();
    HttpError settled = multiplexer.WaitForHttp2Settings(exchange);
    if (settled != HttpError.None)
    {
        connection.FinishHttp2Connection();
        return Fail(settled);
    }
    return Ok(connection);
}

/// How long to wait for 100 (Continue) before sending a body anyway.
internal int ComputeHttpContinueMilliseconds(HttpDeadline deadline)
{
    if (!deadline.IsBounded)
        return HttpExpectContinueMilliseconds;
    long left = deadline.RemainingMilliseconds;
    return left < (long)HttpExpectContinueMilliseconds ? (int)left : HttpExpectContinueMilliseconds;
}

// ------------------------------------------------------------ the messages

/// The request's header list (RFC 9113 §8.3.1): the four pseudo-headers,
/// then every field lower-cased, less those that belong to one connection,
/// with `cookie` split into crumbs (§8.2.3). Empty, or what is wrong.
internal String BuildHttp2RequestFields(HttpWireRequest request, List<String> fields)
{
    String method = request.Method.Method;
    if (method == "CONNECT")
        return "CONNECT is not sent over HTTP/2";
    String? host = request.Fields.GetFirstHttpValue("host");
    fields.Add(":method");
    fields.Add(method);
    fields.Add(":scheme");
    fields.Add(request.Scheme);
    fields.Add(":authority");
    fields.Add(host != null ? host : request.Authority);
    fields.Add(":path");
    fields.Add(request.Path);

    foreach (var field in request.Fields.Fields)
    {
        String name = field.Key;
        switch (name)
        {
            case "host":
            case "connection":
            case "keep-alive":
            case "proxy-connection":
            case "transfer-encoding":
            case "upgrade":
                continue;
        }
        foreach (var value in field.Values)
        {
            if (name == "te")
            {
                if (IsHttpNameEqual(TrimHttpWhitespace(value), "trailers"))
                {
                    fields.Add(name);
                    fields.Add("trailers");
                }
            }
            else if (name == "cookie")
            {
                foreach (var crumb in value.Split(';'))
                {
                    String trimmed = TrimHttpWhitespace(crumb);
                    if (trimmed.IsEmpty)
                        continue;
                    fields.Add(name);
                    fields.Add(trimmed);
                }
            }
            else
            {
                fields.Add(name);
                fields.Add(value);
            }
        }
    }
    return "";
}

/// Whether a field name is one RFC 9113 §8.2.2 keeps out of HTTP/2.
internal bool IsHttp2ConnectionSpecificName(String name)
{
    switch (name)
    {
        case "connection":
        case "keep-alive":
        case "proxy-connection":
        case "transfer-encoding":
        case "upgrade":
            return true;
    }
    return false;
}

/// Why a received field is malformed (RFC 9113 §8.2), or empty: a name
/// that is not a lower-case token, a connection-specific name, or a value
/// with NUL, CR or LF in it or whitespace at either end.
internal String CheckHttp2Field(String name, String value)
{
    nuint length = name.ByteLength();
    if (length == 0u)
        return "an empty field name";
    for (nuint i = 0u; i < length; i++)
    {
        byte c = name.GetByteAt(i);
        if (c >= (byte)'A' && c <= (byte)'Z')
            return "the field name '" + name + "' has upper-case letters";
        if (!IsHttpTokenByte(c))
            return "the field name '" + name + "' is not a token";
    }
    if (IsHttp2ConnectionSpecificName(name))
        return "the connection-specific field '" + name + "'";
    nuint valueLength = value.ByteLength();
    for (nuint i = 0u; i < valueLength; i++)
    {
        byte c = value.GetByteAt(i);
        if (c == 0 || c == 0x0D || c == 0x0A)
            return "the field '" + name + "' has NUL, CR or LF in its value";
    }
    if (valueLength > 0u && (IsHttpWhitespace(value.GetByteAt(0u)) ||
                             IsHttpWhitespace(value.GetByteAt(valueLength - 1u))))
        return "the field '" + name + "' has whitespace at an end of its value";
    return "";
}

/// A response's head: exactly one `:status` of three digits, before every
/// other field, and no other pseudo-header. Empty, or what is wrong.
internal String ParseHttp2ResponseHead(List<HpackField> fields, HttpWireHeaders head, out int status)
{
    status = 0;
    bool regular = false;
    bool hasStatus = false;
    foreach (var field in fields)
    {
        String name = field.Name;
        if (name.StartsWith(":"))
        {
            if (regular)
                return "a pseudo-header after a regular field";
            if (name != ":status")
                return "the pseudo-header '" + name + "' in a response";
            if (hasStatus)
                return "two :status pseudo-headers";
            hasStatus = true;
            String value = field.Value;
            if (value.ByteLength() != 3u)
                return "a malformed :status";
            for (nuint i = 0u; i < 3u; i++)
            {
                byte c = value.GetByteAt(i);
                if (c < (byte)'0' || c > (byte)'9')
                    return "a malformed :status";
                status = status * 10 + (int)(c - (byte)'0');
            }
            if (status < 100)
                return "a malformed :status";
            continue;
        }
        regular = true;
        String problem = CheckHttp2Field(name, field.Value);
        if (!problem.IsEmpty)
            return problem;
        head.AppendHttpValue(name, field.Value);
    }
    if (!hasStatus)
        return "a response without :status";
    return "";
}

/// A trailer block: fields only, no pseudo-header. Empty, or what is wrong.
internal String ParseHttp2Trailers(List<HpackField> fields, HttpWireHeaders trailers)
{
    foreach (var field in fields)
    {
        if (field.Name.StartsWith(":"))
            return "a pseudo-header in trailers";
        String problem = CheckHttp2Field(field.Name, field.Value);
        if (!problem.IsEmpty)
            return problem;
        trailers.AppendHttpValue(field.Name, field.Value);
    }
    return "";
}

/// The `content-length` a head declares, or -1. Empty, or what is wrong.
internal String ReadHttp2ContentLength(HttpWireHeaders head, out long declared)
{
    declared = -1;
    var field = head.FindHttpField("content-length");
    if (field == null)
        return "";
    bool first = true;
    foreach (var value in field.Values)
    {
        foreach (var element in SplitHttpList(value))
        {
            if (!TryParseHttpDecimal(element, out long parsed) || (!first && parsed != declared))
                return "the response's content-length was malformed or ambiguous";
            declared = parsed;
            first = false;
        }
    }
    if (first)
        return "the response's content-length was empty";
    return "";
}
