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

import Standard.Text;
import Standard.Bits;

// ============================================================ what can fail

/// Why an operation did not happen.
///
/// One enum for the module, as `IOError` is for `Standard.IO`: a caller
/// switching on the failure of a decrypt wants the same vocabulary as one
/// checking a key length.
public enum CryptoError
{
    /// The key is not a length this algorithm takes. AES takes 16, 24 or 32
    /// bytes; an HMAC key may be any length at all, so this never comes from
    /// one.
    KeyLength,

    /// The initialization vector is not one block long.
    IvLength,

    /// The nonce is not a length this mode takes. AES-GCM takes any non-empty
    /// nonce and wants twelve bytes; ChaCha20 takes twelve and nothing else.
    NonceLength,

    /// The authentication tag is not a length this mode produces.
    TagLength,

    /// The input is not a whole number of blocks, and the padding mode in
    /// force does not add any.
    BlockLength,

    /// The padding on a decrypted block does not describe itself. Usually the
    /// wrong key, and deliberately says no more than that.
    Padding,

    /// The tag did not match. **The plaintext is not returned**, because a
    /// plaintext that failed authentication is attacker-controlled and
    /// handling it at all is the mistake AEAD exists to prevent.
    AuthenticationFailed,

    /// A parameter outside the range the algorithm defines: an iteration count
    /// or an output length of zero, a salt too short, a cost that is not a
    /// power of two or asks for more memory than is allowed, or more data than
    /// a stream cipher's counter covers.
    Parameter,

    /// The platform would not supply entropy.
    NoEntropy,

    /// A key that is the right length and still not a key: an RSA modulus
    /// that is even or too small, a private key whose parts disagree, a
    /// scalar of zero or not below the group order, or a Diffie-Hellman
    /// result that is the identity.
    InvalidKey,

    /// A signature that does not verify, or is not a well-formed signature
    /// at all. The two are deliberately not told apart.
    InvalidSignature,

    /// A point that is not on the curve, is the point at infinity where one
    /// is not allowed, or is encoded in a form this does not read.
    InvalidPoint,

    /// A key or signature whose DER, PEM or other encoding does not parse,
    /// or parses as something other than what was asked for.
    Encoding,

    /// A message too long for the key: more than an RSA modulus can carry
    /// under the padding asked for.
    MessageLength,

    /// A well-formed request this does not implement: a curve, a hash or a
    /// padding mode it has no code for.
    Unsupported,
}
