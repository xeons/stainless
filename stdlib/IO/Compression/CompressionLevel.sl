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

/// How hard a compressor works, as .NET's enum of the name.
///
/// Every level writes a stream any decompressor reads; the level trades time
/// for size and nothing else.
public enum CompressionLevel
{
    /// A balance, as zlib's level 6: lazy matching over hash chains of up to
    /// 128.
    Optimal = 0,

    /// The quickest that still compresses, as zlib's level 1: greedy matching
    /// over chains of four.
    Fastest = 1,

    /// Stored blocks only. The stream is valid and a little larger than its
    /// input.
    NoCompression = 2,

    /// The smallest this compressor makes, as zlib's level 9: lazy matching
    /// over chains of up to 4096.
    SmallestSize = 3,
}
