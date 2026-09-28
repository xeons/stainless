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

/// An HTTP/1.1 client, over TCP or TLS, in `System.Net.Http`'s shape.
///
/// ```csharp
/// var client = new HttpClient();
/// client.Timeout = TimeSpan.FromSeconds(10);
/// String page = try client.GetString("https://example.com/");
///
/// var response = try client.Post("https://example.com/api",
///                                new StringContent("{}", Encoding.CreateUtf8(),
///                                                  "application/json"));
/// try response.EnsureSuccessStatusCode();
/// ```
///
/// **The shape is .NET's, without the `Async`.** Every call blocks, so
/// `SendAsync` is `Send` and `GetStringAsync` is `GetString`. Where .NET
/// throws `HttpRequestException`, a call here returns
/// `Result<…, HttpError>`; the overloads taking `out HttpFailure` say more —
/// the socket error, the TLS error, the status a proxy refused with.
///
/// **What is implemented** is HTTP/1.1 (RFC 9112) over TCP and TLS 1.3:
/// keep-alive with a pool of connections per server, request bodies of known
/// length or chunked, responses framed by length, by chunks (with trailers)
/// or by the connection closing, `Expect: 100-continue`, redirects, cookies
/// (RFC 6265), gzip and deflate, proxies over HTTP with `CONNECT` tunnels, and
/// one timeout that covers the whole of a request.
///
/// **What is not:** HTTP/2 and HTTP/3, authentication other than Basic to a
/// proxy, a proxy spoken to over TLS, and a timeout on name resolution, which
/// the platform's resolver does not offer.
///
/// **HTTP/2 slots in beside the 1.1 connection.** Each connection is an
/// `IHttpConnection`, and TLS offers the ALPN names of the protocols this
/// module speaks. Today that is `http/1.1` alone; a connection that agrees on
/// `h2` will be made as a second implementation of the same interface, and
/// the pool, the redirects, the cookies and the decompression above it will
/// not change.
///
/// **Responses are parsed strictly.** A status line that is not
/// `HTTP/1.x NNN reason`, a folded header, a header line or block over its
/// limit, a chunk size that is not hexadecimal or does not fit, two
/// disagreeing `Content-Length`s, and a `Content-Length` beside a
/// `Transfer-Encoding` are all refused as `HttpError.InvalidResponse`, since
/// each is how one message is smuggled inside another.
///
/// **Certificates are judged by the TLS module's validator** unless
/// `HttpClientHandler.ServerCertificateCustomValidationCallback` is set, in
/// which case it decides, and is told what the default would have answered.
///
/// **One client MAY be used by several threads at once.** The pool is under
/// a lock; a request and its response belong to the thread that sent it.
module Standard.Net.Http;

import Standard.Collections;
import Standard.IO;
import Standard.Text;

extern "C"
{
    byte* memcpy(byte* to, byte* from, nuint count);
}

// ------------------------------------------------------------------ limits

/// The longest status line, header line or chunk-size line read.
internal const nuint HttpMaxLineLength = 16384u;

/// The most header lines in one response head or one trailer block.
internal const nuint HttpMaxHeaderCount = 256u;

/// How much of a response body is drained so that its connection can be
/// reused, when the body is not wanted: a redirect's, or a refusal's.
internal const long HttpMaxDrainLength = 65536;

/// The size of the blocks a body is copied in.
internal const nuint HttpCopyBlockSize = 16384u;

/// How long a request with `Expect: 100-continue` waits for the server's
/// interim answer before sending its body anyway.
internal const int HttpExpectContinueMilliseconds = 1000;

// ------------------------------------------------------------------ errors

/// A sentence describing an HTTP error, for a message a person will read.
///
/// @see HttpError
public String DescribeHttpError(HttpError error)
{
    switch (error)
    {
        case HttpError.None: return "no error";
        case HttpError.NameResolutionFailure: return "the host name did not resolve";
        case HttpError.ConnectFailure: return "the connection could not be made";
        case HttpError.ConnectionClosed: return "the connection closed before the response ended";
        case HttpError.Timeout: return "the request timed out";
        case HttpError.TlsFailure: return "the TLS handshake or a TLS record failed";
        case HttpError.InvalidResponse: return "the response was malformed";
        case HttpError.ResponseTooLarge: return "the response was larger than allowed";
        case HttpError.TooManyRedirects: return "there were too many redirects";
        case HttpError.ProxyFailure: return "the proxy refused or failed";
        case HttpError.DecompressionFailed: return "the response body could not be decompressed";
        case HttpError.InvalidRequest: return "the request could not be sent as it is";
        case HttpError.UnsuccessfulStatusCode: return "the response status was not a success";
        case HttpError.ContentFailure: return "reading or writing the content failed";
        case HttpError.Disposed: return "the client has been disposed";
    }
    return "an unknown error";
}

// ------------------------------------------------------------------ syntax

/// Whether `c` may appear in a token: a header name, a method, a coding.
internal bool IsHttpTokenByte(byte c)
{
    if ((c >= (byte)'a' && c <= (byte)'z') || (c >= (byte)'A' && c <= (byte)'Z'))
        return true;
    if (c >= (byte)'0' && c <= (byte)'9')
        return true;
    return "!#$%&'*+-.^_`|~".Contains((char)c);
}

/// Whether `text` is a non-empty token.
internal bool IsHttpToken(String text)
{
    nuint length = text.ByteLength();
    if (length == 0u)
        return false;
    for (nuint i = 0u; i < length; i++)
    {
        if (!IsHttpTokenByte(text.GetByteAt(i)))
            return false;
    }
    return true;
}

/// Whether `text` may be a field value: no control character but HTAB, so
/// no CR, LF or NUL to end a line early.
internal bool IsHttpFieldValue(String text)
{
    nuint length = text.ByteLength();
    for (nuint i = 0u; i < length; i++)
    {
        byte c = text.GetByteAt(i);
        if ((c < 0x20 && c != 0x09) || c == 0x7F)
            return false;
    }
    return true;
}

/// Whether `c` is optional whitespace: SP or HTAB.
internal bool IsHttpWhitespace(byte c) => c == 0x20 || c == 0x09;

/// `text` without the SP and HTAB at either end.
internal String TrimHttpWhitespace(String text)
{
    nuint length = text.ByteLength();
    nuint start = 0u;
    while (start < length && IsHttpWhitespace(text.GetByteAt(start)))
        start++;
    nuint end = length;
    while (end > start && IsHttpWhitespace(text.GetByteAt(end - 1u)))
        end--;
    if (start == 0u && end == length)
        return text;
    return text.Substring(start, end - start);
}

/// The elements of a comma-separated field value, trimmed, with empty ones
/// dropped and a comma inside a quoted string left alone.
internal List<String> SplitHttpList(String value)
{
    var parts = new List<String>();
    nuint length = value.ByteLength();
    nuint start = 0u;
    bool quoted = false;
    for (nuint i = 0u; i < length; i++)
    {
        byte c = value.GetByteAt(i);
        if (c == (byte)'"')
        {
            quoted = !quoted;
        }
        else if (c == (byte)'\\' && quoted)
        {
            i++;
        }
        else if (c == (byte)',' && !quoted)
        {
            AddHttpListElement(parts, value.Substring(start, i - start));
            start = i + 1u;
        }
    }
    if (start <= length)
        AddHttpListElement(parts, value.Substring(start));
    return parts;
}

internal void AddHttpListElement(List<String> parts, String element)
{
    String trimmed = TrimHttpWhitespace(element);
    if (!trimmed.IsEmpty)
        parts.Add(trimmed);
}

/// A decimal count with nothing but digits in it, as `Content-Length` is.
/// False on anything else, and on a value past `long`'s range.
internal bool TryParseHttpDecimal(String text, out long value)
{
    value = 0;
    nuint length = text.ByteLength();
    if (length == 0u || length > 18u)
        return false;
    for (nuint i = 0u; i < length; i++)
    {
        byte c = text.GetByteAt(i);
        if (c < (byte)'0' || c > (byte)'9')
            return false;
        value = value * 10 + (long)(c - (byte)'0');
    }
    return true;
}

/// The value of one hexadecimal digit, or -1.
internal int ParseHttpHexadecimalDigit(byte c)
{
    if (c >= (byte)'0' && c <= (byte)'9')
        return c - (byte)'0';
    if (c >= (byte)'a' && c <= (byte)'f')
        return c - (byte)'a' + 10;
    if (c >= (byte)'A' && c <= (byte)'F')
        return c - (byte)'A' + 10;
    return -1;
}

/// `count` bytes of `data` from `offset`, as text.
internal String ConvertHttpBytesToText(byte[] data, nuint offset, nuint count)
{
    if (count == 0u)
        return "";
    return Text.FromBytes(&data[offset], count);
}

/// Whether `name` is `wanted`, ignoring ASCII case.
internal bool IsHttpNameEqual(String name, String wanted) => name.EqualsIgnoreCaseAscii(wanted);

// ------------------------------------------------------------------ streams

/// Writes all `count` bytes of `buffer` from `offset` to `stream`, looping
/// over short writes. False when the stream took nothing.
internal bool WriteAllHttpBytes(IStream stream, byte[] buffer, nuint offset, nuint count)
{
    nuint at = offset;
    nuint end = offset + count;
    while (at < end)
    {
        nuint wrote = stream.Write(buffer, at, end - at);
        if (wrote == 0u)
            return false;
        at += wrote;
    }
    return true;
}

/// Copies `source` to its end into `destination`, and answers what failed:
/// `None`, or which side.
internal HttpCopyOutcome CopyHttpStream(IStream source, IStream destination)
{
    var block = new byte[HttpCopyBlockSize];
    while (true)
    {
        nuint got = source.Read(block, 0u, block.Length);
        if (got == 0u)
            return source.Error == IOError.None ? HttpCopyOutcome.Done : HttpCopyOutcome.ReadFailed;
        if (!WriteAllHttpBytes(destination, block, 0u, got))
            return HttpCopyOutcome.WriteFailed;
    }
}

/// How a copy ended.
internal enum HttpCopyOutcome
{
    Done,
    ReadFailed,
    WriteFailed,
}
