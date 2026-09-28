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

/// How an RSA ciphertext is encoded: OAEP with a hash and a label, or
/// PKCS #1 v1.5.
///
/// .NET's `RSAEncryptionPadding`, as a value. OAEP masks with MGF1 over the
/// same hash that digests the label, which is the only combination .NET
/// offers.
///
/// @see Rsa.Encrypt
public struct RsaEncryptionPadding
{
    private RsaEncryptionPaddingMode _mode;
    private HashAlgorithmName _oaepHashAlgorithm;
    private byte[] _oaepLabel;

    RsaEncryptionPadding(RsaEncryptionPaddingMode mode, HashAlgorithmName hash, byte[] label)
    {
        _mode = mode;
        _oaepHashAlgorithm = hash;
        _oaepLabel = label;
    }

    /// PKCS #1 v1.5.
    public static RsaEncryptionPadding Pkcs1 =>
        new RsaEncryptionPadding(RsaEncryptionPaddingMode.Pkcs1, new HashAlgorithmName(""),
                                 new byte[0u]);

    /// OAEP over SHA-1, which is still sound here: OAEP needs the hash to be
    /// one-way, not collision-resistant.
    public static RsaEncryptionPadding OaepSha1 => CreateOaep(HashAlgorithmName.Sha1);

    /// OAEP over SHA-256.
    public static RsaEncryptionPadding OaepSha256 => CreateOaep(HashAlgorithmName.Sha256);

    /// OAEP over SHA-384.
    public static RsaEncryptionPadding OaepSha384 => CreateOaep(HashAlgorithmName.Sha384);

    /// OAEP over SHA-512.
    public static RsaEncryptionPadding OaepSha512 => CreateOaep(HashAlgorithmName.Sha512);

    /// Which encoding.
    public RsaEncryptionPaddingMode Mode => _mode;

    /// The hash OAEP uses for the label and for MGF1. An empty name for
    /// PKCS #1 v1.5.
    public HashAlgorithmName OaepHashAlgorithm => _oaepHashAlgorithm;

    /// The OAEP label, empty unless one was given.
    public byte[] OaepLabel => _oaepLabel;

    /// OAEP over `hashAlgorithm`, with an empty label.
    public static RsaEncryptionPadding CreateOaep(HashAlgorithmName hashAlgorithm) =>
        new RsaEncryptionPadding(RsaEncryptionPaddingMode.Oaep, hashAlgorithm, new byte[0u]);

    /// OAEP over `hashAlgorithm`, bound to `label`: a ciphertext decrypts only
    /// under the label it was made with. The label is not secret and is not
    /// carried in the ciphertext.
    ///
    /// @param hashAlgorithm  the hash for the label and for MGF1
    /// @param label          any bytes, copied
    public static RsaEncryptionPadding CreateOaep(HashAlgorithmName hashAlgorithm,
                                                  ReadOnlySpan<byte> label) =>
        new RsaEncryptionPadding(RsaEncryptionPaddingMode.Oaep, hashAlgorithm, label.ToArray());
}
