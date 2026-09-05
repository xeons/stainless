// Stainless - an experimental systems language.
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

// The rest of `String`.
//
// `String` itself is intrinsic: the runtime owns its layout and its allocation,
// and the compiler creates the symbol before any source is read. What it does
// not own is the behaviour, and this file adds it -- a type may be declared
// more than once inside its own module, so `Standard.Text` picks up where
// `Builtins` left off (§3.2).
//
// Two rules run through everything here.
//
// **Positions are byte offsets.** A `String` is UTF-8 and length is O(1)
// precisely because nothing counts characters, so `IndexOf` answers in bytes
// and `Substring` takes bytes. Every position this file produces lands on a
// character boundary, because it came from matching whole text -- a UTF-8
// sequence cannot begin inside another one, which is what makes byte-wise
// search correct on encoded text rather than merely fast. Positions a *caller*
// invents are its own business; `CodePointAt` and `NextCodePoint` are here for
// walking the text properly.
//
// **Case and whitespace are ASCII.** Full Unicode case mapping is a table of
// several thousand entries with locale exceptions, and the runtime has no room
// for it yet. What is here maps A-Z and a-z and leaves every other byte alone,
// which is exactly right for identifiers, protocol tokens and file extensions,
// and visibly wrong for prose in most languages. Anything that says `Ascii` in
// its name says so; anything that does not is either encoding-independent or
// documented here.
module Standard.Text;

/// The byte a search returns when it found nothing.
///
/// Searches answer with a `long` rather than a `nuint` for exactly this: a
/// position is unsigned, "nowhere" is not a position, and every unsigned
/// sentinel anyone has tried -- `npos`, the length, zero -- is a real position
/// in some other string. -1 is not.
public const long NotFound = -1;

public class String {

    // -------------------------------------------------------------- testing

    /// True when this text begins with `prefix`. An empty prefix always does.
    public bool StartsWith(String prefix) {
        nuint wanted = prefix.ByteLength();
        if (wanted > this.ByteLength()) { return false; }
        return Matches(this.ToPointer(), prefix.ToPointer(), wanted);
    }

    /// True when this text ends with `suffix`. An empty suffix always does.
    public bool EndsWith(String suffix) {
        nuint wanted = suffix.ByteLength();
        nuint size = this.ByteLength();
        if (wanted > size) { return false; }
        return Matches(this.ToPointer() + (size - wanted), suffix.ToPointer(), wanted);
    }

    /// True when `value` appears anywhere in this text.
    public bool Contains(String value) {
        return this.IndexOf(value) != NotFound;
    }

    /// True when this single code unit appears. Only meaningful for ASCII: a
    /// `char` above 127 is one byte of a sequence rather than a character.
    public bool Contains(char value) {
        return this.IndexOf(value) != NotFound;
    }

    // ------------------------------------------------------------ searching

    /// Where `value` first appears, or `NotFound`.
    ///
    /// An empty `value` is found at 0, which is where it is: every string
    /// begins with the empty string.
    public long IndexOf(String value) {
        return this.IndexOf(value, 0);
    }

    /// Where `value` first appears at or after `start`, or `NotFound`.
    public long IndexOf(String value, nuint start) {
        nuint size = this.ByteLength();
        nuint wanted = value.ByteLength();

        if (start > size) { return NotFound; }
        if (wanted == 0) { return (long)start; }
        if (wanted > size - start) { return NotFound; }

        var mine = this.ToPointer();
        var theirs = value.ToPointer();
        byte first = theirs[0];

        for (nuint i = start; i <= size - wanted; i = i + 1) {
            if (mine[i] == first && Matches(mine + i, theirs, wanted)) { return (long)i; }
        }
        return NotFound;
    }

    /// Where `value` last appears, or `NotFound`.
    public long LastIndexOf(String value) {
        nuint size = this.ByteLength();
        nuint wanted = value.ByteLength();

        if (wanted == 0) { return (long)size; }
        if (wanted > size) { return NotFound; }

        var mine = this.ToPointer();
        var theirs = value.ToPointer();

        for (nuint i = size - wanted + 1; i > 0; i = i - 1) {
            if (Matches(mine + (i - 1), theirs, wanted)) { return (long)(i - 1); }
        }
        return NotFound;
    }

    /// Where this code unit first appears, or `NotFound`.
    public long IndexOf(char value) {
        nuint size = this.ByteLength();
        var mine = this.ToPointer();

        for (nuint i = 0; i < size; i = i + 1) {
            if (mine[i] == value) { return (long)i; }
        }
        return NotFound;
    }

    /// Where this code unit last appears, or `NotFound`.
    public long LastIndexOf(char value) {
        var mine = this.ToPointer();

        for (nuint i = this.ByteLength(); i > 0; i = i - 1) {
            if (mine[i - 1] == value) { return (long)(i - 1); }
        }
        return NotFound;
    }

    // -------------------------------------------------------------- slicing

    /// Everything from `start` to the end. A `start` past the end gives "".
    public String Substring(nuint start) {
        nuint size = this.ByteLength();
        if (start >= size) { return ""; }
        return this.Substring(start, size - start);
    }

    /// The text before the first `separator`, or all of it when there is none.
    public String Before(String separator) {
        long at = this.IndexOf(separator);
        if (at == NotFound) { return this; }
        return this.Substring(0, (nuint)at);
    }

    /// The text after the first `separator`, or "" when there is none.
    public String After(String separator) {
        long at = this.IndexOf(separator);
        if (at == NotFound) { return ""; }
        return this.Substring((nuint)at + separator.ByteLength());
    }

    /// The text after the last `separator`, or all of it when there is none.
    public String AfterLast(String separator) {
        long at = this.LastIndexOf(separator);
        if (at == NotFound) { return this; }
        return this.Substring((nuint)at + separator.ByteLength());
    }

    // ------------------------------------------------------------- trimming

    /// This text without leading or trailing ASCII whitespace.
    public String Trim() {
        return this.TrimStart().TrimEnd();
    }

    /// This text without leading ASCII whitespace.
    public String TrimStart() {
        nuint size = this.ByteLength();
        var mine = this.ToPointer();

        nuint at = 0;
        while (at < size && IsAsciiWhiteSpace(mine[at])) { at = at + 1; }

        if (at == 0) { return this; }
        return this.Substring(at, size - at);
    }

    /// This text without trailing ASCII whitespace.
    public String TrimEnd() {
        nuint size = this.ByteLength();
        var mine = this.ToPointer();

        nuint end = size;
        while (end > 0 && IsAsciiWhiteSpace(mine[end - 1])) { end = end - 1; }

        if (end == size) { return this; }
        return this.Substring(0, end);
    }

    // -------------------------------------------------------------- rebuilding

    /// Every occurrence of `from` replaced by `to`.
    ///
    /// Left to right and non-overlapping, so the replacement is never searched
    /// again: replacing "a" with "aa" terminates.
    public String Replace(String from, String to) {
        if (from.ByteLength() == 0) { return this; }

        var built = new StringBuilder();
        nuint at = 0;
        nuint size = this.ByteLength();

        while (at < size) {
            long found = this.IndexOf(from, at);
            if (found == NotFound) { break; }

            built.Append(this.Substring(at, (nuint)found - at));
            built.Append(to);
            at = (nuint)found + from.ByteLength();
        }

        if (at == 0) { return this; }
        built.Append(this.Substring(at));
        return built.ToText();
    }

    /// This text `count` times over. Zero gives "".
    public String Repeat(nuint count) {
        if (count == 0 || this.ByteLength() == 0) { return ""; }
        if (count == 1) { return this; }

        var built = new StringBuilder();
        for (nuint i = 0; i < count; i = i + 1) { built.Append(this); }
        return built.ToText();
    }

    /// Spaces on the left until the text is `width` bytes. Never truncates.
    public String PadLeft(nuint width) {
        nuint size = this.ByteLength();
        if (size >= width) { return this; }
        return " ".Repeat(width - size) + this;
    }

    /// Spaces on the right until the text is `width` bytes. Never truncates.
    public String PadRight(nuint width) {
        nuint size = this.ByteLength();
        if (size >= width) { return this; }
        return this + " ".Repeat(width - size);
    }

    // -------------------------------------------------------------- splitting

    /// This text cut at every `separator`.
    ///
    /// Adjacent separators produce empty parts, and so do ones at either end:
    /// splitting "a,,b" on ',' gives three parts, and "" gives one. That is
    /// what makes it reversible -- joining the result with the same separator
    /// gives the original back.
    public String[] Split(String separator) {
        if (separator.ByteLength() == 0) { return [this]; }

        // Counted first so the array is allocated once at exactly the size it
        // needs, rather than grown.
        nuint parts = 1;
        nuint at = 0;
        while (true) {
            long found = this.IndexOf(separator, at);
            if (found == NotFound) { break; }
            parts = parts + 1;
            at = (nuint)found + separator.ByteLength();
        }

        var result = new String[parts];
        nuint index = 0;
        at = 0;

        while (index + 1 < parts) {
            long found = this.IndexOf(separator, at);
            result[index] = this.Substring(at, (nuint)found - at);
            at = (nuint)found + separator.ByteLength();
            index = index + 1;
        }

        result[index] = this.Substring(at);
        return result;
    }

    /// This text cut at every occurrence of one code unit.
    public String[] Split(char separator) {
        nuint size = this.ByteLength();
        var mine = this.ToPointer();

        nuint parts = 1;
        for (nuint i = 0; i < size; i = i + 1) {
            if (mine[i] == separator) { parts = parts + 1; }
        }

        var result = new String[parts];
        nuint index = 0;
        nuint start = 0;

        for (nuint i = 0; i < size; i = i + 1) {
            if (mine[i] == separator) {
                result[index] = this.Substring(start, i - start);
                index = index + 1;
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
    public String[] SplitLines() {
        nuint size = this.ByteLength();
        if (size == 0) { return []; }

        var mine = this.ToPointer();

        nuint lines = 1;
        for (nuint i = 0; i < size; i = i + 1) {
            if (mine[i] == 10 && i + 1 < size) { lines = lines + 1; }
        }

        var result = new String[lines];
        nuint index = 0;
        nuint start = 0;

        for (nuint i = 0; i < size; i = i + 1) {
            if (mine[i] != 10) { continue; }

            nuint end = i;
            if (end > start && mine[end - 1] == 13) { end = end - 1; }
            result[index] = this.Substring(start, end - start);
            index = index + 1;
            start = i + 1;
        }

        if (index < lines) {
            nuint end = size;
            if (end > start && mine[end - 1] == 13) { end = end - 1; }
            result[index] = this.Substring(start, end - start);
        }
        return result;
    }

    // ------------------------------------------------------------------ case

    /// This text with every ASCII letter uppercased, and every other byte left
    /// as it was. See the note at the top of this file.
    public String ToUpperAscii() {
        return this.MapAscii(true);
    }

    /// This text with every ASCII letter lowercased.
    public String ToLowerAscii() {
        return this.MapAscii(false);
    }

    /// True when the two texts differ only in the case of ASCII letters.
    public bool EqualsIgnoreCaseAscii(String other) {
        nuint size = this.ByteLength();
        if (size != other.ByteLength()) { return false; }

        var mine = this.ToPointer();
        var theirs = other.ToPointer();

        for (nuint i = 0; i < size; i = i + 1) {
            if (LowerByte(mine[i]) != LowerByte(theirs[i])) { return false; }
        }
        return true;
    }

    // ----------------------------------------------------------- comparison

    /// Orders two texts by their bytes: negative, zero or positive.
    ///
    /// Comparing UTF-8 byte by byte happens to order by code point as well,
    /// because the encoding was designed so that it would. It is not a
    /// linguistic ordering and does not claim to be one.
    public int CompareTo(String other) {
        nuint mineSize = this.ByteLength();
        nuint theirSize = other.ByteLength();
        nuint shorter = mineSize < theirSize ? mineSize : theirSize;

        var mine = this.ToPointer();
        var theirs = other.ToPointer();

        for (nuint i = 0; i < shorter; i = i + 1) {
            if (mine[i] != theirs[i]) { return mine[i] < theirs[i] ? -1 : 1; }
        }

        if (mineSize == theirSize) { return 0; }
        return mineSize < theirSize ? -1 : 1;
    }

    // ---------------------------------------------------------- code points

    /// The byte at `index`, which is a code unit and not a character.
    public byte ByteAt(nuint index) {
        return this.ToPointer()[index];
    }

    /// The scalar beginning at `index`.
    ///
    /// `index` must be the start of a character; one that lands inside a
    /// sequence gives U+FFFD, which is what a decoder does with a byte that
    /// cannot begin one.
    public char32 CodePointAt(nuint index) {
        nuint size = this.ByteLength();
        if (index >= size) { return (char32)0xFFFD; }

        var mine = this.ToPointer();
        byte lead = mine[index];

        if (lead < 0x80) { return (char32)(uint)lead; }

        nuint width = SequenceWidth(lead);
        if (width == 0 || index + width > size) { return (char32)0xFFFD; }

        uint scalar = (uint)(lead & (byte)(0x7F >> (int)width));
        for (nuint i = 1; i < width; i = i + 1) {
            byte next = mine[index + i];
            if ((next & 0xC0) != 0x80) { return (char32)0xFFFD; }
            scalar = (scalar << 6) | (uint)(next & 0x3F);
        }
        return (char32)scalar;
    }

    /// The index of the character after the one at `index`.
    ///
    /// Together with `CodePointAt` this is how the text is walked properly:
    ///
    /// ```
    /// for (nuint at = 0; at < s.ByteLength(); at = s.NextCodePoint(at)) {
    ///     var c = s.CodePointAt(at);
    /// }
    /// ```
    public nuint NextCodePoint(nuint index) {
        nuint size = this.ByteLength();
        if (index >= size) { return size; }

        nuint width = SequenceWidth(this.ToPointer()[index]);
        if (width == 0) { width = 1; }
        if (index + width > size) { return size; }
        return index + width;
    }

    // -------------------------------------------------------------- joining

    /// `parts` written out with this text between them. The inverse of `Split`.
    ///
    /// A method on the separator rather than a free function, because every
    /// module imports `Standard.Text` without asking and a global named `Join`
    /// is a global named `Join`. `", ".Join(parts)` also reads in the order it
    /// happens.
    public String Join(String[] parts) {
        if (parts.Length == 0) { return ""; }
        if (parts.Length == 1) { return parts[0]; }

        var built = new StringBuilder();
        for (nuint i = 0; i < parts.Length; i = i + 1) {
            if (i > 0) { built.Append(this); }
            built.Append(parts[i]);
        }
        return built.ToText();
    }

    // ------------------------------------------------------------ conversion

    /// This text's bytes, copied into an array.
    ///
    /// A copy rather than a view: a `String` is immutable and an array is not,
    /// so handing out the storage would let one be changed through the other.
    public byte[] ToBytes() {
        nuint size = this.ByteLength();
        var bytes = new byte[size];
        var mine = this.ToPointer();

        for (nuint i = 0; i < size; i = i + 1) { bytes[i] = mine[i]; }
        return bytes;
    }

    // --------------------------------------------------------------- private

    String MapAscii(bool upper) {
        nuint size = this.ByteLength();
        var mine = this.ToPointer();

        // Nothing to do is the common case, and it costs a scan rather than an
        // allocation to find out.
        bool differs = false;
        for (nuint i = 0; i < size; i = i + 1) {
            byte mapped = upper ? UpperByte(mine[i]) : LowerByte(mine[i]);
            if (mapped != mine[i]) { differs = true; }
        }
        if (!differs) { return this; }

        var bytes = new byte[size];
        for (nuint i = 0; i < size; i = i + 1) {
            bytes[i] = upper ? UpperByte(mine[i]) : LowerByte(mine[i]);
        }
        return FromBytes(&bytes[0], size);
    }
}

public class StringBuilder {

    // ------------------------------------------------------------ appending

    /// One Unicode scalar, encoded as UTF-8.
    ///
    /// This rather than `Append(char)`, because a `char` is one code unit and
    /// appending a lone continuation byte would put the builder into a state
    /// no `String` can be made from. A scalar always encodes to something
    /// whole.
    public void AppendCodePoint(char32 value) {
        uint scalar = (uint)value;

        // A surrogate or an out-of-range value is not a scalar, and the
        // replacement character is what a decoder would have produced.
        if (scalar > 0x10FFFF || (scalar >= 0xD800 && scalar <= 0xDFFF)) { scalar = 0xFFFD; }

        byte[4] encoded;
        nuint width = 0;

        if (scalar < 0x80) {
            encoded[0] = (byte)scalar;
            width = 1;
        } else if (scalar < 0x800) {
            encoded[0] = (byte)(0xC0 | (scalar >> 6));
            encoded[1] = (byte)(0x80 | (scalar & 0x3F));
            width = 2;
        } else if (scalar < 0x10000) {
            encoded[0] = (byte)(0xE0 | (scalar >> 12));
            encoded[1] = (byte)(0x80 | ((scalar >> 6) & 0x3F));
            encoded[2] = (byte)(0x80 | (scalar & 0x3F));
            width = 3;
        } else {
            encoded[0] = (byte)(0xF0 | (scalar >> 18));
            encoded[1] = (byte)(0x80 | ((scalar >> 12) & 0x3F));
            encoded[2] = (byte)(0x80 | ((scalar >> 6) & 0x3F));
            encoded[3] = (byte)(0x80 | (scalar & 0x3F));
            width = 4;
        }

        this.Append(FromBytes(&encoded[0], width));
    }

    /// A newline on its own.
    public void AppendLine() {
        this.Append("\n");
    }

    /// `true` or `false`.
    ///
    /// There is deliberately no `Append(long)` or `Append(double)` beside this
    /// one. An integer literal converts to both, so the two together would make
    /// `Append(42)` ambiguous -- which is why `AppendInteger` and `AppendDouble`
    /// were spelled out in the first place. A bool converts to neither.
    public void Append(bool value) {
        this.Append(FromBool(value));
    }

    /// Raw bytes. They are appended as they are, so it is the caller who
    /// decides whether what comes out is text.
    public void AppendBytes(byte[] data) {
        for (nuint i = 0; i < data.Length; i = i + 1) {
            this.Append(FromBytes(&data[i], 1));
        }
    }

    /// `parts` with `separator` between them.
    public void AppendJoined(String separator, String[] parts) {
        for (nuint i = 0; i < parts.Length; i = i + 1) {
            if (i > 0) { this.Append(separator); }
            this.Append(parts[i]);
        }
    }

    // ------------------------------------------------------------- reading

    /// Whether anything has been appended. The opposite of `IsEmpty`.
    public bool HasContent() {
        return !this.IsEmpty();
    }

    /// Where `value` first appears in what has been built, or `NotFound`.
    ///
    /// Byte by byte through the runtime rather than over a pointer, because a
    /// builder's storage moves when it grows and a pointer into it would be a
    /// pointer into the previous allocation.
    public long IndexOf(String value) {
        nuint size = this.ByteLength();
        nuint wanted = value.ByteLength();

        if (wanted == 0) { return 0; }
        if (wanted > size) { return NotFound; }

        var theirs = value.ToPointer();

        for (nuint i = 0; i <= size - wanted; i = i + 1) {
            bool same = true;
            for (nuint j = 0; j < wanted; j = j + 1) {
                if (this.ByteAt(i + j) != theirs[j]) { same = false; }
            }
            if (same) { return (long)i; }
        }
        return NotFound;
    }

    /// True when `value` appears in what has been built.
    public bool Contains(String value) {
        return this.IndexOf(value) != NotFound;
    }

    // ------------------------------------------------------------- editing

    /// Everything from `at` to the end, thrown away.
    public void Truncate(nuint at) {
        nuint size = this.ByteLength();
        if (at >= size) { return; }
        this.Remove(at, size - at);
    }

    /// The first occurrence of `from` replaced by `to`, if there is one.
    public bool ReplaceFirst(String from, String to) {
        long at = this.IndexOf(from);
        if (at == NotFound) { return false; }

        this.Remove((nuint)at, from.ByteLength());
        this.Insert((nuint)at, to);
        return true;
    }

    /// Every occurrence of `from` replaced by `to`.
    ///
    /// The search resumes past the replacement, so replacing "a" with "aa"
    /// terminates rather than growing forever.
    public nuint ReplaceAll(String from, String to) {
        if (from.ByteLength() == 0) { return 0; }

        nuint replaced = 0;
        nuint at = 0;

        while (at < this.ByteLength()) {
            long found = this.IndexOfFrom(from, at);
            if (found == NotFound) { break; }

            this.Remove((nuint)found, from.ByteLength());
            this.Insert((nuint)found, to);
            at = (nuint)found + to.ByteLength();
            replaced = replaced + 1;
        }
        return replaced;
    }

    /// Where `value` first appears at or after `start`, or `NotFound`.
    long IndexOfFrom(String value, nuint start) {
        nuint size = this.ByteLength();
        nuint wanted = value.ByteLength();

        if (start > size || wanted > size - start) { return NotFound; }

        var theirs = value.ToPointer();

        for (nuint i = start; i <= size - wanted; i = i + 1) {
            bool same = true;
            for (nuint j = 0; j < wanted; j = j + 1) {
                if (this.ByteAt(i + j) != theirs[j]) { same = false; }
            }
            if (same) { return (long)i; }
        }
        return NotFound;
    }
}

public class Utf16String {

    /// Whether there are any units at all.
    public bool IsEmpty() {
        return this.UnitCount() == 0;
    }

    /// The unit at `index`. A unit, not a character: one half of a surrogate
    /// pair is a unit and is not a character.
    public char16 UnitAt(nuint index) {
        return this.ToPointer()[index];
    }

    /// The scalar beginning at `index`, joining a surrogate pair.
    ///
    /// An unpaired surrogate gives U+FFFD, which is what transcoding it would
    /// have produced -- a lone half cannot be encoded in UTF-8 at all.
    public char32 CodePointAt(nuint index) {
        nuint count = this.UnitCount();
        if (index >= count) { return (char32)0xFFFD; }

        var units = this.ToPointer();
        uint first = (uint)units[index];

        if (first < 0xD800 || first > 0xDFFF) { return (char32)first; }
        if (first > 0xDBFF || index + 1 >= count) { return (char32)0xFFFD; }

        uint second = (uint)units[index + 1];
        if (second < 0xDC00 || second > 0xDFFF) { return (char32)0xFFFD; }

        return (char32)(0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00));
    }

    /// The index of the character after the one at `index`.
    public nuint NextCodePoint(nuint index) {
        nuint count = this.UnitCount();
        if (index >= count) { return count; }

        uint first = (uint)this.ToPointer()[index];
        if (first >= 0xD800 && first <= 0xDBFF && index + 1 < count) { return index + 2; }
        return index + 1;
    }

    /// True when the two hold the same units.
    public bool Equals(Utf16String other) {
        nuint count = this.UnitCount();
        if (count != other.UnitCount()) { return false; }

        var mine = this.ToPointer();
        var theirs = other.ToPointer();

        for (nuint i = 0; i < count; i = i + 1) {
            if (mine[i] != theirs[i]) { return false; }
        }
        return true;
    }

    /// The units as raw bytes, little-endian, which is what a Windows API and
    /// a UTF-16LE file both expect.
    public byte[] ToBytes() {
        nuint count = this.UnitCount();
        var bytes = new byte[count * 2];
        var units = this.ToPointer();

        for (nuint i = 0; i < count; i = i + 1) {
            uint unit = (uint)units[i];
            bytes[i * 2] = (byte)(unit & 0xFF);
            bytes[i * 2 + 1] = (byte)(unit >> 8);
        }
        return bytes;
    }
}

// ---------------------------------------------------------------- helpers
//
// None of these is public. `Standard.Text` is imported into every module
// whether the program asked for it or not, so a public function here is a name
// in every scope in the program -- which is how a `Join(String, String[])`
// managed to shadow `TaskScope`'s own `Join()`. What is worth having outside
// this file lives in `Standard.Ascii`, which has to be imported.

/// True for space, tab, newline, carriage return, vertical tab and form feed.
bool IsAsciiWhiteSpace(byte value) {
    return value == 32 || (value >= 9 && value <= 13);
}

/// The uppercase of an ASCII letter, or the byte unchanged.
byte UpperByte(byte value) {
    if (value >= 97 && value <= 122) { return (byte)(value - 32); }
    return value;
}

/// The lowercase of an ASCII letter, or the byte unchanged.
byte LowerByte(byte value) {
    if (value >= 65 && value <= 90) { return (byte)(value + 32); }
    return value;
}

/// How many bytes the UTF-8 sequence starting with this byte occupies, or 0
/// when it cannot start one.
nuint SequenceWidth(byte lead) {
    if (lead < 0x80) { return 1; }
    if ((lead & 0xE0) == 0xC0) { return 2; }
    if ((lead & 0xF0) == 0xE0) { return 3; }
    if ((lead & 0xF8) == 0xF0) { return 4; }
    return 0;
}

/// Whether `count` bytes at two addresses are the same.
bool Matches(byte* left, byte* right, nuint count) {
    for (nuint i = 0; i < count; i = i + 1) {
        if (left[i] != right[i]) { return false; }
    }
    return true;
}
