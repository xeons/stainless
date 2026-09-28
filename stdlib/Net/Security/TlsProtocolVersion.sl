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

module Standard.Net.Security;

/// Versions of TLS, as bits so that a set of them can be enabled at once.
///
/// @see TlsClientOptions.EnabledProtocols
[Flags]
public enum TlsProtocolVersion
{
    /// No version: what a set with nothing in it holds.
    None = 0,

    /// TLS 1.2, RFC 5246. Named so that a set can hold it; no connection is
    /// made in it yet, and a peer that offers nothing newer is refused.
    Tls12 = 1,

    /// TLS 1.3, RFC 8446.
    Tls13 = 2,
}
