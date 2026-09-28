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

module Standard.Formats.Asn1;

/// Which namespace a tag number belongs to.
///
/// The values are the top two bits of an identifier octet, as .NET's are, so
/// a class is its own encoding.
public enum TagClass
{
    /// Defined by X.680 itself: `INTEGER`, `SEQUENCE`, `UTF8String`.
    Universal = 0x00,

    /// Defined by a whole specification, once for all of it.
    Application = 0x40,

    /// Meaningful only inside the type that uses it — the `[0]` and `[3]` of
    /// an X.509 certificate.
    ContextSpecific = 0x80,

    /// Defined by an organisation for its own use.
    Private = 0xC0,
}
