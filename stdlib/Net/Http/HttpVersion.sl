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

/// The protocol versions a message can name.
public static class HttpVersion
{
    /// HTTP/1.0, which a server may still answer in.
    public static readonly Version Version10 = new Version(1, 0);

    /// HTTP/1.1, which every request here is sent in.
    public static readonly Version Version11 = new Version(1, 1);

    /// HTTP/2, which is not spoken yet: a request asking for it is sent as
    /// HTTP/1.1.
    public static readonly Version Version20 = new Version(2, 0);
}
