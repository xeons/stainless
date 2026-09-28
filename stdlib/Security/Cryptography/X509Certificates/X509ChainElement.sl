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

/// One certificate of a built chain and what is wrong with it: .NET's
/// `X509ChainElement`.
public sealed class X509ChainElement
{
    private X509Certificate2 _certificate;
    private X509ChainStatusFlags _statusFlags;

    internal X509ChainElement(X509Certificate2 certificate, X509ChainStatusFlags statusFlags)
    {
        _certificate = certificate;
        _statusFlags = statusFlags;
    }

    /// The certificate.
    public X509Certificate2 Certificate => _certificate;

    /// Everything wrong with it, one flag each.
    public X509ChainStatus[] ChainElementStatus => X509Chain.DescribeStatusFlags(_statusFlags);

    /// Everything wrong with it, as one set of flags; `NoError` when nothing is.
    public X509ChainStatusFlags StatusFlags => _statusFlags;
}
