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

/// `multipart/form-data`: named fields and files, as an HTML form with a file
/// input posts them (RFC 7578).
///
///     var form = new MultipartFormDataContent();
///     form.Add(new StringContent("ann"), "user");
///     form.Add(new ByteArrayContent(photo), "photo", "photo.jpg");
public class MultipartFormDataContent : MultipartContent
{
    /// A form with a random boundary.
    public MultipartFormDataContent() : base("form-data") { }

    /// A form divided by `boundary`.
    public MultipartFormDataContent(String boundary) : base("form-data", boundary) { }

    /// Adds `content` as the field `name`.
    public void Add(HttpContent content, String name)
    {
        content.Headers.ContentDisposition = "form-data; name=" + QuoteHttpFormName(name);
        base.Add(content);
    }

    /// Adds `content` as the file `fileName` in the field `name`.
    public void Add(HttpContent content, String name, String fileName)
    {
        content.Headers.ContentDisposition =
            "form-data; name=" + QuoteHttpFormName(name) + "; filename=" + QuoteHttpFormName(fileName);
        base.Add(content);
    }
}

/// A form name as a quoted string, as RFC 7578 writes one.
internal String QuoteHttpFormName(String name)
{
    String escaped = name.Replace("\\", "\\\\").Replace("\"", "\\\"");
    return "\"" + escaped.Replace("\r", "%0D").Replace("\n", "%0A") + "\"";
}
