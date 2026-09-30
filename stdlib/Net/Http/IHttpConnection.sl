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
import Standard.Time;

/// One connection to a server, whatever protocol it speaks.
///
/// `Http11Connection` carries one exchange at a time and is lent to a
/// request; `Http2Connection` carries many at once and is shared, a stream
/// reserved for each. The connector offers TLS the protocols a request
/// allows and makes the connection ALPN agreed on, and everything above —
/// the pool, redirects, cookies, decompression — is written against this
/// interface.
internal interface IHttpConnection
{
    /// The version this connection speaks.
    Version ProtocolVersion { get; }

    /// Which pool entry it belongs to: scheme, host, port and proxy.
    String PoolKey { get; }

    /// Whether it has carried a request before this one, so that a failure
    /// before any response may only mean the server had closed it.
    bool HasCarriedRequest { get; }

    /// Whether it carries several exchanges at once, and so is shared rather
    /// than lent.
    bool IsMultiplexed { get; }

    /// Whether it still looks open: nothing unread and no end from the peer.
    bool IsHttpConnectionAlive();

    /// Takes a place for one more exchange on a multiplexed connection.
    /// False when it is full or closing, and always on one that is not
    /// multiplexed.
    bool TryReserveHttpStream();

    /// Whether a multiplexed connection has had nothing to do for `timeout`.
    bool HasHttpIdleTimeoutPassed(TimeSpan now, TimeSpan timeout);

    /// Sends `request` and reads the head of the response. The body is read
    /// through the response's content, which gives the connection back to its
    /// pool when it ends.
    Result<HttpResponseMessage, HttpError> SendHttpRequest(HttpWireRequest request,
                                                          HttpExchange exchange);

    /// Closes it: at once for HTTP/1.1, and for HTTP/2 once its streams
    /// have ended, after a GOAWAY.
    void CloseHttpConnection();
}

/// The ALPN names TLS offers, most preferred first: `h2` then `http/1.1`,
/// as far as `choice` allows each.
internal List<String> CreateHttpApplicationProtocols(HttpVersionChoice choice)
{
    var protocols = new List<String>();
    if (choice.AllowsHttp2)
        protocols.Add("h2");
    if (choice.AllowsHttp11)
        protocols.Add("http/1.1");
    return protocols;
}

/// Which protocols a request may be sent in, once its version, its policy
/// and its route have been weighed.
internal sealed class HttpVersionChoice
{
    internal bool AllowsHttp11;
    internal bool AllowsHttp2;

    internal HttpVersionChoice(bool allowsHttp11, bool allowsHttp2)
    {
        AllowsHttp11 = allowsHttp11;
        AllowsHttp2 = allowsHttp2;
    }
}

/// One request in flight: its deadline, where its failure is reported, and
/// what the connection learned that decides whether it may be retried.
internal sealed class HttpExchange
{
    internal HttpDeadline Deadline;
    internal HttpFailure Failure;

    /// The most bytes a response head may take.
    internal nuint MaxHeaderBytes;

    /// Whether the failure came before a byte of the response arrived, on a
    /// connection that had carried a request already.
    internal bool IsRetryable = false;

    /// Whether the server said it never processed the request — a GOAWAY
    /// below its stream, or REFUSED_STREAM — so that any method may be sent
    /// again (RFC 9113 §8.7).
    internal bool IsUnprocessed = false;

    /// Whether a body with `Expect: 100-continue` is sent without waiting,
    /// after a wait on an earlier connection met a socket readable with no
    /// response on it.
    internal bool SkipsContinueWait = false;

    internal HttpExchange(HttpDeadline deadline, HttpFailure failure, nuint maxHeaderBytes)
    {
        Deadline = deadline;
        Failure = failure;
        MaxHeaderBytes = maxHeaderBytes;
    }
}

/// A request as it goes on the wire: every field decided, the target in the
/// form its route needs.
internal sealed class HttpWireRequest
{
    internal HttpMethod Method;

    /// Origin-form, `/path?query`, or absolute-form for a proxy.
    internal String Target;

    /// What HTTP/2's pseudo-headers carry: the scheme, the authority as the
    /// URI has it, and the path with its query.
    internal String Scheme = "";
    internal String Authority = "";
    internal String Path = "/";

    internal HttpWireHeaders Fields = new HttpWireHeaders();
    internal HttpContent? Content;

    /// Whether the body is sent chunked, its length being unknown.
    internal bool IsChunked = false;

    /// The `Content-Length` sent, which the body MUST then be.
    internal long DeclaredLength = 0;

    internal bool ExpectContinue = false;

    internal HttpWireRequest(HttpMethod method, String target)
    {
        Method = method;
        Target = target;
    }
}

/// Fields with no rule about which collection they belong to: a request's as
/// sent, or a response's as read.
internal sealed class HttpWireHeaders : HttpHeaders
{
    internal HttpWireHeaders() { }
}
