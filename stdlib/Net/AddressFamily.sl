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

/// Which internet protocol.
public enum AddressFamily
{
    /// Whichever the name resolves to.
    ///
    /// Only meaningful where a name is being resolved: connecting to one, or
    /// `ResolveHost`. There is no socket of no family, so opening one with `Any`
    /// is `SocketError.Invalid` -- which is what Linux says and Windows
    /// quietly does not, handing back an IPv4 socket instead.
    Any = 0,
    /// IPv4 only.
    IPv4 = 4,
    /// IPv6 only. Whether it also accepts IPv4 is the platform's default,
    /// not something set here.
    IPv6 = 6,
}
