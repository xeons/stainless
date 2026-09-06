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

// XML, in the two layers `Standard.Json` has: a document that needs no type,
// and a mapping onto one that reads a `[Reflect]` type's field tables.
//
// **What this reads.** Elements, attributes, text, CDATA, comments, the five
// predefined entities and numeric character references, and an optional
// declaration or doctype at the front. That is the shape of a configuration
// file, a document a program exchanges, and most of what XML is used for now.
//
// **What it does not.** Namespaces are not resolved: `<x:name>` is an element
// whose name is the whole of `x:name`, and `xmlns` is an ordinary attribute. A
// DTD is skipped rather than applied, so no entity a document declares for
// itself is expanded and no default attribute appears. Both are refusals to
// half-implement something: a program that needs them needs all of them, and
// what is here says so rather than working until it does not.
module Standard.Xml;

import Standard.Collections;
import Standard.Reflection;
import Standard.Convert;

// ------------------------------------------------------------------- errors

public enum XmlError {
    None,
    Unexpected,         // a character that cannot appear here
    UnclosedTag,        // a '<' with no '>'
    UnclosedText,       // a quoted attribute value with no closing quote
    MismatchedEnd,      // </b> closing <a>
    UnexpectedEnd,      // the document stopped inside something
    BadName,            // a tag or attribute name that is not one
    BadEntity,          // an & that is not an entity this reads
    NoRoot,             // nothing but whitespace and comments
    TrailingContent,    // a second root element
    TooDeep,            // nested past the limit below
    DuplicateAttribute, // one element naming an attribute twice
    NotReflected,       // a type with no field metadata to map onto
}

public String Describe(XmlError error) {
    switch (error) {
        case XmlError.None: return "no error";
        case XmlError.Unexpected: return "unexpected character";
        case XmlError.UnclosedTag: return "unclosed tag";
        case XmlError.UnclosedText: return "unterminated attribute value";
        case XmlError.MismatchedEnd: return "end tag does not match its start tag";
        case XmlError.UnexpectedEnd: return "the document ended inside an element";
        case XmlError.BadName: return "malformed name";
        case XmlError.BadEntity: return "unknown entity";
        case XmlError.NoRoot: return "no root element";
        case XmlError.TrailingContent: return "content after the root element";
        case XmlError.TooDeep: return "nested too deeply";
        case XmlError.DuplicateAttribute: return "the element repeats an attribute";
        case XmlError.NotReflected: return "the type carries no field metadata";
        default: return "unknown error";
    }
}

/// How far the parser will nest, for the reason `Json.MaxDepth` exists: the
/// nesting is recursion, and a hostile document is one long line.
public const nuint MaxDepth = 128u;

// --------------------------------------------------------------- attributes

/// An element's attributes, in the order they were written.
///
/// The same `OrderedDictionary` a JSON object's members are, and for the same
/// reason: an attribute list that came back reordered is a document nobody
/// wrote.
public class XmlAttributes {
    OrderedDictionary<String, String> entries;

    public XmlAttributes() { entries = new OrderedDictionary<String, String>(); }

    public nuint Count() { return entries.Count(); }
    public String NameAt(nuint index) { return entries.KeyAt(index); }
    public String ValueAt(nuint index) { return entries.ValueAt(index); }

    public void Add(String name, String value) { entries.Add(name, value); }
    public void Set(String name, String value) { entries.Set(name, value); }

    /// Where a name is, or `None`.
    public Optional<nuint> IndexOf(String name) { return entries.IndexOf(name); }

    public bool Has(String name) { return entries.Has(name); }

    /// The value of an attribute, or the fallback when it is not there.
    public String Find(String name, String fallback) { return entries.Find(name, fallback); }

    public bool Remove(String name) { return entries.Remove(name); }
}

// ----------------------------------------------------------------- elements

/// One element: a name, its attributes, its child elements and its text.
///
/// **Text is gathered rather than interleaved.** A node's `Text` is every
/// character run inside it joined together, which loses where each sat between
/// the children. That is the wrong model for a document with mixed content --
/// a paragraph with `<em>` inside it -- and the right one for the data XML is
/// mostly used to carry. `Children` and `Text` together are what a
/// configuration file has.
public class XmlNode {
    public String Name;
    public XmlAttributes Attributes;
    public List<XmlNode> Children;
    public String Text;

    public XmlNode(String name) {
        Name = name;
        Attributes = new XmlAttributes();
        Children = new List<XmlNode>();
        Text = "";
    }

    /// The first child of that name, or null.
    public XmlNode? Child(String name) {
        for (nuint i = 0u; i < Children.Count(); i++) {
            var child = Children.At(i);
            if (child.Name == name) { return child; }
        }
        return null;
    }

    /// Every child of that name, in order.
    public List<XmlNode> ChildrenNamed(String name) {
        var found = new List<XmlNode>();
        for (nuint i = 0u; i < Children.Count(); i++) {
            var child = Children.At(i);
            if (child.Name == name) { found.Add(child); }
        }
        return found;
    }

    /// The text of the first child of that name, or the fallback.
    public String TextOf(String name, String fallback) {
        var child = Child(name);
        if (child == null) { return fallback; }
        return child.Text;
    }

    public void Add(XmlNode child) { Children.Add(child); }
}

// ------------------------------------------------------------------ parsing

class Cursor {
    public String Source;
    public nuint At;
    public nuint Depth;
    public XmlError Failure;

    public Cursor(String source) {
        Source = source;
        At = 0u;
        Depth = 0u;
        Failure = XmlError.None;
    }

    public bool Failed() { return Failure != XmlError.None; }

    public void Reject(XmlError why) {
        if (Failure == XmlError.None) { Failure = why; }
    }

    public bool AtEnd() { return At >= Source.ByteLength(); }

    public byte Peek() {
        if (AtEnd()) { return (byte)0; }
        return Source.ByteAt(At);
    }

    public byte PeekAt(nuint ahead) {
        if (At + ahead >= Source.ByteLength()) { return (byte)0; }
        return Source.ByteAt(At + ahead);
    }

    public void Skip() { At = At + 1u; }

    /// Consumes `word` when it is next, and answers whether it was.
    public bool Take(String word) {
        if (At + word.ByteLength() > Source.ByteLength()) { return false; }

        for (nuint i = 0u; i < word.ByteLength(); i++) {
            if (Source.ByteAt(At + i) != word.ByteAt(i)) { return false; }
        }

        At = At + word.ByteLength();
        return true;
    }

    /// Moves past `word`, or to the end when it is not there.
    public bool SkipPast(String word) {
        while (!AtEnd()) {
            if (Take(word)) { return true; }
            Skip();
        }
        return false;
    }
}

bool IsSpace(byte c) {
    return c == (byte)' ' || c == (byte)'\t' || c == (byte)'\n' || c == (byte)'\r';
}

/// What may start a name. Deliberately generous: a letter, an underscore or a
/// colon, plus every byte above ASCII, since a name may be any Unicode letter
/// and checking which would mean a table this does not carry.
bool IsNameStart(byte c) {
    if (c >= (byte)'a' && c <= (byte)'z') { return true; }
    if (c >= (byte)'A' && c <= (byte)'Z') { return true; }
    if (c == (byte)'_' || c == (byte)':') { return true; }
    return c >= (byte)128;
}

bool IsNamePart(byte c) {
    if (IsNameStart(c)) { return true; }
    if (c >= (byte)'0' && c <= (byte)'9') { return true; }
    return c == (byte)'-' || c == (byte)'.';
}

void SkipSpace(Cursor cursor) {
    while (!cursor.AtEnd() && IsSpace(cursor.Source.ByteAt(cursor.At))) { cursor.Skip(); }
}

String ParseName(Cursor cursor) {
    nuint start = cursor.At;

    if (cursor.AtEnd() || !IsNameStart(cursor.Peek())) {
        cursor.Reject(XmlError.BadName);
        return "";
    }

    while (!cursor.AtEnd() && IsNamePart(cursor.Source.ByteAt(cursor.At))) { cursor.Skip(); }

    return cursor.Source.Substring(start, cursor.At - start);
}

/// Skips a comment, a processing instruction, a CDATA section or a doctype,
/// answering whether it found one. CDATA is the one that produces text, so it
/// is handled by the caller instead.
bool SkipAside(Cursor cursor) {
    if (cursor.Take("<!--")) {
        if (!cursor.SkipPast("-->")) { cursor.Reject(XmlError.UnclosedTag); }
        return true;
    }

    if (cursor.Take("<?")) {
        if (!cursor.SkipPast("?>")) { cursor.Reject(XmlError.UnclosedTag); }
        return true;
    }

    if (cursor.Take("<!DOCTYPE")) {
        // An internal subset is bracketed; skipping to the first '>' would
        // stop inside it, so the brackets are counted.
        nuint depth = 0u;

        while (!cursor.AtEnd()) {
            byte c = cursor.Peek();
            cursor.Skip();

            if (c == (byte)'[') { depth = depth + 1u; }
            else if (c == (byte)']') { if (depth > 0u) { depth = depth - 1u; } }
            else if (c == (byte)'>' && depth == 0u) { return true; }
        }

        cursor.Reject(XmlError.UnclosedTag);
        return true;
    }

    return false;
}

/// One element, its attributes and everything inside it.
XmlNode ParseElement(Cursor cursor) {
    if (cursor.Depth > MaxDepth) {
        cursor.Reject(XmlError.TooDeep);
        return new XmlNode("");
    }

    cursor.Skip();                              // past '<'

    var name = ParseName(cursor);
    if (cursor.Failed()) { return new XmlNode(""); }

    var node = new XmlNode(name);

    // --- attributes
    while (true) {
        SkipSpace(cursor);

        if (cursor.AtEnd()) {
            cursor.Reject(XmlError.UnclosedTag);
            return node;
        }

        byte c = cursor.Peek();

        if (c == (byte)'>') {
            cursor.Skip();
            break;
        }

        if (c == (byte)'/') {
            cursor.Skip();
            if (cursor.Peek() != (byte)'>') {
                cursor.Reject(XmlError.Unexpected);
                return node;
            }
            cursor.Skip();
            return node;                        // <name ... /> has no content
        }

        var key = ParseName(cursor);
        if (cursor.Failed()) { return node; }

        SkipSpace(cursor);
        if (cursor.Peek() != (byte)'=') {
            cursor.Reject(XmlError.Unexpected);
            return node;
        }
        cursor.Skip();
        SkipSpace(cursor);

        byte quote = cursor.Peek();
        if (quote != (byte)'"' && quote != (byte)'\'') {
            cursor.Reject(XmlError.Unexpected);
            return node;
        }
        cursor.Skip();

        var value = ParseUntil(cursor, quote);
        if (cursor.Failed()) { return node; }

        // XML forbids a repeated attribute on one element, and a document with
        // one means something its writer did not: which of the two is the
        // value is not a question with an answer.
        if (node.Attributes.Has(key)) {
            cursor.Reject(XmlError.DuplicateAttribute);
            return node;
        }

        node.Attributes.Add(key, value);
    }

    // --- content
    cursor.Depth++;
    var text = new StringBuilder();

    while (true) {
        if (cursor.AtEnd()) {
            cursor.Reject(XmlError.UnexpectedEnd);
            break;
        }

        if (cursor.Peek() == (byte)'<') {
            if (cursor.PeekAt(1u) == (byte)'/') {
                cursor.Skip();
                cursor.Skip();

                var closing = ParseName(cursor);
                if (cursor.Failed()) { break; }

                if (closing != node.Name) {
                    cursor.Reject(XmlError.MismatchedEnd);
                    break;
                }

                SkipSpace(cursor);
                if (cursor.Peek() != (byte)'>') {
                    cursor.Reject(XmlError.Unexpected);
                    break;
                }
                cursor.Skip();
                break;
            }

            if (cursor.Take("<![CDATA[")) {
                nuint start = cursor.At;

                if (!cursor.SkipPast("]]>")) {
                    cursor.Reject(XmlError.UnclosedTag);
                    break;
                }

                // Everything between, with no entities expanded, which is what
                // a CDATA section is for.
                text.Append(cursor.Source.Substring(start, cursor.At - start - 3u));
                continue;
            }

            if (SkipAside(cursor)) {
                if (cursor.Failed()) { break; }
                continue;
            }

            var child = ParseElement(cursor);
            if (cursor.Failed()) { break; }

            node.Add(child);
            continue;
        }

        text.Append(ParseUntil(cursor, (byte)'<'));
        if (cursor.Failed()) { break; }
    }

    cursor.Depth--;
    node.Text = text.ToText();
    return node;
}

/// Reads text up to `stop`, expanding entities. The stop character is consumed
/// when it is a quote and left when it is `<`, because the caller needs to see
/// which tag follows.
String ParseUntil(Cursor cursor, byte stop) {
    var text = new StringBuilder();
    nuint run = cursor.At;

    while (true) {
        if (cursor.AtEnd()) {
            // Running out inside a quoted value is an error; running out of
            // content is the caller's to notice.
            if (stop != (byte)'<') { cursor.Reject(XmlError.UnclosedText); }
            break;
        }

        byte c = cursor.Source.ByteAt(cursor.At);

        if (c == stop) {
            if (cursor.At > run) {
                text.Append(cursor.Source.Substring(run, cursor.At - run));
            }
            if (stop != (byte)'<') { cursor.Skip(); }
            break;
        }

        if (c != (byte)'&') {
            cursor.Skip();
            continue;
        }

        if (cursor.At > run) {
            text.Append(cursor.Source.Substring(run, cursor.At - run));
        }

        text.Append(ParseEntity(cursor));
        if (cursor.Failed()) { break; }

        run = cursor.At;
    }

    return text.ToText();
}

/// One `&...;`: the five XML predefines, or a numeric character reference.
String ParseEntity(Cursor cursor) {
    if (cursor.Take("&amp;")) { return "&"; }
    if (cursor.Take("&lt;")) { return "<"; }
    if (cursor.Take("&gt;")) { return ">"; }
    if (cursor.Take("&quot;")) { return "\""; }
    if (cursor.Take("&apos;")) { return "'"; }

    if (cursor.Take("&#x") || cursor.Take("&#X")) { return ParseCharacterReference(cursor, 16u); }
    if (cursor.Take("&#")) { return ParseCharacterReference(cursor, 10u); }

    // A document's own entity would have been declared in a DTD, and the DTD
    // was skipped -- so this is honest about not knowing rather than dropping
    // the reference silently.
    cursor.Reject(XmlError.BadEntity);
    return "";
}

String ParseCharacterReference(Cursor cursor, uint radix) {
    uint value = 0u;
    nuint digits = 0u;

    while (!cursor.AtEnd()) {
        byte c = cursor.Peek();
        uint digit = 0u;

        if (c >= (byte)'0' && c <= (byte)'9') { digit = (uint)(c - (byte)'0'); }
        else if (radix == 16u && c >= (byte)'a' && c <= (byte)'f') {
            digit = (uint)(c - (byte)'a' + 10);
        }
        else if (radix == 16u && c >= (byte)'A' && c <= (byte)'F') {
            digit = (uint)(c - (byte)'A' + 10);
        }
        else { break; }

        value = value * radix + digit;
        digits++;
        cursor.Skip();

        if (digits > 8u) {
            cursor.Reject(XmlError.BadEntity);
            return "";
        }
    }

    if (digits == 0u || cursor.Peek() != (byte)';') {
        cursor.Reject(XmlError.BadEntity);
        return "";
    }
    cursor.Skip();

    // Anything that is not a scalar becomes U+FFFD, as everywhere else.
    if (value > 0x10FFFFu || (value >= 0xD800u && value <= 0xDFFFu)) { value = 0xFFFDu; }

    return Text.FromChar((char32)value);
}

/// Reads a whole document and answers with its root element.
public Result<XmlNode, XmlError> Parse(String source) {
    var cursor = new Cursor(source);

    // Anything before the root: a declaration, a doctype, comments.
    while (true) {
        SkipSpace(cursor);
        if (cursor.AtEnd()) { return Fail(XmlError.NoRoot); }

        if (cursor.Peek() != (byte)'<') { return Fail(XmlError.Unexpected); }
        if (!SkipAside(cursor)) { break; }
        if (cursor.Failed()) { return Fail(cursor.Failure); }
    }

    if (cursor.PeekAt(1u) == (byte)'/') { return Fail(XmlError.Unexpected); }

    var root = ParseElement(cursor);
    if (cursor.Failed()) { return Fail(cursor.Failure); }

    // And anything after it, which may only be more of the same.
    while (true) {
        SkipSpace(cursor);
        if (cursor.AtEnd()) { break; }

        if (cursor.Peek() != (byte)'<') { return Fail(XmlError.TrailingContent); }
        if (!SkipAside(cursor)) { return Fail(XmlError.TrailingContent); }
        if (cursor.Failed()) { return Fail(cursor.Failure); }
    }

    return Ok(root);
}

// ------------------------------------------------------------------ writing

/// The element as text, on one line.
public String Write(XmlNode node) {
    var text = new StringBuilder();
    WriteInto(text, node, 0u, false);
    return text.ToText();
}

/// The same, indented two spaces a level. An element with text in it is still
/// written on one line, because the whitespace an indent adds would become
/// part of that text when it was read back.
public String WriteIndented(XmlNode node) {
    var text = new StringBuilder();
    WriteInto(text, node, 0u, true);
    return text.ToText();
}

/// The declaration and the element under it, which is what a whole file wants.
public String WriteDocument(XmlNode node) {
    return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" + WriteIndented(node);
}

void WriteInto(StringBuilder text, XmlNode node, nuint depth, bool pretty) {
    if (pretty) {
        for (nuint i = 0u; i < depth; i++) { text.Append("  "); }
    }

    text.Append("<");
    text.Append(node.Name);

    for (nuint i = 0u; i < node.Attributes.Count(); i++) {
        text.Append(" ");
        text.Append(node.Attributes.NameAt(i));
        text.Append("=\"");
        WriteEscaped(text, node.Attributes.ValueAt(i), true);
        text.Append("\"");
    }

    bool empty = node.Children.Count() == 0u && node.Text.ByteLength() == 0u;
    if (empty) {
        text.Append("/>");
        return;
    }

    text.Append(">");

    // Text first, then the children, which is the order this model can
    // represent -- see the note on XmlNode.
    WriteEscaped(text, node.Text, false);

    for (nuint i = 0u; i < node.Children.Count(); i++) {
        if (pretty) { text.Append("\n"); }
        WriteInto(text, node.Children.At(i), depth + 1u, pretty);
    }

    if (pretty && node.Children.Count() > 0u) {
        text.Append("\n");
        for (nuint i = 0u; i < depth; i++) { text.Append("  "); }
    }

    text.Append("</");
    text.Append(node.Name);
    text.Append(">");
}

/// Escapes what XML requires and nothing else.
///
/// `<` and `&` always; `>` too, because `]]>` in text is not allowed and
/// escaping every `>` is the cheap way to be sure. `"` only inside an
/// attribute, which is the only place it could end anything.
void WriteEscaped(StringBuilder text, String value, bool inAttribute) {
    nuint run = 0u;

    for (nuint i = 0u; i < value.ByteLength(); i++) {
        byte c = value.ByteAt(i);
        String escaped = "";

        if (c == (byte)'&') { escaped = "&amp;"; }
        else if (c == (byte)'<') { escaped = "&lt;"; }
        else if (c == (byte)'>') { escaped = "&gt;"; }
        else if (c == (byte)'"' && inAttribute) { escaped = "&quot;"; }
        else if (c == (byte)'\n' && inAttribute) { escaped = "&#10;"; }
        else if (c == (byte)'\t' && inAttribute) { escaped = "&#9;"; }
        else if (c == (byte)'\r') { escaped = "&#13;"; }
        else { continue; }

        if (i > run) { text.Append(value.Substring(run, i - run)); }
        text.Append(escaped);
        run = i + 1u;
    }

    if (value.ByteLength() > run) {
        text.Append(value.Substring(run, value.ByteLength() - run));
    }
}

// ------------------------------------------------------- mapping onto a type

/// The element name a field is written as, when it differs from the field's.
public attribute XmlName { String Name; }

/// Writes the field as an attribute of its element rather than as a child.
public attribute XmlAttribute { }

/// Leaves the field out entirely, in both directions.
public attribute XmlIgnore { }

/// Lets a reader make this field's object when the element is there and the
/// field is null. The same opt-in, and the same hazard, as `[JsonCreate]`.
public attribute XmlCreate { }

/// A value as an element, with each field a child element under it.
///
/// A field marked `[XmlAttribute]` becomes an attribute instead, which is what
/// makes the output look like XML a person would have written rather than a
/// JSON document with angle brackets.
public XmlNode ToNode<T>(T value, String name) {
    return NodeOfInstance((byte*)value, typeof(T), name);
}

/// The element as text.
public String Serialize<T>(T value, String name) { return Write(ToNode(value, name)); }

/// The same, with a declaration and indentation.
public String SerializeDocument<T>(T value, String name) {
    return WriteDocument(ToNode(value, name));
}

XmlNode NodeOfInstance(byte* instance, Type type, String name) {
    var node = new XmlNode(name);
    if (instance == null) { return node; }

    var text = new StringBuilder();

    for (nuint i = 0u; i < type.FieldCount(); i++) {
        var field = type.FieldAt(i);
        if (field.Has("XmlIgnore")) { continue; }

        var fieldName = NameOf(field);

        if (field.IsWalkable()) {
            byte* nested = Reflection.ReadAggregate(instance, field);
            if (nested == null) { continue; }

            node.Add(NodeOfInstance(nested, field.TypeOf(), fieldName));
            continue;
        }

        // An array is repeated children of one name, which is how XML says a
        // sequence. A `List<T>` still cannot be walked -- its own fields are
        // its private storage -- and is left out rather than misstated.
        if (WalksAsArray(field)) {
            AddArray(node, instance, field, fieldName);
            continue;
        }

        if (!field.IsSimple()) { continue; }

        var written = TextOfField(instance, field);

        if (field.Has("XmlAttribute")) {
            node.Attributes.Add(fieldName, written);
            continue;
        }

        var child = new XmlNode(fieldName);
        child.Text = written;
        node.Add(child);
    }

    return node;
}

String NameOf(Field field) {
    if (field.Has("XmlName")) { return field.Get("XmlName").AsText(0u); }
    return field.Name();
}

/// An array whose elements this can write and read back.
bool WalksAsArray(Field field) {
    if (!field.IsArray()) { return false; }

    int kind = field.ElementKind();
    if (kind == KindString || kind == KindBool) { return true; }
    if (kind == KindFloat || kind == KindDouble) { return true; }
    if (kind >= KindChar && kind <= KindNUInt) { return true; }
    if (kind == KindChar16 || kind == KindChar32) { return true; }

    if (kind == KindClass || kind == KindStruct) {
        var inner = field.ElementType();
        return inner.Exists() && inner.Has("Reflect");
    }

    return false;
}

/// One child element per element of the array, all of the same name.
///
/// A null array writes nothing at all, which reads back as an array left
/// alone -- the same answer an absent element gives, and the right one, since
/// an object without the array is not an object with an empty one.
void AddArray(XmlNode node, byte* instance, Field field, String name) {
    byte* array = Reflection.ReadArray(instance, field);
    if (array == null) { return; }

    int kind = field.ElementKind();

    for (nuint i = 0u; i < Reflection.ArrayLength(array); i++) {
        byte* at = Reflection.ElementAt(array, field, i);

        if (kind == KindClass || kind == KindStruct) {
            byte* nested = Reflection.ReadAggregateAt(at, field);
            if (nested == null) { continue; }
            node.Add(NodeOfInstance(nested, field.ElementType(), name));
            continue;
        }

        var child = new XmlNode(name);
        child.Text = TextOfElement(at, field);
        node.Add(child);
    }
}

String TextOfElement(byte* at, Field field) {
    int kind = field.ElementKind();

    if (kind == KindString) { return Reflection.ReadTextAt(at); }
    if (kind == KindBool) { return Text.FromBool(Reflection.ReadBoolAt(at)); }
    if (kind == KindFloat || kind == KindDouble) {
        return Text.FromDouble(Reflection.ReadDoubleAt(at, field));
    }
    return Text.FromInteger(Reflection.ReadIntegerAt(at, field));
}

String TextOfField(byte* instance, Field field) {
    if (field.Kind() == KindString) { return Reflection.ReadText(instance, field); }
    if (field.Kind() == KindBool) { return Text.FromBool(Reflection.ReadBool(instance, field)); }
    if (field.IsFloating()) { return Text.FromDouble(Reflection.ReadDouble(instance, field)); }
    if (field.IsInteger()) { return Text.FromInteger(Reflection.ReadInteger(instance, field)); }
    return "";
}

/// Fills an object's fields from an element.
///
/// The object is the program's, for the reason `Json.Populate` takes one: its
/// constructor has run, so a field the document does not mention keeps the
/// value the type promised rather than a zero.
public XmlError Populate<T>(T value, String source) {
    var parsed = Parse(source);
    if (!parsed.Ok) { return parsed.Error; }

    return PopulateFrom(value, parsed.Value);
}

/// The same, from an element already parsed.
public XmlError PopulateFrom<T>(T value, XmlNode node) {
    var type = typeof(T);
    if (type.FieldCount() == 0u) { return XmlError.NotReflected; }

    FillInstance((byte*)value, type, node);
    return XmlError.None;
}

void FillInstance(byte* instance, Type type, XmlNode node) {
    for (nuint i = 0u; i < type.FieldCount(); i++) {
        var field = type.FieldAt(i);
        if (field.Has("XmlIgnore")) { continue; }

        var name = NameOf(field);

        if (field.IsWalkable()) {
            var child = node.Child(name);
            if (child == null) { continue; }

            byte* nested = Reflection.ReadAggregate(instance, field);
            if (nested == null && field.Has("XmlCreate")) {
                nested = Reflection.MakeInto(instance, field);
            }

            if (nested != null) { FillInstance(nested, field.TypeOf(), child); }
            continue;
        }

        if (WalksAsArray(field)) {
            FillArray(instance, field, node.ChildrenNamed(name));
            continue;
        }

        if (!field.IsSimple()) { continue; }

        // An attribute first, then a child element of the name: a document
        // that writes one is read by whichever the type asked for, and one
        // that writes both is read the way the type is marked.
        if (field.Has("XmlAttribute")) {
            // A call result cannot carry a narrowing -- it could answer
            // differently the second time -- so the name is what holds it.
            if (node.Attributes.IndexOf(name) is Some at) {
                FillField(instance, field, node.Attributes.ValueAt(at.Value));
            }
            continue;
        }

        var element = node.Child(name);
        if (element != null) { FillField(instance, field, element.Text); }
    }
}

/// Fills an array field from the children of that name, as far as both go.
///
/// The array is not replaced: its length is the one the constructor chose, for
/// the reason `Standard.Json` gives -- allocating from the document is how a
/// message becomes a memory bill.
void FillArray(byte* instance, Field field, List<XmlNode> found) {
    byte* array = Reflection.ReadArray(instance, field);
    if (array == null) { return; }

    nuint length = Reflection.ArrayLength(array);
    int kind = field.ElementKind();

    for (nuint i = 0u; i < found.Count() && i < length; i++) {
        byte* at = Reflection.ElementAt(array, field, i);

        if (kind == KindClass || kind == KindStruct) {
            byte* nested = Reflection.ReadAggregateAt(at, field);
            if (nested != null) { FillInstance(nested, field.ElementType(), found.At(i)); }
            continue;
        }

        FillElement(at, field, found.At(i).Text);
    }
}

void FillElement(byte* at, Field field, String written) {
    int kind = field.ElementKind();

    if (kind == KindString) { Reflection.WriteTextAt(at, written); return; }

    if (kind == KindBool) {
        Reflection.WriteBoolAt(at, written == "true" || written == "1");
        return;
    }

    if (kind == KindFloat || kind == KindDouble) {
        var parsed = Convert.ToDouble(written);
        if (parsed.Ok) { Reflection.WriteDoubleAt(at, field, parsed.Value); }
        return;
    }

    var whole = Convert.ToLong(written);
    if (whole.Ok) { Reflection.WriteIntegerAt(at, field, whole.Value); }
}

void FillField(byte* instance, Field field, String written) {
    if (field.Kind() == KindString) {
        Reflection.WriteText(instance, field, written);
        return;
    }

    if (field.Kind() == KindBool) {
        // `true` and `1` both, which is what documents in the wild contain.
        Reflection.WriteBool(instance, field, written == "true" || written == "1");
        return;
    }

    if (field.IsFloating()) {
        var parsed = Convert.ToDouble(written);
        if (parsed.Ok) { Reflection.WriteDouble(instance, field, parsed.Value); }
        return;
    }

    if (field.IsInteger()) {
        var parsed = Convert.ToLong(written);
        if (parsed.Ok) { Reflection.WriteInteger(instance, field, parsed.Value); }
        return;
    }
}
