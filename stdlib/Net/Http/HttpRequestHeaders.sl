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

/// The fields of a request head.
///
/// A content field — `Content-Type`, `Content-Length` and the rest — is
/// refused here; it belongs on `HttpContent.Headers`. The typed properties
/// read and write the fields of the same name, so setting `UserAgent` is
/// `Remove("User-Agent")` and an `Add`, and a null removes it.
public sealed class HttpRequestHeaders : HttpHeaders
{
    public HttpRequestHeaders() { }

    /// `Accept`: the media types wanted.
    public String? Accept
    {
        get => GetJoinedHttpValue("accept");
        set => SetHttpValue("Accept", value);
    }

    /// `Accept-Encoding`. `HttpClientHandler.AutomaticDecompression` sets it
    /// when the request does not.
    public String? AcceptEncoding
    {
        get => GetJoinedHttpValue("accept-encoding");
        set => SetHttpValue("Accept-Encoding", value);
    }

    /// `Accept-Language`.
    public String? AcceptLanguage
    {
        get => GetJoinedHttpValue("accept-language");
        set => SetHttpValue("Accept-Language", value);
    }

    /// `Authorization`: a scheme and its credentials, as `Bearer abc`. Sent
    /// to the request's origin and dropped by a redirect to another.
    public String? Authorization
    {
        get => GetFirstHttpValue("authorization");
        set => SetHttpValue("Authorization", value);
    }

    /// `Connection`, as written.
    public String? Connection
    {
        get => GetJoinedHttpValue("connection");
        set => SetHttpValue("Connection", value);
    }

    /// Whether `Connection` holds `close`, which ends the connection after
    /// this exchange instead of pooling it.
    public bool ConnectionClose
    {
        get => HasHttpListToken("connection", "close");
        set => SetHttpListToken("Connection", "close", value);
    }

    /// Whether `Expect` holds `100-continue`: the body waits for the server's
    /// `100 Continue`, or for a second, whichever comes first.
    public bool ExpectContinue
    {
        get => HasHttpListToken("expect", "100-continue");
        set => SetHttpListToken("Expect", "100-continue", value);
    }

    /// `Host`, when it should differ from the request URI's authority. Sent
    /// to the request's origin and dropped by a redirect to another.
    public String? Host
    {
        get => GetFirstHttpValue("host");
        set => SetHttpValue("Host", value);
    }

    /// `Referer`, as the field is spelt.
    public String? Referrer
    {
        get => GetFirstHttpValue("referer");
        set => SetHttpValue("Referer", value);
    }

    /// Whether the body is sent chunked even when its length is known.
    public bool TransferEncodingChunked
    {
        get => HasHttpListToken("transfer-encoding", "chunked");
        set => SetHttpListToken("Transfer-Encoding", "chunked", value);
    }

    /// `User-Agent`.
    public String? UserAgent
    {
        get => GetJoinedHttpValue("user-agent");
        set => SetHttpValue("User-Agent", value);
    }

    protected override bool IsHttpHeaderAllowed(String key) => !IsHttpContentHeaderKey(key);
}
