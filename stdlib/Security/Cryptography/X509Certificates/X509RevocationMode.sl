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

module Standard.Security.Cryptography.X509Certificates;

/// Whether a chain asks if a certificate is revoked: .NET's
/// `X509RevocationMode`.
///
/// **Only `NoCheck` can succeed.** There is no CRL and no OCSP here, so
/// either of the others marks every element `RevocationStatusUnknown` and
/// `OfflineRevocation`, which fails the chain, rather than pretending to
/// have looked.
public enum X509RevocationMode
{
    /// Revocation is not asked about. The default.
    NoCheck,

    /// Ask the network; not possible here.
    Online,

    /// Ask what is cached; not possible here.
    Offline,
}
