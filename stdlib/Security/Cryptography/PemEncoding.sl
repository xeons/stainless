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

module Standard.Security.Cryptography;

import Standard.Ascii;
import Standard.Convert;

/// The textual encoding of RFC 7468: DER in base64, between two boundary
/// lines that name what it is.
///
/// ```csharp
/// if (PemEncoding.Find(text) is Some found)
/// {
///     var reader = new AsnReader(found.Value.Data, AsnEncodingRules.Der);
///     ...
/// }
/// String pem = PemEncoding.Write("CERTIFICATE", der);
/// ```
///
/// As .NET's `PemEncoding`: a block may sit anywhere in surrounding text, the
/// base64 may be wrapped at any width and with CRLF or LF, and a block whose
/// `END` label is not its `BEGIN` label is not a block. `Find` passes over
/// anything malformed and answers the first block that is whole, in one
/// forward pass: its time is linear in the text it reads.
public static class PemEncoding
{
    /// The first well-formed block in `text`.
    ///
    /// @param text  where to look
    /// @returns the block, or `None` when there is no well-formed one
    /// @see PemEncoding.Write
    public static Optional<PemFields> Find(String text) => Find(text, 0u);

    /// The first well-formed block in `text` at or after byte `start`, which
    /// is how to walk a file of several: pass the end of the last one's
    /// `Location`.
    ///
    /// A `BEGIN` boundary MUST start the text or follow whitespace, and an
    /// `END` boundary MUST end it or be followed by whitespace. Between them is
    /// base64 in the standard alphabet, padded, with whitespace anywhere.
    ///
    /// A caller walking one text SHOULD convert it once and call
    /// `FindUtf8`, since this converts `text` on every call.
    ///
    /// @param text   where to look
    /// @param start  the byte to look from; past the end finds nothing
    /// @returns the block, or `None` when there is no well-formed one
    public static Optional<PemFields> Find(String text, nuint start) =>
        FindUtf8(text.ToBytes(), start);

    /// The first well-formed block in the UTF-8 text `utf8`: .NET's
    /// `FindUtf8`.
    ///
    /// @param utf8  where to look
    /// @returns the block, or `None` when there is no well-formed one
    public static Optional<PemFields> FindUtf8(ReadOnlySpan<byte> utf8) => FindUtf8(utf8, 0u);

    /// `Find` over UTF-8 text, at or after byte `start`.
    ///
    /// Base64 holds no `-`, so the `END` boundary of a block is the first
    /// `-` after its `BEGIN` boundary, and a block whose first `-` is
    /// anything else is not one. Each byte is looked at a bounded number of
    /// times.
    ///
    /// @param utf8   where to look
    /// @param start  the byte to look from; past the end finds nothing
    /// @returns the block, or `None` when there is no well-formed one
    public static Optional<PemFields> FindUtf8(ReadOnlySpan<byte> utf8, nuint start)
    {
        ReadOnlySpan<byte> bytes = utf8;
        nuint at = start;
        while (at < bytes.Length)
        {
            var begin = FindPemBytes(bytes, "-----BEGIN ", at);
            if (!begin.Some)
                return None;

            nuint preeb = begin.Value;
            at = preeb + 1u;
            if (preeb > 0u && !IsWhiteSpace(bytes[preeb - 1u]))
                continue;

            nuint labelStart = preeb + 11u;
            var labelEnd = FindPemLabelEnd(bytes, labelStart);
            if (!labelEnd.Some || !IsValidPemLabel(bytes, labelStart, labelEnd.Value))
                continue;

            nuint contentStart = labelEnd.Value + 5u;
            nuint post = contentStart;
            while (post < bytes.Length && bytes[post] != 45 && IsPemContentByte(bytes[post]))
                post++;
            if (post == bytes.Length)
                return None;
            if (bytes[post] != 45)                                  // '-'
                continue;
            if (!IsPemEndBoundaryAt(bytes, post, labelStart, labelEnd.Value))
                continue;

            nuint blockEnd = post + 9u + (labelEnd.Value - labelStart) + 5u;
            if (blockEnd < bytes.Length && !IsWhiteSpace(bytes[blockEnd]))
                continue;

            nuint base64Start = contentStart;
            nuint base64End = post;
            while (base64Start < base64End && IsWhiteSpace(bytes[base64Start]))
                base64Start++;
            while (base64End > base64Start && IsWhiteSpace(bytes[base64End - 1u]))
                base64End--;

            var data = DecodePemBase64(bytes, base64Start, base64End);
            if (!data.Some)
                continue;

            String label = CreatePemString(bytes, labelStart, labelEnd.Value);
            return new PemFields(label, data.Value,
                                 new Range(preeb, blockEnd),
                                 new Range(labelStart, labelEnd.Value),
                                 new Range(base64Start, base64End));
        }

        return None;
    }

    /// `data` as a PEM block: the boundaries, and base64 in lines of 64
    /// separated by `\n`. No newline follows the `END` boundary.
    ///
    /// @param label  what the data is; MUST be valid, which `IsValidLabel` answers,
    ///               and aborts when it is not
    /// @param data   the bytes to encode, usually DER
    /// @see PemEncoding.Find
    public static String Write(String label, ReadOnlySpan<byte> data)
    {
        if (!IsValidLabel(label))
            sl_fail("PemEncoding.Write: the label is not valid under RFC 7468");

        String base64 = Convert.ToBase64String(data.ToArray());
        var built = new StringBuilder();
        built.Append($"-----BEGIN {label}-----\n");

        byte[] characters = base64.ToBytes();
        for (nuint line = 0u; line < characters.Length; line += 64)
        {
            nuint end = line + 64u;
            if (end > characters.Length)
                end = characters.Length;
            built.Append(CreatePemString(characters, line, end));
            built.Append("\n");
        }

        built.Append($"-----END {label}-----");
        return built.ToText();
    }

    /// Whether RFC 7468 allows `label`: printable ASCII other than `-`, with a
    /// single space or hyphen allowed between two such characters. Empty is
    /// allowed.
    public static bool IsValidLabel(String label)
    {
        byte[] bytes = label.ToBytes();
        return IsValidPemLabel(bytes, 0u, bytes.Length);
    }
}

bool IsValidPemLabel(ReadOnlySpan<byte> bytes, nuint start, nuint end)
{
    bool previousWasSeparator = true;
    for (nuint i = start; i < end; i++)
    {
        byte one = bytes[i];
        if (one == 32 || one == 45)                                 // ' ' or '-'
        {
            if (previousWasSeparator)
                return false;
            previousWasSeparator = true;
        }
        else if (one > 32 && one < 127)
        {
            previousWasSeparator = false;
        }
        else
        {
            return false;
        }
    }

    return start == end || !previousWasSeparator;
}

/// Where the `-----` closing a `BEGIN` label starting at `start` is: the
/// first one, before any byte a label cannot hold.
Optional<nuint> FindPemLabelEnd(ReadOnlySpan<byte> bytes, nuint start)
{
    for (nuint at = start; at < bytes.Length; at++)
    {
        byte one = bytes[at];
        if (one < 32 || one > 126)
            return None;
        if (one == 45 && at + 5u <= bytes.Length && bytes[at + 1u] == 45 &&
            bytes[at + 2u] == 45 && bytes[at + 3u] == 45 && bytes[at + 4u] == 45)
        {
            return Some(at);
        }
    }
    return None;
}

/// Whether `one` may sit between two boundaries: base64 or whitespace.
bool IsPemContentByte(byte one) =>
    (one >= 65 && one <= 90) || (one >= 97 && one <= 122) || (one >= 48 && one <= 57) ||
    one == 43 || one == 47 || one == 61 || IsWhiteSpace(one);

/// Whether `-----END `, the label between `labelStart` and `labelEnd`, and
/// `-----` start at `at`.
bool IsPemEndBoundaryAt(ReadOnlySpan<byte> bytes, nuint at, nuint labelStart, nuint labelEnd)
{
    nuint labelLength = labelEnd - labelStart;
    if (at + 9u + labelLength + 5u > bytes.Length)
        return false;
    byte[] opening = "-----END ".ToBytes();
    for (nuint i = 0u; i < 9u; i++)
    {
        if (bytes[at + i] != opening[i])
            return false;
    }
    for (nuint i = 0u; i < labelLength; i++)
    {
        if (bytes[at + 9u + i] != bytes[labelStart + i])
            return false;
    }
    for (nuint i = 0u; i < 5u; i++)
    {
        if (bytes[at + 9u + labelLength + i] != 45)
            return false;
    }
    return true;
}

/// Where `needle` next occurs in `bytes` at or after `start`.
Optional<nuint> FindPemBytes(ReadOnlySpan<byte> bytes, String needle, nuint start)
{
    byte[] wanted = needle.ToBytes();
    if (wanted.Length > bytes.Length)
        return None;

    for (nuint at = start; at + wanted.Length <= bytes.Length; at++)
    {
        bool matched = true;
        for (nuint i = 0u; i < wanted.Length; i++)
        {
            if (bytes[at + i] != wanted[i])
            {
                matched = false;
                break;
            }
        }
        if (matched)
            return Some(at);
    }

    return None;
}

String CreatePemString(ReadOnlySpan<byte> bytes, nuint start, nuint end)
{
    var built = new StringBuilder();
    built.AppendBytes(bytes[start:end].ToArray());
    return built.ToText();
}

/// The base64 between `start` and `end` decoded, or `None` when it holds a
/// character outside the standard alphabet, padding anywhere but the end, or
/// a count of characters that is not a multiple of four.
Optional<byte[]> DecodePemBase64(ReadOnlySpan<byte> bytes, nuint start, nuint end)
{
    var characters = new StringBuilder();
    nuint count = 0u;
    nuint padding = 0u;
    for (nuint i = start; i < end; i++)
    {
        byte one = bytes[i];
        if (IsWhiteSpace(one))
            continue;

        bool letter = (one >= 65 && one <= 90) || (one >= 97 && one <= 122);
        bool digit = one >= 48 && one <= 57;
        if (one == 61)                                              // '='
        {
            padding++;
        }
        else if (padding > 0u || !(letter || digit || one == 43 || one == 47))
        {
            return None;
        }

        characters.AppendByte(one);
        count++;
    }

    if (count % 4u != 0u || padding > 2u)
        return None;

    var decoded = Convert.FromBase64String(characters.ToText());
    if (!decoded.Ok)
        return None;
    return Some(decoded.Value);
}
