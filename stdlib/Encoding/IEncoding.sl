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

module Standard.Encoding;

import Standard.Text;

/// One way of writing text as bytes.
///
/// Implement it to add an encoding; nothing here is closed. The two `Get`
/// methods are lossy and total, the `Try` one is strict, and `CanRepresent`
/// asks the encode direction the question `TryGetString` asks of the other.
public interface IEncoding
{
    /// The name IANA gives it, which is also what an HTTP header would carry.
    String Name { get; }

    /// The bytes that mark this encoding at the start of a file, if any.
    byte[] Preamble { get; }

    /// How many bytes `GetBytes` would produce. Costs a pass, saves an
    /// allocation.
    ///
    /// @see IEncoding.GetBytes
    nuint GetByteCount(String text);

    /// `text` in this encoding. A scalar the encoding cannot write becomes
    /// `?`, which is what .NET's default fallback does and what the caller
    /// almost always wants when the alternative is failing a whole file.
    ///
    /// @see IEncoding.GetString
    /// @seealso IEncoding.CanRepresent
    byte[] GetBytes(String text);

    /// `bytes` read as this encoding. Anything malformed becomes U+FFFD, so
    /// the result is always valid UTF-8 -- which it must be, because it is a
    /// `String`.
    ///
    /// @see IEncoding.GetBytes
    /// @seealso IEncoding.TryGetString
    String GetString(byte[] bytes);

    /// The same, but saying what went wrong instead of papering over it.
    ///
    /// @failure EncodingError.Incomplete  the bytes end part-way through a character
    /// @failure EncodingError.Invalid     a byte or a sequence this encoding cannot produce
    /// @see IEncoding.GetString
    Result<String, EncodingError> TryGetString(byte[] bytes);

    /// Whether this encoding can write that scalar at all.
    bool CanRepresent(char32 scalar);

    /// A converter that remembers what a buffer ended in the middle of.
    ///
    /// `GetString` takes whole text and cannot help a caller reading a stream
    /// in pieces, because a character may straddle two of them. This is .NET's
    /// `Encoding.GetDecoder`, and it exists for exactly that: the decoder holds
    /// the trailing bytes of an unfinished character and finishes it when the
    /// next piece arrives.
    IDecoder GetDecoder();
}
