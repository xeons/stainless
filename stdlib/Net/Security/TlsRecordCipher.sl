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

/// One direction's record protection: the AEAD, its key, the static IV and
/// the sequence number that makes each nonce.
///
/// TLS 1.3 (RFC 8446 §5.3) XORs the sequence number into a 12-byte IV, and
/// authenticates the record header. TLS 1.2 authenticates the sequence
/// number, the type, the version and the plaintext's length (RFC 5246
/// §6.2.3.3), and makes its nonce one of two ways: ChaCha20 as TLS 1.3 does
/// (RFC 7905), and AES-GCM from 4 bytes of salt and 8 sent before the
/// ciphertext (RFC 5288). The 8 sent are the sequence number, which is
/// what the XOR gives when the salt is padded with zeros.
internal sealed class TlsRecordCipher
{
    private AesGcm? _aesGcm;
    private ChaCha20Poly1305? _chaCha;
    private byte[] _iv;
    private byte[] _nonce;
    private ulong _sequence;
    private bool _isTls12;
    private nuint _explicitNonceLength;

    private TlsRecordCipher(AesGcm? aesGcm, ChaCha20Poly1305? chaCha, byte[] iv, bool isTls12)
    {
        _aesGcm = aesGcm;
        _chaCha = chaCha;
        _iv = iv;
        _nonce = new byte[12u];
        _sequence = 0u;
        _isTls12 = isTls12;
        _explicitNonceLength = isTls12 && aesGcm != null ? Tls12ExplicitNonceLength : 0u;
    }

    /// The TLS 1.3 protection `suite` names under `key` and `iv`.
    internal static Result<TlsRecordCipher, TlsError> Create(
        TlsCipherSuite suite, byte[] key, byte[] iv) => CreateTlsRecordCipher(suite, key, iv, false);

    /// The TLS 1.2 protection `suite` names under `key` and `iv`, which is 4
    /// bytes of salt for AES-GCM and 12 for ChaCha20.
    internal static Result<TlsRecordCipher, TlsError> CreateTls12(
        TlsCipherSuite suite, byte[] key, byte[] iv)
    {
        var padded = new byte[12u];
        memcpy(&padded[0u], &iv[0u], iv.Length);
        return CreateTlsRecordCipher(suite, key, padded, true);
    }

    private static Result<TlsRecordCipher, TlsError> CreateTlsRecordCipher(
        TlsCipherSuite suite, byte[] key, byte[] iv, bool isTls12)
    {
        if (IsTlsChaChaCipherSuite(suite))
        {
            var chaCha = ChaCha20Poly1305.FromKey(key);
            if (!chaCha.Ok)
                return Fail(TlsError.InternalError);
            return Ok(new TlsRecordCipher(null, chaCha.Value, iv, isTls12));
        }

        var gcm = AesGcm.FromKey(key);
        if (!gcm.Ok)
            return Fail(TlsError.InternalError);
        return Ok(new TlsRecordCipher(gcm.Value, null, iv, isTls12));
    }

    /// Whether this is TLS 1.2's protection.
    internal bool IsTls12 => _isTls12;

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

    // ------------------------------------------------------------- TLS 1.2

    /// Seals `length` bytes of `data` from `offset` as one TLS 1.2 record of
    /// `type`, header and all.
    internal Result<byte[], TlsError> SealTls12Record(
        TlsContentType type, byte[] data, nuint offset, nuint length)
    {
        nuint bodyLength = _explicitNonceLength + length + TlsAeadTagSize;
        var record = new byte[TlsRecordHeaderSize + bodyLength];
        record[0u] = (byte)type;
        record[1u] = 0x03;
        record[2u] = 0x03;
        record[3u] = (byte)(bodyLength >> 8);
        record[4u] = (byte)(bodyLength & 0xFFu);

        ComputeTlsNonce();
        if (_explicitNonceLength > 0u)
            memcpy(&record[TlsRecordHeaderSize], &_nonce[4u], _explicitNonceLength);
        byte[] additional = BuildTls12AdditionalData(type, length);
        var tag = new byte[TlsAeadTagSize];
        ReadOnlySpan<byte> plaintext = data[offset:][:length];

        Result<byte[], CryptoError> encrypted = Fail(CryptoError.Parameter);
        var gcm = _aesGcm;
        var chaCha = _chaCha;
        if (gcm != null)
        {
            encrypted = gcm.Encrypt(_nonce, plaintext, additional, tag);
        }
        else if (chaCha != null)
        {
            encrypted = chaCha.Encrypt(_nonce, plaintext, additional, tag);
        }
        if (!encrypted.Ok)
            return Fail(TlsError.InternalError);

        byte[] ciphertext = encrypted.Value;
        nuint at = TlsRecordHeaderSize + _explicitNonceLength;
        if (length > 0u)
            memcpy(&record[at], &ciphertext[0u], length);
        memcpy(&record[at + length], &tag[0u], TlsAeadTagSize);
        _sequence++;
        return Ok(record);
    }

    /// Opens the TLS 1.2 record whose header starts at `at` in `input` and
    /// whose body is `bodyLength` bytes, answering its plaintext.
    internal Result<byte[], TlsError> OpenTls12Record(byte[] input, nuint at, nuint bodyLength)
    {
        if (bodyLength < _explicitNonceLength + TlsAeadTagSize)
            return Fail(TlsError.BadRecordMac);

        ComputeTlsNonce();
        nuint body = at + TlsRecordHeaderSize;
        if (_explicitNonceLength > 0u)
            memcpy(&_nonce[4u], &input[body], _explicitNonceLength);

        var type = (TlsContentType)input[at];
        nuint cipherLength = bodyLength - _explicitNonceLength - TlsAeadTagSize;
        byte[] additional = BuildTls12AdditionalData(type, cipherLength);
        ReadOnlySpan<byte> ciphertext = input[body + _explicitNonceLength:][:cipherLength];
        ReadOnlySpan<byte> tag = input[body + _explicitNonceLength + cipherLength:][:TlsAeadTagSize];

        Result<byte[], CryptoError> opened = Fail(CryptoError.Parameter);
        var gcm = _aesGcm;
        var chaCha = _chaCha;
        if (gcm != null)
        {
            opened = gcm.Decrypt(_nonce, ciphertext, additional, tag);
        }
        else if (chaCha != null)
        {
            opened = chaCha.Decrypt(_nonce, ciphertext, additional, tag);
        }
        if (!opened.Ok)
            return Fail(TlsError.BadRecordMac);

        _sequence++;
        return Ok(opened.Value);
    }

    /// The 13 bytes a TLS 1.2 AEAD authenticates beside the plaintext: the
    /// sequence number, the type, the version and the plaintext's length.
    private byte[] BuildTls12AdditionalData(TlsContentType type, nuint length)
    {
        var additional = new byte[13u];
        for (nuint i = 0u; i < 8u; i++)
            additional[i] = (byte)((_sequence >> (56u - 8u * i)) & 0xFFu);
        additional[8u] = (byte)type;
        additional[9u] = 0x03;
        additional[10u] = 0x03;
        additional[11u] = (byte)(length >> 8);
        additional[12u] = (byte)(length & 0xFFu);
        return additional;
    }

    // -------------------------------------------------------------- nonces

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
