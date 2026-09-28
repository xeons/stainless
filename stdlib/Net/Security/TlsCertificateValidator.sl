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

/// Decides whether the peer's certificate chain is to be trusted.
///
/// `chain` is the certificates as the peer sent them, each in DER, the leaf
/// first. `targetHost` is the name the client asked for: what a server
/// certificate MUST be valid for, and empty when a server is judging a client.
/// The answer is `TlsError.None` to go on; anything else ends the handshake
/// and is sent to the peer as that error's alert, so `CertificateExpired`
/// and `UnknownCertificateAuthority` are the precise refusals and
/// `CertificateRefused` the general one.
///
/// The validator is asked before the CertificateVerify signature is checked,
/// and the signature is then checked against the leaf whatever it answered.
public closure TlsError TlsCertificateValidator(List<byte[]> chain, String targetHost);

/// The validator used when none is configured. **It refuses every chain.**
///
/// X.509 path validation is not in this library yet, and a default that
/// trusted anything would be an invitation to a machine in the middle. A
/// program that has pinned its peer's certificate, or accepts any for a
/// test, supplies its own.
///
/// @param chain       the peer's certificates, DER, leaf first
/// @param targetHost  the name the certificate must be valid for
public TlsError ValidateTlsCertificateChainByDefault(List<byte[]> chain, String targetHost)
{
    // X.509: build an X509Chain from `chain`, validate it against the system
    // store and `targetHost`, and map its status to TlsError here.
    return TlsError.UnknownCertificateAuthority;
}
