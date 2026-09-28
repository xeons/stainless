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

import Standard.Security.Cryptography;

/// One direction's record protection in TLS 1.3: the AEAD, its key, the
/// static IV and the sequence number that makes each nonce (RFC 8446 §5.3).
internal sealed class TlsRecordCipher
{
    private AesGcm? _aesGcm;
    private ChaCha20Poly1305? _chaCha;
    private byte[] _iv;
    private byte[] _nonce;
    private ulong _sequence;

    private TlsRecordCipher(AesGcm? aesGcm, ChaCha20Poly1305? chaCha, byte[] iv)
    {
        _aesGcm = aesGcm;
        _chaCha = chaCha;
        _iv = iv;
        _nonce = new byte[12u];
        _sequence = 0u;
    }

    /// The protection `suite` names under `key` and `iv`.
    internal static Result<TlsRecordCipher, TlsError> Create(
        TlsCipherSuite suite, byte[] key, byte[] iv)
    {
        if (suite == TlsCipherSuite.TlsChaCha20Poly1305Sha256)
        {
            var chaCha = ChaCha20Poly1305.FromKey(key);
            if (!chaCha.Ok)
                return Fail(TlsError.InternalError);
            return Ok(new TlsRecordCipher(null, chaCha.Value, iv));
        }

        var gcm = AesGcm.FromKey(key);
        if (!gcm.Ok)
            return Fail(TlsError.InternalError);
        return Ok(new TlsRecordCipher(gcm.Value, null, iv));
    }

    /// How many records this key has protected or opened.
    internal ulong Sequence => _sequence;

    /// Seals `inner` into a whole record, header and all: the header is the
    /// associated data, so it is written first.
    internal Result<byte[], TlsError> SealTlsRecord(byte[] inner, nuint innerLength)
    {
        nuint bodyLength = innerLength + TlsAeadTagSize;
        var record = new byte[TlsRecordHeaderSize + bodyLength];
        record[0u] = (byte)TlsContentType.ApplicationData;
        record[1u] = 0x03;
        record[2u] = 0x03;
        record[3u] = (byte)(bodyLength >> 8);
        record[4u] = (byte)(bodyLength & 0xFFu);

        ComputeTlsNonce();
        var tag = new byte[TlsAeadTagSize];
        ReadOnlySpan<byte> header = record[:TlsRecordHeaderSize];
        ReadOnlySpan<byte> plaintext = inner[:innerLength];

        Result<byte[], CryptoError> encrypted = Fail(CryptoError.Parameter);
        var gcm = _aesGcm;
        var chaCha = _chaCha;
        if (gcm != null)
        {
            encrypted = gcm.Encrypt(_nonce, plaintext, header, tag);
        }
        else if (chaCha != null)
        {
            encrypted = chaCha.Encrypt(_nonce, plaintext, header, tag);
        }
        if (!encrypted.Ok)
            return Fail(TlsError.InternalError);

        byte[] ciphertext = encrypted.Value;
        if (innerLength > 0u)
            memcpy(&record[TlsRecordHeaderSize], &ciphertext[0u], innerLength);
        memcpy(&record[TlsRecordHeaderSize + innerLength], &tag[0u], TlsAeadTagSize);
        _sequence++;
        return Ok(record);
    }

    /// Opens the record whose header starts at `at` in `input` and whose body
    /// is `bodyLength` bytes, answering the inner plaintext.
    internal Result<byte[], TlsError> OpenTlsRecord(byte[] input, nuint at, nuint bodyLength)
    {
        if (bodyLength < TlsAeadTagSize + 1u)
            return Fail(TlsError.BadRecordMac);

        ComputeTlsNonce();
        nuint cipherLength = bodyLength - TlsAeadTagSize;
        ReadOnlySpan<byte> header = input[at:][:TlsRecordHeaderSize];
        ReadOnlySpan<byte> ciphertext = input[at + TlsRecordHeaderSize:][:cipherLength];
        ReadOnlySpan<byte> tag = input[at + TlsRecordHeaderSize + cipherLength:][:TlsAeadTagSize];

        Result<byte[], CryptoError> opened = Fail(CryptoError.Parameter);
        var gcm = _aesGcm;
        var chaCha = _chaCha;
        if (gcm != null)
        {
            opened = gcm.Decrypt(_nonce, ciphertext, header, tag);
        }
        else if (chaCha != null)
        {
            opened = chaCha.Decrypt(_nonce, ciphertext, header, tag);
        }
        if (!opened.Ok)
            return Fail(TlsError.BadRecordMac);

        _sequence++;
        return Ok(opened.Value);
    }

    /// The per-record nonce: the sequence number, big-endian and padded on
    /// the left to the IV's length, XORed into the IV.
    private void ComputeTlsNonce()
    {
        for (nuint i = 0u; i < 4u; i++)
            _nonce[i] = _iv[i];
        for (nuint i = 0u; i < 8u; i++)
        {
            byte counter = (byte)((_sequence >> (56u - 8u * i)) & 0xFFu);
            _nonce[4u + i] = (byte)(_iv[4u + i] ^ counter);
        }
    }
}
