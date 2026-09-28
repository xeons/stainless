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

import Standard.Text;

/// A request: a method, a URI, fields and perhaps a body.
///
///     var request = new HttpRequestMessage(HttpMethod.Post, "https://example.com/items");
///     request.Headers.Accept = "application/json";
///     request.Content = new StringContent(json, null, "application/json");
///     var response = try client.Send(request);
///
/// A redirect that is followed changes `RequestUri`, and a `303` changes
/// `Method` to `GET` and drops `Content`, as .NET does; afterwards the
/// message describes the request that was answered last.
public class HttpRequestMessage
{
    private HttpRequestHeaders _headers = new HttpRequestHeaders();

    /// A `GET` with no URI, which `HttpClient.BaseAddress` MUST supply.
    public HttpRequestMessage() { }

    /// `method` to `requestUri`, absolute or relative to
    /// `HttpClient.BaseAddress`. Text that is not a URI leaves `RequestUri`
    /// null, and sending the request fails with `InvalidRequest`.
    public HttpRequestMessage(HttpMethod method, String requestUri)
    {
        Method = method;
        if (Uri.TryCreate(requestUri, UriKind.RelativeOrAbsolute) is Ok parsed)
            RequestUri = parsed.Value;
    }

    /// `method` to `requestUri`.
    public HttpRequestMessage(HttpMethod method, Uri? requestUri)
    {
        Method = method;
        RequestUri = requestUri;
    }

    /// The method.
    public HttpMethod Method { get; set; } = HttpMethod.Get;

    /// Where the request goes, or null to take `HttpClient.BaseAddress`.
    public Uri? RequestUri { get; set; }

    /// The request's own fields. `HttpClient.DefaultRequestHeaders` are
    /// added to them when sent, where these do not already name the field.
    public HttpRequestHeaders Headers => _headers;

    /// The body, or null for none.
    public HttpContent? Content { get; set; }

    /// The version asked for. Every request is sent as HTTP/1.1 for now.
    public Version Version { get; set; } = HttpVersion.Version11;

    /// Disposes the content.
    public void Dispose()
    {
        var content = Content;
        if (content != null)
            content.Dispose();
    }

    /// The method and the URI.
    public String ToString()
    {
        if (RequestUri is Uri uri)
            return Method.Method + " " + uri.ToString();
        return Method.Method + " <no URI>";
    }
}
