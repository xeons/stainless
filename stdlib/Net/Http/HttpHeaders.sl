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

/// The fields of a message head, by name, each with every value it was
/// given.
///
///     request.Headers.Add("Accept", "text/html");
///     request.Headers.Add("Accept", "application/xhtml+xml");
///     String[] accepted = request.Headers.GetValues("accept");   // both
///
/// Names compare without regard to ASCII case and keep the spelling they were
/// first added with. A field given several values is written as several lines,
/// so a `Set-Cookie` is never joined with a comma.
///
/// .NET's `HttpHeaders`, with `GetValues` answering an empty array where .NET
/// throws. `Add` validates what it is given; `TryAddWithoutValidation` checks
/// only the name, and a value with a line break in it is refused when the
/// request is sent rather than written.
public class HttpHeaders
{
    private List<HttpHeaderField> _fields = new List<HttpHeaderField>();

    protected HttpHeaders() { }

    /// How many distinct names are present.
    public nuint Count => _fields.Count;

    /// Adds `value` to the field `name`, after its existing values.
    ///
    /// @param name   the field name, which MUST be a token
    /// @param value  the value, which MUST NOT hold a control character but
    ///               HTAB
    /// @returns false when either is malformed, or `name` belongs to another
    ///          collection — a `Content-Type` belongs on the content
    public bool Add(String name, String value)
    {
        if (!IsHttpToken(name) || !IsHttpFieldValue(value))
            return false;
        if (!IsHttpHeaderAllowed(name.ToLowerAscii()))
            return false;
        AppendHttpValue(name, TrimHttpWhitespace(value));
        return true;
    }

    /// Adds each of `values` to the field `name`. Nothing is added when any
    /// of them is malformed.
    public bool Add(String name, ReadOnlySpan<String> values)
    {
        foreach (var value in values)
        {
            if (!IsHttpFieldValue(value))
                return false;
        }
        if (!IsHttpToken(name) || !IsHttpHeaderAllowed(name.ToLowerAscii()))
            return false;
        foreach (var value in values)
            AppendHttpValue(name, TrimHttpWhitespace(value));
        return true;
    }

    /// Adds `value` as it is, checking only that `name` is a token that
    /// belongs here.
    public bool TryAddWithoutValidation(String name, String value)
    {
        if (!IsHttpToken(name) || !IsHttpHeaderAllowed(name.ToLowerAscii()))
            return false;
        AppendHttpValue(name, value);
        return true;
    }

    /// Whether the field `name` is present.
    public bool Contains(String name) => FindHttpField(name.ToLowerAscii()) != null;

    /// Removes the field `name` and every value it had. False when it was not
    /// present.
    public bool Remove(String name)
    {
        String key = name.ToLowerAscii();
        for (nuint i = 0u; i < _fields.Count; i++)
        {
            if (_fields[i].Key == key)
            {
                _fields.RemoveAt(i);
                return true;
            }
        }
        return false;
    }

    /// Removes every field.
    public void Clear() => _fields.Clear();

    /// Every value of the field `name`, in the order added; empty when it is
    /// not present.
    public String[] GetValues(String name)
    {
        var field = FindHttpField(name.ToLowerAscii());
        if (field == null)
            return new String[0u];
        return field.Values.ToArray();
    }

    /// Every value of the field `name`, or none when it is not present.
    public Optional<String[]> TryGetValues(String name)
    {
        var field = FindHttpField(name.ToLowerAscii());
        if (field == null)
            return None;
        return field.Values.ToArray();
    }

    /// Each field's name and values, in the order the names were first added.
    public IEnumerator<KeyValuePair<String, String[]>> GetEnumerator()
    {
        var pairs = new List<KeyValuePair<String, String[]>>();
        foreach (var field in _fields)
            pairs.Add(new KeyValuePair<String, String[]>(field.Name, field.Values.ToArray()));
        return pairs.GetEnumerator();
    }

    /// The fields as a head writes them: a line per name, its values joined by
    /// `, `, each line ending in CRLF.
    public String ToString()
    {
        var text = new StringBuilder();
        foreach (var field in _fields)
        {
            text.Append(field.Name);
            text.Append(": ");
            text.Append(", ".Join(field.Values.ToArray()));
            text.Append("\r\n");
        }
        return text.ToText();
    }

    /// Whether a field of this lower-case name belongs in this collection.
    protected virtual bool IsHttpHeaderAllowed(String key) => true;

    // ------------------------------------------------------------ for the module

    internal List<HttpHeaderField> Fields => _fields;

    internal HttpHeaderField? FindHttpField(String key)
    {
        foreach (var field in _fields)
        {
            if (field.Key == key)
                return field;
        }
        return null;
    }

    /// The first value of the field with this lower-case name, or null.
    internal String? GetFirstHttpValue(String key)
    {
        var field = FindHttpField(key);
        if (field == null || field.Values.IsEmpty)
            return null;
        return field.Values[0u];
    }

    /// Every value of the field joined by `, `, or null.
    internal String? GetJoinedHttpValue(String key)
    {
        var field = FindHttpField(key);
        if (field == null)
            return null;
        return ", ".Join(field.Values.ToArray());
    }

    /// Replaces the field's values with `value`, or removes it for null.
    internal void SetHttpValue(String name, String? value)
    {
        Remove(name);
        if (value != null)
            AppendHttpValue(name, value);
    }

    internal void AppendHttpValue(String name, String value)
    {
        var found = FindHttpField(name.ToLowerAscii());
        if (found != null)
        {
            found.Values.Add(value);
            return;
        }
        var field = new HttpHeaderField(name);
        field.Values.Add(value);
        _fields.Add(field);
    }

    /// Whether any element of any value of the field is `token`, ignoring
    /// case: `close` in `Connection`, `chunked` in `Transfer-Encoding`.
    internal bool HasHttpListToken(String key, String token)
    {
        var field = FindHttpField(key);
        if (field == null)
            return false;
        foreach (var value in field.Values)
        {
            foreach (var element in SplitHttpList(value))
            {
                if (IsHttpNameEqual(element, token))
                    return true;
            }
        }
        return false;
    }

    /// Adds `token` to a list field, or takes every copy of it out.
    internal void SetHttpListToken(String name, String token, bool present)
    {
        String key = name.ToLowerAscii();
        var kept = new List<String>();
        var field = FindHttpField(key);
        if (field != null)
        {
            foreach (var value in field.Values)
            {
                foreach (var element in SplitHttpList(value))
                {
                    if (!IsHttpNameEqual(element, token))
                        kept.Add(element);
                }
            }
        }
        if (present)
            kept.Add(token);
        Remove(name);
        foreach (var element in kept)
            AppendHttpValue(name, element);
    }

    /// Copies every field of `other` in after these.
    internal void AppendHttpHeaders(HttpHeaders other)
    {
        foreach (var field in other._fields)
        {
            foreach (var value in field.Values)
                AppendHttpValue(field.Name, value);
        }
    }
}

/// One field: its name as first written, and every value it was given.
internal sealed class HttpHeaderField
{
    internal String Name;
    internal String Key;
    internal List<String> Values;

    internal HttpHeaderField(String name)
    {
        Name = name;
        Key = name.ToLowerAscii();
        Values = new List<String>();
    }
}

/// Whether a lower-case field name describes the content rather than the
/// message, and so belongs in `HttpContentHeaders`.
internal bool IsHttpContentHeaderKey(String key)
{
    switch (key)
    {
        case "allow":
        case "content-disposition":
        case "content-encoding":
        case "content-language":
        case "content-length":
        case "content-location":
        case "content-md5":
        case "content-range":
        case "content-type":
        case "expires":
        case "last-modified":
            return true;
    }
    return false;
}

/// Whether a lower-case field name belongs to a request or a response head
/// and never to content.
internal bool IsHttpMessageHeaderKey(String key)
{
    switch (key)
    {
        case "accept":
        case "accept-charset":
        case "accept-encoding":
        case "accept-language":
        case "authorization":
        case "cache-control":
        case "connection":
        case "cookie":
        case "date":
        case "expect":
        case "host":
        case "keep-alive":
        case "location":
        case "proxy-authenticate":
        case "proxy-authorization":
        case "proxy-connection":
        case "referer":
        case "server":
        case "set-cookie":
        case "te":
        case "trailer":
        case "transfer-encoding":
        case "upgrade":
        case "user-agent":
        case "via":
        case "www-authenticate":
            return true;
    }
    return false;
}
