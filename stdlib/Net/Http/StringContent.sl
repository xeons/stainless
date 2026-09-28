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

module Standard.Net.Http;

import Standard.Encoding;

/// A body of text, encoded when it is made.
///
///     new StringContent("hello")                          // text/plain; charset=utf-8
///     new StringContent(json, Encoding.CreateUtf8(), "application/json")
///
/// `Content-Type` names the media type and the encoding's charset.
public class StringContent : ByteArrayContent
{
    /// `content` as UTF-8, sent as `text/plain`.
    public StringContent(String content) : this(content, null, "text/plain") { }

    /// `content` in `encoding`, or UTF-8 for null, sent as `text/plain`.
    public StringContent(String content, IEncoding? encoding) : this(content, encoding, "text/plain") { }

    /// `content` in `encoding`, or UTF-8 for null, sent as `mediaType`.
    public StringContent(String content, IEncoding? encoding, String mediaType)
    {
        base(EncodeHttpText(content, encoding));
        String charSet = encoding == null ? "utf-8" : encoding.Name;
        Headers.ContentType = new MediaTypeHeaderValue(mediaType, charSet);
    }

    /// `content` as UTF-8, sent as `mediaType`, whose own charset, when it
    /// names one this module knows, decides the encoding instead.
    public StringContent(String content, MediaTypeHeaderValue mediaType)
    {
        base(EncodeHttpText(content, FindHttpEncodingOrNull(mediaType.CharSet)));
        Headers.ContentType = mediaType;
    }
}

internal byte[] EncodeHttpText(String content, IEncoding? encoding)
{
    if (encoding == null)
        return content.ToBytes();
    return encoding.GetBytes(content);
}

internal IEncoding? FindHttpEncodingOrNull(String? charSet)
{
    if (charSet == null)
        return null;
    return FindHttpEncoding(charSet);
}
