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

/// One thing wrong with a chain or an element of it: .NET's
/// `X509ChainStatus`.
public struct X509ChainStatus
{
    /// The flag, one bit of `X509ChainStatusFlags`.
    public X509ChainStatusFlags Status;

    /// A sentence saying what it means.
    public String StatusInformation;

    /// A status for `status`, one flag.
    public X509ChainStatus(X509ChainStatusFlags status, String statusInformation)
    {
        Status = status;
        StatusInformation = statusInformation;
    }
}
