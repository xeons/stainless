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

/// Which content codings `HttpClientHandler` asks for and undoes.
///
/// @see HttpClientHandler.AutomaticDecompression
[Flags]
public enum DecompressionMethods
{
    /// None: the body arrives as the server sent it.
    None = 0,

    /// gzip, RFC 1952.
    GZip = 1,

    /// deflate: RFC 1950's zlib format, or RFC 1951's raw deflate, which
    /// some servers send under the same name and every browser accepts.
    Deflate = 2,

    /// Every coding this module can undo.
    All = 3,
}
