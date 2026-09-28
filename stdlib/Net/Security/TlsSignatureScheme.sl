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

/// A signature algorithm and its hash, with the number IANA gives it.
///
/// Each of the ECDSA schemes names its curve as well as its hash, and the
/// RSA-PSS schemes are split by the kind of key: `RsaPssRsae` for a key
/// published as `rsaEncryption` and `RsaPssPss` for one published as
/// `RSASSA-PSS`. PKCS #1 v1.5 is accepted in certificates and never in a
/// handshake signature.
public enum TlsSignatureScheme : ushort
{
    /// RSA with PKCS #1 v1.5 padding and SHA-256. Certificates only.
    RsaPkcs1Sha256 = 0x0401,

    /// RSA with PKCS #1 v1.5 padding and SHA-384. Certificates only.
    RsaPkcs1Sha384 = 0x0501,

    /// RSA with PKCS #1 v1.5 padding and SHA-512. Certificates only.
    RsaPkcs1Sha512 = 0x0601,

    /// ECDSA on P-256 with SHA-256.
    EcdsaSecp256r1Sha256 = 0x0403,

    /// ECDSA on P-384 with SHA-384.
    EcdsaSecp384r1Sha384 = 0x0503,

    /// ECDSA on P-521 with SHA-512. Named and never offered: there is no
    /// P-521 here.
    EcdsaSecp521r1Sha512 = 0x0603,

    /// RSA-PSS with SHA-256, for an `rsaEncryption` key.
    RsaPssRsaeSha256 = 0x0804,

    /// RSA-PSS with SHA-384, for an `rsaEncryption` key.
    RsaPssRsaeSha384 = 0x0805,

    /// RSA-PSS with SHA-512, for an `rsaEncryption` key.
    RsaPssRsaeSha512 = 0x0806,

    /// Ed25519, RFC 8032.
    Ed25519 = 0x0807,

    /// Ed448. Named and never offered.
    Ed448 = 0x0808,

    /// RSA-PSS with SHA-256, for an `RSASSA-PSS` key.
    RsaPssPssSha256 = 0x0809,

    /// RSA-PSS with SHA-384, for an `RSASSA-PSS` key.
    RsaPssPssSha384 = 0x080A,

    /// RSA-PSS with SHA-512, for an `RSASSA-PSS` key.
    RsaPssPssSha512 = 0x080B,
}
