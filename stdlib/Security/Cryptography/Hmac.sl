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

// ===================================================== message authentication

/// HMAC over any hash: RFC 2104, and .NET's `HMACSHA256` and its siblings.
///
/// A hash is not a MAC. `Sha256.HashData(key + message)` can be extended by
/// anyone who has the digest and not the key, because the digest *is* the
/// state; this is the construction that fixes that, and it is what every
/// protocol means when it says "keyed hash".
///
/// Any key length works. A key longer than the hash's block is replaced by its
/// digest, a shorter one is padded with zeros, and both of those are the
/// standard's rules rather than a convenience.
public sealed class Hmac : IHashAlgorithm
{
    IHashAlgorithm _inner;
    byte[] _innerPad;
    byte[] _outerPad;
    String _name;

    /// `hash` is used for both passes and is left reset. It belongs to this
    /// object afterwards: appending to it from outside would corrupt the MAC.
    public Hmac(IHashAlgorithm hash, byte[:] key)
    {
        _inner = hash;
        _name = "HMAC-" + hash.Name;

        nuint blockSize = hash.BlockSizeInBytes;
        byte[] shortened = new byte[blockSize];

        if (key.Length > blockSize)
        {
            hash.Reset();
            hash.AppendData(key);
            byte[] digest = hash.GetHashAndReset();
            for (nuint i = 0u; i < digest.Length; i++)
                shortened[i] = digest[i];
        }
        else
        {
            for (nuint i = 0u; i < key.Length; i++)
                shortened[i] = key[i];
        }

        _innerPad = new byte[blockSize];
        _outerPad = new byte[blockSize];
        for (nuint i = 0u; i < blockSize; i++)
        {
            _innerPad[i] = (byte)(shortened[i] ^ 0x36u);
            _outerPad[i] = (byte)(shortened[i] ^ 0x5Cu);
        }

        CryptographicOperations.ZeroMemory(shortened);
        Reset();
    }

    public String Name => _name;

    public nuint HashSizeInBytes => _inner.HashSizeInBytes;

    public nuint BlockSizeInBytes => _inner.BlockSizeInBytes;

    public void AppendData(byte[:] data) => _inner.AppendData(data);

    public byte[] GetHashAndReset()
    {
        byte[] first = _inner.GetHashAndReset();
        _inner.AppendData(_outerPad);
        _inner.AppendData(first);
        byte[] mac = _inner.GetHashAndReset();
        Reset();
        return mac;
    }

    public void Reset()
    {
        _inner.Reset();
        _inner.AppendData(_innerPad);
    }

    /// The MAC of `data` under `key`, with no object to keep.
    public byte[] ComputeHash(byte[:] data)
    {
        Reset();
        AppendData(data);
        return GetHashAndReset();
    }
}
