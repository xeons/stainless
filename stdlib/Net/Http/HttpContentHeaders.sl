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

import Standard.Text;
import Standard.Time;

/// The fields that describe a body: its type, its length, its coding.
///
/// `ContentLength` answers the content's own length when no field was set,
/// as .NET's does, so a `ByteArrayContent` knows its length without being
/// told.
public sealed class HttpContentHeaders : HttpHeaders
{
    private weak HttpContent? _owner;

    internal HttpContentHeaders(HttpContent owner) => _owner = owner;

    /// `Content-Disposition`, as written: `form-data; name="file"`.
    public String? ContentDisposition
    {
        get => GetFirstHttpValue("content-disposition");
        set => SetHttpValue("Content-Disposition", value);
    }

    /// The codings of `Content-Encoding`, outermost last. A body that
    /// `AutomaticDecompression` undid has none left.
    public String[] ContentEncoding
    {
        get
        {
            String? joined = GetJoinedHttpValue("content-encoding");
            if (joined == null)
                return new String[0u];
            return SplitHttpList(joined).ToArray();
        }
    }

    /// `Content-Language`.
    public String? ContentLanguage
    {
        get => GetJoinedHttpValue("content-language");
        set => SetHttpValue("Content-Language", value);
    }

    /// `Content-Length`: the field when it is set, and otherwise the
    /// content's own length when it knows one.
    public Optional<long> ContentLength
    {
        get
        {
            String? text = GetFirstHttpValue("content-length");
            if (text != null)
            {
                if (TryParseHttpDecimal(text, out long declared))
                    return declared;
                return None;
            }
            HttpContent? owner = _owner;
            if (owner != null && owner.TryComputeHttpContentLength(out long computed))
                return computed;
            return None;
        }
        set
        {
            if (value is Some length)
                SetHttpValue("Content-Length", Text.FromInteger(length.Value));
            else
                SetHttpValue("Content-Length", null);
        }
    }

    /// `Content-Type`, parsed; null when it is absent or malformed.
    public MediaTypeHeaderValue? ContentType
    {
        get
        {
            String? text = GetFirstHttpValue("content-type");
            if (text == null)
                return null;
            if (MediaTypeHeaderValue.Parse(text) is Ok parsed)
                return parsed.Value;
            return null;
        }
        set
        {
            if (value == null)
                SetHttpValue("Content-Type", null);
            else
                SetHttpValue("Content-Type", value.ToString());
        }
    }

    /// `Expires`, when it is an HTTP-date.
    public Optional<DateTimeOffset> Expires => ReadHttpDateValue("expires");

    /// `Last-Modified`, when it is an HTTP-date.
    public Optional<DateTimeOffset> LastModified
    {
        get => ReadHttpDateValue("last-modified");
        set
        {
            if (value is Some at)
                SetHttpValue("Last-Modified", at.Value.FormatHttpDate());
            else
                SetHttpValue("Last-Modified", null);
        }
    }

    protected override bool IsHttpHeaderAllowed(String key) => !IsHttpMessageHeaderKey(key);

    private Optional<DateTimeOffset> ReadHttpDateValue(String key)
    {
        String? text = GetFirstHttpValue(key);
        if (text == null)
            return None;
        if (DateTimeOffset.ParseHttpDate(text) is Ok parsed)
            return parsed.Value;
        return None;
    }
}
