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

import Standard.Collections;
import Standard.IO;
import Standard.Threading;

/// Everything a TLS connection is once the record layer is under it: the
/// handshake messages it reassembles, the alerts, the application data, and
/// the post-handshake messages. The handshakes fill it in; `TlsStream` is its
/// public face.
///
/// **One reader and one writer MAY use it at once**, as with .NET's
/// `SslStream`. Every record written goes under one lock, because a read can
/// write too: an alert, or the answer to a KeyUpdate.
internal sealed class TlsConnection
{
    internal TlsRecordLayer _records;
    internal bool _isServer;
    internal bool _leaveInnerStreamOpen;

    private TlsBuffer _handshakeInput;
    private TlsBuffer _handshakeOutput;
    private Mutex<int> _writeLock;

    // What the handshake settled.
    internal bool _handshakeComplete;
    internal TlsCipherSuite _cipherSuite;
    internal TlsNamedGroup _group;
    internal TlsSignatureScheme _signatureScheme;
    internal String? _applicationProtocol;
    internal String _targetHost;
    internal List<byte[]> _remoteChain;
    internal bool _mutuallyAuthenticated;
    internal TlsKeySchedule? _schedule;
    internal byte[] _readTrafficSecret;
    internal byte[] _writeTrafficSecret;
    internal TlsSessionTicketHandler _ticketHandler;

    // How it ended, or is ending.
    internal TlsError _error;
    internal TlsAlertDescription _alertReceived;
    private bool _alertSent;
    private bool _closeNotifyReceived;
    private bool _closed;
    private bool _keyUpdateOwed;

    // Application data read and not yet handed out.
    private byte[] _plaintext;
    private nuint _plaintextOffset;
    private nuint _plaintextLength;

    internal TlsConnection(IStream inner, bool isServer, bool leaveInnerStreamOpen)
    {
        _records = new TlsRecordLayer(inner);
        _isServer = isServer;
        _leaveInnerStreamOpen = leaveInnerStreamOpen;
        _handshakeInput = new TlsBuffer(4096u);
        _handshakeOutput = new TlsBuffer(4096u);
        _writeLock = new Mutex<int>(0);
        _handshakeComplete = false;
        _cipherSuite = TlsCipherSuite.TlsAes128GcmSha256;
        _group = TlsNamedGroup.X25519;
        _signatureScheme = TlsSignatureScheme.Ed25519;
        _applicationProtocol = null;
        _targetHost = "";
        _remoteChain = new List<byte[]>();
        _mutuallyAuthenticated = false;
        _schedule = null;
        _readTrafficSecret = new byte[0u];
        _writeTrafficSecret = new byte[0u];
        _ticketHandler = DiscardTlsSessionTicket;
        _error = TlsError.None;
        _alertReceived = TlsAlertDescription.CloseNotify;
        _alertSent = false;
        _closeNotifyReceived = false;
        _closed = false;
        _keyUpdateOwed = false;
        _plaintext = new byte[0u];
        _plaintextOffset = 0u;
        _plaintextLength = 0u;
    }

    internal IStream Inner => _records.Inner;

    internal bool IsClosed => _closed;

    // ------------------------------------------------------------- handshake

    /// The next whole handshake message, header and all, reassembled from as
    /// many records as it took.
    internal Result<byte[], TlsError> ReadTlsHandshakeMessage()
    {
        while (true)
        {
            var message = TakeTlsHandshakeMessage();
            if (!message.Ok)
                return Fail(message.Error);
            if (message.Value.Length > 0u)
                return message;

            var record = _records.ReadTlsRecord();
            if (!record.Ok)
                return Fail(record.Error);
            TlsRecord got = record.Value;

            switch (got.Type)
            {
                case TlsContentType.Handshake:
                    _handshakeInput.WriteArray(got.Data, got.Offset, got.Length);
                    break;
                case TlsContentType.Alert:
                {
                    if (_handshakeInput.Length > 0u)
                        return Fail(TlsError.UnexpectedMessage);
                    TlsError alerted = ProcessTlsAlert(got);
                    if (alerted != TlsError.None)
                        return Fail(alerted);
                    break;
                }
                default:
                    return Fail(TlsError.UnexpectedMessage);
            }
        }
    }

    /// A whole message from the reassembly buffer, or an empty array when
    /// there is not one yet.
    private Result<byte[], TlsError> TakeTlsHandshakeMessage()
    {
        nuint held = _handshakeInput.Length;
        if (held < 4u)
            return Ok(new byte[0u]);

        byte[] bytes = _handshakeInput.Storage;
        nuint length = ((nuint)bytes[1u] << 16) | ((nuint)bytes[2u] << 8) | (nuint)bytes[3u];
        if (length > TlsMaxHandshakeMessage)
            return Fail(TlsError.Decode);
        if (held < 4u + length)
            return Ok(new byte[0u]);

        var message = new byte[4u + length];
        memcpy(&message[0u], &bytes[0u], 4u + length);
        _handshakeInput.RemoveFront(4u + length);
        return Ok(message);
    }

    /// Refuses a handshake message that runs on past a change of key: RFC
    /// 8446 §5.1 requires each key change to fall at a record boundary.
    internal TlsError RequireTlsRecordBoundary()
    {
        if (_handshakeInput.Length != 0u)
            return TlsError.UnexpectedMessage;
        return TlsError.None;
    }

    /// Adds a message to the flight being built. `FlushTlsHandshake` sends
    /// the flight in as few records as it fits in.
    internal void QueueTlsHandshakeMessage(ReadOnlySpan<byte> message) =>
        _handshakeOutput.WriteBytes(message);

    internal TlsError FlushTlsHandshake()
    {
        if (_handshakeOutput.Length == 0u)
            return TlsError.None;
        var held = _writeLock.Enter();
        TlsError written = _records.WriteTlsRecords(TlsContentType.Handshake, _handshakeOutput.Storage,
                                                    0u, _handshakeOutput.Length);
        _handshakeOutput.Clear();
        return written;
    }

    internal TlsError WriteTlsChangeCipherSpec()
    {
        var held = _writeLock.Enter();
        return _records.WriteTlsChangeCipherSpec();
    }

    internal void InstallTlsWriteCipher(TlsRecordCipher cipher)
    {
        var held = _writeLock.Enter();
        _records.InstallTlsWriteCipher(cipher);
    }

    // ---------------------------------------------------------------- alerts

    /// Records `error` and tells the peer, when there is an alert for it and
    /// nothing has been said yet. Answers `error`, for a `return`.
    internal TlsError FailTls(TlsError error)
    {
        if (_error == TlsError.None)
            _error = error;
        if (MapTlsErrorToAlert(error, out TlsAlertDescription alert) && !_alertSent)
            SendTlsAlert(alert);
        return error;
    }

    private void SendTlsAlert(TlsAlertDescription description)
    {
        var held = _writeLock.Enter();
        if (_alertSent)
            return;
        _alertSent = true;

        var alert = new byte[2u];
        alert[0u] = description == TlsAlertDescription.CloseNotify ? (byte)1 : (byte)2;
        alert[1u] = (byte)description;
        _records.WriteTlsRecords(TlsContentType.Alert, alert, 0u, 2u);
    }

    /// Reads an alert: `None` for one that is not the end of anything,
    /// `Closed` for close_notify, and `AlertReceived` for the rest.
    private TlsError ProcessTlsAlert(TlsRecord record)
    {
        if (record.Length != 2u)
            return TlsError.Decode;

        var description = (TlsAlertDescription)record.Data[record.Offset + 1u];
        switch (description)
        {
            case TlsAlertDescription.UserCanceled:
                return TlsError.None;
            case TlsAlertDescription.CloseNotify:
                _closeNotifyReceived = true;
                if (!_handshakeComplete)
                {
                    _alertReceived = description;
                    _error = TlsError.AlertReceived;
                    return TlsError.AlertReceived;
                }
                return TlsError.Closed;
            default:
                _alertReceived = description;
                _alertSent = true;
                if (_error == TlsError.None)
                    _error = TlsError.AlertReceived;
                return TlsError.AlertReceived;
        }
    }

    // ------------------------------------------------------ application data

    /// Up to `count` bytes of application data, blocking until some arrive.
    /// Zero at close_notify, and zero with `_error` set on a failure.
    internal nuint ReadTlsApplicationData(byte[] buffer, nuint offset, nuint count)
    {
        if (count == 0u || _closed)
            return 0u;

        while (_plaintextLength == 0u)
        {
            if (_closeNotifyReceived || _error != TlsError.None)
                return 0u;

            var record = _records.ReadTlsRecord();
            if (!record.Ok)
            {
                FailTls(record.Error);
                return 0u;
            }
            TlsRecord got = record.Value;

            switch (got.Type)
            {
                case TlsContentType.ApplicationData:
                    if (_handshakeInput.Length > 0u)
                    {
                        FailTls(TlsError.UnexpectedMessage);
                        return 0u;
                    }
                    _plaintext = got.Data;
                    _plaintextOffset = got.Offset;
                    _plaintextLength = got.Length;
                    break;

                case TlsContentType.Alert:
                {
                    TlsError alerted = ProcessTlsAlert(got);
                    if (alerted == TlsError.Closed)
                        return 0u;
                    if (alerted != TlsError.None)
                    {
                        FailTls(alerted);
                        return 0u;
                    }
                    break;
                }

                case TlsContentType.Handshake:
                {
                    _handshakeInput.WriteArray(got.Data, got.Offset, got.Length);
                    TlsError processed = ProcessTlsPostHandshakeMessages();
                    if (processed != TlsError.None)
                    {
                        FailTls(processed);
                        return 0u;
                    }
                    break;
                }

                default:
                    FailTls(TlsError.UnexpectedMessage);
                    return 0u;
            }
        }

        nuint taking = count < _plaintextLength ? count : _plaintextLength;
        memcpy(&buffer[offset], &_plaintext[_plaintextOffset], taking);
        _plaintextOffset += taking;
        _plaintextLength -= taking;
        return taking;
    }

    /// Writes all of `count` bytes as application data. Answers `count`, or
    /// zero with `_error` set.
    internal nuint WriteTlsApplicationData(byte[] buffer, nuint offset, nuint count)
    {
        if (_closed || _error != TlsError.None)
            return 0u;
        if (count == 0u)
            return 0u;

        nuint done = 0u;
        while (done < count)
        {
            TlsError updated = UpdateTlsWriteKeyWhenDue();
            if (updated != TlsError.None)
            {
                FailTls(updated);
                return 0u;
            }

            // A key update is due at most every few million records, so the
            // run between checks can be long; 64 records keeps the check
            // cheap and the limit exact enough.
            nuint chunk = count - done;
            if (chunk > 64u * TlsMaxPlaintext)
                chunk = 64u * TlsMaxPlaintext;

            TlsError written = WriteTlsRecordsUnderLock(TlsContentType.ApplicationData, buffer,
                                                        offset + done, chunk);
            if (written != TlsError.None)
            {
                _error = written;
                return 0u;
            }
            done += chunk;
        }
        return count;
    }

    private TlsError WriteTlsRecordsUnderLock(TlsContentType type, byte[] data, nuint offset,
                                              nuint length)
    {
        var held = _writeLock.Enter();
        return _records.WriteTlsRecords(type, data, offset, length);
    }

    // ---------------------------------------------------- after the handshake

    private TlsError ProcessTlsPostHandshakeMessages()
    {
        while (true)
        {
            var message = TakeTlsHandshakeMessage();
            if (!message.Ok)
                return message.Error;
            byte[] bytes = message.Value;
            if (bytes.Length == 0u)
                return TlsError.None;

            var type = (TlsHandshakeType)bytes[0u];
            var reader = new TlsReader(bytes, 4u, bytes.Length - 4u);
            switch (type)
            {
                case TlsHandshakeType.KeyUpdate:
                {
                    TlsError updated = ProcessTlsKeyUpdate(reader);
                    if (updated != TlsError.None)
                        return updated;
                    break;
                }
                case TlsHandshakeType.NewSessionTicket:
                {
                    if (_isServer)
                        return TlsError.UnexpectedMessage;
                    TlsError taken = ProcessTlsNewSessionTicket(reader);
                    if (taken != TlsError.None)
                        return taken;
                    break;
                }
                default:
                    return TlsError.UnexpectedMessage;
            }
        }
    }

    private TlsError ProcessTlsKeyUpdate(TlsReader reader)
    {
        uint requested = reader.ReadByte();
        if (reader.Failed || !reader.IsAtEnd)
            return TlsError.Decode;
        if (requested > 1u)
            return TlsError.IllegalParameter;
        TlsError boundary = RequireTlsRecordBoundary();
        if (boundary != TlsError.None)
            return boundary;

        var schedule = _schedule;
        if (schedule == null)
            return TlsError.InternalError;
        _readTrafficSecret = schedule.UpdateTlsTrafficSecret(_readTrafficSecret);
        var cipher = schedule.CreateTlsRecordCipher(_cipherSuite, _readTrafficSecret);
        if (!cipher.Ok)
            return cipher.Error;
        _records.InstallTlsReadCipher(cipher.Value);

        // One answer for any number of requests received while silent.
        if (requested == 1u)
            _keyUpdateOwed = true;
        return TlsError.None;
    }

    private TlsError ProcessTlsNewSessionTicket(TlsReader reader)
    {
        uint lifetime = reader.ReadUInt32();
        uint ageAdd = reader.ReadUInt32();
        byte[] nonce = reader.ReadVectorArray(1u, 0u, 255u);
        byte[] ticket = reader.ReadVectorArray(2u, 1u, 65535u);
        TlsReader extensions = reader.ReadVector(2u, 0u, 65534u);
        if (reader.Failed || !reader.IsAtEnd)
            return TlsError.Decode;
        if (lifetime > 604800u)
            return TlsError.IllegalParameter;

        uint maxEarlyData = 0u;
        var seen = new List<uint>();
        while (!extensions.IsAtEnd)
        {
            uint type = extensions.ReadUInt16();
            TlsReader data = extensions.ReadVector(2u, 0u, 65535u);
            if (extensions.Failed)
                return TlsError.Decode;
            if (seen.Contains(type))
                return TlsError.IllegalParameter;
            seen.Add(type);

            if (type == (uint)TlsExtensionType.EarlyData)
            {
                maxEarlyData = data.ReadUInt32();
                if (data.Failed || !data.IsAtEnd)
                    return TlsError.Decode;
            }
        }

        var schedule = _schedule;
        if (schedule == null)
            return TlsError.InternalError;
        byte[] key = schedule.DeriveTlsResumptionKey(nonce);
        _ticketHandler(new TlsSessionTicket(_cipherSuite, _targetHost, lifetime, ageAdd, nonce,
                                            ticket, key, maxEarlyData));
        return TlsError.None;
    }

    /// Sends a KeyUpdate and moves to the next write key, when the peer
    /// asked for one or the key has protected as much as it safely can.
    private TlsError UpdateTlsWriteKeyWhenDue()
    {
        if (!_keyUpdateOwed && _records.WriteSequence < TlsKeyUsageLimit)
            return TlsError.None;
        _keyUpdateOwed = false;
        return SendTlsKeyUpdate(false);
    }

    /// Sends a KeyUpdate, asking the peer to update too when
    /// `requestPeerUpdate`, and moves this side to its next write key.
    internal TlsError SendTlsKeyUpdate(bool requestPeerUpdate)
    {
        if (!_handshakeComplete || _closed || _error != TlsError.None)
            return TlsError.Closed;
        var schedule = _schedule;
        if (schedule == null)
            return TlsError.InternalError;

        var message = new byte[5u];
        message[0u] = (byte)TlsHandshakeType.KeyUpdate;
        message[3u] = 1;
        message[4u] = requestPeerUpdate ? (byte)1 : (byte)0;

        var held = _writeLock.Enter();
        TlsError written = _records.WriteTlsRecords(TlsContentType.Handshake, message, 0u, 5u);
        if (written != TlsError.None)
            return written;

        _writeTrafficSecret = schedule.UpdateTlsTrafficSecret(_writeTrafficSecret);
        var cipher = schedule.CreateTlsRecordCipher(_cipherSuite, _writeTrafficSecret);
        if (!cipher.Ok)
            return cipher.Error;
        _records.InstallTlsWriteCipher(cipher.Value);
        return TlsError.None;
    }

    // ---------------------------------------------------------------- closing

    /// Sends close_notify, unless an alert has already ended the connection,
    /// and closes the stream underneath unless it is to be left open.
    internal void CloseTls()
    {
        if (_closed)
            return;
        if (_handshakeComplete && !_alertSent)
            SendTlsAlert(TlsAlertDescription.CloseNotify);
        _closed = true;
        if (!_leaveInnerStreamOpen)
            _records.Inner.Close();
    }

    /// Ends a handshake that failed: the alert, then the stream.
    internal void AbandonTls(TlsError error)
    {
        FailTls(error);
        _closed = true;
        if (!_leaveInnerStreamOpen)
            _records.Inner.Close();
    }
}
