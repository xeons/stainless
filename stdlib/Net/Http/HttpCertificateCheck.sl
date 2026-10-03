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

/// The request a TLS validation is for, and the callback that judges it: what
/// turns the handler's callback into the TLS module's validator.
internal sealed class HttpCertificateCheck
{
    private HttpRequestMessage _request;
    private HttpServerCertificateValidator _callback;

    internal HttpCertificateCheck(HttpRequestMessage request, HttpServerCertificateValidator callback)
    {
        _request = request;
        _callback = callback;
    }

    internal TlsError ValidateHttpCertificateChain(List<byte[]> chain, String targetHost)
    {
        TlsError verdict = ValidateTlsCertificateChainByDefault(chain, targetHost);
        X509Certificate2? leaf = null;
        if (chain.Count > 0u && X509Certificate2.FromDer(chain[0u]) is Ok parsed)
            leaf = parsed.Value;
        if (_callback(_request, leaf, chain, verdict))
            return TlsError.None;
        return verdict == TlsError.None ? TlsError.CertificateRefused : verdict;
    }
}
