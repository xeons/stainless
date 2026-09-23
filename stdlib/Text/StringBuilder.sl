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

module Standard.Text;

import Standard.Limits;

public class StringBuilder
{
    /// The bytes, their count, and the room there is for them.
    ///
    /// A growable allocation rather than a `byte[]`, because the buffer is
    /// rewritten in place on every append and an array would be bounds-checked
    /// per byte for no gain -- nothing outside this class can reach it.
    byte* _bytes;
    nuint _length;
    nuint _capacity;

    /// Nothing is allocated until the first append, so a builder that is made
    /// and never used costs one object.
    public StringBuilder()
    {
        _bytes = null;
        _length = 0u;
        _capacity = 0u;
    }

    /// The buffer is this object's, and ARC frees the object rather than what
    /// it points at.
    ~StringBuilder()
    {
        free((void*)_bytes);
    }

    // -------------------------------------------------------------- the room

    /// Room for `extra` bytes beyond what is already here, doubling so that
    /// appending stays amortised O(1) -- which is the whole reason this type
    /// exists, since building text by repeated concatenation is O(n^2).
    ///
    /// Capacity outlives any particular length, so `Clear` keeps it.
    void EnsureCapacity(nuint extra)
    {
        // Both of these would wrap rather than fail: the size wanted, and the
        // doubling that reaches for it -- which on wrapping to zero would loop
        // for ever rather than merely allocate too little.
        if (extra > MaxNUInt - _length)
            sl_fail("string is too large to build");

        nuint wanted = _length + extra;
        if (wanted <= _capacity)
            return;

        nuint capacity = _capacity == 0u ? 32u : _capacity;
        while (capacity < wanted)
        {
            if (capacity > MaxNUInt / 2u)
            {
                capacity = wanted;
                break;
            }
            capacity = capacity * 2u;
        }

        byte* bytes = (byte*)realloc((void*)_bytes, capacity);
        if (bytes == null)
            sl_fail("out of memory");

        _bytes = bytes;
        _capacity = capacity;
    }

    /// The one place bytes enter the buffer. Everything that appends comes
    /// through here.
    void WriteBytes(byte* data, nuint byteLength)
    {
        if (byteLength == 0u || data == null)
            return;

        this.EnsureCapacity(byteLength);
        memcpy(_bytes + _length, data, byteLength);
        _length = _length + byteLength;
    }

    // ------------------------------------------------------------ appending

    /// Text, as its bytes.
    public void Append(String text)
    {
        this.WriteBytes(text.ToPointer(), text.ByteLength());
    }

    /// Text and a newline.
    public void AppendLine(String text)
    {
        this.Append(text);
        this.AppendByte(0x0A);
    }

    /// A signed integer in base ten.
    ///
    /// Written into the buffer a digit at a time rather than through
    /// `FromInteger`, because a builder appending numbers in a loop should not
    /// allocate a `String` per number.
    ///
    /// @see Text.FromInteger
    public void AppendInteger(long value)
    {
        // The magnitude as unsigned, so that the smallest long -- whose
        // magnitude is not itself a long -- survives being negated.
        bool negative = value < 0;
        ulong magnitude = negative ? (ulong)(-(value + 1)) + 1u : (ulong)value;

        // Twenty digits is every ulong there is; the sign is written apart.
        byte[20] digits;
        nuint written = 0u;

        if (magnitude == 0u)
        {
            digits[0] = 0x30;
            written = 1u;
        }
        else
        {
            while (magnitude > 0u)
            {
                digits[written] = (byte)(0x30u + (uint)(magnitude % 10u));
                written++;
                magnitude = magnitude / 10u;
            }
        }

        this.EnsureCapacity(written + 1u);
        if (negative)
        {
            _bytes[_length] = 0x2D;
            _length++;
        }

        // The digits came out least significant first.
        for (nuint i = written; i > 0u; i--)
        {
            _bytes[_length] = digits[i - 1u];
            _length++;
        }
    }

    /// The shortest text that reads back as the same number.
    ///
    /// This one does allocate a `String` first: shortest round-trip formatting
    /// is the runtime's, and there is nothing to gain by copying it here.
    ///
    /// @see Text.FromDouble
    public void AppendDouble(double value)
    {
        this.Append(FromDouble(value));
    }

    /// One byte.
    ///
    /// The builder holds bytes, so nothing here validates: a caller writing
    /// half a character has written half a character.
    public void AppendByte(byte value)
    {
        this.EnsureCapacity(1u);
        _bytes[_length] = value;
        _length++;
    }

    // --------------------------------------------------------------- reading

    /// How many bytes have been built. Not a character count.
    public nuint ByteLength() => _length;

    /// Whether nothing has been appended, or everything has been cleared.
    ///
    /// @see StringBuilder.HasContent
    public bool IsEmpty => _length == 0u;

    /// Throws the length away and keeps the room, so a builder reused in a
    /// loop allocates once.
    public void Clear()
    {
        _length = 0u;
    }

    /// One byte by position.
    ///
    /// A call rather than a pointer, because the buffer moves as it grows and
    /// a `byte*` into it would dangle at the next append -- the one thing
    /// `String`'s own pointer can never do.
    public byte GetByteAt(nuint index)
    {
        if (index >= _length)
            sl_array_bounds_fail(index, _length);
        return _bytes[index];
    }

    /// Replaces one byte by position.
    public void SetByteAt(nuint index, byte value)
    {
        if (index >= _length)
            sl_array_bounds_fail(index, _length);
        _bytes[index] = value;
    }

    // --------------------------------------------------------------- editing

    /// Text put in at a position. Inserting at the length is appending, which
    /// is why `at == ByteLength()` is allowed.
    ///
    /// @see StringBuilder.Remove
    public void Insert(nuint at, String text)
    {
        if (text.ByteLength() == 0u)
            return;
        if (at > _length)
            sl_array_bounds_fail(at, _length + 1u);

        nuint count = text.ByteLength();
        this.EnsureCapacity(count);

        memmove(_bytes + at + count, _bytes + at, _length - at);
        memcpy(_bytes + at, text.ToPointer(), count);
        _length = _length + count;
    }

    /// Bytes taken out from a position. Removing more than is there removes to
    /// the end rather than failing.
    ///
    /// @see StringBuilder.Insert
    /// @seealso StringBuilder.TruncateTo
    public void Remove(nuint at, nuint count)
    {
        if (at >= _length || count == 0u)
            return;
        if (count > _length - at)
            count = _length - at;

        memmove(_bytes + at, _bytes + at + count, _length - at - count);
        _length = _length - count;
    }

    /// What has been built, as text. The builder stays usable afterwards and
    /// the string does not change when it is appended to again.
    public String ToText()
    {
        if (_length == 0u)
            return "";
        return FromBytes(_bytes, _length);
    }


    /// One Unicode scalar, encoded as UTF-8.
    ///
    /// This rather than `Append(char)`, because a `char` is one code unit and
    /// appending a lone continuation byte would put the builder into a state
    /// no `String` can be made from. A scalar always encodes to something
    /// whole.
    ///
    /// @see Text.FromChar
    public void AppendCodePoint(char32 value)
    {
        uint scalar = (uint)value;

        // A surrogate or an out-of-range value is not a scalar, and the
        // replacement character is what a decoder would have produced.
        if (scalar > 0x10FFFF || (scalar >= 0xD800 && scalar <= 0xDFFF))
            scalar = 0xFFFD;

        byte[4] encoded;
        nuint width = 0;

        if (scalar < 0x80)
        {
            encoded[0] = (byte)scalar;
            width = 1;
        }
        else if (scalar < 0x800)
        {
            encoded[0] = (byte)(0xC0 | (scalar >> 6));
            encoded[1] = (byte)(0x80 | (scalar & 0x3F));
            width = 2;
        }
        else if (scalar < 0x10000)
        {
            encoded[0] = (byte)(0xE0 | (scalar >> 12));
            encoded[1] = (byte)(0x80 | ((scalar >> 6) & 0x3F));
            encoded[2] = (byte)(0x80 | (scalar & 0x3F));
            width = 3;
        }
        else
        {
            encoded[0] = (byte)(0xF0 | (scalar >> 18));
            encoded[1] = (byte)(0x80 | ((scalar >> 12) & 0x3F));
            encoded[2] = (byte)(0x80 | ((scalar >> 6) & 0x3F));
            encoded[3] = (byte)(0x80 | (scalar & 0x3F));
            width = 4;
        }

        this.Append(FromBytes(&encoded[0], width));
    }

    /// A newline on its own.
    public void AppendLine()
    {
        this.Append("\n");
    }

    /// `true` or `false`.
    ///
    /// There is deliberately no `Append(long)` or `Append(double)` beside this
    /// one. An integer literal converts to both, so the two together would make
    /// `Append(42)` ambiguous -- which is why `AppendInteger` and `AppendDouble`
    /// were spelled out in the first place. A bool converts to neither.
    public void Append(bool value)
    {
        this.Append(FromBool(value));
    }

    /// Raw bytes. They are appended as they are, so it is the caller who
    /// decides whether what comes out is text.
    public void AppendBytes(byte[] data)
    {
        if (data.Length == 0)
            return;
        this.WriteBytes(&data[0], data.Length);
    }

    /// `parts` with `separator` between them.
    public void AppendJoined(String separator, String[] parts)
    {
        for (nuint i = 0; i < parts.Length; i++)
        {
            if (i > 0)
                this.Append(separator);
            this.Append(parts[i]);
        }
    }

    // ------------------------------------------------------------- reading

    /// Whether anything has been appended. The opposite of `IsEmpty`.
    ///
    /// @see StringBuilder.IsEmpty
    public bool HasContent
    {
        get
        {
            return !this.IsEmpty;
        }
    }

    /// Where `value` first appears in what has been built, or `NotFound`.
    ///
    /// Byte by byte through the runtime rather than over a pointer, because a
    /// builder's storage moves when it grows and a pointer into it would be a
    /// pointer into the previous allocation.
    ///
    /// @see StringBuilder.Contains
    public long IndexOf(String value)
    {
        nuint size = this.ByteLength();
        nuint wanted = value.ByteLength();

        if (wanted == 0)
            return 0;
        if (wanted > size)
            return NotFound;

        var theirs = value.ToPointer();

        for (nuint i = 0; i <= size - wanted; i++)
        {
            bool same = true;
            for (nuint j = 0; j < wanted; j++)
            {
                if (this.GetByteAt(i + j) != theirs[j])
                    same = false;
            }
            if (same)
                return (long)i;
        }
        return NotFound;
    }

    /// True when `value` appears in what has been built.
    ///
    /// @see StringBuilder.IndexOf
    public bool Contains(String value)
    {
        return this.IndexOf(value) != NotFound;
    }

    // ------------------------------------------------------------- editing

    /// Everything from `at` to the end, thrown away.
    public void TruncateTo(nuint at)
    {
        nuint size = this.ByteLength();
        if (at >= size)
            return;
        this.Remove(at, size - at);
    }

    /// The first occurrence of `from` replaced by `to`, if there is one.
    ///
    /// @returns whether there was one to replace
    /// @see StringBuilder.ReplaceAll
    public bool ReplaceFirst(String from, String to)
    {
        long at = this.IndexOf(from);
        if (at == NotFound)
            return false;

        this.Remove((nuint)at, from.ByteLength());
        this.Insert((nuint)at, to);
        return true;
    }

    /// Every occurrence of `from` replaced by `to`.
    ///
    /// The search resumes past the replacement, so replacing "a" with "aa"
    /// terminates rather than growing forever.
    ///
    /// @returns how many occurrences were replaced
    /// @see StringBuilder.ReplaceFirst
    public nuint ReplaceAll(String from, String to)
    {
        if (from.ByteLength() == 0)
            return 0;

        nuint replaced = 0;
        nuint at = 0;

        while (at < this.ByteLength())
        {
            long found = this.IndexOfFrom(from, at);
            if (found == NotFound)
                break;

            this.Remove((nuint)found, from.ByteLength());
            this.Insert((nuint)found, to);
            at = (nuint)found + to.ByteLength();
            replaced++;
        }
        return replaced;
    }

    /// Where `value` first appears at or after `start`, or `NotFound`.
    long IndexOfFrom(String value, nuint start)
    {
        nuint size = this.ByteLength();
        nuint wanted = value.ByteLength();

        if (start > size || wanted > size - start)
            return NotFound;

        var theirs = value.ToPointer();

        for (nuint i = start; i <= size - wanted; i++)
        {
            bool same = true;
            for (nuint j = 0; j < wanted; j++)
            {
                if (this.GetByteAt(i + j) != theirs[j])
                    same = false;
            }
            if (same)
                return (long)i;
        }
        return NotFound;
    }
}
