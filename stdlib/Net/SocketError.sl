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

// ------------------------------------------------------------------ errors

/// Why an operation did not work. `None` is success.
///
/// These are the distinctions a program can act on rather than the platform's
/// whole list, for the reason `IOError` gives: the values are the same
/// everywhere, and neither `errno` nor a WSA code is.
public enum SocketError
{
    /// Nothing went wrong.
    None = 0,

    /// Nothing to read, or no room to write, on a socket that is not blocking.
    /// Not a failure -- it is what a non-blocking socket says instead of
    /// waiting.
    WouldBlock = 1,

    /// Nothing is listening there.
    Refused = 2,

    /// A timeout set on the socket ran out before the call finished.
    TimedOut = 3,
    /// No route to that address.
    Unreachable = 4,

    /// Something else already has that port.
    AddressInUse = 5,

    /// An operation that needs a connection, on a socket that has none.
    NotConnected = 6,

    /// The peer went away without closing: a reset rather than an ending.
    Reset = 7,

    /// The socket was closed before the call.
    Closed = 8,
    /// A signal arrived mid-call. Retrying is usually right.
    Interrupted = 9,
    /// Not permitted -- a low port without the privilege for it, or a
    /// broadcast send on a socket that was not asked to allow one.
    AccessDenied = 10,

    /// The name did not resolve.
    NoName = 11,

    /// The request made no sense for this socket in this state.
    Invalid = 12,
    /// The platform said something this enum has no name for.
    Unknown = 13,
}
