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

/// Why a value could not be read or written.
public enum AsnError
{
    /// Nothing went wrong. What an operation that produces no value answers on
    /// success.
    None,

    /// The input ends inside an identifier, a length or the contents that
    /// length promised.
    Truncated,

    /// A length that is malformed, or impossible for the type: a `BOOLEAN`
    /// that is not one octet, a `NULL` that is not empty, an `INTEGER` of none.
    BadLength,

    /// The next value's tag is not the one asked for, or it is constructed
    /// where the type is primitive or the other way round.
    UnexpectedTag,

    /// A form the rules in force forbid although a looser set allows it: a
    /// length or tag number in more octets than it needs, an `INTEGER` with a
    /// redundant leading `0x00` or `0xFF`, a `BOOLEAN` true other than `0xFF`
    /// or a constructed string under DER.
    NonMinimalEncoding,

    /// The value is well-formed and does not fit what it is being read into:
    /// an `INTEGER` too wide for a `long`, an arc too wide for a `ulong`, a
    /// time outside the years a `UTCTime` can name.
    OutOfRange,

    /// A character string holds a character its type does not allow, or
    /// octets that are not a valid encoding in its character set.
    BadStringContent,

    /// A `UTCTime` or `GeneralizedTime` that is not in the form the rules
    /// require, or does not name a real moment.
    BadTime,

    /// Something follows the last value where nothing may.
    TrailingData,

    /// Valid ASN.1 this module does not read: an indefinite length, a
    /// constructed string under BER, a time with no zone.
    Unsupported,

    /// Contents that are not an encoding of their type under any rules: a
    /// `BIT STRING` claiming more than seven unused bits, an object identifier
    /// whose last arc does not end, a dotted string that is not one.
    Malformed,
}
