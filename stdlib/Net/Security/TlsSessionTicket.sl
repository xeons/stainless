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

/// Receives each session ticket a server sends after the handshake.
public closure void TlsSessionTicketHandler(TlsSessionTicket ticket);

/// A session ticket (RFC 8446 §4.6.1), and the pre-shared key it stands for.
///
/// Nothing here resumes a session yet. A cache can keep these now, and
/// resumption will offer them back.
public sealed class TlsSessionTicket
{
    private TlsCipherSuite _cipherSuite;
    private String _targetHost;
    private uint _lifetime;
    private uint _ageAdd;
    private byte[] _nonce;
    private byte[] _ticket;
    private byte[] _resumptionKey;
    private uint _maxEarlyDataSize;

    internal TlsSessionTicket(TlsCipherSuite cipherSuite, String targetHost, uint lifetime,
                              uint ageAdd, byte[] nonce, byte[] ticket, byte[] resumptionKey,
                              uint maxEarlyDataSize)
    {
        _cipherSuite = cipherSuite;
        _targetHost = targetHost;
        _lifetime = lifetime;
        _ageAdd = ageAdd;
        _nonce = nonce;
        _ticket = ticket;
        _resumptionKey = resumptionKey;
        _maxEarlyDataSize = maxEarlyDataSize;
    }

    /// The suite of the connection that issued it, whose hash a resumption
    /// MUST use.
    public TlsCipherSuite CipherSuite => _cipherSuite;

    /// The name the connection was made to.
    public String TargetHost => _targetHost;

    /// How many seconds the server will honour it for, at most a week.
    public uint Lifetime => _lifetime;

    /// What obscures the ticket's age when it is offered back.
    public uint AgeAdd => _ageAdd;

    /// The per-ticket value the key is derived with.
    public byte[] Nonce => _nonce;

    /// The server's opaque label for the session.
    public byte[] Ticket => _ticket;

    /// The pre-shared key: HKDF-Expand-Label of the resumption master secret
    /// over the nonce. **A secret**, and to be kept as one.
    public byte[] ResumptionKey => _resumptionKey;

    /// How much 0-RTT data the server would take, or zero. 0-RTT is never
    /// sent by this library.
    public uint MaxEarlyDataSize => _maxEarlyDataSize;
}

/// What a client does with a ticket when no handler is configured: nothing.
public void DiscardTlsSessionTicket(TlsSessionTicket ticket)
{
}
