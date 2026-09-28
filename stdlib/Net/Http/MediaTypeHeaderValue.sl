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

/// A media type and its parameters: the value of `Content-Type`.
///
///     var type = new MediaTypeHeaderValue("text/plain", "utf-8");
///     type.ToString();                     // text/plain; charset=utf-8
///
/// Parameter names compare without regard to case. A value that is not a
/// token is written as a quoted string.
public sealed class MediaTypeHeaderValue
{
    private String _mediaType;
    private List<KeyValuePair<String, String>> _parameters = new List<KeyValuePair<String, String>>();

    /// `mediaType`, as `type/subtype`, with no parameters.
    public MediaTypeHeaderValue(String mediaType) => _mediaType = mediaType;

    /// `mediaType` with a `charset` parameter, when `charSet` is not null.
    public MediaTypeHeaderValue(String mediaType, String? charSet)
    {
        _mediaType = mediaType;
        if (charSet != null)
            _parameters.Add(new KeyValuePair<String, String>("charset", charSet));
    }

    /// `type/subtype`, without parameters.
    public String MediaType
    {
        get => _mediaType;
        set => _mediaType = value;
    }

    /// The `charset` parameter, or null.
    public String? CharSet
    {
        get => GetParameter("charset");
        set => SetParameter("charset", value);
    }

    /// The parameters, in order, names as written.
    public List<KeyValuePair<String, String>> Parameters => _parameters;

    /// The parameter `name`, or null.
    public String? GetParameter(String name)
    {
        foreach (var parameter in _parameters)
        {
            if (IsHttpNameEqual(parameter.Key, name))
                return parameter.Value;
        }
        return null;
    }

    /// Replaces the parameter `name`, or removes it for null.
    public void SetParameter(String name, String? value)
    {
        for (nuint i = 0u; i < _parameters.Count; i++)
        {
            if (IsHttpNameEqual(_parameters[i].Key, name))
            {
                _parameters.RemoveAt(i);
                break;
            }
        }
        if (value != null)
            _parameters.Add(new KeyValuePair<String, String>(name, value));
    }

    /// `text` read as `type/subtype *( ; name=value )`, a value either a token
    /// or a quoted string.
    ///
    /// @failure ParseError.Empty      there is nothing but whitespace
    /// @failure ParseError.Malformed  it is not that shape
    public static Result<MediaTypeHeaderValue, ParseError> Parse(String text)
    {
        String trimmed = TrimHttpWhitespace(text);
        if (trimmed.IsEmpty)
            return Fail(ParseError.Empty);

        long semicolon = trimmed.IndexOf(';');
        String type = TrimHttpWhitespace(semicolon < 0 ? trimmed : trimmed.Substring(0u, (nuint)semicolon));
        long slash = type.IndexOf('/');
        if (slash <= 0 || !IsHttpToken(type.Substring(0u, (nuint)slash)) ||
            !IsHttpToken(type.Substring((nuint)slash + 1u)))
            return Fail(ParseError.Malformed);

        var parsed = new MediaTypeHeaderValue(type);
        if (semicolon < 0)
            return Ok(parsed);

        nuint at = (nuint)semicolon + 1u;
        nuint length = trimmed.ByteLength();
        while (at < length)
        {
            while (at < length && (IsHttpWhitespace(trimmed.GetByteAt(at)) || trimmed.GetByteAt(at) == (byte)';'))
                at++;
            if (at >= length)
                break;

            nuint nameStart = at;
            while (at < length && IsHttpTokenByte(trimmed.GetByteAt(at)))
                at++;
            if (at == nameStart || at >= length || trimmed.GetByteAt(at) != (byte)'=')
                return Fail(ParseError.Malformed);
            String name = trimmed.Substring(nameStart, at - nameStart);
            at++;

            String value = "";
            if (at < length && trimmed.GetByteAt(at) == (byte)'"')
            {
                var quoted = new StringBuilder();
                at++;
                bool closed = false;
                while (at < length)
                {
                    byte c = trimmed.GetByteAt(at);
                    if (c == (byte)'"')
                    {
                        closed = true;
                        at++;
                        break;
                    }
                    if (c == (byte)'\\' && at + 1u < length)
                        at++;
                    quoted.AppendByte(trimmed.GetByteAt(at));
                    at++;
                }
                if (!closed)
                    return Fail(ParseError.Malformed);
                value = quoted.ToText();
            }
            else
            {
                nuint valueStart = at;
                while (at < length && IsHttpTokenByte(trimmed.GetByteAt(at)))
                    at++;
                if (at == valueStart)
                    return Fail(ParseError.Malformed);
                value = trimmed.Substring(valueStart, at - valueStart);
            }
            parsed._parameters.Add(new KeyValuePair<String, String>(name, value));

            while (at < length && IsHttpWhitespace(trimmed.GetByteAt(at)))
                at++;
            if (at < length && trimmed.GetByteAt(at) != (byte)';')
                return Fail(ParseError.Malformed);
        }
        return Ok(parsed);
    }

    /// The value as a field writes it.
    public String ToString()
    {
        var text = new StringBuilder();
        text.Append(_mediaType);
        foreach (var parameter in _parameters)
        {
            text.Append("; ");
            text.Append(parameter.Key);
            text.Append("=");
            text.Append(QuoteHttpValueIfNeeded(parameter.Value));
        }
        return text.ToText();
    }
}

/// `value` as a token when it is one, and as a quoted string when not.
internal String QuoteHttpValueIfNeeded(String value)
{
    if (IsHttpToken(value))
        return value;
    var quoted = new StringBuilder();
    quoted.Append("\"");
    for (nuint i = 0u; i < value.ByteLength(); i++)
    {
        byte c = value.GetByteAt(i);
        if (c == (byte)'"' || c == (byte)'\\')
            quoted.Append("\\");
        quoted.AppendByte(c);
    }
    quoted.Append("\"");
    return quoted.ToText();
}
