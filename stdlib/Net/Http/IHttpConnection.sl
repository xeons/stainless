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
