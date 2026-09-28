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

module Standard.IO.Compression;

/// Why compressed data was refused. `None` is success.
///
/// A stream rounds every one of these to `IOError.InvalidData` for a reader
/// that knows only `IStream`, and keeps the exact one in
/// `CompressionErrorCode`; the one-shot functions report it directly.
public enum CompressionError
{
    /// Nothing went wrong.
    None = 0,

    /// The data ended in the middle of a block, a header or a trailer.
    Truncated = 1,

    /// A gzip or zlib header that is not one: the wrong magic, a method
    /// other than deflate, reserved bits set, or a zlib check that fails.
    InvalidHeader = 2,

    /// A zlib stream that needs a preset dictionary. Nothing here can supply
    /// one.
    DictionaryRequired = 3,

    /// A block of type 3, which RFC 1951 reserves.
    InvalidBlockType = 4,

    /// A stored block whose length and its complement disagree.
    StoredLengthMismatch = 5,

    /// A dynamic block's code lengths do not describe a usable code: too
    /// many or too few symbols, an over-subscribed or incomplete set, a
    /// repeat with nothing to repeat, or no end-of-block code.
    InvalidCodeLengths = 6,

    /// A bit pattern that no code in the block's tables stands for, or a
    /// length or distance symbol the format reserves.
    InvalidCode = 7,

    /// A match reaching back past the start of the data.
    InvalidDistance = 8,

    /// The CRC-32 or Adler-32 in the trailer does not match the data.
    ChecksumMismatch = 9,

    /// The length in a gzip trailer does not match the data.
    LengthMismatch = 10,
}
