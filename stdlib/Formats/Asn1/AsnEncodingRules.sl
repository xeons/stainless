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

/// Which of X.690's encodings a reader holds its input to.
///
/// CER is not here. Nothing a certificate or a TLS handshake carries uses it,
/// and its one distinguishing feature is the indefinite length this module
/// does not read.
public enum AsnEncodingRules
{
    /// The Basic Encoding Rules, where they are cheap to accept: a long-form
    /// length that fits the short form, a length with leading zeros, a
    /// `BOOLEAN` true other than `0xFF`, unused bits that are not zero, and a
    /// time with an offset or without its seconds.
    ///
    /// **Indefinite lengths and constructed strings are refused** with
    /// `AsnError.Unsupported`. Both need a reader that reassembles what it
    /// hands back, and neither appears in the formats this module exists for.
    Ber,

    /// The Distinguished Encoding Rules: exactly one encoding for every value.
    /// What X.509 signs, and the rules a reader SHOULD use for anything a
    /// signature covers.
    Der,
}
