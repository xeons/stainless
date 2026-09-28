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

/// The tag numbers X.680 assigns in the `Universal` class.
///
/// Every one is listed so that a tag read from the wire can be named. Only
/// some have a reader of their own; the rest are reached through
/// `AsnReader.ReadEncodedValue`.
public enum UniversalTagNumber
{
    /// Ends an indefinite-length encoding, which this module does not read.
    EndOfContents = 0,
    Boolean = 1,
    Integer = 2,
    BitString = 3,
    OctetString = 4,
    Null = 5,
    ObjectIdentifier = 6,
    ObjectDescriptor = 7,
    External = 8,
    Real = 9,
    Enumerated = 10,
    Embedded = 11,
    Utf8String = 12,
    RelativeObjectIdentifier = 13,
    Time = 14,

    /// `SEQUENCE` and `SEQUENCE OF`, which share a tag.
    Sequence = 16,

    /// `SET` and `SET OF`, which share a tag.
    Set = 17,
    NumericString = 18,
    PrintableString = 19,

    /// TeletexString. Read and written here as Latin-1, as every X.509
    /// implementation in practice does.
    T61String = 20,
    VideotexString = 21,
    IA5String = 22,
    UtcTime = 23,
    GeneralizedTime = 24,
    GraphicString = 25,
    VisibleString = 26,
    GeneralString = 27,

    /// UCS-4, big-endian.
    UniversalString = 28,
    UnrestrictedCharacterString = 29,

    /// UCS-2, big-endian: the Basic Multilingual Plane and nothing past it.
    BmpString = 30,
    Date = 31,
    TimeOfDay = 32,
    DateTime = 33,
    Duration = 34,
}
