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

/// The buffering and the padding, which every Merkle-Damgard hash shares.
///
/// MD5, SHA-1, SHA-256, SHA-384 and SHA-512 differ in three things -- the
/// compression function, the state, and whether the length that terminates the
/// message is written big-endian -- and agree about everything else: fill a
/// block, compress it, and finish by appending a one bit, zeros, and the
/// length in bits. That is what is here, so a new algorithm of this family is
/// `CompressBlock`, `ComputeDigest` and `InitializeState` and nothing else.
public abstract class HashAlgorithm : IHashAlgorithm
{
    /// The block being filled. `BlockSizeInBytes` long, and never full on
    /// return from `AppendData` -- a block that fills is compressed at once, which
    /// is what lets `FinishHash` assume there is room for the one bit.
    protected byte[] _block;

    /// How much of `_block` is filled.
    protected nuint _used;

    /// How many bytes have been appended in total, which becomes the length
    /// field.
    protected ulong _byteCount;

    nuint _lengthBytes;
    bool _bigEndianLength;

    /// `lengthBytes` is the width of the length field: eight for the 32-bit
    /// family, sixteen for SHA-512, whose upper eight bytes are always zero
    /// here because no input reaches 2^64 bytes.
    protected HashAlgorithm(nuint blockSize, nuint lengthBytes, bool bigEndianLength)
    {
        _block = new byte[blockSize];
        _used = 0u;
        _byteCount = 0u;
        _lengthBytes = lengthBytes;
        _bigEndianLength = bigEndianLength;
    }

    public abstract String Name { get; }

    public abstract nuint HashSizeInBytes { get; }

    public nuint BlockSizeInBytes => _block.Length;

    public void AppendData(byte[:] data)
    {
        nuint at = 0u;
        while (at < data.Length)
        {
            nuint room = _block.Length - _used;
            nuint take = data.Length - at;
            if (take > room)
                take = room;

            for (nuint i = 0u; i < take; i++)
                _block[_used + i] = data[at + i];

            _used += take;
            at += take;
            _byteCount += (ulong)take;

            if (_used == _block.Length)
            {
                CompressBlock(_block);
                _used = 0u;
            }
        }
    }

    public byte[] GetHashAndReset()
    {
        byte[] digest = FinishHash();
        Reset();
        return digest;
    }

    public void Reset()
    {
        for (nuint i = 0u; i < _block.Length; i++)
            _block[i] = 0;

        _used = 0u;
        _byteCount = 0u;
        InitializeState();
    }

    /// The digest of `data` on its own. Resets first, so an object that has
    /// been appended to is still safe to ask.
    public byte[] ComputeHash(byte[:] data)
    {
        Reset();
        AppendData(data);
        return GetHashAndReset();
    }

    /// One block into the state.
    protected abstract void CompressBlock(byte[] block);

    /// The state as bytes, once the last block has been compressed.
    protected abstract byte[] ComputeDigest();

    /// The state as a fresh hash has it.
    protected abstract void InitializeState();

    /// The one bit, the zeros and the length, then the digest.
    byte[] FinishHash()
    {
        ulong bits = _byteCount * 8u;

        _block[_used] = 0x80;
        _used++;

        // The length has to fit in this block. If it does not, fill this one
        // with zeros, compress it, and put the length in the next.
        if (_used > _block.Length - _lengthBytes)
        {
            while (_used < _block.Length)
            {
                _block[_used] = 0;
                _used++;
            }

            CompressBlock(_block);
            _used = 0u;
        }

        while (_used < _block.Length - _lengthBytes)
        {
            _block[_used] = 0;
            _used++;
        }

        nuint field = _block.Length - _lengthBytes;
        for (nuint i = 0u; i < _lengthBytes; i++)
            _block[field + i] = 0;

        // Eight bytes of it either way; a sixteen-byte field's top half stays
        // zero, since `_byteCount` is a ulong and cannot fill it.
        for (nuint i = 0u; i < 8u; i++)
        {
            byte octet = (byte)((bits >> (uint)(8u * i)) & 0xFFu);
            if (_bigEndianLength)
                _block[_block.Length - 1u - i] = octet;
            else
                _block[field + i] = octet;
        }

        CompressBlock(_block);
        return ComputeDigest();
    }
}
