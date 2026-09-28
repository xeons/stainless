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

import Standard.IO;
import Standard.Text;

/// A response: a status, fields, a body, and the request it answered.
///
///     var response = try client.Get("https://example.com/");
///     if (response.IsSuccessStatusCode)
///         Console.WriteLine(try response.Content.ReadAsString());
///
/// A response holds its connection until its body has been read to the end,
/// and closes it when disposed or released before then.
public class HttpResponseMessage
{
    private HttpResponseHeaders _headers = new HttpResponseHeaders();
    private HttpResponseHeaders _trailingHeaders = new HttpResponseHeaders();
    private String? _reasonPhrase;

    /// A `200 OK` with no body.
    public HttpResponseMessage() { }

    /// A response of `statusCode` with no body.
    public HttpResponseMessage(HttpStatusCode statusCode) => StatusCode = statusCode;

    /// The status.
    public HttpStatusCode StatusCode { get; set; } = HttpStatusCode.OK;

    /// The reason phrase the server sent, or RFC 9110's for the status when
    /// none was set.
    public String ReasonPhrase
    {
        get
        {
            var phrase = _reasonPhrase;
            return phrase == null ? DescribeHttpStatusCode(StatusCode) : phrase;
        }
        set => _reasonPhrase = value;
    }

    /// The response's fields, less the content's.
    public HttpResponseHeaders Headers => _headers;

    /// The trailer of a chunked body. Filled in once the body has been read
    /// to its end, and empty until then.
    public HttpResponseHeaders TrailingHeaders => _trailingHeaders;

    /// The body. A response with none has empty content rather than null.
    public HttpContent Content { get; set; } = new HttpEmptyContent();

    /// The version the server answered in.
    public Version Version { get; set; } = HttpVersion.Version11;

    /// The request this answered: after redirects, the last one sent.
    public HttpRequestMessage? RequestMessage { get; set; }

    /// Whether the status is in 200–299.
    public bool IsSuccessStatusCode => (int)StatusCode >= 200 && (int)StatusCode <= 299;

    /// This response when `IsSuccessStatusCode`, and a failure otherwise.
    ///
    /// @failure HttpError.UnsuccessfulStatusCode  the status is outside 200–299
    public Result<HttpResponseMessage, HttpError> EnsureSuccessStatusCode() =>
        EnsureSuccessStatusCode(out HttpFailure failure);

    /// The same, saying which status it was.
    ///
    /// @param failure  the status and a message when it fails
    /// @failure HttpError.UnsuccessfulStatusCode  the status is outside 200–299
    public Result<HttpResponseMessage, HttpError> EnsureSuccessStatusCode(out HttpFailure failure)
    {
        failure = new HttpFailure();
        if (IsSuccessStatusCode)
            return Ok(this);
        failure.StatusCode = StatusCode;
        if (RequestMessage is HttpRequestMessage request)
            failure.RequestUri = request.RequestUri;
        failure.RecordHttpFailure(HttpError.UnsuccessfulStatusCode,
            "the response status was " + Text.FromInteger((long)(int)StatusCode) + " " + ReasonPhrase);
        return Fail(HttpError.UnsuccessfulStatusCode);
    }

    /// Releases the body, closing the connection if it was not read to its
    /// end.
    public void Dispose() => Content.Dispose();

    /// The status line.
    public String ToString() =>
        "HTTP/" + Version.ToString(2) + " " + Text.FromInteger((long)(int)StatusCode) + " " + ReasonPhrase;
}

/// The body of a response that has none.
internal sealed class HttpEmptyContent : HttpContent
{
    internal HttpEmptyContent() { }

    protected override HttpError SerializeToStream(IStream stream) => HttpError.None;

    protected override bool TryComputeLength(out long length)
    {
        length = 0;
        return true;
    }
}
