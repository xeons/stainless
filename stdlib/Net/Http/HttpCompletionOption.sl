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

/// When `Send` returns: once the whole response has been read, or as soon as
/// its head has.
public enum HttpCompletionOption
{
    /// The body is read into memory before `Send` returns, within
    /// `HttpClient.Timeout` and `MaxResponseContentBufferSize`, and the
    /// connection goes back to the pool at once.
    ResponseContentRead = 0,

    /// `Send` returns once the head is read, and the body is read from
    /// `Content.ReadAsStream()` as it arrives. The connection goes back to the
    /// pool when the body has been read to its end; a response disposed
    /// before then closes it. `HttpClient.Timeout` does not cover the body.
    ResponseHeadersRead = 1,
}
