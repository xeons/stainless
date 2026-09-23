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

/// Immutable UTF-8 text.
///
/// The declaration is the runtime's and the behaviour is here, so this is the
/// second half of a type that `Builtins` opened. Three things a caller needs
/// before reaching for anything below:
///
/// A string cannot be changed once made. Every method that looks like it edits
/// one -- `Trim`, `Replace`, `ToUpperAscii` -- answers a new string, and the
/// ones that would have nothing to change answer `this` rather than a copy.
///
/// Every position is a byte offset, and every length is a byte count.
/// `ByteLength` is O(1) and no method here counts characters. Use
/// `GetCodePointAt` and `SkipCodePoint` to walk by character.
///
/// Slicing clamps rather than failing: a `start` past the end and a length
/// past the end both give what is actually there, so `Substring` cannot be
/// made to abort. `GetByteAt` is the exception and reads the buffer directly. A
/// search that finds nothing answers `NotFound`.
public class String
{

    /// Text with no bytes in it.
    ///
    /// A property rather than a static field, and the reason is worth knowing:
    /// a `--shared` library has no entry point to run a static's initializer
    /// from (SL0380), so a field here would have made the whole standard
    /// library unusable in one. This costs nothing either way -- a string
    /// literal is one interned object, so every `String.Empty` is the same
    /// object that every `""` already was.
    public static String Empty { get { return ""; } }

    // -------------------------------------------------------------- testing

    /// True when this text begins with `prefix`. An empty prefix always does.
    public bool StartsWith(String prefix)
    {
        nuint wanted = prefix.ByteLength();
        if (wanted > this.ByteLength())
            return false;
        return AreBytesEqual(this.ToPointer(), prefix.ToPointer(), wanted);
    }

    /// True when this text ends with `suffix`. An empty suffix always does.
    public bool EndsWith(String suffix)
    {
        nuint wanted = suffix.ByteLength();
        nuint size = this.ByteLength();
        if (wanted > size)
            return false;
        return AreBytesEqual(this.ToPointer() + (size - wanted), suffix.ToPointer(), wanted);
    }

    /// True when `value` appears anywhere in this text.
    ///
    /// @see String.IndexOf
    public bool Contains(String value)
    {
        return this.IndexOf(value) != NotFound;
    }

    /// True when this single code unit appears. Only meaningful for ASCII: a
    /// `char` above 127 is one byte of a sequence rather than a character.
    public bool Contains(char value)
    {
        return this.IndexOf(value) != NotFound;
    }

    // ------------------------------------------------------------ searching

    /// Where `value` first appears, or `NotFound`.
    ///
    /// An empty `value` is found at 0, which is where it is: every string
    /// begins with the empty string.
    ///
    /// @see String.LastIndexOf
    /// @seealso Text.NotFound
    public long IndexOf(String value)
    {
        return this.IndexOf(value, 0);
    }

    /// Where `value` first appears at or after `start`, or `NotFound`.
    public long IndexOf(String value, nuint start)
    {
        nuint size = this.ByteLength();
        nuint wanted = value.ByteLength();

        if (start > size)
            return NotFound;
        if (wanted == 0)
            return (long)start;
        if (wanted > size - start)
            return NotFound;

        var mine = this.ToPointer();
        var theirs = value.ToPointer();
        byte first = theirs[0];

        for (nuint i = start; i <= size - wanted; i++)
        {
            if (mine[i] == first && AreBytesEqual(mine + i, theirs, wanted))
                return (long)i;
        }
        return NotFound;
    }

    /// Where `value` last appears, or `NotFound`.
    ///
    /// @see String.IndexOf
    public long LastIndexOf(String value)
    {
        nuint size = this.ByteLength();
        nuint wanted = value.ByteLength();

        if (wanted == 0)
            return (long)size;
        if (wanted > size)
            return NotFound;

        var mine = this.ToPointer();
        var theirs = value.ToPointer();

        for (nuint i = size - wanted + 1; i > 0; i--)
        {
            if (AreBytesEqual(mine + (i - 1), theirs, wanted))
                return (long)(i - 1);
        }
        return NotFound;
    }

    /// Where this code unit first appears, or `NotFound`.
    public long IndexOf(char value)
    {
        nuint size = this.ByteLength();
        var mine = this.ToPointer();

        for (nuint i = 0; i < size; i++)
        {
            if (mine[i] == value)
                return (long)i;
        }
        return NotFound;
    }

    /// Where this code unit last appears, or `NotFound`.
    public long LastIndexOf(char value)
    {
        var mine = this.ToPointer();

        for (nuint i = this.ByteLength(); i > 0; i--)
        {
            if (mine[i - 1] == value)
                return (long)(i - 1);
        }
        return NotFound;
    }

    // -------------------------------------------------------------- slicing

    /// Everything from `start` to the end. A `start` past the end gives "".
    public String Substring(nuint start)
    {
        nuint size = this.ByteLength();
        if (start >= size)
            return "";
        return this.Substring(start, size - start);
    }

    /// The text before the first `separator`, or all of it when there is none.
    ///
    /// @see String.SubstringAfter
    public String SubstringBefore(String separator)
    {
        long at = this.IndexOf(separator);
        if (at == NotFound)
            return this;
        return this.Substring(0, (nuint)at);
    }

    /// The text after the first `separator`, or "" when there is none.
    ///
    /// @see String.SubstringBefore
    /// @seealso String.SubstringAfterLast
    public String SubstringAfter(String separator)
    {
        long at = this.IndexOf(separator);
        if (at == NotFound)
            return "";
        return this.Substring((nuint)at + separator.ByteLength());
    }

    /// The text after the last `separator`, or all of it when there is none.
    ///
    /// @see String.SubstringAfter
    public String SubstringAfterLast(String separator)
    {
        long at = this.LastIndexOf(separator);
        if (at == NotFound)
            return this;
        return this.Substring((nuint)at + separator.ByteLength());
    }

    // ------------------------------------------------------------- trimming

    /// This text without leading or trailing ASCII whitespace.
    ///
    /// @see String.TrimStart
    /// @seealso String.TrimEnd
    public String Trim()
    {
        return this.TrimStart().TrimEnd();
    }

    /// This text without leading ASCII whitespace.
    public String TrimStart()
    {
        nuint size = this.ByteLength();
        var mine = this.ToPointer();

        nuint at = 0;
        while (at < size && IsAsciiWhiteSpace(mine[at]))
            at = at + 1;

        if (at == 0)
            return this;
        return this.Substring(at, size - at);
    }

    /// This text without trailing ASCII whitespace.
    public String TrimEnd()
    {
        nuint size = this.ByteLength();
        var mine = this.ToPointer();

        nuint end = size;
        while (end > 0 && IsAsciiWhiteSpace(mine[end - 1]))
            end = end - 1;

        if (end == size)
            return this;
        return this.Substring(0, end);
    }

    // -------------------------------------------------------------- rebuilding

    /// Every occurrence of `from` replaced by `to`.
    ///
    /// Left to right and non-overlapping, so the replacement is never searched
    /// again: replacing "a" with "aa" terminates.
    ///
    /// @see StringBuilder.ReplaceAll
    public String Replace(String from, String to)
    {
        if (from.ByteLength() == 0)
            return this;

        var built = new StringBuilder();
        nuint at = 0;
        nuint size = this.ByteLength();

        while (at < size)
        {
            long found = this.IndexOf(from, at);
            if (found == NotFound)
                break;

            built.Append(this.Substring(at, (nuint)found - at));
            built.Append(to);
            at = (nuint)found + from.ByteLength();
        }

        if (at == 0)
            return this;
        built.Append(this.Substring(at));
        return built.ToText();
    }

    /// This text `count` times over. Zero gives "".
    public String Repeat(nuint count)
    {
        if (count == 0 || this.ByteLength() == 0)
            return "";
        if (count == 1)
            return this;

        var built = new StringBuilder();
        for (nuint i = 0; i < count; i++)
            built.Append(this);
        return built.ToText();
    }

    /// Spaces on the left until the text is `width` bytes. Never truncates.
    ///
    /// @see String.PadRight
    public String PadLeft(nuint width)
    {
        nuint size = this.ByteLength();
        if (size >= width)
            return this;
        return " ".Repeat(width - size) + this;
    }

    /// Spaces on the right until the text is `width` bytes. Never truncates.
    ///
    /// @see String.PadLeft
    public String PadRight(nuint width)
    {
        nuint size = this.ByteLength();
        if (size >= width)
            return this;
        return this + " ".Repeat(width - size);
    }

    /// The same, padded with something other than a space -- a zero, usually,
    /// which is what a formatted number wants.
    ///
    /// The padding is measured in bytes like everything else here, so a `with`
    /// of more than one byte pads by whole copies and may fall short of the
    /// width rather than overshoot it. A single character is the sane case and
    /// the one to use.
    public String PadLeft(nuint width, String with)
    {
        nuint size = this.ByteLength();
        nuint unit = with.ByteLength();
        if (size >= width || unit == 0u)
            return this;

        return with.Repeat((width - size) / unit) + this;
    }

    /// The same as `PadRight(width)` with something other than a space.
    ///
    /// Measured in bytes, so a multi-byte `with` pads by whole copies and may
    /// fall short of the width rather than overshoot it. An empty `with`
    /// answers the string unchanged, since no number of copies would reach.
    public String PadRight(nuint width, String with)
    {
        nuint size = this.ByteLength();
        nuint unit = with.ByteLength();
        if (size >= width || unit == 0u)
            return this;

        return this + with.Repeat((width - size) / unit);
    }

    // -------------------------------------------------------------- splitting

    /// This text cut at every `separator`.
    ///
    /// Adjacent separators produce empty parts, and so do ones at either end:
    /// splitting "a,,b" on ',' gives three parts, and "" gives one. That is
    /// what makes it reversible -- joining the result with the same separator
    /// gives the original back.
    ///
    /// @see String.Join
    /// @seealso String.SplitLines
    public String[] Split(String separator)
    {
        if (separator.ByteLength() == 0)
            return [this];

        // Counted first so the array is allocated once at exactly the size it
        // needs, rather than grown.
        nuint parts = 1;
        nuint at = 0;
        while (true)
        {
            long found = this.IndexOf(separator, at);
            if (found == NotFound)
                break;
            parts++;
            at = (nuint)found + separator.ByteLength();
        }

        var result = new String[parts];
        nuint index = 0;
        at = 0;

        while (index + 1 < parts)
        {
            long found = this.IndexOf(separator, at);
            result[index] = this.Substring(at, (nuint)found - at);
            at = (nuint)found + separator.ByteLength();
            index++;
        }

        result[index] = this.Substring(at);
        return result;
    }

    /// This text cut at every occurrence of one code unit.
    public String[] Split(char separator)
    {
        nuint size = this.ByteLength();
        var mine = this.ToPointer();

        nuint parts = 1;
        for (nuint i = 0; i < size; i++)
        {
            if (mine[i] == separator)
                parts = parts + 1;
        }

        var result = new String[parts];
        nuint index = 0;
        nuint start = 0;

        for (nuint i = 0; i < size; i++)
        {
            if (mine[i] == separator)
            {
                result[index] = this.Substring(start, i - start);
                index++;
                start = i + 1;
            }
        }

        result[index] = this.Substring(start);
        return result;
    }

    /// This text cut into lines, on "\n" or "\r\n".
    ///
    /// A trailing newline does not produce a final empty line, because a file
    /// that ends in one has as many lines as one that does not -- which is the
    /// opposite of what `Split` does, and the reason this is not `Split('\n')`.
    ///
    /// @see String.Split
    public String[] SplitLines()
    {
        nuint size = this.ByteLength();
        if (size == 0)
            return [];

        var mine = this.ToPointer();

        nuint lines = 1;
        for (nuint i = 0; i < size; i++)
        {
            if (mine[i] == 10 && i + 1 < size)
                lines = lines + 1;
        }

        var result = new String[lines];
        nuint index = 0;
        nuint start = 0;

        for (nuint i = 0; i < size; i++)
        {
            if (mine[i] != 10)
                continue;

            nuint end = i;
            if (end > start && mine[end - 1] == 13)
                end = end - 1;
            result[index] = this.Substring(start, end - start);
            index++;
            start = i + 1;
        }

        if (index < lines)
        {
            nuint end = size;
            if (end > start && mine[end - 1] == 13)
                end = end - 1;
            result[index] = this.Substring(start, end - start);
        }
        return result;
    }

    // ------------------------------------------------------------------ case

    /// This text with every ASCII letter uppercased, and every other byte left
    /// as it was. See the note at the top of this file.
    ///
    /// @see String.ToLowerAscii
    /// @seealso String.EqualsIgnoreCaseAscii
    public String ToUpperAscii()
    {
        return this.MapAscii(true);
    }

    /// This text with every ASCII letter lowercased.
    ///
    /// @see String.ToUpperAscii
    public String ToLowerAscii()
    {
        return this.MapAscii(false);
    }

    /// True when the two texts differ only in the case of ASCII letters.
    public bool EqualsIgnoreCaseAscii(String other)
    {
        nuint size = this.ByteLength();
        if (size != other.ByteLength())
            return false;

        var mine = this.ToPointer();
        var theirs = other.ToPointer();

        for (nuint i = 0; i < size; i++)
        {
            if (ToLowerByte(mine[i]) != ToLowerByte(theirs[i]))
                return false;
        }
        return true;
    }

    // ----------------------------------------------------------- comparison

    /// Orders two texts by their bytes: negative, zero or positive.
    ///
    /// Comparing UTF-8 byte by byte happens to order by code point as well,
    /// because the encoding was designed so that it would. It is not a
    /// linguistic ordering and does not claim to be one.
    public int CompareTo(String other)
    {
        nuint mineSize = this.ByteLength();
        nuint theirSize = other.ByteLength();
        nuint shorter = mineSize < theirSize ? mineSize : theirSize;

        var mine = this.ToPointer();
        var theirs = other.ToPointer();

        for (nuint i = 0; i < shorter; i++)
        {
            if (mine[i] != theirs[i])
                return mine[i] < theirs[i] ? -1 : 1;
        }

        if (mineSize == theirSize)
            return 0;
        return mineSize < theirSize ? -1 : 1;
    }

    // ---------------------------------------------------------- code points

    /// The byte at `index`, which is a code unit and not a character.
    ///
    /// Unchecked, unlike the slicing methods: this reads the buffer directly,
    /// so an `index` at or past `ByteLength` reads memory that is not the
    /// string's. Check the length first, or slice instead.
    ///
    /// @see String.GetCodePointAt
    public byte GetByteAt(nuint index)
    {
        return this.ToPointer()[index];
    }

    /// The scalar beginning at `index`.
    ///
    /// `index` must be the start of a character; one that lands inside a
    /// sequence gives U+FFFD, which is what a decoder does with a byte that
    /// cannot begin one. So does a sequence that is not well formed: one cut
    /// short, an overlong form, a surrogate or a value past U+10FFFF.
    ///
    /// @see String.SkipCodePoint
    public char32 GetCodePointAt(nuint index)
    {
        nuint size = this.ByteLength();
        if (index >= size)
            return (char32)0xFFFD;

        var mine = this.ToPointer();
        nuint width = GetWellFormedWidth(mine, index, size);
        if (width == 0)
            return (char32)0xFFFD;

        byte lead = mine[index];
        if (width == 1)
            return (char32)(uint)lead;

        uint scalar = (uint)(lead & (byte)(0x7F >> (int)width));
        for (nuint i = 1; i < width; i++)
            scalar = (scalar << 6) | (uint)(mine[index + i] & 0x3F);
        return (char32)scalar;
    }

    /// The index of the character after the one at `index`.
    ///
    /// Together with `GetCodePointAt` this is how the text is walked properly:
    ///
    /// ```
    /// for (nuint at = 0; at < s.ByteLength(); at = s.SkipCodePoint(at)) {
    ///     var c = s.GetCodePointAt(at);
    /// }
    /// ```
    ///
    /// A sequence that is not well formed is stepped over one byte at a time,
    /// each byte reading as U+FFFD. `CodePointCount` counts the same steps.
    ///
    /// @see String.GetCodePointAt
    public nuint SkipCodePoint(nuint index)
    {
        nuint size = this.ByteLength();
        if (index >= size)
            return size;

        nuint width = GetWellFormedWidth(this.ToPointer(), index, size);
        if (width == 0)
            width = 1;
        return index + width;
    }

    // -------------------------------------------------------------- joining

    /// `parts` written out with this text between them. The inverse of `Split`.
    ///
    /// A method on the separator rather than a free function, because every
    /// module imports `Standard.Text` without asking and a global named `Join`
    /// is a global named `Join`. `", ".Join(parts)` also reads in the order it
    /// happens.
    ///
    /// @see String.Split
    public String Join(String[] parts)
    {
        if (parts.Length == 0)
            return "";
        if (parts.Length == 1)
            return parts[0];

        var built = new StringBuilder();
        for (nuint i = 0; i < parts.Length; i++)
        {
            if (i > 0)
                built.Append(this);
            built.Append(parts[i]);
        }
        return built.ToText();
    }

    // ------------------------------------------------------------ conversion

    /// This text's bytes, copied into an array.
    ///
    /// A copy rather than a view: a `String` is immutable and an array is not,
    /// so handing out the storage would let one be changed through the other.
    ///
    /// @see Text.FromBytes
    public byte[] ToBytes()
    {
        nuint size = this.ByteLength();
        var bytes = new byte[size];
        var mine = this.ToPointer();

        for (nuint i = 0; i < size; i++)
            bytes[i] = mine[i];
        return bytes;
    }

    // --------------------------------------------------------------- private

    String MapAscii(bool upper)
    {
        nuint size = this.ByteLength();
        var mine = this.ToPointer();

        // Nothing to do is the common case, and it costs a scan rather than an
        // allocation to find out.
        bool differs = false;
        for (nuint i = 0; i < size; i++)
        {
            byte mapped = upper ? ToUpperByte(mine[i]) : ToLowerByte(mine[i]);
            if (mapped != mine[i])
                differs = true;
        }
        if (!differs)
            return this;

        var bytes = new byte[size];
        for (nuint i = 0; i < size; i++)
        {
            bytes[i] = upper ? ToUpperByte(mine[i]) : ToLowerByte(mine[i]);
        }
        return FromBytes(&bytes[0], size);
    }
}
