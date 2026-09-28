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

import Standard.IO;

/// One record as read: its content type and where its content is.
///
/// A plaintext record's content is a view of the layer's input buffer, and
/// is valid only until the next read.
internal struct TlsRecord
{
    public TlsContentType Type;
    public byte[] Data;
    public nuint Offset;
    public nuint Length;
}

/// The record layer of RFC 8446 §5 over a stream: framing, the limits, and
/// protection in each direction once a key is installed.
///
/// It knows nothing of the handshake. What it is told is when a key changes
/// and whether a change_cipher_spec may be dropped; the version-specific
/// part is `TlsRecordCipher`, which TLS 1.2's explicit-nonce protection
/// would sit beside.
internal sealed class TlsRecordLayer
{
    private IStream _inner;
    private byte[] _input;
    private nuint _inputStart;
    private nuint _inputEnd;
    private TlsRecordCipher? _readCipher;
    private TlsRecordCipher? _writeCipher;

    /// The version in the header of plaintext records written. A first
    /// ClientHello goes out under 0x0301, for old middleboxes.
    internal uint _plaintextVersion;

    /// Whether a plaintext change_cipher_spec is dropped rather than
    /// refused: from the first ClientHello until the peer's Finished.
    internal bool _changeCipherSpecAllowed;

    /// Whether a plaintext alert is taken although a read key is installed:
    /// a peer that failed to read the other's ServerHello has no key to
    /// protect its alert with.
    internal bool _plaintextAlertAllowed;

    internal TlsRecordLayer(IStream inner)
    {
        _inner = inner;
        _input = new byte[2u * (TlsRecordHeaderSize + TlsMaxCiphertext)];
        _inputStart = 0u;
        _inputEnd = 0u;
        _readCipher = null;
        _writeCipher = null;
        _plaintextVersion = TlsLegacyVersion;
        _changeCipherSpecAllowed = false;
        _plaintextAlertAllowed = true;
    }

    internal IStream Inner => _inner;

    internal bool IsReadProtected => _readCipher != null;

    /// Records written under the current write key.
    internal ulong WriteSequence
    {
        get
        {
            var cipher = _writeCipher;
            if (cipher == null)
                return 0u;
            return cipher.Sequence;
        }
    }

    internal void InstallTlsReadCipher(TlsRecordCipher cipher) => _readCipher = cipher;

    internal void InstallTlsWriteCipher(TlsRecordCipher cipher) => _writeCipher = cipher;

    /// Bytes read from the stream and not yet taken as records.
    internal nuint BufferedInput => _inputEnd - _inputStart;

    // ---------------------------------------------------------------- reading

    /// The next record that is not a dropped change_cipher_spec.
    internal Result<TlsRecord, TlsError> ReadTlsRecord()
    {
        while (true)
        {
            TlsError filled = FillTlsInput(TlsRecordHeaderSize);
            if (filled != TlsError.None)
                return Fail(filled);

            nuint at = _inputStart;
            var type = (TlsContentType)_input[at];
            nuint length = ((nuint)_input[at + 3u] << 8) | (nuint)_input[at + 4u];

            switch (type)
            {
                case TlsContentType.ChangeCipherSpec:
                case TlsContentType.Alert:
                case TlsContentType.Handshake:
                    if (length > TlsMaxPlaintext)
                        return Fail(TlsError.RecordOverflow);
                    break;
                case TlsContentType.ApplicationData:
                    if (length > TlsMaxCiphertext)
                        return Fail(TlsError.RecordOverflow);
                    break;
                default:
                    return Fail(TlsError.UnexpectedMessage);
            }

            filled = FillTlsInput(TlsRecordHeaderSize + length);
            if (filled != TlsError.None)
                return Fail(filled);
            at = _inputStart;
            _inputStart += TlsRecordHeaderSize + length;
            nuint body = at + TlsRecordHeaderSize;

            var cipher = _readCipher;
            if (type == TlsContentType.ChangeCipherSpec)
            {
                if (!_changeCipherSpecAllowed || length != 1u || _input[body] != 1)
                    return Fail(TlsError.UnexpectedMessage);
                continue;
            }

            if (type != TlsContentType.ApplicationData)
            {
                if (length == 0u)
                    return Fail(TlsError.UnexpectedMessage);
                if (cipher != null && !(type == TlsContentType.Alert && _plaintextAlertAllowed))
                    return Fail(TlsError.UnexpectedMessage);

                TlsRecord plain;
                plain.Type = type;
                plain.Data = _input;
                plain.Offset = body;
                plain.Length = length;
                return Ok(plain);
            }

            if (cipher == null)
                return Fail(TlsError.UnexpectedMessage);
            var opened = cipher.OpenTlsRecord(_input, at, length);
            if (!opened.Ok)
                return Fail(opened.Error);
            return UnwrapTlsInnerPlaintext(opened.Value);
        }
    }

    /// The content type and content of a TLSInnerPlaintext: the last nonzero
    /// byte is the type, and the zeros after it are padding.
    ///
    /// The scan covers every byte and chooses by mask rather than by branch,
    /// so its time depends on the record's length and not on how much of it
    /// was padding.
    private Result<TlsRecord, TlsError> UnwrapTlsInnerPlaintext(byte[] inner)
    {
        if (inner.Length > TlsMaxPlaintext + 1u)
            return Fail(TlsError.RecordOverflow);

        ulong last = 0u;
        ulong found = 0u;
        for (nuint i = 0u; i < inner.Length; i++)
        {
            ulong nonzero = ((ulong)inner[i] + 0xFFu) >> 8;
            ulong mask = 0u - nonzero;
            last = (last & ~mask) | ((ulong)i & mask);
            found |= nonzero;
        }
        if (found == 0u)
            return Fail(TlsError.UnexpectedMessage);

        var type = (TlsContentType)inner[(nuint)last];
        nuint length = (nuint)last;
        switch (type)
        {
            case TlsContentType.ApplicationData:
                break;
            case TlsContentType.Alert:
            case TlsContentType.Handshake:
                if (length == 0u)
                    return Fail(TlsError.UnexpectedMessage);
                break;
            default:
                return Fail(TlsError.UnexpectedMessage);
        }

        TlsRecord record;
        record.Type = type;
        record.Data = inner;
        record.Offset = 0u;
        record.Length = length;
        return Ok(record);
    }

    /// Reads from the stream until `count` bytes are buffered.
    private TlsError FillTlsInput(nuint count)
    {
        if (_inputEnd - _inputStart >= count)
            return TlsError.None;

        if (_inputStart + count > _input.Length)
        {
            nuint held = _inputEnd - _inputStart;
            if (held > 0u)
                memmove(&_input[0u], &_input[_inputStart], held);
            _inputStart = 0u;
            _inputEnd = held;
        }

        while (_inputEnd - _inputStart < count)
        {
            nuint got = _inner.Read(_input, _inputEnd, _input.Length - _inputEnd);
            if (got == 0u)
                return _inner.Error == IOError.None ? TlsError.Closed : TlsError.Io;
            _inputEnd += got;
        }
        return TlsError.None;
    }

    // ---------------------------------------------------------------- writing

    /// Writes `length` bytes of `data` from `offset` as records of `type`,
    /// each carrying at most 2^14 bytes, protected when a write key is
    /// installed.
    internal TlsError WriteTlsRecords(TlsContentType type, byte[] data, nuint offset, nuint length)
    {
        nuint done = 0u;
        while (done < length)
        {
            nuint chunk = length - done;
            if (chunk > TlsMaxPlaintext)
                chunk = TlsMaxPlaintext;
            TlsError written = WriteTlsRecord(type, data, offset + done, chunk);
            if (written != TlsError.None)
                return written;
            done += chunk;
        }
        return TlsError.None;
    }

    private TlsError WriteTlsRecord(TlsContentType type, byte[] data, nuint offset, nuint length)
    {
        var cipher = _writeCipher;
        if (cipher == null)
        {
            var plain = new byte[TlsRecordHeaderSize + length];
            plain[0u] = (byte)type;
            plain[1u] = (byte)(_plaintextVersion >> 8);
            plain[2u] = (byte)(_plaintextVersion & 0xFFu);
            plain[3u] = (byte)(length >> 8);
            plain[4u] = (byte)(length & 0xFFu);
            if (length > 0u)
                memcpy(&plain[TlsRecordHeaderSize], &data[offset], length);
            return WriteAllTlsBytes(plain);
        }

        var inner = new byte[length + 1u];
        if (length > 0u)
            memcpy(&inner[0u], &data[offset], length);
        inner[length] = (byte)type;
        var protectedRecord = cipher.SealTlsRecord(inner, length + 1u);
        if (!protectedRecord.Ok)
            return protectedRecord.Error;
        return WriteAllTlsBytes(protectedRecord.Value);
    }

    /// The compatibility change_cipher_spec of RFC 8446 Appendix D.4, which
    /// is never protected.
    internal TlsError WriteTlsChangeCipherSpec()
    {
        var record = new byte[6u];
        record[0u] = (byte)TlsContentType.ChangeCipherSpec;
        record[1u] = 0x03;
        record[2u] = 0x03;
        record[3u] = 0;
        record[4u] = 1;
        record[5u] = 1;
        return WriteAllTlsBytes(record);
    }

    private TlsError WriteAllTlsBytes(byte[] bytes)
    {
        nuint done = 0u;
        while (done < bytes.Length)
        {
            nuint wrote = _inner.Write(bytes, done, bytes.Length - done);
            if (wrote == 0u)
                return TlsError.Io;
            done += wrote;
        }
        return TlsError.None;
    }
}
