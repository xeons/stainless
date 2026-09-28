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

/// One connection to a server, whatever protocol it speaks.
///
/// **This is where HTTP/2 slots in.** `Http11Connection` is the one
/// implementation today. The connector offers TLS the protocols
/// `CreateHttpApplicationProtocols` names and makes the connection ALPN
/// agreed on; an
/// `h2` connection will implement this interface too, carrying several
/// exchanges at once where a 1.1 connection carries one, and everything
/// above — the pool, redirects, cookies, decompression — is written against
/// the interface and does not change.
internal interface IHttpConnection
{
    /// The version this connection speaks.
    Version ProtocolVersion { get; }

    /// Which pool entry it belongs to: scheme, host, port and proxy.
    String PoolKey { get; }

    /// Whether it has carried a request before this one, so that a failure
    /// before any response may only mean the server had closed it.
    bool HasCarriedRequest { get; }

    /// Whether it still looks open: nothing unread and no end from the peer.
    bool IsHttpConnectionAlive();

    /// Sends `request` and reads the head of the response. The body is read
    /// through the response's content, which gives the connection back to its
    /// pool when it ends.
    Result<HttpResponseMessage, HttpError> SendHttpRequest(HttpWireRequest request,
                                                          HttpExchange exchange);

    /// Closes it, whatever it was doing.
    void CloseHttpConnection();
}

/// The ALPN names TLS offers, most preferred first. `h2` joins this list when
/// there is an HTTP/2 connection to make.
internal List<String> CreateHttpApplicationProtocols()
{
    var protocols = new List<String>();
    protocols.Add("http/1.1");
    return protocols;
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
