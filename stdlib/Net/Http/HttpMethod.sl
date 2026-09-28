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

/// An HTTP method: one of the standard nine, or any other token.
///
///     var request = new HttpRequestMessage(HttpMethod.Put, uri);
///     var custom = new HttpMethod("PROPFIND");
///
/// Methods compare by name, and the name is case-sensitive, as RFC 9110 says.
/// The standard ones are made afresh each time they are asked for rather than
/// kept in statics, which would be alive at exit in every program that
/// imports this module.
public sealed threadsafe class HttpMethod : IEquatable<HttpMethod>
{
    private String _method;

    /// A method of any name. The name MUST be a token; one that is not is
    /// refused when the request is sent.
    public HttpMethod(String method) => _method = method;

    public static HttpMethod Get => new HttpMethod("GET");

    public static HttpMethod Post => new HttpMethod("POST");

    public static HttpMethod Put => new HttpMethod("PUT");

    public static HttpMethod Delete => new HttpMethod("DELETE");

    public static HttpMethod Head => new HttpMethod("HEAD");

    public static HttpMethod Options => new HttpMethod("OPTIONS");

    public static HttpMethod Patch => new HttpMethod("PATCH");

    public static HttpMethod Trace => new HttpMethod("TRACE");

    public static HttpMethod Connect => new HttpMethod("CONNECT");

    /// The name, as it goes on the request line.
    public String Method => _method;

    /// Whether RFC 9110 calls the method idempotent, so that a request which
    /// failed before any answer MAY be sent again.
    internal bool IsIdempotent
    {
        get
        {
            switch (_method)
            {
                case "GET":
                case "HEAD":
                case "PUT":
                case "DELETE":
                case "OPTIONS":
                case "TRACE":
                    return true;
            }
            return false;
        }
    }

    public bool Equals(HttpMethod other) => _method == other._method;

    public static bool operator ==(HttpMethod left, HttpMethod right) => left._method == right._method;

    public static bool operator !=(HttpMethod left, HttpMethod right) => left._method != right._method;

    public String ToString() => _method;
}
