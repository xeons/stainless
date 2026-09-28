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

import Standard.IO.Compression;
import Standard.Net;
import Standard.Net.Security;

/// What went wrong with a request, in more detail than its `HttpError`.
///
///     var response = client.Send(request, HttpCompletionOption.ResponseContentRead,
///                                out HttpFailure failure);
///     if (!response.Ok)
///         Console.WriteLine(failure.Message);
///
/// .NET's `HttpRequestException`, handed back through `out` rather than
/// thrown. A request that succeeded leaves `Error` as `None`.
public sealed class HttpFailure
{
    /// A failure that has not happened.
    public HttpFailure() { }

    /// The case the request failed with.
    public HttpError Error { get; set; } = HttpError.None;

    /// A sentence saying what happened.
    public String Message { get; set; } = "";

    /// The status that caused the failure: a proxy's refusal, or what
    /// `EnsureSuccessStatusCode` found.
    public Optional<HttpStatusCode> StatusCode { get; set; } = None;

    /// The socket's own error, when a connection failed.
    public SocketError SocketErrorCode { get; set; } = SocketError.None;

    /// The TLS error, when `Error` is `TlsFailure`.
    public TlsError TlsErrorCode { get; set; } = TlsError.None;

    /// The alert the server sent, when `TlsErrorCode` is `AlertReceived`.
    public TlsAlertDescription TlsAlert { get; set; } = TlsAlertDescription.CloseNotify;

    /// The decompressor's error, when `Error` is `DecompressionFailed`.
    public CompressionError CompressionErrorCode { get; set; } = CompressionError.None;

    /// The URI of the request that failed.
    public Uri? RequestUri { get; set; }

    /// Records `error` and a message, and answers `error`, for a `return`.
    internal HttpError RecordHttpFailure(HttpError error, String message)
    {
        Error = error;
        Message = message;
        return error;
    }

    internal void ResetHttpFailure()
    {
        Error = HttpError.None;
        Message = "";
        StatusCode = None;
        SocketErrorCode = SocketError.None;
        TlsErrorCode = TlsError.None;
        TlsAlert = TlsAlertDescription.CloseNotify;
        CompressionErrorCode = CompressionError.None;
    }

    /// The failure in words: the message, or the case described when there
    /// is none.
    public String ToString() => Message.IsEmpty ? DescribeHttpError(Error) : Message;
}
