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

module Standard.Net;

import Standard.Collections;
import Standard.IO;
import Standard.Text;

// ------------------------------------------------------------- an endpoint

/// A host and a port, together, because they always travel together.
///
/// A struct rather than a class: it holds a `String`, so copying it retains --
/// which is fine, and is why it cannot cross `extern "C"` (§7.6). Nothing here
/// needs it to.
public struct EndPoint
{
    /// The address or name. An empty host means every address on this machine,
    /// which is what a server binds to.
    public String Host;

    /// The port. Zero asks the system to choose one, which `LocalEndPoint`
    /// will then say.
    public ushort Port;

    /// An endpoint, made in one expression.
    public static EndPoint Create(String host, ushort port)
    {
        EndPoint made;
        made.Host = host;
        made.Port = port;
        return made;
    }

    /// Written the way one is written.
    public String Format()
    {
        // A bare IPv6 address contains colons, so the port needs the brackets
        // that a URL puts round one. IPv4 and a name do not.
        if (Host.Contains(':'))
        {
            return $"[{Host}]:{Port}";
        }
        return $"{Host}:{Port}";
    }
}
