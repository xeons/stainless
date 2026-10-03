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

module Standard.Net.Http;

import Standard.Collections;
import Standard.Net.Security;
import Standard.Security.Cryptography.X509Certificates;

/// Decides whether to trust a server's certificate chain for a request.
///
/// `certificate` is the leaf, parsed, or null when it could not be; `chain`
/// is every certificate as the server sent it, DER, leaf first. `defaultVerdict`
/// is what the TLS module's own validator answered — `None` when it would
/// have trusted the chain — as .NET hands over its `SslPolicyErrors`. The
/// answer is whether to go on.
///
/// @see HttpClientHandler.ServerCertificateCustomValidationCallback
public closure bool HttpServerCertificateValidator(HttpRequestMessage request,
                                                   X509Certificate2? certificate,
                                                   List<byte[]> chain, TlsError defaultVerdict);

/// The policy when no callback is set: trust what the TLS module trusts.
internal bool AcceptHttpCertificateByDefault(HttpRequestMessage request, X509Certificate2? certificate,
                                             List<byte[]> chain, TlsError defaultVerdict) =>
    defaultVerdict == TlsError.None;

/// Trusts every chain.
internal bool AcceptAnyHttpCertificate(HttpRequestMessage request, X509Certificate2? certificate,
                                       List<byte[]> chain, TlsError defaultVerdict) => true;
