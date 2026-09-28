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

module Standard.Formats.Asn1;

/// Object identifiers between their dotted form and their contents octets.
///
/// ```csharp
/// byte[] contents = try Oid.FromDottedString("1.2.840.113549");   // 2a 86 48 86 f7 0d
/// String dotted = try Oid.ToDottedString(contents);
/// ```
///
/// The contents are what follows the tag and the length; `AsnReader` and
/// `AsnWriter` add those. **Every arc MUST fit a `ulong`.** The UUID arcs
/// under `2.25` are 128 bits and are refused with `AsnError.OutOfRange`;
/// nothing in X.509 or TLS uses them.
public static class Oid
{
    /// The dotted form of an identifier's contents octets.
    ///
    /// The first octet group holds two arcs, as X.690 §8.19.4 says: under 40
    /// is `0.n`, under 80 is `1.n`, and the rest is `2.n`.
    ///
    /// @param contents  the octets after the tag and the length
    /// @failure AsnError.BadLength           there are no octets
    /// @failure AsnError.NonMinimalEncoding  an arc starts with the padding octet `0x80`
    /// @failure AsnError.Malformed           the last arc does not end
    /// @failure AsnError.OutOfRange          an arc does not fit a `ulong`
    /// @see Oid.FromDottedString
    public static Result<String, AsnError> ToDottedString(ReadOnlySpan<byte> contents)
    {
        if (contents.Length == 0u)
            return Fail(AsnError.BadLength);

        var built = new StringBuilder();
        nuint at = 0u;
        bool first = true;
        while (at < contents.Length)
        {
            if (contents[at] == 0x80)
                return Fail(AsnError.NonMinimalEncoding);

            ulong arc = 0u;
            bool ended = false;
            while (at < contents.Length)
            {
                uint octet = (uint)contents[at];
                at++;
                if (arc > (18446744073709551615u >> 7))
                    return Fail(AsnError.OutOfRange);
                arc = (arc << 7) | (ulong)(octet & 0x7Fu);
                if ((octet & 0x80u) == 0u)
                {
                    ended = true;
                    break;
                }
            }

            if (!ended)
                return Fail(AsnError.Malformed);

            if (first)
            {
                if (arc < 40u)
                {
                    built.Append("0.");
                    built.Append(FromInteger(arc));
                }
                else if (arc < 80u)
                {
                    built.Append("1.");
                    built.Append(FromInteger(arc - 40u));
                }
                else
                {
                    built.Append("2.");
                    built.Append(FromInteger(arc - 80u));
                }
                first = false;
            }
            else
            {
                built.Append(".");
                built.Append(FromInteger(arc));
            }
        }

        return Ok(built.ToText());
    }

    /// The contents octets of a dotted identifier.
    ///
    /// Two arcs at least, decimal digits with no sign and no leading zero, and
    /// one dot between each pair. The first arc is 0, 1 or 2, and under 0 and
    /// 1 the second is below 40.
    ///
    /// @param dotted  the identifier, as `1.2.840.113549`
    /// @failure AsnError.Malformed   the text is not in that form
    /// @failure AsnError.OutOfRange  an arc does not fit a `ulong`
    /// @see Oid.ToDottedString
    public static Result<byte[], AsnError> FromDottedString(String dotted)
    {
        byte[] text = dotted.ToBytes();
        var arcs = new ulong[text.Length / 2u + 1u];
        nuint count = 0u;
        nuint at = 0u;

        while (true)
        {
            nuint start = at;
            ulong arc = 0u;
            while (at < text.Length && text[at] >= 48 && text[at] <= 57)
            {
                ulong digit = (ulong)(text[at] - 48);
                if (arc > (18446744073709551615u - digit) / 10u)
                    return Fail(AsnError.OutOfRange);
                arc = arc * 10u + digit;
                at++;
            }

            if (at == start)
                return Fail(AsnError.Malformed);
            if (at - start > 1u && text[start] == 48)
                return Fail(AsnError.Malformed);

            arcs[count] = arc;
            count++;

            if (at == text.Length)
                break;
            if (text[at] != 46)
                return Fail(AsnError.Malformed);
            at++;
        }

        if (count < 2u || arcs[0u] > 2u)
            return Fail(AsnError.Malformed);
        if (arcs[0u] < 2u && arcs[1u] >= 40u)
            return Fail(AsnError.Malformed);
        if (arcs[1u] > 18446744073709551615u - 80u)
            return Fail(AsnError.OutOfRange);

        arcs[1u] = arcs[0u] * 40u + arcs[1u];

        nuint length = 0u;
        for (nuint i = 1u; i < count; i++)
            length += CountBase128Octets(arcs[i]);

        var contents = new byte[length];
        nuint written = 0u;
        for (nuint i = 1u; i < count; i++)
        {
            nuint octets = CountBase128Octets(arcs[i]);
            for (nuint j = 0u; j < octets; j++)
            {
                uint shift = (uint)(7u * (octets - 1u - j));
                uint septet = (uint)((arcs[i] >> shift) & 0x7Fu);
                if (j + 1u < octets)
                    septet |= 0x80u;
                contents[written + j] = (byte)septet;
            }
            written += octets;
        }

        return Ok(contents);
    }

    /// How many seven-bit groups `value` needs; zero needs one.
    static nuint CountBase128Octets(ulong value)
    {
        nuint octets = 1u;
        while (value > 0x7Fu)
        {
            octets++;
            value >>= 7;
        }
        return octets;
    }
}
