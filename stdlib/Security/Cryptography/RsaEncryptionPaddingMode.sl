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

/// Which of RFC 8017's two encryption encodings an RSA ciphertext uses.
public enum RsaEncryptionPaddingMode
{
    /// RSAES-PKCS1-v1_5 (RFC 8017 §7.2), for talking to what cannot do
    /// better. Its decryption is Bleichenbacher's oracle unless handled with
    /// care; see `Rsa.Decrypt` for how it is here.
    Pkcs1,

    /// RSAES-OAEP (RFC 8017 §7.1), the one to choose.
    Oaep,
}
