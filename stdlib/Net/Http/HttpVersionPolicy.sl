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

/// How strictly `HttpRequestMessage.Version` is kept to: .NET's
/// `HttpVersionPolicy`.
///
/// | Version | Policy | https | http |
/// |---|---|---|---|
/// | 1.1 | `RequestVersionOrLower` | HTTP/1.1 | HTTP/1.1 |
/// | 1.1 | `RequestVersionOrHigher` | h2 if ALPN agrees, else 1.1 | HTTP/1.1 |
/// | 1.1 | `RequestVersionExact` | HTTP/1.1 | HTTP/1.1 |
/// | 2.0 | `RequestVersionOrLower` | h2 if ALPN agrees, else 1.1 | HTTP/1.1 |
/// | 2.0 | `RequestVersionOrHigher` | h2, or a failure | h2 with prior knowledge |
/// | 2.0 | `RequestVersionExact` | h2, or a failure | h2 with prior knowledge |
///
/// Plain http never upgrades: HTTP/2 is used there only when the request
/// will take nothing else, and then it is spoken from the first byte. A
/// request through a plain proxy is always HTTP/1.1, since the proxy is
/// spoken to in absolute form; through a `CONNECT` tunnel it is https as
/// above. A version this module does not speak — 3.0 — is taken as 2.0 when
/// the policy lets it be lower, and refused otherwise.
public enum HttpVersionPolicy
{
    /// The version asked for, or a lower one the server prefers. The default.
    RequestVersionOrLower,

    /// The version asked for, or a higher one the server offers.
    RequestVersionOrHigher,

    /// The version asked for and no other.
    RequestVersionExact,
}
