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

module Standard.Security.Cryptography;

/// How the two numbers of a DSA or ECDSA signature, `r` and `s`, are laid out
/// as bytes: .NET's `DSASignatureFormat`.
public enum DsaSignatureFormat
{
    /// `r` then `s`, each big-endian and as wide as the group order: 64 bytes
    /// for P-256 and 96 for P-384. What JOSE, WebAuthn and .NET's default use.
    IeeeP1363FixedFieldConcatenation,

    /// A DER `SEQUENCE` of two `INTEGER`s, as RFC 3279 defines it. What X.509,
    /// TLS and OpenSSL use; its length varies by a few bytes.
    Rfc3279DerSequence,
}
