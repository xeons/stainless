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

import Standard.Time;

/// The fields of a response head, or of the trailer that follows a chunked
/// body.
///
/// A content field is kept on `HttpContent.Headers` instead, as .NET keeps
/// it. The typed properties read the fields of the same name.
public sealed class HttpResponseHeaders : HttpHeaders
{
    public HttpResponseHeaders() { }

    /// `Age`, in seconds, or none.
    public Optional<long> Age
    {
        get
        {
            String? text = GetFirstHttpValue("age");
            if (text == null || !TryParseHttpDecimal(text, out long seconds))
                return None;
            return seconds;
        }
    }

    /// `Connection`, as written.
    public String? Connection
    {
        get => GetJoinedHttpValue("connection");
        set => SetHttpValue("Connection", value);
    }

    /// Whether `Connection` holds `close`: the server will close the
    /// connection after this response.
    public bool ConnectionClose
    {
        get => HasHttpListToken("connection", "close");
        set => SetHttpListToken("Connection", "close", value);
    }

    /// `Date`, when it is an HTTP-date.
    public Optional<DateTimeOffset> Date
    {
        get
        {
            String? text = GetFirstHttpValue("date");
            if (text == null)
                return None;
            if (DateTimeOffset.ParseHttpDate(text) is Ok parsed)
                return parsed.Value;
            return None;
        }
    }

    /// `ETag`, quotes and all.
    public String? ETag
    {
        get => GetFirstHttpValue("etag");
        set => SetHttpValue("ETag", value);
    }

    /// `Location`: where a redirect points, or what a `201 Created` made.
    /// Relative when the server wrote it relative; resolve it against the
    /// request URI.
    public Uri? Location
    {
        get
        {
            String? text = GetFirstHttpValue("location");
            if (text == null)
                return null;
            if (Uri.TryCreate(text, UriKind.RelativeOrAbsolute) is Ok parsed)
                return parsed.Value;
            return null;
        }
    }

    /// `Proxy-Authenticate`: the challenge a proxy answered `407` with.
    public String? ProxyAuthenticate => GetJoinedHttpValue("proxy-authenticate");

    /// `Server`.
    public String? Server
    {
        get => GetJoinedHttpValue("server");
        set => SetHttpValue("Server", value);
    }

    /// Whether `Transfer-Encoding` ends in `chunked`.
    public bool TransferEncodingChunked
    {
        get => HasHttpListToken("transfer-encoding", "chunked");
        set => SetHttpListToken("Transfer-Encoding", "chunked", value);
    }

    /// `WWW-Authenticate`: the challenge a `401` came with.
    public String? WwwAuthenticate => GetJoinedHttpValue("www-authenticate");

    protected override bool IsHttpHeaderAllowed(String key) => !IsHttpContentHeaderKey(key);
}
