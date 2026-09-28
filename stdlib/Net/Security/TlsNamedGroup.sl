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

/// A group for the ephemeral key exchange, with the number IANA gives it.
public enum TlsNamedGroup : ushort
{
    /// NIST P-256, as `secp256r1`.
    Secp256r1 = 0x0017,

    /// NIST P-384, as `secp384r1`.
    Secp384r1 = 0x0018,

    /// Curve25519 in Montgomery form, RFC 7748.
    X25519 = 0x001D,
}
