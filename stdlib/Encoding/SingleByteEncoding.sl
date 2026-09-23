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

// ------------------------------------------------------- one byte, one scalar

/// An encoding in which every byte is exactly one character.
///
/// Decoding one of these cannot fail: there is no sequence to run out of and no
/// byte that means nothing, only a table with 256 entries. Encoding can, since
/// most of Unicode is not in that table, and what cannot be written becomes
/// `?`.
///
/// A base class rather than three copies, because the three differ only in the
/// table -- and the two that matter differ only in the 32 entries between 0x80
/// and 0x9F.
public abstract class SingleByteEncoding : IEncoding
{
    /// What this byte means. Every byte means something.
    public abstract char32 ToScalar(byte value);

    /// Which byte writes this scalar, or -1 when none does.
    public abstract int FromScalar(char32 scalar);

    /// The IANA name, which each subclass supplies.
    public abstract String Name { get; }

    /// None of these has one: a byte order mark is a Unicode idea.
    ///
    /// @value an empty array, always.
    public byte[] Preamble => [];

    /// Whether the table has a byte for that scalar. Most of Unicode is not in
    /// any of these tables, so this is false far more often than it is true.
    public bool CanRepresent(char32 scalar) => this.FromScalar(scalar) >= 0;

    /// One byte is one character here, so a decoder has nothing to hold.
    public IDecoder GetDecoder() => new WholeDecoder(this);

    /// One byte per scalar, always -- so the count is the scalar count, not
    /// the text's byte length.
    public nuint GetByteCount(String text) => text.CodePointCount();

    /// The text in this encoding, with anything the table cannot write
    /// becoming `?`. Check `CanRepresent` first where losing it matters.
    ///
    /// @see SingleByteEncoding.CanRepresent
    public byte[] GetBytes(String text)
    {
        var bytes = new byte[text.CodePointCount()];
        nuint out = 0;

        for (nuint at = 0; at < text.ByteLength(); at = text.SkipCodePoint(at))
        {
            int written = this.FromScalar(text.GetCodePointAt(at));
            bytes[out] = written < 0 ? (byte)63 : (byte)written;      // '?'
            out++;
        }
        return bytes;
    }

    /// `bytes` through the table, one character per byte. Cannot fail: every
    /// byte means something, even if that something is U+FFFD.
    public String GetString(byte[] bytes)
    {
        var built = new StringBuilder();
        for (nuint i = 0; i < bytes.Length; i++)
        {
            built.AppendCodePoint(this.ToScalar(bytes[i]));
        }
        return built.ToText();
    }

    /// Never fails, which is the whole character of a single-byte encoding.
    public Result<String, EncodingError> TryGetString(byte[] bytes)
    {
        return Ok(this.GetString(bytes));
    }
}
