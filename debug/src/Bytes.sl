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

// Reading DWARF's variable-length encodings out of a byte array.
//
// **This is not how the container headers are read, and it should not be.** A
// COFF or ELF header is a fixed-layout C structure, this language has C's
// layout, so `Image/Pe.sl` and `Image/Elf.sl` declare those structures and cast
// a pointer at the bytes. A field called `TimeDateStamp` cannot disagree with
// itself; `Skip(4u) // TimeDateStamp` can, and eventually does. Anything with a
// shape a struct can express belongs over there.
//
// What is left here is the half that has no shape to declare:
//
//   - **LEB128**, unsigned and signed, which is variable-length by
//     construction and is how DWARF spells nearly every number.
//   - **The DIE stream**, where an entry is an abbreviation code followed by
//     attributes whose widths are decided at run time by a table read from
//     another section entirely. There is no structure; there is a parser.
//   - **The line-number program**, which is a bytecode interpreter.
//   - Strings at arbitrary offsets, which both containers and DWARF all want.
//
// **A cursor that cannot run off the end.** Every read is bounds-checked and a
// read past the end answers zero and sets `Overran` rather than aborting. That
// is deliberate and it is not defensive programming: the input is a file on
// disk that some other program wrote, and half the point of a reader like this
// is to survive one that is truncated, corrupt, or simply a format it was not
// expecting. A debugger that aborts on a bad binary is worse than one that says
// the binary is bad. The struct readers buy the same guarantee with one `BytesRemainAt`
// per header instead of one check per field.
//
// **The byte order is hardcoded little-endian, and that is not what the cursor
// is for.** Every target this compiler has is little-endian and DWARF takes its
// order from the container, so a flag would be a branch that is never taken. If
// a big-endian target ever appears this is the file that grows one -- but it is
// not the reason this file exists today.
module Debugger;

import Standard.Collections;
import Standard.Text;

/// A position in a byte array, and the reads that move it.
public class Cursor
{
    byte[] _data;
    nuint _at;
    bool _overran;

    public Cursor(byte[] data)
    {
        _data = data;
        _at = 0u;
        _overran = false;
    }

    /// A cursor over part of another's data, starting at an absolute offset.
    ///
    /// The bytes are shared rather than copied -- a `.debug_info` is megabytes
    /// and a reader makes one of these per unit.
    public Cursor(byte[] data, nuint from)
    {
        _data = data;
        _at = from;
        _overran = from > data.Length;
        if (_overran)
            _at = data.Length;
    }

    /// Where the cursor is, counted from the start of the whole array -- which
    /// is what DWARF's section-relative offsets are expressed in, so this is
    /// the number that gets compared against them.
    public nuint Offset => _at;
    public nuint Length => _data.Length;
    public bool AtEnd => _at >= _data.Length;

    /// Whether any read has been refused for running past the end.
    ///
    /// **Sticky.** Once set it stays set, so a caller can do a run of reads and
    /// ask once at the end rather than checking each -- which is what makes a
    /// parser of a fixed-shape header readable.
    public bool Overran => _overran;

    public void Seek(nuint to)
    {
        if (to > _data.Length)
        {
            _overran = true;
            _at = _data.Length;
            return;
        }
        _at = to;
    }

    public void Skip(nuint count) => Seek(_at + count);

    /// Whether `count` more bytes are actually there. Answering this without
    /// moving is what lets a caller decide rather than find out.
    public bool Has(nuint count) => _at + count <= _data.Length;

    public byte U8()
    {
        if (_at >= _data.Length)
        {
            _overran = true;
            return 0;
        }
        byte here = _data[_at];
        _at++;
        return here;
    }

    public ushort U16()
    {
        uint low = (uint)U8();
        uint high = (uint)U8();
        return (ushort)(low | (high << 8));
    }

    public uint U32()
    {
        uint low = (uint)U16();
        uint high = (uint)U16();
        return low | (high << 16);
    }

    public ulong U64()
    {
        ulong low = (ulong)U32();
        ulong high = (ulong)U32();
        return low | (high << 32);
    }

    /// An unsigned number of the container's pointer width.
    public ulong Address(bool is64) => is64 ? U64() : (ulong)U32();

    /// LEB128, unsigned. DWARF's usual way of spelling a number.
    ///
    /// **Stops at ten bytes**, which is the most that can contribute to a
    /// 64-bit result. Without that a run of bytes with the high bit set -- which
    /// is what a corrupt section looks like -- walks the whole file shifting
    /// into nothing.
    public ulong Leb()
    {
        ulong answer = 0u;
        int shift = 0;
        for (int step = 0; step < 10; step++)
        {
            byte here = U8();
            if (shift < 64)
                answer = answer | ((ulong)(here & 0x7F) << shift);
            shift = shift + 7;
            if ((here & 0x80) == 0)
                return answer;
        }
        _overran = true;
        return answer;
    }

    /// LEB128, signed: the same, with the last byte's sign bit smeared upwards.
    public long SLeb()
    {
        ulong answer = 0u;
        int shift = 0;
        for (int step = 0; step < 10; step++)
        {
            byte here = U8();
            if (shift < 64)
                answer = answer | ((ulong)(here & 0x7F) << shift);
            shift = shift + 7;
            if ((here & 0x80) == 0)
            {
                // The number is `shift` bits wide; everything above that takes
                // the sign of its top bit.
                if (shift < 64 && (here & 0x40) != 0)
                    answer = answer | (~((ulong)0) << shift);
                return (long)answer;
            }
        }
        _overran = true;
        return (long)answer;
    }

    /// A NUL-terminated string, leaving the cursor after the terminator.
    ///
    /// A string that runs to the end of the array with no NUL is still
    /// answered, with `Overran` set -- the bytes are probably what was meant,
    /// and refusing them would lose a name a reader could otherwise show.
    public String CString()
    {
        var made = new StringBuilder();
        while (true)
        {
            if (_at >= _data.Length)
            {
                _overran = true;
                return made.ToText();
            }
            byte here = _data[_at];
            _at++;
            if (here == 0)
                return made.ToText();
            made.AppendByte(here);
        }
    }

    /// `count` bytes, copied out.
    public byte[] Take(nuint count)
    {
        if (!Has(count))
        {
            _overran = true;
            count = _data.Length - (_at < _data.Length ? _at : _data.Length);
        }
        var made = new byte[count];
        for (nuint i = 0u; i < count; i++)
            made[i] = _data[_at + i];
        _at = _at + count;
        return made;
    }
}

/// A NUL-terminated string at an absolute offset, without disturbing a cursor.
///
/// Both formats keep their names in one blob and index into it, so this is what
/// a section-name lookup and a DWARF `.debug_str` read are both spelled as.
public String ReadCStringAt(byte[] data, nuint at)
{
    var reader = new Cursor(data, at);
    return reader.CString();
}
