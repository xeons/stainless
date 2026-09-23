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

// ------------------------------------------------------------------- UTF-16

/// UTF-16, in either byte order.
public class Utf16Encoding : IEncoding
{
    bool _bigEndian;

    /// A UTF-16 encoding, big-endian when `big`. `CreateUtf16()` and
    /// `CreateUtf16BigEndian()` are the names to reach for.
    ///
    /// @see Encoding.CreateUtf16
    /// @see Encoding.CreateUtf16BigEndian
    public Utf16Encoding(bool big) => _bigEndian = big;

    /// `"utf-16be"` or `"utf-16le"`, whichever this is.
    public String Name => _bigEndian ? "utf-16be" : "utf-16le";
    // Written as an if rather than a ternary: an array literal takes its type
    // from where it is going, and a ternary arm is not somewhere that says.
    /// FE FF big-endian, FF FE little. Worth writing here, unlike UTF-8's:
    /// without it there is no way to tell the two orders apart.
    public byte[] Preamble
    {
        get
        {
            if (_bigEndian)
                return [0xFE, 0xFF];
            return [0xFF, 0xFE];
        }
    }

    /// Every scalar, in one unit or two.
    public bool CanRepresent(char32 scalar) => true;

    /// A decoder that holds an odd byte, and a high surrogate waiting for
    /// its low one.
    public IDecoder GetDecoder() => new Utf16Decoder(this, _bigEndian);

    /// Two bytes per unit, so four for a scalar outside the basic plane.
    /// Costs a transcode to count, which is what `GetBytes` then does again.
    public nuint GetByteCount(String text) => text.ToUtf16().UnitCount() * 2;

    /// The text as UTF-16 in this byte order, with no byte order mark --
    /// prepend `Preamble` if the reader will need one.
    public byte[] GetBytes(String text)
    {
        var wide = text.ToUtf16();
        nuint count = wide.UnitCount();
        var bytes = new byte[count * 2];

        for (nuint i = 0; i < count; i++)
        {
            uint unit = (uint)wide.GetUnitAt(i);
            if (_bigEndian)
            {
                bytes[i * 2] = (byte)(unit >> 8);
                bytes[i * 2 + 1] = (byte)(unit & 0xFF);
            }
            else
            {
                bytes[i * 2] = (byte)(unit & 0xFF);
                bytes[i * 2 + 1] = (byte)(unit >> 8);
            }
        }
        return bytes;
    }

    /// `bytes` read as UTF-16, with an unpaired surrogate or a trailing odd
    /// byte becoming U+FFFD. A byte order mark, if present, is not stripped --
    /// `StripPreamble` is what does that.
    public String GetString(byte[] bytes)
    {
        var built = new StringBuilder();
        nuint at = 0;

        // A trailing odd byte is half a unit and cannot be anything.
        while (at + 1 < bytes.Length)
        {
            uint first = this.ReadUnitAt(bytes, at);
            at = at + 2;

            if (first < 0xD800 || first > 0xDFFF)
            {
                built.AppendCodePoint((char32)first);
                continue;
            }

            if (first > 0xDBFF || at + 1 >= bytes.Length)
            {
                built.AppendCodePoint((char32)0xFFFD);
                continue;
            }

            uint second = this.ReadUnitAt(bytes, at);
            if (second < 0xDC00 || second > 0xDFFF)
            {
                built.AppendCodePoint((char32)0xFFFD);
                continue;
            }

            at = at + 2;
            built.AppendCodePoint((char32)(0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00)));
        }

        if (at < bytes.Length)
            built.AppendCodePoint((char32)0xFFFD);
        return built.ToText();
    }

    /// The strict decode: `Incomplete` for an odd number of bytes or a high
    /// surrogate at the end, `Invalid` for a surrogate that is not paired.
    ///
    /// @failure EncodingError.Incomplete  an odd number of bytes, or a high surrogate with no
    ///                                    unit after it
    /// @failure EncodingError.Invalid     a low surrogate first, or a high one followed by
    ///                                    something that is not a low one
    /// @see Utf16Encoding.GetString
    public Result<String, EncodingError> TryGetString(byte[] bytes)
    {
        if (bytes.Length % 2 != 0)
            return Fail(EncodingError.Incomplete);

        nuint at = 0;
        while (at < bytes.Length)
        {
            uint first = this.ReadUnitAt(bytes, at);
            at = at + 2;

            if (first < 0xD800 || first > 0xDFFF)
                continue;
            if (first > 0xDBFF)
                return Fail(EncodingError.Invalid);
            if (at >= bytes.Length)
                return Fail(EncodingError.Incomplete);

            uint second = this.ReadUnitAt(bytes, at);
            if (second < 0xDC00 || second > 0xDFFF)
                return Fail(EncodingError.Invalid);
            at = at + 2;
        }
        return Ok(GetString(bytes));
    }

    uint ReadUnitAt(byte[] bytes, nuint at)
    {
        if (_bigEndian)
            return ((uint)bytes[at] << 8) | (uint)bytes[at + 1];
        return (uint)bytes[at] | ((uint)bytes[at + 1] << 8);
    }
}
