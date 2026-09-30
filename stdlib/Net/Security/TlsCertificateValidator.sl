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
import Standard.Security.Cryptography.X509Certificates;

/// Decides whether the peer's certificate chain is to be trusted.
///
/// `chain` is the certificates as the peer sent them, each in DER, the leaf
/// first. On a client `targetHost` is the name it asked for, which a server
/// certificate MUST be valid for; on a server it is empty. The answer is
/// `TlsError.None` to go on; anything else ends the handshake and is sent to
/// the peer as that error's alert, so `CertificateExpired` and
/// `UnknownCertificateAuthority` are the precise refusals and
/// `CertificateRefused` the general one.
///
/// The validator is asked before the CertificateVerify signature is checked.
/// A refusal ends the handshake without that check; an acceptance is followed
/// by it, against the leaf.
public closure TlsError TlsCertificateValidator(List<byte[]> chain, String targetHost);

/// The validator a client uses when none is configured: the platform's
/// trust, for a server.
///
/// The leaf MUST reach a root in the system store (crypt32's on Windows, the
/// system bundle elsewhere) through the peer's other certificates and the
/// system's intermediates, pass every check `X509Chain` makes now, carry the
/// server-authentication usage, and be valid for `targetHost`. An empty
/// `targetHost` is refused, since no certificate can be checked against it.
/// Revocation is not checked; `X509Chain` says why.
///
/// @param chain       the server's certificates, DER, leaf first
/// @param targetHost  the name the certificate must be valid for
/// @see ValidateTlsClientCertificateChainByDefault
public TlsError ValidateTlsCertificateChainByDefault(List<byte[]> chain, String targetHost)
{
    if (targetHost.IsEmpty)
        return TlsError.CertificateRefused;
    return ValidateTlsCertificateChainForRole(chain, targetHost, true);
}

/// The validator a server uses when none is configured: the platform's
/// trust, for a client.
///
/// As `ValidateTlsCertificateChainByDefault`, with the client-authentication
/// usage in place of the server's and no name to match. `targetHost` is not
/// read.
///
/// @param chain       the client's certificates, DER, leaf first
/// @param targetHost  not read; a server passes an empty string
public TlsError ValidateTlsClientCertificateChainByDefault(List<byte[]> chain, String targetHost) =>
    ValidateTlsCertificateChainForRole(chain, targetHost, false);

/// The platform's trust for a peer in the role `judgingServer` names: the
/// server-authentication usage and `targetHost` for a server, the
/// client-authentication usage alone for a client.
internal TlsError ValidateTlsCertificateChainForRole(
    List<byte[]> chain, String targetHost, bool judgingServer)
{
    if (chain.Count == 0u)
        return TlsError.CertificateRequired;

    var leaf = X509Certificate2.FromDer(chain[0u]);
    if (!leaf.Ok)
        return TlsError.UnsupportedCertificate;

    var path = new X509Chain();
    for (nuint i = 1u; i < chain.Count; i++)
    {
        // A certificate that does not parse cannot be on any path, and the
        // leaf is judged by the path that is found without it.
        var issuer = X509Certificate2.FromDer(chain[i]);
        if (issuer.Ok)
            path.ChainPolicy.ExtraStore.Add(issuer.Value);
    }

    path.ChainPolicy.ApplicationPolicy.Add(judgingServer
        ? X509EnhancedKeyUsageExtension.ServerAuthenticationOid
        : X509EnhancedKeyUsageExtension.ClientAuthenticationOid);

    if (!path.Build(leaf.Value))
        return TlsErrorForChainStatus(path.StatusFlags);

    if (judgingServer && !leaf.Value.MatchesHostname(targetHost))
        return TlsError.CertificateRefused;

    return TlsError.None;
}

/// The refusal a failed chain is sent as: the precise alert where there is
/// one, and `bad_certificate` for the rest.
TlsError TlsErrorForChainStatus(X509ChainStatusFlags status)
{
    if ((status & X509ChainStatusFlags.NotTimeValid) != X509ChainStatusFlags.NoError)
        return TlsError.CertificateExpired;

    X509ChainStatusFlags unanchored =
        X509ChainStatusFlags.UntrustedRoot | X509ChainStatusFlags.PartialChain;
    if ((status & unanchored) != X509ChainStatusFlags.NoError)
        return TlsError.UnknownCertificateAuthority;

    return TlsError.CertificateRefused;
}
