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
import Standard.Text;
import Standard.Time;

/// An HTTP/1.1 connection (RFC 9112): one exchange at a time, kept alive
/// between them unless either end says `close` or the framing needs the close
/// to mark the end.
internal sealed class Http11Connection : IHttpConnection
{
    private String _key;
    private TcpClient _tcp;
    private IStream _stream;
    private TlsStream? _tls;
    private HttpBufferedReader _reader;
    private weak HttpConnectionPool? _pool;
    private HttpExchange? _exchange;
    private nuint _requestCount = 0u;
    private ulong _consumedAtStart = 0u;
    private bool _closed = false;

    internal Http11Connection(String key, TcpClient tcp, IStream stream, TlsStream? tls,
                              HttpConnectionPool pool)
    {
        _key = key;
        _tcp = tcp;
        _stream = stream;
        _tls = tls;
        _reader = new HttpBufferedReader(stream, HttpMaxLineLength);
        _pool = pool;
    }

    ~Http11Connection() { CloseHttpConnection(); }

    public Version ProtocolVersion => HttpVersion.Version11;

    public String PoolKey => _key;

    public bool HasCarriedRequest => _requestCount > 1u;

    public bool IsMultiplexed => false;

    public bool TryReserveHttpStream() => false;

    public bool HasHttpIdleTimeoutPassed(TimeSpan now, TimeSpan timeout) => false;

    public bool IsHttpConnectionAlive()
    {
        if (_closed || _reader.BufferedCount > 0u)
            return false;
        // Readable while idle is an end from the peer, or bytes nobody asked for.
        return !_tcp.WaitToRead(0);
    }

    public void CloseHttpConnection()
    {
        if (_closed)
            return;
        _closed = true;
        if (_tls is TlsStream tls)
            tls.Close();
        else
            _tcp.Close();
    }

    // ------------------------------------------------------------- sending

    public Result<HttpResponseMessage, HttpError> SendHttpRequest(HttpWireRequest request,
                                                                 HttpExchange exchange)
    {
        _exchange = exchange;
        _requestCount++;
        HttpFailure failure = exchange.Failure;

        if (!ApplyHttpDeadline())
            return Fail(failure.RecordHttpFailure(HttpError.Timeout, "the request timed out before it was sent"));

        var writer = new HttpBufferedWriter(_stream);
        byte[] head = FormatHttpRequestHead(request).ToBytes();
        writer.Write(head, 0u, head.Length);
        _consumedAtStart = _reader.ConsumedCount;

        HttpContent? content = request.Content;
        if (content != null && request.ExpectContinue)
        {
            if (!writer.FlushHttpBuffer())
                return Fail(FailHttpWrite());
            if (_tcp.WaitToRead(ComputeHttpContinueMilliseconds(exchange.Deadline)))
            {
                var interim = ReadHttpResponseHead(exchange);
                if (!interim.Ok)
                    return Fail(interim.Error);
                Http11Head early = interim.Value;
                if (early.Status != 100)
                    return FinishHttpResponse(request, early, true);
            }
        }

        if (content != null)
        {
            HttpError sent = WriteHttpRequestBody(writer, request, content);
            if (sent != HttpError.None)
                return Fail(sent);
        }
        if (!writer.FlushHttpBuffer())
            return Fail(FailHttpWrite());

        nuint interimCount = 0u;
        while (true)
        {
            var read = ReadHttpResponseHead(exchange);
            if (!read.Ok)
                return Fail(read.Error);
            Http11Head got = read.Value;
            if (got.Status >= 200)
                return FinishHttpResponse(request, got, false);
            if (got.Status == 101)
            {
                return Fail(failure.RecordHttpFailure(HttpError.InvalidResponse,
                    "the server switched protocols without being asked"));
            }
            interimCount++;
            if (interimCount > 32u)
                return Fail(failure.RecordHttpFailure(HttpError.InvalidResponse, "too many interim responses"));
        }
    }

    private HttpError WriteHttpRequestBody(HttpBufferedWriter writer, HttpWireRequest request,
                                           HttpContent content)
    {
        HttpFailure failure = ((HttpExchange)_exchange).Failure;
        if (request.IsChunked)
        {
            var chunks = new HttpChunkedWriter(writer);
            HttpError written = content.WriteHttpContent(chunks);
            if (writer.HasFailed)
                return FailHttpWrite();
            if (written != HttpError.None)
                return failure.RecordHttpFailure(written, "the request content could not be read");
            if (!chunks.FinishHttpChunks())
                return FailHttpWrite();
            return HttpError.None;
        }

        var counted = new HttpCountingStream(writer);
        HttpError copied = content.WriteHttpContent(counted);
        if (writer.HasFailed)
            return FailHttpWrite();
        if (copied != HttpError.None)
            return failure.RecordHttpFailure(copied, "the request content could not be read");
        if (request.DeclaredLength != counted.CountedBytes)
        {
            return failure.RecordHttpFailure(HttpError.ContentFailure,
                "the request content was not the length it declared");
        }
        return HttpError.None;
    }

    private HttpError FailHttpWrite()
    {
        var exchange = (HttpExchange)_exchange;
        HttpError error = ClassifyHttpIoFailure("while the request was being sent");
        if (error == HttpError.ConnectionClosed && HasCarriedRequest)
            exchange.IsRetryable = true;
        CloseHttpConnection();
        return error;
    }

    // ------------------------------------------------------------- reading

    /// Reads a status line and the fields after it.
    private Result<Http11Head, HttpError> ReadHttpResponseHead(HttpExchange exchange)
    {
        HttpFailure failure = exchange.Failure;
        HttpLineStatus status = _reader.ReadHttpLine(HttpMaxLineLength, out String line);
        if (status != HttpLineStatus.Line)
        {
            bool nothingArrived = _reader.ConsumedCount == _consumedAtStart && _reader.BufferedCount == 0u;
            if (nothingArrived && HasCarriedRequest &&
                (status == HttpLineStatus.EndOfStream || status == HttpLineStatus.Failed))
                exchange.IsRetryable = true;
            return Fail(FailHttpLine(status, "before the response began"));
        }

        var head = new Http11Head();
        if (!ParseHttpStatusLine(line, head))
        {
            CloseHttpConnection();
            return Fail(failure.RecordHttpFailure(HttpError.InvalidResponse,
                "the status line was malformed: " + DescribeHttpLine(line)));
        }

        nuint budget = exchange.MaxHeaderBytes > line.ByteLength()
            ? exchange.MaxHeaderBytes - line.ByteLength()
            : 0u;
        HttpError fields = ReadHttpFieldBlock(head.Fields, budget, "in the response head");
        if (fields != HttpError.None)
            return Fail(fields);
        return Ok(head);
    }

    /// Reads field lines up to the empty line that ends them.
    internal HttpError ReadHttpFieldBlock(HttpHeaders into, nuint budget, String where)
    {
        HttpFailure failure = ((HttpExchange)_exchange).Failure;
        HttpError read = ReadHttpFieldLines(_reader, into, budget, failure, where,
                                            out HttpLineStatus failedLine);
        if (read == HttpError.None)
            return HttpError.None;
        if (failedLine != HttpLineStatus.Line)
            return FailHttpLine(failedLine, where);
        CloseHttpConnection();
        return read;
    }

    /// Why a line could not be read, recorded, and the connection closed.
    internal HttpError FailHttpLine(HttpLineStatus status, String where)
    {
        HttpFailure failure = ((HttpExchange)_exchange).Failure;
        HttpError error = HttpError.None;
        switch (status)
        {
            case HttpLineStatus.EndOfStream:
            case HttpLineStatus.Truncated:
                error = failure.RecordHttpFailure(HttpError.ConnectionClosed, "the connection ended " + where);
                break;
            case HttpLineStatus.TooLong:
                error = failure.RecordHttpFailure(HttpError.ResponseTooLarge, "a line was too long " + where);
                break;
            case HttpLineStatus.Malformed:
                error = failure.RecordHttpFailure(HttpError.InvalidResponse, "a bare CR " + where);
                break;
            default:
                error = ClassifyHttpIoFailure(where);
                break;
        }
        CloseHttpConnection();
        return error;
    }

    /// Makes the response from its head: where its fields go, how its body is
    /// framed, and whether the connection outlives it.
    private Result<HttpResponseMessage, HttpError> FinishHttpResponse(
        HttpWireRequest request, Http11Head head, bool bodyWithheld)
    {
        HttpFailure failure = ((HttpExchange)_exchange).Failure;
        var response = new HttpResponseMessage((HttpStatusCode)head.Status);
        response.ReasonPhrase = head.Reason;
        response.Version = head.Minor == 0 ? HttpVersion.Version10 : HttpVersion.Version11;

        bool keepAlive = head.Minor >= 1
            ? !head.Fields.HasHttpListToken("connection", "close")
            : head.Fields.HasHttpListToken("connection", "keep-alive");
        if (request.Fields.HasHttpListToken("connection", "close") || bodyWithheld)
            keepAlive = false;

        bool hasBody = request.Method.Method != "HEAD" && head.Status != 204 && head.Status != 304;
        Http11Framing framing = Http11Framing.Length;
        long length = 0;
        if (hasBody)
        {
            HttpError framed = DecideHttpFraming(head, out framing, out length);
            if (framed != HttpError.None)
            {
                CloseHttpConnection();
                return Fail(framed);
            }
            if (framing == Http11Framing.UntilClose)
                keepAlive = false;
            if (framing == Http11Framing.Chunked && head.Minor == 0)
                keepAlive = false;
            if (framing == Http11Framing.Length && length == 0)
                hasBody = false;
        }

        HttpContent content = new HttpEmptyContent();
        if (hasBody)
        {
            var body = new Http11BodyStream(this, framing, length, keepAlive, response.TrailingHeaders);
            content = new HttpResponseContent(body, body);
        }
        foreach (var field in head.Fields.Fields)
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

        if (!hasBody)
            FinishHttpExchange(keepAlive);
        return Ok(response);
    }

    /// Reads RFC 9112 §6.3: chunked, a length, or to the close.
    private HttpError DecideHttpFraming(Http11Head head, out Http11Framing framing, out long length)
    {
        HttpFailure failure = ((HttpExchange)_exchange).Failure;
        framing = Http11Framing.UntilClose;
        length = 0;

        var coding = head.Fields.FindHttpField("transfer-encoding");
        var declared = head.Fields.FindHttpField("content-length");
        if (coding != null)
        {
            if (declared != null)
            {
                return failure.RecordHttpFailure(HttpError.InvalidResponse,
                    "the response had both Content-Length and Transfer-Encoding");
            }
            nuint chunked = 0u;
            foreach (var value in coding.Values)
            {
                foreach (var element in SplitHttpList(value))
                {
                    if (!IsHttpNameEqual(element, "chunked"))
                    {
                        return failure.RecordHttpFailure(HttpError.InvalidResponse,
                            "the response used the transfer coding '" + element + "'");
                    }
                    chunked++;
                }
            }
            if (chunked != 1u)
                return failure.RecordHttpFailure(HttpError.InvalidResponse, "the response was chunked twice");
            framing = Http11Framing.Chunked;
            return HttpError.None;
        }

        if (declared != null)
        {
            bool first = true;
            long agreed = 0;
            foreach (var value in declared.Values)
            {
                foreach (var element in SplitHttpList(value))
                {
                    if (!TryParseHttpDecimal(element, out long parsed) || (!first && parsed != agreed))
                    {
                        return failure.RecordHttpFailure(HttpError.InvalidResponse,
                            "the response's Content-Length was malformed or ambiguous");
                    }
                    agreed = parsed;
                    first = false;
                }
            }
            if (first)
                return failure.RecordHttpFailure(HttpError.InvalidResponse, "the response's Content-Length was empty");
            framing = Http11Framing.Length;
            length = agreed;
        }
        return HttpError.None;
    }

    // ------------------------------------------------------------- the body

    internal HttpBufferedReader Reader => _reader;

    /// Sets the socket's timeouts to what the exchange has left. False when
    /// nothing is left.
    internal bool ApplyHttpDeadline()
    {
        var exchange = _exchange;
        if (exchange == null)
            return !_closed;
        HttpDeadline deadline = exchange.Deadline;
        if (deadline.HasExpired)
            return false;
        Socket socket = _tcp.Underlying;
        int timeout = deadline.SocketTimeoutMilliseconds;
        socket.SetReceiveTimeout(timeout);
        socket.SetSendTimeout(timeout);
        return true;
    }

    /// Says why a read or write failed: the deadline, TLS, or the connection.
    internal HttpError ClassifyHttpIoFailure(String where)
    {
        var exchange = _exchange;
        if (exchange == null)
            return HttpError.ConnectionClosed;
        HttpFailure failure = exchange.Failure;
        SocketError socketError = _tcp.SocketErrorCode;
        if (exchange.Deadline.HasExpired || socketError == SocketError.TimedOut ||
            socketError == SocketError.WouldBlock)
        {
            failure.SocketErrorCode = SocketError.TimedOut;
            return failure.RecordHttpFailure(HttpError.Timeout, "the request timed out " + where);
        }
        if (_tls is TlsStream tls)
        {
            TlsError tlsError = tls.TlsErrorCode;
            if (tlsError != TlsError.None && tlsError != TlsError.Io && tlsError != TlsError.Closed)
            {
                failure.TlsErrorCode = tlsError;
                failure.TlsAlert = tls.AlertDescription;
                return failure.RecordHttpFailure(HttpError.TlsFailure,
                    DescribeTlsError(tlsError) + " " + where);
            }
        }
        failure.SocketErrorCode = socketError;
        return failure.RecordHttpFailure(HttpError.ConnectionClosed, "the connection failed " + where);
    }

    /// Records a failure on the exchange in progress, when there is one.
    internal HttpError RecordHttpExchangeFailure(HttpError error, String message)
    {
        var exchange = _exchange;
        if (exchange != null)
            exchange.Failure.RecordHttpFailure(error, message);
        return error;
    }

    /// The exchange is over: back to the pool when `reusable`, closed if not.
    internal void FinishHttpExchange(bool reusable)
    {
        _exchange = null;
        HttpConnectionPool? pool = _pool;
        if (pool != null)
            pool.ReleaseHttpConnection(this, reusable && !_closed);
        else
            CloseHttpConnection();
    }
}

/// A response head as read: the status line, and every field.
internal sealed class Http11Head
{
    internal int Status = 0;
    internal int Minor = 1;
    internal String Reason = "";
    internal HttpWireHeaders Fields = new HttpWireHeaders();

    internal Http11Head() { }
}

/// How a response body ends.
internal enum Http11Framing
{
    Length,
    Chunked,
    UntilClose,
}

/// `HTTP/1.x NNN reason`, or `HTTP/1.x NNN` with nothing after the code.
internal bool ParseHttpStatusLine(String line, Http11Head head)
{
    nuint length = line.ByteLength();
    if (length < 12u || !line.StartsWith("HTTP/1.") || line.GetByteAt(8u) != (byte)' ')
        return false;
    byte minor = line.GetByteAt(7u);
    if (minor < (byte)'0' || minor > (byte)'9')
        return false;
    int status = 0;
    for (nuint i = 9u; i < 12u; i++)
    {
        byte digit = line.GetByteAt(i);
        if (digit < (byte)'0' || digit > (byte)'9')
            return false;
        status = status * 10 + (int)(digit - (byte)'0');
    }
    if (status < 100)
        return false;
    if (length > 12u)
    {
        if (line.GetByteAt(12u) != (byte)' ')
            return false;
        String reason = line.Substring(13u);
        if (!IsHttpFieldValue(reason))
            return false;
        head.Reason = reason;
    }
    head.Status = status;
    head.Minor = (int)(minor - (byte)'0');
    return true;
}

/// A line quoted for a message, cut short and with control bytes made
/// visible.
internal String DescribeHttpLine(String line)
{
    var text = new StringBuilder();
    text.Append("\"");
    nuint length = line.ByteLength();
    for (nuint i = 0u; i < length && i < 64u; i++)
    {
        byte c = line.GetByteAt(i);
        if (c < 0x20 || c == 0x7F)
            text.Append("?");
        else
            text.AppendByte(c);
    }
    if (length > 64u)
        text.Append("...");
    text.Append("\"");
    return text.ToText();
}

/// The request line and the fields, ending in the empty line.
internal String FormatHttpRequestHead(HttpWireRequest request)
{
    var text = new StringBuilder();
    text.Append(request.Method.Method);
    text.Append(" ");
    text.Append(request.Target);
    text.Append(" HTTP/1.1\r\n");
    foreach (var field in request.Fields.Fields)
    {
        foreach (var value in field.Values)
        {
            text.Append(field.Name);
            text.Append(": ");
            text.Append(value);
            text.Append("\r\n");
        }
    }
    text.Append("\r\n");
    return text.ToText();
}
