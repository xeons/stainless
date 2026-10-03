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

import Standard.Text;

/// Where a request goes and how: its origin, and the proxy between, if any.
internal sealed class HttpRoute
{
    internal String Scheme;

    /// The host, without the brackets an IPv6 literal has in a URI.
    internal String Host;

    internal ushort Port;

    /// An HTTP proxy, or null to go direct.
    internal Uri? Proxy;

    internal NetworkCredential? ProxyCredentials;

    internal HttpRoute(String scheme, String host, ushort port)
    {
        Scheme = scheme;
        Host = host;
        Port = port;
    }

    internal bool IsHttps => Scheme == "https";

    /// The pool's key: everything that makes one connection unlike another.
    internal String PoolKey
    {
        get
        {
            String key = Scheme + "://" + FormatHttpAuthority(Host, Port);
            if (Proxy is Uri proxy)
                key += " via " + proxy.Host + ":" + Text.FromInteger((long)proxy.Port);
            return key;
        }
    }
}
