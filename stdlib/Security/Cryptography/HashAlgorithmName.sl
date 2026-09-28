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

/// Which hash a signature or a key derivation uses, as .NET's
/// `HashAlgorithmName` names it.
///
/// ```csharp
/// var signature = try key.SignData(message, HashAlgorithmName.Sha256);
/// ```
///
/// The zero value names no hash, and everything given it answers
/// `CryptoError.Unsupported`.
public struct HashAlgorithmName
{
    private int _kind;

    HashAlgorithmName(int kind)
    {
        _kind = kind;
    }

    /// SHA-1, for verifying what older systems signed. Nothing new SHOULD be
    /// signed with it.
    public static HashAlgorithmName Sha1 => new HashAlgorithmName(1);

    /// SHA-256.
    public static HashAlgorithmName Sha256 => new HashAlgorithmName(2);

    /// SHA-384.
    public static HashAlgorithmName Sha384 => new HashAlgorithmName(3);

    /// SHA-512.
    public static HashAlgorithmName Sha512 => new HashAlgorithmName(4);

    /// The name .NET gives it — `SHA256` — and empty for the zero value.
    public String Name
    {
        get
        {
            switch (_kind)
            {
                case 1: return "SHA1";
                case 2: return "SHA256";
                case 3: return "SHA384";
                case 4: return "SHA512";
            }
            return "";
        }
    }

    /// How many bytes its digest is, and zero for the zero value.
    public nuint HashSizeInBytes
    {
        get
        {
            switch (_kind)
            {
                case 1: return 20u;
                case 2: return 32u;
                case 3: return 48u;
                case 4: return 64u;
            }
            return 0u;
        }
    }

    /// A fresh hash of this kind, to append to or to key an `Hmac` with.
    ///
    /// @failure CryptoError.Unsupported  this is the zero value
    public Result<IHashAlgorithm, CryptoError> CreateHashAlgorithm()
    {
        switch (_kind)
        {
            case 1: return Ok(new Sha1());
            case 2: return Ok(new Sha256());
            case 3: return Ok(new Sha384());
            case 4: return Ok(new Sha512());
        }
        return Fail(CryptoError.Unsupported);
    }

    public bool Equals(HashAlgorithmName other) => _kind == other._kind;

    public static bool operator ==(HashAlgorithmName left, HashAlgorithmName right) =>
        left.Equals(right);

    public static bool operator !=(HashAlgorithmName left, HashAlgorithmName right) =>
        !left.Equals(right);
}
