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

/// Every handshake message so far, header and all, in the order sent and
/// received.
///
/// The bytes are kept rather than a running hash, because the hash is not
/// known until the server has chosen a suite, and a HelloRetryRequest
/// replaces the first ClientHello with a hash of it (RFC 8446 §4.4.1). A
/// handshake is a few kilobytes, so hashing it whole at each of the half
/// dozen points that need it costs less than a hash state per candidate.
internal sealed class TlsTranscript
{
    private TlsBuffer _messages;

    internal TlsTranscript()
    {
        _messages = new TlsBuffer(4096u);
    }

    internal void AddTlsMessage(ReadOnlySpan<byte> message) => _messages.WriteBytes(message);

    internal byte[] ComputeTlsTranscriptHash(TlsKeySchedule schedule) =>
        schedule.HashTlsBytes(_messages.Written);

    internal byte[] ComputeTls12TranscriptHash(Tls12KeySchedule schedule) =>
        schedule.HashTlsBytes(_messages.Written);

    /// The messages themselves, which a TLS 1.2 CertificateVerify signs.
    internal ReadOnlySpan<byte> Messages => _messages.Written;

    /// Replaces the first ClientHello with the synthetic `message_hash`
    /// message that stands for it after a HelloRetryRequest.
    internal void ReplaceWithTlsMessageHash(TlsKeySchedule schedule)
    {
        byte[] digest = schedule.HashTlsBytes(_messages.Written);
        _messages.Clear();
        _messages.WriteByte((uint)TlsHandshakeType.MessageHash);
        _messages.WriteUInt24((uint)digest.Length);
        _messages.WriteBytes(digest);
    }
}
