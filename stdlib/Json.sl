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

/// JSON, in two layers.
///
/// The lower one is a document: `Json.Parse` gives a `JsonValue`, a variant that
/// is exactly one of the six things JSON has, and `Write` puts one back. Nothing
/// about it needs a type, so it handles a document whose shape a program learns
/// at run time -- which is most of them.
///
/// The upper one maps a document onto a type, through the field tables a
/// `[Reflect]` type carries (§6). `Serialize` reads an object's fields and
/// `Populate` writes them.
///
/// **Why the mapping fills an object rather than making one.** A constructor is
/// what establishes a type's invariants, and a deserializer that allocated
/// zeroed memory would produce an object whose non-nullable fields were null --
/// a hole in the type system rather than a value. So `Populate` takes an
/// instance the program made, and `Deserialize<T>` calls `new T()` first, which
/// is what `where T : new()` is there to guarantee.
module Standard.Json;

import Standard.Collections;
import Standard.Reflection;
import Standard.Convert;

// ------------------------------------------------------------------- errors

/// Why a document could not be read.
public enum JsonError
{
    /// Nothing went wrong.
    None,

    /// A character that cannot start what is expected here.
    Unexpected,

    /// A string with no closing quote.
    UnterminatedText,

    /// A backslash followed by something that is not an escape.
    BadEscape,

    /// Digits that are not a JSON number.
    BadNumber,

    /// Something that started like `true`, `false` or `null` and was not.
    BadLiteral,

    /// A second value after the first. A JSON document is one value.
    TrailingContent,

    /// Nesting past `MaxDepth`.
    TooDeep,

    /// A document that is not the object a type wants. Only reflection-based
    /// reading raises this; parsing to a `JsonValue` takes any value.
    NotAnObject,

    /// A type with no field tables to map onto.
    NotReflected,
}

/// A sentence describing an error, for a message a person will read.
public String Describe(JsonError error)
{
    switch (error)
    {
        case JsonError.None: return "no error";
        case JsonError.Unexpected: return "unexpected character";
        case JsonError.UnterminatedText: return "unterminated string";
        case JsonError.BadEscape: return "bad escape sequence";
        case JsonError.BadNumber: return "malformed number";
        case JsonError.BadLiteral: return "expected true, false or null";
        case JsonError.TrailingContent: return "trailing content after the value";
        case JsonError.TooDeep: return "nested too deeply";
        case JsonError.NotAnObject: return "the document is not an object";
        case JsonError.NotReflected: return "the type carries no field metadata";
        default: return "unknown error";
    }
}

/// How far in the parser will nest before giving up.
///
/// A document is nested by recursion, so the limit is really about the stack.
/// It exists because a hostile document is one line -- ten thousand `[` -- and
/// the alternative to a limit is a crash that looks like a compiler bug.
public const nuint MaxDepth = 128u;

// ------------------------------------------------------------------ objects

/// The members of a JSON object, in the order they were written.
///
/// An `OrderedDictionary` rather than a `Dictionary`: order is what makes a
/// document read back the way it was written, which matters for a file a
/// person edits. The cost is that a lookup is a scan -- see the note there.
public class JsonObject
{
    OrderedDictionary<String, JsonValue> _members;

    /// An object with no members.
    public JsonObject() => _members = new OrderedDictionary<String, JsonValue>();

    /// How many members there are. Members rather than distinct names: a
    /// repeated name is kept, so this can exceed the number of names.
    public nuint Count => _members.Count;

    /// The name at a position, in the order the document wrote them.
    public String NameAt(nuint index) => _members.KeyAt(index);

    /// The value at a position, pairing with `NameAt` at the same index.
    public JsonValue ValueAt(nuint index) => _members.ValueAt(index);

    /// Adds a member. A repeated name is kept rather than replaced, because
    /// that is what the document said; `Find` answers with the first.
    public void Add(String name, JsonValue value) => _members.Add(name, value);

    /// Replaces the value of a name, or adds it.
    public void Set(String name, JsonValue value) => _members.Set(name, value);

    /// Where a name is, or `None`. One lookup rather than the two that asking
    /// whether it is there and then asking for it would cost.
    public Optional<nuint> IndexOf(String name) => _members.IndexOf(name);

    /// Whether a member of that name is there. A scan, so `IndexOf` once
    /// beats this followed by a lookup.
    public bool Has(String name) => _members.Has(name);

    /// The value of a name, or `Null` when it is not there. A document that
    /// does not mention a field and one that says `null` are the same thing to
    /// a reader that has a default already.
    public JsonValue Find(String name) => _members.Find(name, JsonValue.Null);

    /// Removes the first member of that name, answering whether there was one.
    public bool Remove(String name) => _members.Remove(name);
}

// ------------------------------------------------------------------- values

/// A JSON document, or any part of one.
///
/// Exactly the six things the grammar has. A variant rather than a class with
/// a kind field, so reading the wrong one is a compile error rather than a
/// null: `case Text t:` is the only way to reach `t.Value`.
public variant JsonValue
{
    /// The literal `null`. Also what `JsonObject.Find` answers for a name the
    /// document does not mention, since a reader with a default cannot tell
    /// the two apart and neither should have to.
    Null;

    /// `true` or `false`.
    Bool(bool Value);

    /// A number. JSON has only the one numeric type and it is a double, so an
    /// integer past 2^53 has already lost precision by the time it is here.
    Number(double Value);

    /// A string, decoded: the escapes are gone and the text is what they meant.
    Text(String Value);

    /// An array, in document order.
    Array(List<JsonValue> Items);

    /// An object, in the order its members were written.
    Object(JsonObject Members);
}

/// An empty array, ready to add to.
public JsonValue NewArray() => JsonValue.Array(new List<JsonValue>());

/// An empty object, ready to add to.
public JsonValue NewObject() => JsonValue.Object(new JsonObject());

/// A whole number as a JSON number, which has only the one numeric type.
///
/// Not `FromInteger`: `Standard.Text` is imported everywhere and has one of
/// those, and two functions of a name reached without a prefix is an ambiguity
/// at every call rather than at this declaration.
public JsonValue NumberOf(long value) => JsonValue.Number((double)value);

// The readers below answer with a default rather than a failure: a program
// that wants to know which case it has switches instead.
//
// Each is a tag test, the short form §2.6 describes: `value.Text` asks the
// tag, and inside the `if` the compiler has established the case, so the field
// that case carries is readable under its own name.

/// The text of a `Text`, or the fallback for anything else.
public String TextOr(JsonValue value, String fallback)
{
    if (value.Text)
        return value.Value;
    return fallback;
}

/// The value of a `Number`, or the fallback for anything else. A JSON number
/// is a double, so a large integer has already lost precision by here.
public double NumberOr(JsonValue value, double fallback)
{
    if (value.Number)
        return value.Value;
    return fallback;
}

/// The value of a `Number` truncated toward zero, or the fallback.
///
/// Truncation, not rounding: `3.9` is 3. JSON has one number type, so this is
/// how a field that is conceptually an integer is read back, and a value past
/// what a `long` holds is not detected.
public long IntegerOr(JsonValue value, long fallback)
{
    if (value.Number)
        return (long)value.Value;
    return fallback;
}

/// The value of a `Bool`, or the fallback. A `Number` of 1 is not true here;
/// only the JSON literals are.
public bool BoolOr(JsonValue value, bool fallback)
{
    if (value.Bool)
        return value.Value;
    return fallback;
}

/// True for the one case that carries nothing.
public bool IsNull(JsonValue value) => value.Null;

/// The members of an `Object`, or an empty one.
public JsonObject MembersOf(JsonValue value)
{
    if (value.Object)
        return value.Members;
    return new JsonObject();
}

/// The elements of an `Array`, or an empty list.
public List<JsonValue> ItemsOf(JsonValue value)
{
    if (value.Array)
        return value.Items;
    return new List<JsonValue>();
}

// ------------------------------------------------------------------ parsing

/// Where a parser is, which is a byte offset and a reason it stopped.
///
/// A class rather than a struct so that every function below shares the one
/// cursor without `ref` at each call: a recursive descent that has to say
/// `ref` twenty times reads like plumbing rather than like the grammar it is.
class Cursor
{
    public String Text;
    public nuint At;
    public nuint Depth;
    public JsonError Failure;

    public Cursor(String text)
    {
        Text = text;
        At = 0u;
        Depth = 0u;
        Failure = JsonError.None;
    }

    public bool Failed => Failure != JsonError.None;

    /// The first reason wins: everything after a failure is noise about the
    /// same mistake, and the first one is where it was made.
    public void Reject(JsonError why)
    {
        if (Failure == JsonError.None)
            Failure = why;
    }

    public bool AtEnd => At >= Text.ByteLength();

    public byte Peek()
    {
        if (AtEnd)
            return (byte)0;
        return Text.ByteAt(At);
    }

    public void Skip() => At = At + 1u;
}

void SkipSpace(Cursor cursor)
{
    while (!cursor.AtEnd)
    {
        byte c = cursor.Text.ByteAt(cursor.At);
        if (c != (byte)' ' && c != (byte)'\t' && c != (byte)'\n' && c != (byte)'\r')
        {
            return;
        }
        cursor.Skip();
    }
}

/// Reads one value, whatever it is. The whole grammar is five cases and the
/// two that recurse.
JsonValue ParseValue(Cursor cursor)
{
    if (cursor.Failed)
        return JsonValue.Null;

    if (cursor.Depth > MaxDepth)
    {
        cursor.Reject(JsonError.TooDeep);
        return JsonValue.Null;
    }

    SkipSpace(cursor);

    if (cursor.AtEnd)
    {
        cursor.Reject(JsonError.Unexpected);
        return JsonValue.Null;
    }

    byte c = cursor.Peek();

    if (c == (byte)'{')
        return ParseObject(cursor);
    if (c == (byte)'[')
        return ParseArray(cursor);
    if (c == (byte)'"')
        return JsonValue.Text(ParseText(cursor));
    if (c == (byte)'t' || c == (byte)'f' || c == (byte)'n')
        return ParseLiteral(cursor);
    if (c == (byte)'-' || (c >= (byte)'0' && c <= (byte)'9'))
        return ParseNumber(cursor);

    cursor.Reject(JsonError.Unexpected);
    return JsonValue.Null;
}

JsonValue ParseObject(Cursor cursor)
{
    cursor.Skip();                          // past '{'
    cursor.Depth++;

    var members = new JsonObject();

    SkipSpace(cursor);
    if (cursor.Peek() == (byte)'}')
    {
        cursor.Skip();
        cursor.Depth--;
        return JsonValue.Object(members);
    }

    while (true)
    {
        SkipSpace(cursor);

        if (cursor.Peek() != (byte)'"')
        {
            cursor.Reject(JsonError.Unexpected);
            break;
        }

        var name = ParseText(cursor);
        if (cursor.Failed)
            break;

        SkipSpace(cursor);
        if (cursor.Peek() != (byte)':')
        {
            cursor.Reject(JsonError.Unexpected);
            break;
        }
        cursor.Skip();

        var value = ParseValue(cursor);
        if (cursor.Failed)
            break;

        members.Add(name, value);

        SkipSpace(cursor);
        byte next = cursor.Peek();

        if (next == (byte)',')
        {
            cursor.Skip();
            continue;
        }

        if (next == (byte)'}')
        {
            cursor.Skip();
            break;
        }

        cursor.Reject(JsonError.Unexpected);
        break;
    }

    cursor.Depth--;
    return JsonValue.Object(members);
}

JsonValue ParseArray(Cursor cursor)
{
    cursor.Skip();                          // past '['
    cursor.Depth++;

    var items = new List<JsonValue>();

    SkipSpace(cursor);
    if (cursor.Peek() == (byte)']')
    {
        cursor.Skip();
        cursor.Depth--;
        return JsonValue.Array(items);
    }

    while (true)
    {
        var value = ParseValue(cursor);
        if (cursor.Failed)
            break;

        items.Add(value);

        SkipSpace(cursor);
        byte next = cursor.Peek();

        if (next == (byte)',')
        {
            cursor.Skip();
            continue;
        }

        if (next == (byte)']')
        {
            cursor.Skip();
            break;
        }

        cursor.Reject(JsonError.Unexpected);
        break;
    }

    cursor.Depth--;
    return JsonValue.Array(items);
}

/// A quoted string with its escapes undone.
///
/// `\u` is decoded to a code point and appended as UTF-8, surrogate pairs
/// joined -- which is the one place JSON's encoding and this language's differ,
/// since a `String` is UTF-8 by invariant and a lone surrogate is not a
/// character. An unpaired one becomes U+FFFD, the same answer the rest of the
/// library gives.
String ParseText(Cursor cursor)
{
    cursor.Skip();                          // past the opening quote

    var text = new StringBuilder();

    // The stretch since the last escape, appended whole rather than a byte at
    // a time. A string with no escapes in it is one substring and one append.
    nuint run = cursor.At;

    while (true)
    {
        if (cursor.AtEnd)
        {
            cursor.Reject(JsonError.UnterminatedText);
            return "";
        }

        byte c = cursor.Text.ByteAt(cursor.At);

        if (c == (byte)'"')
        {
            if (cursor.At > run)
            {
                text.Append(cursor.Text.Substring(run, cursor.At - run));
            }
            cursor.Skip();
            return text.ToText();
        }

        if (c != (byte)'\\')
        {
            cursor.Skip();
            continue;
        }

        if (cursor.At > run)
        {
            text.Append(cursor.Text.Substring(run, cursor.At - run));
        }

        cursor.Skip();
        if (cursor.AtEnd)
        {
            cursor.Reject(JsonError.UnterminatedText);
            return "";
        }

        byte escape = cursor.Text.ByteAt(cursor.At);
        cursor.Skip();

        if (escape == (byte)'"')
        {
            text.Append("\"");
        }
        else if (escape == (byte)'\\')
        {
            text.Append("\\");
        }
        else if (escape == (byte)'/')
        {
            text.Append("/");
        }
        else if (escape == (byte)'b')
        {
            text.Append(Text.FromChar((char32)8u));
        }
        else if (escape == (byte)'f')
        {
            text.Append(Text.FromChar((char32)12u));
        }
        else if (escape == (byte)'n')
        {
            text.Append("\n");
        }
        else if (escape == (byte)'r')
        {
            text.Append("\r");
        }
        else if (escape == (byte)'t')
        {
            text.Append("\t");
        }
        else if (escape == (byte)'u')
        {
            uint first = ParseHex4(cursor);
            if (cursor.Failed)
                return "";

            uint scalar = first;

            // A high surrogate is half a character; the low half follows it as
            // a second \u, and together they are one code point.
            if (first >= 0xD800u && first <= 0xDBFFu)
            {
                if (cursor.At + 1u < cursor.Text.ByteLength() &&
                    cursor.Text.ByteAt(cursor.At) == (byte)'\\' &&
                    cursor.Text.ByteAt(cursor.At + 1u) == (byte)'u')
                {
                    cursor.At = cursor.At + 2u;
                    uint second = ParseHex4(cursor);
                    if (cursor.Failed)
                        return "";

                    if (second >= 0xDC00u && second <= 0xDFFFu)
                    {
                        scalar = (uint)(0x10000u + ((first - 0xD800u) << 10) + (second - 0xDC00u));
                    }
                    else
                    {
                        scalar = 0xFFFDu;
                    }
                }
                else
                {
                    scalar = 0xFFFDu;
                }
            }
            else if (first >= 0xDC00u && first <= 0xDFFFu)
            {
                scalar = 0xFFFDu;
            }

            text.Append(Text.FromChar((char32)scalar));
        }
        else
        {
            cursor.Reject(JsonError.BadEscape);
            return "";
        }

        run = cursor.At;
    }
}

uint ParseHex4(Cursor cursor)
{
    uint value = 0u;

    for (nuint i = 0u; i < 4u; i++)
    {
        if (cursor.AtEnd)
        {
            cursor.Reject(JsonError.BadEscape);
            return 0u;
        }

        byte c = cursor.Text.ByteAt(cursor.At);
        uint digit = 0u;

        if (c >= (byte)'0' && c <= (byte)'9')
        {
            digit = (uint)(c - (byte)'0');
        }
        else if (c >= (byte)'a' && c <= (byte)'f')
        {
            digit = (uint)(c - (byte)'a' + 10);
        }
        else if (c >= (byte)'A' && c <= (byte)'F')
        {
            digit = (uint)(c - (byte)'A' + 10);
        }
        else
        {
            cursor.Reject(JsonError.BadEscape);
            return 0u;
        }

        value = (value << 4) + digit;
        cursor.Skip();
    }

    return value;
}

/// A JSON number, which is stricter than what a C parser accepts: no leading
/// `+`, no leading zero, no hex, and a `.` needs a digit on both sides.
JsonValue ParseNumber(Cursor cursor)
{
    nuint start = cursor.At;

    if (cursor.Peek() == (byte)'-')
        cursor.At = cursor.At + 1u;

    nuint digits = cursor.At;
    while (!cursor.AtEnd && IsDigit(cursor.Text.ByteAt(cursor.At)))
    {
        cursor.Skip();
    }

    if (cursor.At == digits)
    {
        cursor.Reject(JsonError.BadNumber);
        return JsonValue.Null;
    }

    // A leading zero may only be the whole of the integer part.
    if (cursor.Text.ByteAt(digits) == (byte)'0' && cursor.At - digits > 1u)
    {
        cursor.Reject(JsonError.BadNumber);
        return JsonValue.Null;
    }

    if (!cursor.AtEnd && cursor.Text.ByteAt(cursor.At) == (byte)'.')
    {
        cursor.Skip();
        nuint fraction = cursor.At;

        while (!cursor.AtEnd && IsDigit(cursor.Text.ByteAt(cursor.At)))
        {
            cursor.Skip();
        }

        if (cursor.At == fraction)
        {
            cursor.Reject(JsonError.BadNumber);
            return JsonValue.Null;
        }
    }

    if (!cursor.AtEnd)
    {
        byte e = cursor.Text.ByteAt(cursor.At);
        if (e == (byte)'e' || e == (byte)'E')
        {
            cursor.Skip();

            if (!cursor.AtEnd)
            {
                byte sign = cursor.Text.ByteAt(cursor.At);
                if (sign == (byte)'+' || sign == (byte)'-')
                    cursor.At = cursor.At + 1u;
            }

            nuint exponent = cursor.At;
            while (!cursor.AtEnd && IsDigit(cursor.Text.ByteAt(cursor.At)))
            {
                cursor.Skip();
            }

            if (cursor.At == exponent)
            {
                cursor.Reject(JsonError.BadNumber);
                return JsonValue.Null;
            }
        }
    }

    var text = cursor.Text.Substring(start, cursor.At - start);
    var parsed = Convert.ToDouble(text);

    if (!parsed.Ok)
    {
        cursor.Reject(JsonError.BadNumber);
        return JsonValue.Null;
    }

    return JsonValue.Number(parsed.Value);
}

bool IsDigit(byte c) => c >= (byte)'0' && c <= (byte)'9';

JsonValue ParseLiteral(Cursor cursor)
{
    if (Matches(cursor, "true"))
        return JsonValue.Bool(true);
    if (Matches(cursor, "false"))
        return JsonValue.Bool(false);
    if (Matches(cursor, "null"))
        return JsonValue.Null;

    cursor.Reject(JsonError.BadLiteral);
    return JsonValue.Null;
}

bool Matches(Cursor cursor, String word)
{
    if (cursor.At + word.ByteLength() > cursor.Text.ByteLength())
        return false;

    for (nuint i = 0u; i < word.ByteLength(); i++)
    {
        if (cursor.Text.ByteAt(cursor.At + i) != word.ByteAt(i))
            return false;
    }

    cursor.At = cursor.At + word.ByteLength();
    return true;
}

/// Reads a whole document. Trailing content is an error rather than ignored,
/// because a document with a second value in it is a document the writer meant
/// something else by.
public Result<JsonValue, JsonError> Parse(String text)
{
    var cursor = new Cursor(text);

    var value = ParseValue(cursor);
    if (cursor.Failed)
        return Fail(cursor.Failure);

    SkipSpace(cursor);
    if (!cursor.AtEnd)
        return Fail(JsonError.TrailingContent);

    return Ok(value);
}

// ------------------------------------------------------------------ writing

/// The document as text, on one line.
public String Write(JsonValue value)
{
    var text = new StringBuilder();
    WriteInto(text, value, 0u, false);
    return text.ToText();
}

/// The document as text, indented two spaces a level.
public String WriteIndented(JsonValue value)
{
    var text = new StringBuilder();
    WriteInto(text, value, 0u, true);
    return text.ToText();
}

void Newline(StringBuilder text, nuint depth)
{
    text.Append("\n");
    for (nuint i = 0u; i < depth; i++)
        text.Append("  ");
}

void WriteInto(StringBuilder text, JsonValue value, nuint depth, bool pretty)
{
    switch (value)
    {
        case Null:
            text.Append("null");
            break;

        case Bool flag:
            text.Append(flag.Value ? "true" : "false");
            break;

        case Number number:
            WriteNumber(text, number.Value);
            break;

        case Text held:
            WriteText(text, held.Value);
            break;

        case Array array:
            if (array.Items.Count == 0u)
            {
                text.Append("[]");
                break;
            }

            text.Append("[");
            for (nuint i = 0u; i < array.Items.Count; i++)
            {
                if (i > 0u)
                    text.Append(",");
                if (pretty)
                    Newline(text, depth + 1u);
                WriteInto(text, array.Items.At(i), depth + 1u, pretty);
            }
            if (pretty)
                Newline(text, depth);
            text.Append("]");
            break;

        case Object object:
            if (object.Members.Count == 0u)
            {
                text.Append("{}");
                break;
            }

            text.Append("{");
            for (nuint i = 0u; i < object.Members.Count; i++)
            {
                if (i > 0u)
                    text.Append(",");
                if (pretty)
                    Newline(text, depth + 1u);

                WriteText(text, object.Members.NameAt(i));
                text.Append(pretty ? ": " : ":");
                WriteInto(text, object.Members.ValueAt(i), depth + 1u, pretty);
            }
            if (pretty)
                Newline(text, depth);
            text.Append("}");
            break;
    }
}

/// A number, without the trailing `.0` a float formatter would add: JSON has
/// one numeric type, and a reader that wanted an integer should get one back.
void WriteNumber(StringBuilder text, double value)
{
    // A whole number small enough to be exact as a double is written as one.
    if (value == (double)(long)value &&
        value >= -9007199254740992.0 && value <= 9007199254740992.0)
    {
        text.AppendInteger((long)value);
        return;
    }

    text.AppendDouble(value);
}

/// A quoted string with everything JSON requires escaped, and nothing else.
///
/// The control characters below 0x20 must be escaped; `"` and `\` must be;
/// everything above is UTF-8 and passes through, because a JSON document is
/// UTF-8 and a `String` already is.
void WriteText(StringBuilder text, String value)
{
    text.Append("\"");

    // As in the reader: the stretch that needs nothing done to it is appended
    // whole, and only an escape interrupts.
    nuint run = 0u;

    for (nuint i = 0u; i < value.ByteLength(); i++)
    {
        byte c = value.ByteAt(i);

        String escaped = "";

        if (c == (byte)'"')
        {
            escaped = "\\\"";
        }
        else if (c == (byte)'\\')
        {
            escaped = "\\\\";
        }
        else if (c == 8u)
        {
            escaped = "\\b";
        }
        else if (c == 12u)
        {
            escaped = "\\f";
        }
        else if (c == 10u)
        {
            escaped = "\\n";
        }
        else if (c == 13u)
        {
            escaped = "\\r";
        }
        else if (c == 9u)
        {
            escaped = "\\t";
        }
        else if (c < 32u)
        {
            escaped = "\\u00" + Nibble((byte)(c >> 4)) + Nibble((byte)(c & 15u));
        }
        else
        {
            continue;
        }

        if (i > run)
            text.Append(value.Substring(run, i - run));
        text.Append(escaped);
        run = i + 1u;
    }

    if (value.ByteLength() > run)
    {
        text.Append(value.Substring(run, value.ByteLength() - run));
    }

    text.Append("\"");
}

/// One hex digit, for the `\u00XX` a control character is written as.
String Nibble(byte value)
{
    if (value < 10u)
        return Text.FromChar((char32)((uint)value + 48u));
    return Text.FromChar((char32)((uint)value - 10u + 97u));
}

// ------------------------------------------------------- mapping onto a type

// The two attributes a field may carry. They are declared here so that a
// program writing `[JsonName("id")]` needs nothing but this import.

/// The name this field has in the document, when it differs from the field's.
public attribute JsonName { String Name; }

/// Leaves the field out of the document entirely, in both directions.
public attribute JsonIgnore { }

/// Lets a reader make this field's object when the document has one and the
/// field is null.
///
/// Off by default, and opt-in per field rather than per call, because the type
/// is what knows whether it is safe. An object made this way is **zeroed**:
/// every reference in it starts null, and only the document fills them. Mark a
/// field with this when the document is what decides whether the object is
/// there, and leave it alone when the constructor already made one.
public attribute JsonCreate { }

/// The document a value would produce, as a `JsonValue`.
///
/// Reads the field tables of `[Reflect] T`, walking into a nested class or
/// struct rather than stopping at it. A field of a kind with no JSON spelling
/// -- a pointer, a delegate, an array -- is left out rather than guessed at.
public JsonValue ToValue<T>(T value)
{
    return ValueOfInstance((byte*)value, typeof(T));
}

/// The document as text.
public String Serialize<T>(T value) => Write(ToValue(value));

/// The same, indented.
public String SerializeIndented<T>(T value) => WriteIndented(ToValue(value));

JsonValue ValueOfInstance(byte* instance, Type type)
{
    if (instance == null)
        return JsonValue.Null;

    var members = new JsonObject();

    for (nuint i = 0u; i < type.FieldCount; i++)
    {
        var field = type.FieldAt(i);
        if (field.Has("JsonIgnore"))
            continue;

        // A field with no JSON spelling is left out rather than written as
        // something it is not. See `Represents` for which those are and why.
        if (!Represents(field))
            continue;

        members.Add(NameOf(field), ValueOfField(instance, field));
    }

    return JsonValue.Object(members);
}

/// Whether this module can write a field and read it back as what it was.
///
/// A number, a bool, a String, a `[Reflect]` object, and an array of any of
/// those. **A `List<T>` is not**: it is a class whose own fields are its
/// private storage, and filling one would mean calling `Add`, which needs
/// method metadata the compiler does not emit. A slice is not either -- it is
/// three words rather than a reference, so its elements are not where the
/// element arithmetic would look.
///
/// Leaving such a field out is the least wrong of the three answers. Writing
/// `null` says the value was absent when it was not, and walking a `List`
/// writes `{}` for a list with things in it -- both of which a reader would
/// believe.
bool Represents(Field field)
{
    if (field.IsSimple)
        return true;
    if (field.IsWalkable)
        return true;
    return RepresentsArray(field);
}

/// An array whose elements are something this can read and write.
bool RepresentsArray(Field field)
{
    if (!field.IsArray)
        return false;

    int kind = field.ElementKind;
    if (kind == KindString || kind == KindBool)
        return true;
    if (kind == KindFloat || kind == KindDouble)
        return true;
    if (kind >= KindChar && kind <= KindNUInt)
        return true;
    if (kind == KindChar16 || kind == KindChar32)
        return true;

    // An array of objects, when the objects carry field tables of their own.
    if (kind == KindClass || kind == KindStruct)
    {
        var inner = field.ElementType;
        return inner.Exists && inner.Has("Reflect");
    }

    return false;
}

String NameOf(Field field)
{
    if (field.Has("JsonName"))
        return field.Get("JsonName").AsText(0u);
    return field.Name;
}

JsonValue ValueOfField(byte* instance, Field field)
{
    int kind = field.Kind;

    if (kind == KindString)
        return JsonValue.Text(Reflection.ReadText(instance, field));
    if (kind == KindBool)
        return JsonValue.Bool(Reflection.ReadBool(instance, field));
    if (field.IsFloating)
        return JsonValue.Number(Reflection.ReadDouble(instance, field));
    if (field.IsInteger)
        return NumberOf(Reflection.ReadInteger(instance, field));

    if (field.IsWalkable)
    {
        byte* nested = Reflection.ReadAggregate(instance, field);
        return ValueOfInstance(nested, field.TypeOf());
    }

    if (RepresentsArray(field))
        return ValueOfArray(instance, field);

    return JsonValue.Null;
}

/// An array field as a JSON array, one element at a time.
///
/// A null array is `null` rather than `[]`: the two are different, and a
/// reader that gets `[]` for an array the object did not have would write it
/// back as one.
JsonValue ValueOfArray(byte* instance, Field field)
{
    byte* array = Reflection.ReadArray(instance, field);
    if (array == null)
        return JsonValue.Null;

    var items = new List<JsonValue>();
    int kind = field.ElementKind;

    for (nuint i = 0u; i < Reflection.ArrayLength(array); i++)
    {
        byte* at = Reflection.ElementAt(array, field, i);

        if (kind == KindString)
        {
            items.Add(JsonValue.Text(Reflection.ReadTextAt(at)));
        }
        else if (kind == KindBool)
        {
            items.Add(JsonValue.Bool(Reflection.ReadBoolAt(at)));
        }
        else if (kind == KindFloat || kind == KindDouble)
        {
            items.Add(JsonValue.Number(Reflection.ReadDoubleAt(at, field)));
        }
        else if (kind == KindClass || kind == KindStruct)
        {
            items.Add(ValueOfInstance(Reflection.ReadAggregateAt(at, field), field.ElementType));
        }
        else
        {
            items.Add(NumberOf(Reflection.ReadIntegerAt(at, field)));
        }
    }

    return JsonValue.Array(items);
}

/// Fills an object's fields from a document.
///
/// The object is the program's, made the ordinary way, so its constructor has
/// already run and its invariants already hold. A field the document does not
/// mention is left alone, which is what makes this safe: the value that stays
/// is the one the constructor chose.
///
/// A nested object is filled in place and never replaced, for the same reason.
/// A document naming a nested object the constructor left null is skipped
/// rather than allocated into, since nothing here could give the rest of that
/// object's fields a value.
public JsonError Populate<T>(T value, String text)
{
    var parsed = Parse(text);
    if (!parsed.Ok)
        return parsed.Error;

    return PopulateFrom(value, parsed.Value);
}

/// The same, from a document already parsed.
public JsonError PopulateFrom<T>(T value, JsonValue document)
{
    var type = typeof(T);
    if (type.FieldCount == 0u)
        return JsonError.NotReflected;

    if (!document.Object)
        return JsonError.NotAnObject;

    FillInstance((byte*)value, type, document.Members);
    return JsonError.None;
}

void FillInstance(byte* instance, Type type, JsonObject members)
{
    for (nuint i = 0u; i < type.FieldCount; i++)
    {
        var field = type.FieldAt(i);
        if (field.Has("JsonIgnore"))
            continue;

        if (!Represents(field))
            continue;

        // A call result cannot carry a narrowing -- it could answer
        // differently the second time -- so the name is what holds it.
        if (members.IndexOf(NameOf(field)) is Some at)
        {
            FillField(instance, field, members.ValueAt(at.Value));
        }
    }
}

void FillField(byte* instance, Field field, JsonValue value)
{
    int kind = field.Kind;

    if (kind == KindString)
    {
        if (value.Text)
            Reflection.WriteText(instance, field, value.Value);
        return;
    }

    if (kind == KindBool)
    {
        if (value.Bool)
            Reflection.WriteBool(instance, field, value.Value);
        return;
    }

    if (field.IsFloating)
    {
        if (value.Number)
            Reflection.WriteDouble(instance, field, value.Value);
        return;
    }

    if (field.IsInteger)
    {
        if (value.Number)
            Reflection.WriteInteger(instance, field, (long)value.Value);
        return;
    }

    if (field.IsWalkable)
    {
        byte* nested = Reflection.ReadAggregate(instance, field);

        // A field the constructor left empty, which the type has said the
        // document may fill.
        if (nested == null && field.Has("JsonCreate") && !IsNull(value))
        {
            nested = Reflection.MakeInto(instance, field);
        }

        if (nested == null)
            return;

        if (value.Object)
            FillInstance(nested, field.TypeOf(), value.Members);
        return;
    }

    if (RepresentsArray(field))
        FillArray(instance, field, value);
}

/// Fills an array field, element by element, as far as both go.
///
/// **The array is not replaced.** Its length is the one the constructor chose,
/// and a document with more elements than that fills what fits and stops; one
/// with fewer leaves the rest as they were. Allocating a new array would mean
/// deciding the length from the document, which is how a message becomes a
/// memory bill, and reading into an object the program made is the whole
/// bargain this module makes.
void FillArray(byte* instance, Field field, JsonValue value)
{
    byte* array = Reflection.ReadArray(instance, field);
    if (array == null)
        return;
    if (!value.Array)
        return;

    nuint length = Reflection.ArrayLength(array);
    int kind = field.ElementKind;

    for (nuint i = 0u; i < value.Items.Count && i < length; i++)
    {
        byte* at = Reflection.ElementAt(array, field, i);
        var item = value.Items.At(i);

        if (kind == KindString)
        {
            if (item.Text)
            {
                Reflection.WriteTextAt(at, item.Value);
            }
        }
        else if (kind == KindBool)
        {
            if (item.Bool)
            {
                Reflection.WriteBoolAt(at, item.Value);
            }
        }
        else if (kind == KindFloat || kind == KindDouble)
        {
            if (item.Number)
            {
                Reflection.WriteDoubleAt(at, field, item.Value);
            }
        }
        else if (kind == KindClass || kind == KindStruct)
        {
            byte* nested = Reflection.ReadAggregateAt(at, field);
            if (nested != null)
            {
                if (item.Object)
                    FillInstance(nested, field.ElementType, item.Members);
            }
        }
        else
        {
            if (item.Number)
                Reflection.WriteIntegerAt(at, field, (long)item.Value);
        }
    }
}
