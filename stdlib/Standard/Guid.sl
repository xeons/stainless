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

module Standard;

import Standard.Collections;

extern "C"
{
    bool sl_random_bytes(byte* buffer, nuint length);
    long sl_time_now();
}

/// A 128-bit identifier: C#'s `System.Guid`, and COM's `GUID`.
///
///     var id = Guid.NewGuid();
///     String text = id.ToString();             // 36 characters, in lower case
///
/// Laid out as C's `GUID` is -- a 32-bit `_a`, two 16-bit `_b` and `_c`, and
/// eight bytes `_d` -- so a `Guid*` is what a COM function takes. The compiler
/// declares that layout, because `iidof` and the COM machinery name the type;
/// this declaration adds the rest. `ToByteArray` and the constructor from
/// bytes use the layout's byte order, as .NET's do, so a value round-trips
/// with a .NET program byte for byte; two compare as their text does.
public struct Guid : IEquatable<Guid>, IComparable<Guid>, IHashable
{

    /// All zeros.
    public static Guid Empty => default(Guid);

    /// All ones, the largest.
    public static Guid AllBitsSet =>
        new Guid(0xFFFFFFFFu, (ushort)0xFFFF, (ushort)0xFFFF, 255, 255, 255, 255, 255, 255, 255, 255);

    /// From sixteen bytes in .NET's order. Aborts on any other count.
    ///
    /// @param bytes  what `ToByteArray` gives
    public Guid(ReadOnlySpan<byte> bytes)
    {
        if (bytes.Length != 16u)
            sl_fail("Guid: sixteen bytes are needed");

        _a = (uint)bytes[0] | ((uint)bytes[1] << 8) | ((uint)bytes[2] << 16) | ((uint)bytes[3] << 24);
        _b = (ushort)((uint)bytes[4] | ((uint)bytes[5] << 8));
        _c = (ushort)((uint)bytes[6] | ((uint)bytes[7] << 8));
        for (nuint i = 0u; i < 8u; i++)
            _d[i] = bytes[8u + i];
    }

    /// From its fields, as C#'s eleven-argument constructor and a COM header's
    /// `DEFINE_GUID` take them.
    public Guid(uint a, ushort b, ushort c, byte d, byte e, byte f, byte g, byte h, byte i, byte j, byte k)
    {
        _a = a;
        _b = b;
        _c = c;
        _d[0] = d;
        _d[1] = e;
        _d[2] = f;
        _d[3] = g;
        _d[4] = h;
        _d[5] = i;
        _d[6] = j;
        _d[7] = k;
    }

    /// Byte `i` in the order the text writes them.
    byte TextByteAt(nuint i)
    {
        if (i < 4u)
            return (byte)(_a >> (int)(24u - 8u * i));
        if (i < 6u)
            return (byte)((uint)_b >> (int)(8u - 8u * (i - 4u)));
        if (i < 8u)
            return (byte)((uint)_c >> (int)(8u - 8u * (i - 6u)));
        return _d[i - 8u];
    }

    /// Sets byte `i` in the order the text writes them.
    void SetTextByteAt(nuint i, byte value)
    {
        if (i < 4u)
        {
            int shift = (int)(24u - 8u * i);
            _a = (_a & ~(0xFFu << shift)) | ((uint)value << shift);
        }
        else if (i < 6u)
        {
            int shift = (int)(8u - 8u * (i - 4u));
            _b = (ushort)(((uint)_b & ~(0xFFu << shift)) | ((uint)value << shift));
        }
        else if (i < 8u)
        {
            int shift = (int)(8u - 8u * (i - 6u));
            _c = (ushort)(((uint)_c & ~(0xFFu << shift)) | ((uint)value << shift));
        }
        else
        {
            _d[i - 8u] = value;
        }
    }

    /// Sixteen random bytes, aborting if the platform supplies none.
    static Guid MadeRandom(String caller)
    {
        byte[] random = new byte[16];
        if (!sl_random_bytes(&random[0], 16u))
            sl_fail((caller + ": the platform supplied no entropy").ToPointer());
        return new Guid(random);
    }

    /// A random one: version 4, 122 random bits. Aborts if the platform will
    /// supply no entropy, as `RandomNumberGenerator` does.
    public static Guid NewGuid() => MadeRandom("Guid.NewGuid").Stamped(4);

    /// A version 7 one: the time in milliseconds first, then random bits, so
    /// one made later sorts later.
    public static Guid CreateVersion7()
    {
        Guid made = MadeRandom("Guid.CreateVersion7");
        long milliseconds = sl_time_now() / 1000000;
        for (nuint i = 0u; i < 6u; i++)
            made.SetTextByteAt(i, (byte)(milliseconds >> (int)(40u - 8u * i)));
        return made.Stamped(7);
    }

    /// Which layout of RFC 9562 this is: 4 for random, 7 for time-ordered.
    public int Version => (int)((uint)_c >> 12);

    /// The variant bits, 0b10 for every one this makes.
    public int Variant => _d[0] >> 6;

    /// This with its version and variant set.
    Guid Stamped(int version)
    {
        Guid made = this;
        made._c = (ushort)(((uint)made._c & 0x0FFFu) | ((uint)version << 12));
        made._d[0] = (byte)((made._d[0] & 0x3F) | 0x80);
        return made;
    }

    /// The sixteen bytes in .NET's order, which is this layout's.
    public byte[] ToByteArray()
    {
        var bytes = new byte[16];
        for (nuint i = 0u; i < 4u; i++)
            bytes[i] = (byte)(_a >> (int)(8u * i));
        bytes[4] = (byte)_b;
        bytes[5] = (byte)((uint)_b >> 8);
        bytes[6] = (byte)_c;
        bytes[7] = (byte)((uint)_c >> 8);
        for (nuint i = 0u; i < 8u; i++)
            bytes[8u + i] = _d[i];
        return bytes;
    }

    /// Writes the sixteen bytes in .NET's order when there is room, and answers
    /// whether there was.
    public bool TryWriteBytes(Span<byte> destination)
    {
        if (destination.Length < 16u)
            return false;
        ReadOnlySpan<byte> bytes = ToByteArray();
        bytes.CopyTo(destination);
        return true;
    }

    /// Hyphenated, in lower case.
    public String ToString() => ToString("D");

    /// In one of C#'s formats: `N` for 32 digits, `D` for hyphens between the
    /// groups, `B` for that in braces, `P` in parentheses. Aborts on any other.
    ///
    /// @param format  "N", "D", "B" or "P", in either case
    public String ToString(String format)
    {
        String upper = format.ToUpperAscii();
        if (upper != "N" && upper != "D" && upper != "B" && upper != "P")
            sl_fail("Guid.ToString: the format is not N, D, B or P");

        var text = new StringBuilder();
        if (upper == "B")
            text.Append("{");
        if (upper == "P")
            text.Append("(");

        for (nuint i = 0u; i < 16u; i++)
        {
            if (upper != "N" && (i == 4u || i == 6u || i == 8u || i == 10u))
                text.Append("-");
            byte value = TextByteAt(i);
            text.Append(HexDigit(value >> 4));
            text.Append(HexDigit(value & 0x0F));
        }

        if (upper == "B")
            text.Append("}");
        if (upper == "P")
            text.Append(")");
        return text.ToText();
    }

    static String HexDigit(int value) => "0123456789abcdef".Substring((nuint)value, 1u);

    /// Reads any of the formats `ToString` writes, in either case.
    ///
    /// @param text  32 hex digits, with or without hyphens, braces or parentheses
    public static Result<Guid, ParseError> Parse(String text)
    {
        String trimmed = text.Trim();
        if (trimmed.IsEmpty)
            return Fail(ParseError.Empty);

        nuint length = trimmed.ByteLength();
        byte first = trimmed.GetByteAt(0u);
        byte last = trimmed.GetByteAt(length - 1u);
        if (length >= 2u && ((first == (byte)'{' && last == (byte)'}') || (first == (byte)'(' && last == (byte)')')))
            trimmed = trimmed.Substring(1u, length - 2u);

        bool hyphens = trimmed.ByteLength() == 36u;
        if (!hyphens && trimmed.ByteLength() != 32u)
            return Fail(ParseError.Malformed);

        Guid made;
        nuint at = 0u;
        for (nuint i = 0u; i < 16u; i++)
        {
            if (hyphens && (i == 4u || i == 6u || i == 8u || i == 10u))
            {
                if (trimmed.GetByteAt(at) != (byte)'-')
                    return Fail(ParseError.Malformed);
                at++;
            }

            int high = HexValue(trimmed.GetByteAt(at));
            int low = HexValue(trimmed.GetByteAt(at + 1u));
            if (high < 0 || low < 0)
                return Fail(ParseError.Malformed);

            made.SetTextByteAt(i, (byte)((high << 4) | low));
            at += 2u;
        }
        return Ok(made);
    }

    static int HexValue(byte digit)
    {
        if (digit >= (byte)'0' && digit <= (byte)'9')
            return digit - (byte)'0';
        if (digit >= (byte)'a' && digit <= (byte)'f')
            return digit - (byte)'a' + 10;
        if (digit >= (byte)'A' && digit <= (byte)'F')
            return digit - (byte)'A' + 10;
        return -1;
    }

    /// Whether the two are the same sixteen bytes.
    public bool Equals(Guid other) => CompareTo(other) == 0;

    /// Byte by byte in text order, which is the order their text sorts in.
    public int CompareTo(Guid other)
    {
        for (nuint i = 0u; i < 16u; i++)
        {
            byte mine = TextByteAt(i);
            byte theirs = other.TextByteAt(i);
            if (mine != theirs)
                return mine < theirs ? -1 : 1;
        }
        return 0;
    }

    public nuint GetHashCode()
    {
        nuint hash = 0u;
        for (nuint i = 0u; i < 16u; i++)
            hash = MixHash(hash, (ulong)TextByteAt(i));
        return hash;
    }

    public static bool operator ==(Guid left, Guid right) => left.Equals(right);
    public static bool operator !=(Guid left, Guid right) => !left.Equals(right);
    public static bool operator <(Guid left, Guid right) => left.CompareTo(right) < 0;
    public static bool operator >(Guid left, Guid right) => left.CompareTo(right) > 0;
    public static bool operator <=(Guid left, Guid right) => left.CompareTo(right) <= 0;
    public static bool operator >=(Guid left, Guid right) => left.CompareTo(right) >= 0;
}
