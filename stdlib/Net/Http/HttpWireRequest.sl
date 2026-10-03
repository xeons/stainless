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

/// A request as it goes on the wire: every field decided, the target in the
/// form its route needs.
internal sealed class HttpWireRequest
{
    internal HttpMethod Method;

    /// Origin-form, `/path?query`, or absolute-form for a proxy.
    internal String Target;

    /// What HTTP/2's pseudo-headers carry: the scheme, the authority as the
    /// URI has it, and the path with its query.
    internal String Scheme = "";
    internal String Authority = "";
    internal String Path = "/";

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
