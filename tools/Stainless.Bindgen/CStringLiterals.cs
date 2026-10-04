// Stainless - an experimental general-purpose language.
// Copyright (C) 2026 Brandon Scott
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

using System.Globalization;
using System.Text;

namespace Stainless.Bindgen;

/// <summary>C string literals read as their bytes, and text written as a Stainless literal.</summary>
public static class CStringLiterals
{
    /// <summary>
    /// The bytes of a macro body that is one or more adjacent narrow string
    /// literals, in parentheses or not; null for anything else.
    /// </summary>
    public static byte[]? Decode(string body)
    {
        string text = body.Trim();
        while (text.Length >= 2 && text[0] == '(' && text[^1] == ')')
            text = text[1..^1].Trim();

        var bytes = new List<byte>();
        int at = 0;
        bool any = false;
        while (true)
        {
            while (at < text.Length && char.IsWhiteSpace(text[at]))
                at++;
            if (at == text.Length) return any ? bytes.ToArray() : null;

            if (text.AsSpan(at).StartsWith("u8\""))
                at += 2;
            if (text[at] != '"') return null;
            at++;

            while (true)
            {
                if (at == text.Length) return null;
                char c = text[at++];
                if (c == '"') break;
                if (c != '\\')
                {
                    string character = char.IsHighSurrogate(c) && at < text.Length ? text.Substring(at++ - 1, 2) : c.ToString();
                    bytes.AddRange(Encoding.UTF8.GetBytes(character));
                    continue;
                }

                if (at == text.Length) return null;
                char escape = text[at++];
                switch (escape)
                {
                    case 'a': bytes.Add(7); break;
                    case 'b': bytes.Add(8); break;
                    case 'f': bytes.Add(12); break;
                    case 'n': bytes.Add(10); break;
                    case 'r': bytes.Add(13); break;
                    case 't': bytes.Add(9); break;
                    case 'v': bytes.Add(11); break;
                    case '\\' or '\'' or '"' or '?': bytes.Add((byte)escape); break;

                    case >= '0' and <= '7':
                    {
                        int value = escape - '0';
                        for (int digits = 1; digits < 3 && at < text.Length && text[at] is >= '0' and <= '7'; digits++)
                            value = value * 8 + (text[at++] - '0');
                        if (value > 0xFF) return null;
                        bytes.Add((byte)value);
                        break;
                    }

                    case 'x':
                    {
                        int start = at;
                        while (at < text.Length && char.IsAsciiHexDigit(text[at]))
                            at++;
                        if (at == start || at - start > 2) return null;
                        bytes.Add(byte.Parse(text.AsSpan(start, at - start), NumberStyles.HexNumber, CultureInfo.InvariantCulture));
                        break;
                    }

                    case 'u' or 'U':
                    {
                        int length = escape == 'u' ? 4 : 8;
                        if (at + length > text.Length ||
                            !int.TryParse(text.AsSpan(at, length), NumberStyles.HexNumber, CultureInfo.InvariantCulture, out int point) ||
                            !Rune.IsValid(point))
                            return null;
                        at += length;
                        bytes.AddRange(Encoding.UTF8.GetBytes(new Rune(point).ToString()));
                        break;
                    }

                    default:
                        return null;
                }
            }

            any = true;
        }
    }

    /// <summary>Text as a Stainless string literal, in ASCII: anything else is escaped by code point.</summary>
    public static string Spell(string text)
    {
        var literal = new StringBuilder("\"");
        foreach (var rune in text.EnumerateRunes())
        {
            int value = rune.Value;
            if (value == '"' || value == '\\')
                literal.Append('\\').Append((char)value);
            else if (value is >= 0x20 and < 0x7F)
                literal.Append((char)value);
            else if (value <= 0xFFFF)
                literal.Append('\\').Append('u').Append(value.ToString("X4", CultureInfo.InvariantCulture));
            else
                literal.Append('\\').Append('U').Append(value.ToString("X8", CultureInfo.InvariantCulture));
        }

        return literal.Append('"').ToString();
    }
}
