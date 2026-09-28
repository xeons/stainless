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

/// A cipher suite, with the number IANA gives it.
///
/// The names are IANA's in this library's casing: `TLS_AES_128_GCM_SHA256`
/// is `TlsAes128GcmSha256`. A TLS 1.3 suite names the record protection and
/// the hash of the key schedule, and nothing else. A TLS 1.2 suite also names
/// the key exchange, which is always ECDHE here, and the kind of key the
/// server's certificate MUST hold: ECDSA or Ed25519 for `Ecdsa`, RSA for
/// `Rsa`. The two sets are disjoint, and one list holds both.
public enum TlsCipherSuite : ushort
{
    /// AES-128 in GCM, with SHA-256. The suite every TLS 1.3 peer MUST
    /// implement.
    TlsAes128GcmSha256 = 0x1301,

    /// AES-256 in GCM, with SHA-384.
    TlsAes256GcmSha384 = 0x1302,

    /// ChaCha20 and Poly1305, with SHA-256. About three times as fast as the
    /// AES suites here, since AES runs in software.
    TlsChaCha20Poly1305Sha256 = 0x1303,

    /// TLS 1.2: ECDHE, an ECDSA or Ed25519 certificate, AES-128 in GCM and
    /// SHA-256. RFC 5289.
    TlsEcdheEcdsaWithAes128GcmSha256 = 0xC02B,

    /// TLS 1.2: ECDHE, an ECDSA or Ed25519 certificate, AES-256 in GCM and
    /// SHA-384. RFC 5289.
    TlsEcdheEcdsaWithAes256GcmSha384 = 0xC02C,

    /// TLS 1.2: ECDHE, an RSA certificate, AES-128 in GCM and SHA-256.
    /// RFC 5289.
    TlsEcdheRsaWithAes128GcmSha256 = 0xC02F,

    /// TLS 1.2: ECDHE, an RSA certificate, AES-256 in GCM and SHA-384.
    /// RFC 5289.
    TlsEcdheRsaWithAes256GcmSha384 = 0xC030,

    /// TLS 1.2: ECDHE, an RSA certificate, ChaCha20 and Poly1305 with
    /// SHA-256. RFC 7905.
    TlsEcdheRsaWithChaCha20Poly1305Sha256 = 0xCCA8,

    /// TLS 1.2: ECDHE, an ECDSA or Ed25519 certificate, ChaCha20 and
    /// Poly1305 with SHA-256. RFC 7905.
    TlsEcdheEcdsaWithChaCha20Poly1305Sha256 = 0xCCA9,
}
