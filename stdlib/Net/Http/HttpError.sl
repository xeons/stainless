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

/// Why a request failed. `None` is success.
///
/// .NET's `HttpRequestError`, as the case a `Result` fails with rather than a
/// property of an exception. `HttpFailure` carries the detail beneath it: the
/// socket error, the TLS error, the status a proxy refused with.
///
/// @see HttpFailure
public enum HttpError
{
    /// Nothing went wrong.
    None = 0,

    /// The host name did not resolve.
    NameResolutionFailure,

    /// No connection could be made: refused, unreachable, or reset while it
    /// was being made.
    ConnectFailure,

    /// The connection ended before the response did, or before it began.
    ConnectionClosed,

    /// `HttpClient.Timeout` ran out: connecting, in TLS, sending, or reading.
    Timeout,

    /// The TLS handshake failed, or a record did; `HttpFailure.TlsErrorCode`
    /// says which.
    TlsFailure,

    /// The response broke HTTP/1.1's syntax or framing.
    InvalidResponse,

    /// The response head or body was over its limit.
    ResponseTooLarge,

    /// More redirects than `HttpClientHandler.MaxAutomaticRedirections`.
    TooManyRedirects,

    /// The proxy could not be reached, refused the tunnel, or asked for
    /// credentials it was not given; `HttpFailure.StatusCode` says which.
    ProxyFailure,

    /// A gzip or deflate body was corrupt.
    DecompressionFailed,

    /// The request cannot be sent as it is: a relative URI with no
    /// `BaseAddress`, a scheme other than http or https, a header value with
    /// a line break in it.
    InvalidRequest,

    /// `EnsureSuccessStatusCode` found a status outside 200–299.
    UnsuccessfulStatusCode,

    /// The request content could not be read, or the response content could
    /// not be written where it was asked to go.
    ContentFailure,

    /// The client or its handler has been disposed.
    Disposed,
}
