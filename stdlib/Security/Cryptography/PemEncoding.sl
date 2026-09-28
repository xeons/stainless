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
/// anything malformed and answers the first block that is whole.
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
    /// @param text   where to look
    /// @param start  the byte to look from; past the end finds nothing
    /// @returns the block, or `None` when there is no well-formed one
    public static Optional<PemFields> Find(String text, nuint start)
    {
        byte[] bytes = text.ToBytes();
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
            var labelEnd = FindPemBytes(bytes, "-----", labelStart);
            if (!labelEnd.Some)
                return None;
            if (!IsValidPemLabel(bytes, labelStart, labelEnd.Value))
                continue;

            var label = CreatePemString(bytes, labelStart, labelEnd.Value);
            nuint contentStart = labelEnd.Value + 5u;
            String postBoundary = $"-----END {label}-----";

            // With no END boundary left at all, no later BEGIN can succeed.
            var anyEnd = FindPemBytes(bytes, "-----END ", contentStart);
            if (!anyEnd.Some)
                return None;

            var post = FindPemBytes(bytes, postBoundary, anyEnd.Value);
            if (!post.Some)
                continue;
            nuint blockEnd = post.Value + postBoundary.ByteLength();
            if (blockEnd < bytes.Length && !IsWhiteSpace(bytes[blockEnd]))
                continue;

            nuint base64Start = contentStart;
            nuint base64End = post.Value;
            while (base64Start < base64End && IsWhiteSpace(bytes[base64Start]))
                base64Start++;
            while (base64End > base64Start && IsWhiteSpace(bytes[base64End - 1u]))
                base64End--;

            var data = DecodePemBase64(bytes, base64Start, base64End);
            if (!data.Some)
                continue;

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

bool IsValidPemLabel(byte[] bytes, nuint start, nuint end)
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

/// Where `needle` next occurs in `bytes` at or after `start`.
Optional<nuint> FindPemBytes(byte[] bytes, String needle, nuint start)
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

String CreatePemString(byte[] bytes, nuint start, nuint end)
{
    var built = new StringBuilder();
    built.AppendBytes(bytes[start:end].ToArray());
    return built.ToText();
}

/// The base64 between `start` and `end` decoded, or `None` when it holds a
/// character outside the standard alphabet, padding anywhere but the end, or
/// a count of characters that is not a multiple of four.
Optional<byte[]> DecodePemBase64(byte[] bytes, nuint start, nuint end)
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
