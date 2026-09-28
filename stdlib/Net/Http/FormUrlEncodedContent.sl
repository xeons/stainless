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

import Standard.Collections;
import Standard.Text;

/// Names and values as `application/x-www-form-urlencoded`: what an HTML
/// form posts.
///
///     var form = new FormUrlEncodedContent([
///         new KeyValuePair<String, String>("user", "ann"),
///         new KeyValuePair<String, String>("note", "a & b"),
///     ]);                                   // user=ann&note=a+%26+b
public class FormUrlEncodedContent : ByteArrayContent
{
    /// `pairs`, in order, each name and value escaped and a space written as
    /// `+`.
    public FormUrlEncodedContent(IEnumerable<KeyValuePair<String, String>> pairs)
    {
        base(EncodeHttpForm(pairs).ToBytes());
        Headers.ContentType = new MediaTypeHeaderValue("application/x-www-form-urlencoded");
    }
}

internal String EncodeHttpForm(IEnumerable<KeyValuePair<String, String>> pairs)
{
    var text = new StringBuilder();
    bool first = true;
    foreach (var pair in pairs)
    {
        if (!first)
            text.Append("&");
        first = false;
        text.Append(EscapeHttpFormText(pair.Key));
        text.Append("=");
        text.Append(EscapeHttpFormText(pair.Value));
    }
    return text.ToText();
}

internal String EscapeHttpFormText(String text) => Uri.EscapeDataString(text).Replace("%20", "+");
