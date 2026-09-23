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

// ------------------------------------------------------------------- UTF-32

/// UTF-32: one scalar per four bytes, and no surrogates anywhere.
public class Utf32Encoding : IEncoding
{
    bool _bigEndian;

    /// A UTF-32 encoding, big-endian when `big`. `CreateUtf32()` and
    /// `CreateUtf32BigEndian()` are the names to reach for.
    ///
    /// @see Encoding.CreateUtf32
    /// @see Encoding.CreateUtf32BigEndian
    public Utf32Encoding(bool big) => _bigEndian = big;

    /// `"utf-32be"` or `"utf-32le"`, whichever this is.
    public String Name => _bigEndian ? "utf-32be" : "utf-32le";

    /// Four bytes, and the little-endian one begins with UTF-16LE's -- which
    /// is why `DetectEncoding` tests UTF-32 first.
    ///
    /// @see Encoding.DetectEncoding
    public byte[] Preamble
    {
        get
        {
            if (_bigEndian)
                return [0x00, 0x00, 0xFE, 0xFF];
            return [0xFF, 0xFE, 0x00, 0x00];
        }
    }

    /// Every scalar, in exactly four bytes.
    public bool CanRepresent(char32 scalar) => true;

    /// A decoder that holds whatever is left of a four-byte group.
    public IDecoder GetDecoder() => new Utf32Decoder(this);

    /// Four bytes per scalar. Costs a pass to count the scalars.
    public nuint GetByteCount(String text) => text.CodePointCount() * 4;

    /// The text as UTF-32 in this byte order, with no byte order mark.
    public byte[] GetBytes(String text)
    {
        var bytes = new byte[text.CodePointCount() * 4];
        nuint out = 0;

        for (nuint at = 0; at < text.ByteLength(); at = text.SkipCodePoint(at))
        {
            uint scalar = (uint)text.GetCodePointAt(at);
            if (_bigEndian)
            {
                bytes[out] = (byte)(scalar >> 24);
                bytes[out + 1] = (byte)((scalar >> 16) & 0xFF);
                bytes[out + 2] = (byte)((scalar >> 8) & 0xFF);
                bytes[out + 3] = (byte)(scalar & 0xFF);
            }
            else
            {
                bytes[out] = (byte)(scalar & 0xFF);
                bytes[out + 1] = (byte)((scalar >> 8) & 0xFF);
                bytes[out + 2] = (byte)((scalar >> 16) & 0xFF);
                bytes[out + 3] = (byte)(scalar >> 24);
            }
            out = out + 4;
        }
        return bytes;
    }

    /// `bytes` read as UTF-32, with a value that is not a scalar -- a
    /// surrogate, or anything past U+10FFFF -- becoming U+FFFD. Trailing bytes
    /// that do not make a whole four are one more U+FFFD.
    public String GetString(byte[] bytes)
    {
        var built = new StringBuilder();

        nuint at = 0;
        while (at + 3 < bytes.Length)
        {
            built.AppendCodePoint((char32)this.ReadScalarAt(bytes, at));
            at = at + 4;
        }

        if (at < bytes.Length)
            built.AppendCodePoint((char32)0xFFFD);
        return built.ToText();
    }

    /// The strict decode: `Incomplete` when the length is not a multiple of
    /// four, `Invalid` for a value that is not a scalar.
    ///
    /// @failure EncodingError.Incomplete  the length is not a multiple of four
    /// @failure EncodingError.Invalid     a surrogate, or a value past U+10FFFF
    /// @see Utf32Encoding.GetString
    public Result<String, EncodingError> TryGetString(byte[] bytes)
    {
        if (bytes.Length % 4 != 0)
            return Fail(EncodingError.Incomplete);

        nuint at = 0;
        while (at < bytes.Length)
        {
            uint scalar = this.ReadScalarAt(bytes, at);
            if (scalar > 0x10FFFF)
                return Fail(EncodingError.Invalid);
            if (scalar >= 0xD800 && scalar <= 0xDFFF)
                return Fail(EncodingError.Invalid);
            at = at + 4;
        }
        return Ok(GetString(bytes));
    }

    uint ReadScalarAt(byte[] bytes, nuint at)
    {
        if (_bigEndian)
        {
            return ((uint)bytes[at] << 24) | ((uint)bytes[at + 1] << 16)
                 | ((uint)bytes[at + 2] << 8) | (uint)bytes[at + 3];
        }
        return (uint)bytes[at] | ((uint)bytes[at + 1] << 8)
             | ((uint)bytes[at + 2] << 16) | ((uint)bytes[at + 3] << 24);
    }
}
