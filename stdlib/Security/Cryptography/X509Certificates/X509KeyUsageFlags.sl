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

module Standard.Security.Cryptography.X509Certificates;

/// What a certificate's key may be used for, as its key usage extension
/// says: .NET's `X509KeyUsageFlags`, with .NET's values.
///
/// The low byte is the first octet of the `BIT STRING` as it is encoded, so
/// `DigitalSignature`, bit 0 of RFC 5280's list, is `0x80`.
[Flags]
public enum X509KeyUsageFlags
{
    /// No usage at all.
    None = 0,

    /// With `KeyAgreement`, the key may only encipher in agreement.
    EncipherOnly = 0x01,

    /// The key may sign revocation lists.
    CrlSign = 0x02,

    /// The key may sign certificates, which a CA's MUST allow.
    KeyCertSign = 0x04,

    /// The key may agree keys, as an ECDH key does.
    KeyAgreement = 0x08,

    /// The key may encipher data directly.
    DataEncipherment = 0x10,

    /// The key may encipher other keys, as RSA key transport does.
    KeyEncipherment = 0x20,

    /// Signatures made with the key are meant not to be repudiated.
    NonRepudiation = 0x40,

    /// The key may make signatures other than on certificates and lists.
    DigitalSignature = 0x80,

    /// With `KeyAgreement`, the key may only decipher in agreement.
    DecipherOnly = 0x8000,
}
