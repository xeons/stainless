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

/// How a server answers: its certificate and key, what it accepts, and
/// whether it asks the client to authenticate.
///
///     var options = new TlsServerOptions();
///     options.CertificateChain.Add(leafDer);
///     options.PrivateKey = try TlsSigningKey.ImportFromPem(keyPem);
///
/// The lists are in the server's order of preference, and the server's
/// preference decides: the first suite, group and protocol on its list that
/// the client also offered.
public sealed class TlsServerOptions
{
    /// The server's certificates, DER, leaf first. It MUST NOT be empty.
    public List<byte[]> CertificateChain { get; set; } = new List<byte[]>();

    /// The key of the leaf certificate.
    public TlsSigningKey? PrivateKey { get; set; }

    /// ALPN protocol names this server speaks, most preferred first. When
    /// both ends name protocols and none is shared, the handshake fails with
    /// `NoApplicationProtocol`.
    public List<String> ApplicationProtocols { get; set; } = new List<String>();

    /// Which versions may be negotiated. TLS 1.2 is accepted here and not yet
    /// implemented, so a client that offers only TLS 1.2 is refused.
    public TlsProtocolVersion EnabledProtocols { get; set; } =
        TlsProtocolVersion.Tls12 | TlsProtocolVersion.Tls13;

    /// Suites to accept, most preferred first.
    public List<TlsCipherSuite> CipherSuites { get; set; } = CreateDefaultTlsCipherSuites();

    /// Groups to accept, most preferred first. A client that sent no share
    /// in any of them is asked for one with a HelloRetryRequest.
    public List<TlsNamedGroup> KeyExchangeGroups { get; set; } = CreateDefaultTlsGroups();

    /// Whether to ask the client for a certificate. It MAY send none.
    public bool ClientCertificateRequested { get; set; } = false;

    /// Whether to ask for a client certificate and refuse a client that sends
    /// none, with `CertificateRequired`. Implies `ClientCertificateRequested`.
    public bool ClientCertificateRequired { get; set; } = false;

    /// Decides whether to trust a client's chain. The target host it is given
    /// is empty. The default refuses every chain.
    public TlsCertificateValidator ClientCertificateValidator { get; set; } =
        ValidateTlsCertificateChainByDefault;

    /// Whether `Close` leaves the stream underneath open.
    public bool LeaveInnerStreamOpen { get; set; } = false;

    // Test hooks: a fixed random and a fixed X25519 share. Empty means unset.
    internal byte[] _fixedRandom = new byte[0u];
    internal byte[] _fixedX25519PrivateKey = new byte[0u];
}
