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

// -------------------------------------------------------------------- UTF-8

/// UTF-8, which is what a `String` already holds.
///
/// Both directions are a copy rather than a transcode. `GetString` still has to
/// validate, because a `byte[]` from outside the program is not a `String` and
/// has promised nothing.
public class Utf8Encoding : IEncoding
{
    /// `"utf-8"`.
    public String Name => "utf-8";

    /// EF BB BF. UTF-8 needs no byte order mark -- there is only one order --
    /// so this is what to *recognise*, not what to write by habit.
    public byte[] Preamble => [0xEF, 0xBB, 0xBF];

    /// The length the text already has. O(1), since no transcode is needed.
    public nuint GetByteCount(String text) => text.ByteLength();

    /// The text's own bytes. A copy, not a transcode.
    public byte[] GetBytes(String text) => text.ToBytes();

    /// Every scalar; that is what UTF-8 is for.
    public bool CanRepresent(char32 scalar) => true;

    /// A decoder that holds the first bytes of a sequence whose rest has
    /// not arrived.
    public IDecoder GetDecoder() => new Utf8Decoder(this);

    /// `bytes` validated, with each malformed byte replaced by U+FFFD.
    ///
    /// One replacement per bad byte rather than per bad sequence, so a run of
    /// rubbish is as many U+FFFDs as it is bytes. Malformed means what
    /// `TryGetString` refuses, overlong forms and surrogates included.
    public String GetString(byte[] bytes)
    {
        var built = new StringBuilder();
        nuint at = 0;

        while (at < bytes.Length)
        {
            nuint width = GetUtf8Width(bytes[at]);

            if (width == 0 || at + width > bytes.Length || !HasContinuationBytes(bytes, at, width))
            {
                built.AppendCodePoint((char32)0xFFFD);
                at++;
                continue;
            }

            char32 scalar = DecodeUtf8Scalar(bytes, at, width);
            if (!IsScalarSpelledOnce((uint)scalar, width))
            {
                built.AppendCodePoint((char32)0xFFFD);
                at++;
                continue;
            }

            built.AppendCodePoint(scalar);
            at = at + width;
        }
        return built.ToText();
    }

    /// The strict decode: `Invalid` for anything that is not a scalar, and
    /// `Incomplete` for a sequence the input ran out during.
    ///
    /// Stricter than `GetString`, and deliberately: an overlong sequence, a
    /// surrogate and a value past U+10FFFF are each refused, because each is a
    /// way of spelling something that is not a character and each has been a
    /// security hole in a decoder that accepted it.
    ///
    /// @failure EncodingError.Incomplete  a sequence the bytes ran out during
    /// @failure EncodingError.Invalid     a byte that starts nothing, a missing continuation
    ///                                    byte, an overlong form, a surrogate, or a value past
    ///                                    U+10FFFF
    /// @see Utf8Encoding.GetString
    public Result<String, EncodingError> TryGetString(byte[] bytes)
    {
        nuint at = 0;

        while (at < bytes.Length)
        {
            nuint width = GetUtf8Width(bytes[at]);
            if (width == 0)
                return Fail(EncodingError.Invalid);
            if (at + width > bytes.Length)
                return Fail(EncodingError.Incomplete);
            if (!HasContinuationBytes(bytes, at, width))
                return Fail(EncodingError.Invalid);

            if (!IsScalarSpelledOnce((uint)DecodeUtf8Scalar(bytes, at, width), width))
                return Fail(EncodingError.Invalid);

            at = at + width;
        }
        return Ok(GetString(bytes));
    }
}
