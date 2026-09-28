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

/// How a client connects: the name it wants, what it offers, and how it
/// decides to trust the answer.
///
///     var options = new TlsClientOptions();
///     options.TargetHost = "example.com";
///     options.ApplicationProtocols.Add("http/1.1");
///     options.CertificateValidator = PinnedLeaf;
///
/// .NET's `SslClientAuthenticationOptions`, with the lists this library can
/// negotiate spelled out rather than left to the platform.
public sealed class TlsClientOptions
{
    /// The server's name: sent as server_name unless it is a literal
    /// address, and handed to the validator as the name the certificate MUST
    /// be valid for.
    public String TargetHost { get; set; } = "";

    /// ALPN protocol names to offer, most preferred first. Empty offers none.
    public List<String> ApplicationProtocols { get; set; } = new List<String>();

    /// Which versions may be negotiated. TLS 1.2 is accepted here and not yet
    /// implemented, so only a TLS 1.3 server is reached.
    public TlsProtocolVersion EnabledProtocols { get; set; } =
        TlsProtocolVersion.Tls12 | TlsProtocolVersion.Tls13;

    /// Suites to offer, most preferred first.
    public List<TlsCipherSuite> CipherSuites { get; set; } = CreateDefaultTlsCipherSuites();

    /// Groups to offer for the key exchange, most preferred first.
    public List<TlsNamedGroup> KeyExchangeGroups { get; set; } = CreateDefaultTlsGroups();

    /// Groups to send a key share for in the first ClientHello. Each MUST be
    /// in `KeyExchangeGroups`. A server that wants another group asks for it
    /// with a HelloRetryRequest, which costs a round trip.
    public List<TlsNamedGroup> KeyShareGroups { get; set; } = CreateDefaultTlsKeyShareGroups();

    /// Decides whether to trust the server's chain. The default trusts what
    /// the platform's root store does, for `TargetHost`.
    ///
    /// @see ValidateTlsCertificateChainByDefault
    public TlsCertificateValidator CertificateValidator { get; set; } =
        ValidateTlsCertificateChainByDefault;

    /// The client's certificates, DER, leaf first, sent when a server asks.
    /// Empty sends an empty Certificate, which a server MAY refuse.
    public List<byte[]> ClientCertificateChain { get; set; } = new List<byte[]>();

    /// The key of the client's leaf certificate.
    public TlsSigningKey? ClientPrivateKey { get; set; }

    /// Given each session ticket the server sends. Resumption is not
    /// implemented yet; this is where a cache would collect them.
    public TlsSessionTicketHandler SessionTicketReceived { get; set; } = DiscardTlsSessionTicket;

    /// Whether `Close` leaves the stream underneath open.
    public bool LeaveInnerStreamOpen { get; set; } = false;

    // Test hooks: fixed randomness, a fixed X25519 share, and a ClientHello
    // sent verbatim. Empty means unset. Reachable only inside this module.
    internal byte[] _fixedRandom = new byte[0u];
    internal byte[] _fixedX25519PrivateKey = new byte[0u];
    internal byte[] _fixedClientHello = new byte[0u];
}

internal List<TlsNamedGroup> CreateDefaultTlsKeyShareGroups()
{
    var groups = new List<TlsNamedGroup>();
    groups.Add(TlsNamedGroup.X25519);
    return groups;
}
