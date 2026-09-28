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

/// A user name and a password, for a proxy that asks for Basic credentials.
///
/// .NET's `System.Net.NetworkCredential`, kept here beside the client that is
/// its only user.
public sealed class NetworkCredential
{
    /// Empty credentials.
    public NetworkCredential() { }

    /// `userName` and `password`.
    public NetworkCredential(String userName, String password)
    {
        UserName = userName;
        Password = password;
    }

    /// `userName` and `password` in `domain`, which Basic does not send.
    public NetworkCredential(String userName, String password, String domain)
    {
        UserName = userName;
        Password = password;
        Domain = domain;
    }

    public String UserName { get; set; } = "";

    public String Password { get; set; } = "";

    public String Domain { get; set; } = "";
}
