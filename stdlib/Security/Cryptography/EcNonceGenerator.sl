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

/// The deterministic nonces of RFC 6979 §3.2: HMAC-DRBG seeded with the
/// private key and the hash.
///
/// Every candidate runs the same HMACs whatever the key is. A candidate
/// outside `[1, n - 1]` is discarded and the next drawn, which reveals only
/// that a number nobody will use was out of range.
sealed class EcNonceGenerator
{
    private HashAlgorithmName _hash;
    private byte[] _key;
    private byte[] _value;
    private EcElement _order;
    private nuint _size;
    private bool _drawn;

    public EcNonceGenerator(EcElement privateScalar, EcElement digest, HashAlgorithmName hash,
                            EcElement order, nuint size)
    {
        _hash = hash;
        _order = order;
        _size = size;

        nuint length = hash.HashSizeInBytes;
        _key = new byte[length];
        _value = new byte[length];
        for (nuint i = 0u; i < length; i++)
            _value[i] = 0x01;

        byte[] seed = new byte[2u * size];
        WriteEcElement(privateScalar, size, seed, 0u);
        WriteEcElement(digest, size, seed, size);

        ReplaceKey(ComputeMac(0x00, seed));
        ReplaceValue(ComputeMac(_value));
        ReplaceKey(ComputeMac(0x01, seed));
        ReplaceValue(ComputeMac(_value));
        CryptographicOperations.ZeroMemory(seed);
    }

    ~EcNonceGenerator()
    {
        CryptographicOperations.ZeroMemory(_key);
        CryptographicOperations.ZeroMemory(_value);
    }

    /// The next nonce in `[1, n - 1]`.
    public EcElement GenerateNonce()
    {
        byte[] candidate = new byte[_size];
        while (true)
        {
            if (_drawn)
            {
                ReplaceKey(ComputeMac(0x00, new byte[0u]));
                ReplaceValue(ComputeMac(_value));
            }
            _drawn = true;

            nuint filled = 0u;
            while (filled < _size)
            {
                ReplaceValue(ComputeMac(_value));
                nuint take = _size - filled < _value.Length ? _size - filled : _value.Length;
                _value[:take].CopyTo(candidate[filled:]);
                filled += take;
            }

            EcElement nonce = ReadEcElement(candidate);
            ulong below = ComputeEcElementBelow(nonce, _order);
            ulong zero = ComputeEcElementZeroMask(nonce) & 1u;
            if ((below & (zero ^ 1u)) != 0u)
            {
                CryptographicOperations.ZeroMemory(candidate);
                return nonce;
            }
        }
    }

    /// `key` in place of K, with the old K overwritten.
    void ReplaceKey(byte[] key)
    {
        CryptographicOperations.ZeroMemory(_key);
        _key = key;
    }

    /// `value` in place of V, with the old V overwritten.
    void ReplaceValue(byte[] value)
    {
        CryptographicOperations.ZeroMemory(_value);
        _value = value;
    }

    /// `HMAC_K(V || separator || material)`.
    byte[] ComputeMac(byte separator, ReadOnlySpan<byte> material)
    {
        var mac = CreateMac();
        mac.AppendData(_value);
        byte[] one = [separator];
        mac.AppendData(one);
        mac.AppendData(material);
        return mac.GetHashAndReset();
    }

    /// `HMAC_K(data)`.
    byte[] ComputeMac(ReadOnlySpan<byte> data)
    {
        var mac = CreateMac();
        mac.AppendData(data);
        return mac.GetHashAndReset();
    }

    /// HMAC under `K`. The constructor's caller has already refused a hash
    /// that cannot be made, so SHA-256 is never the one used.
    Hmac CreateMac()
    {
        var hash = _hash.CreateHashAlgorithm();
        return new Hmac(hash.Ok ? hash.Value : new Sha256(), _key);
    }
}
