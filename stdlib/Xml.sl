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

/// XML, in the two layers `Standard.Json` has: a document that needs no type,
/// and a mapping onto one that reads a `[Reflect]` type's field tables.
///
/// **What this reads.** Elements, attributes, text, CDATA, comments, the five
/// predefined entities and numeric character references, and an optional
/// declaration or doctype at the front. That is the shape of a configuration
/// file, a document a program exchanges, and most of what XML is used for now.
///
/// **What it does not.** Namespaces are not resolved: `<x:name>` is an element
/// whose name is the whole of `x:name`, and `xmlns` is an ordinary attribute. A
/// DTD is skipped rather than applied, so no entity a document declares for
/// itself is expanded and no default attribute appears. Both are refusals to
/// half-implement something: a program that needs them needs all of them, and
/// what is here says so rather than working until it does not.
module Standard.Xml;

import Standard.Collections;
import Standard.Reflection;
import Standard.Convert;
import Standard.Math;

// ------------------------------------------------------------------- errors

/// Why a document could not be read.
public enum XmlError
{
    /// Nothing went wrong.
    None,

    /// A character that cannot appear here.
    Unexpected,

    /// A `<` with no `>`.
    UnclosedTag,

    /// A quoted attribute value with no closing quote.
    UnclosedText,

    /// An end tag naming a different element than the start tag it closes.
    MismatchedEnd,

    /// The document stopped inside something.
    UnexpectedEnd,

    /// A tag or attribute name that is not one.
    BadName,

    /// An `&` that is not an entity this reads. The five XML entities and
    /// numeric character references are what it reads; a DTD's own are not,
    /// and nor is a reference to a character XML does not allow.
    BadEntity,

    /// Nothing but whitespace and comments -- no root element.
    NoRoot,

    /// A second root element. XML allows exactly one.
    TrailingContent,

    /// Nesting past `MaxDepth`.
    TooDeep,

    /// One element naming an attribute twice.
    DuplicateAttribute,

    /// A type with no field metadata to map onto.
    NotReflected,
}

/// A sentence describing an error, for a message a person will read.
public String Describe(XmlError error)
{
    switch (error)
    {
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
public class XmlAttributes
{
    OrderedDictionary<String, String> _entries;

    /// An empty attribute list.
    public XmlAttributes() => _entries = new OrderedDictionary<String, String>();

    /// How many attributes there are.
    public nuint Count => _entries.Count;

    /// The name at a position, in the order they were written.
    public String NameAt(nuint index) => _entries.GetKeyAt(index);

    /// The value at a position, pairing with `NameAt` at the same index.
    public String ValueAt(nuint index) => _entries.GetValueAt(index);

    /// Appends an attribute without looking for the name first. A parsed
    /// document cannot reach here with a repeat -- that is
    /// `XmlError.DuplicateAttribute` -- so this is for building one.
    public void Add(String name, String value) => _entries.Add(name, value);

    /// Sets the value of a name, adding it if it is new. A replaced name keeps
    /// the position it had.
    public void Set(String name, String value) => _entries.SetValue(name, value);

    /// Where a name is, or `None`.
    public Optional<nuint> IndexOf(String name) => _entries.IndexOf(name);

    /// Whether an attribute of that name is there.
    public bool Has(String name) => _entries.ContainsKey(name);

    /// The value of an attribute, or the fallback when it is not there.
    public String Find(String name, String fallback) => _entries.GetValueOrDefault(name, fallback);

    /// Removes an attribute, answering whether it was there.
    public bool Remove(String name) => _entries.Remove(name);
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
///
/// **Whitespace between elements is formatting.** In an element with child
/// elements, a run of text that is only whitespace in the source is dropped:
/// it is the indentation a person or `WriteIndented` put there. A run with
/// anything else in it is kept whole, as is a CDATA section or a character
/// reference, and an element with no children keeps all of its text.
public class XmlNode
{
    /// The tag name, without any namespace prefix being separated out -- a
    /// prefix arrives as part of the name, since nothing here resolves one.
    public String Name;

    /// The attributes, in the order they were written. Never null; an element
    /// with none has an empty list.
    public XmlAttributes Attributes;

    /// The child elements, in document order. Never null.
    public List<XmlNode> Children;

    /// Every character run inside this element, joined. Where each run sat
    /// relative to the children is not kept -- see the note above.
    public String Text;

    /// An element with that name, no attributes, no children and no text.
    public XmlNode(String name)
    {
        Name = name;
        Attributes = new XmlAttributes();
        Children = new List<XmlNode>();
        Text = "";
    }

    /// The first child of that name, or null.
    public XmlNode? Child(String name)
    {
        for (nuint i = 0u; i < Children.Count; i++)
        {
            var child = Children[i];
            if (child.Name == name)
                return child;
        }
        return null;
    }

    /// Every child of that name, in order.
    public List<XmlNode> ChildrenNamed(String name)
    {
        var found = new List<XmlNode>();
        for (nuint i = 0u; i < Children.Count; i++)
        {
            var child = Children[i];
            if (child.Name == name)
                found.Add(child);
        }
        return found;
    }

    /// The text of the first child of that name, or the fallback.
    public String TextOf(String name, String fallback)
    {
        var child = Child(name);
        if (child == null)
            return fallback;
        return child.Text;
    }

    /// Appends a child element. Nothing checks for a cycle, so do not add a
    /// node to one of its own descendants: writing the tree would not end.
    public void Add(XmlNode child) => Children.Add(child);
}

// ------------------------------------------------------------------ parsing

class Cursor
{
    public String Source;
    public nuint At;
    public nuint Depth;
    public XmlError Failure;

    public Cursor(String source)
    {
        Source = source;
        At = 0u;
        Depth = 0u;
        Failure = XmlError.None;
    }

    public bool Failed => Failure != XmlError.None;

    public void Reject(XmlError why)
    {
        if (Failure == XmlError.None)
            Failure = why;
    }

    public bool AtEnd => At >= Source.ByteLength();

    public byte Peek()
    {
        if (AtEnd)
            return (byte)0;
        return Source.GetByteAt(At);
    }

    public byte PeekAt(nuint ahead)
    {
        if (At + ahead >= Source.ByteLength())
            return (byte)0;
        return Source.GetByteAt(At + ahead);
    }

    public void Skip() => At = At + 1u;

    /// Consumes `word` when it is next, and answers whether it was.
    public bool Take(String word)
    {
        if (At + word.ByteLength() > Source.ByteLength())
            return false;

        for (nuint i = 0u; i < word.ByteLength(); i++)
        {
            if (Source.GetByteAt(At + i) != word.GetByteAt(i))
                return false;
        }

        At = At + word.ByteLength();
        return true;
    }

    /// Moves past `word`, or to the end when it is not there.
    public bool SkipPast(String word)
    {
        while (!AtEnd)
        {
            if (Take(word))
                return true;
            Skip();
        }
        return false;
    }
}

bool IsSpace(byte c)
{
    return c == (byte)' ' || c == (byte)'\t' || c == (byte)'\n' || c == (byte)'\r';
}

/// What may start a name. Deliberately generous: a letter, an underscore or a
/// colon, plus every byte above ASCII, since a name may be any Unicode letter
/// and checking which would mean a table this does not carry.
bool IsNameStart(byte c)
{
    if (c >= (byte)'a' && c <= (byte)'z')
        return true;
    if (c >= (byte)'A' && c <= (byte)'Z')
        return true;
    if (c == (byte)'_' || c == (byte)':')
        return true;
    return c >= (byte)128;
}

bool IsNamePart(byte c)
{
    if (IsNameStart(c))
        return true;
    if (c >= (byte)'0' && c <= (byte)'9')
        return true;
    return c == (byte)'-' || c == (byte)'.';
}

void SkipSpace(Cursor cursor)
{
    while (!cursor.AtEnd && IsSpace(cursor.Source.GetByteAt(cursor.At)))
        cursor.Skip();
}

String ParseName(Cursor cursor)
{
    nuint start = cursor.At;

    if (cursor.AtEnd || !IsNameStart(cursor.Peek()))
    {
        cursor.Reject(XmlError.BadName);
        return "";
    }

    while (!cursor.AtEnd && IsNamePart(cursor.Source.GetByteAt(cursor.At)))
        cursor.Skip();

    return cursor.Source.Substring(start, cursor.At - start);
}

/// Skips a comment or a processing instruction, answering whether it found
/// one. These are what may appear anywhere; a CDATA section produces text and
/// a doctype has one place, so their callers handle them.
bool SkipAside(Cursor cursor)
{
    if (cursor.Take("<!--"))
    {
        SkipComment(cursor);
        return true;
    }

    if (cursor.Take("<?"))
    {
        SkipInstruction(cursor);
        return true;
    }

    return false;
}

/// The rest of a comment, which MUST NOT contain `--` before its end.
void SkipComment(Cursor cursor)
{
    while (!cursor.AtEnd)
    {
        if (cursor.Take("--"))
        {
            if (cursor.Peek() != (byte)'>')
            {
                cursor.Reject(XmlError.Unexpected);
                return;
            }
            cursor.Skip();
            return;
        }
        cursor.Skip();
    }

    cursor.Reject(XmlError.UnclosedTag);
}

/// The rest of a processing instruction. Its target MUST be a name and MUST
/// NOT be `xml` in any case: that is the declaration, which `Parse` reads
/// only at the very start.
void SkipInstruction(Cursor cursor)
{
    var target = ParseName(cursor);
    if (cursor.Failed)
        return;

    if (IsReservedTarget(target))
    {
        cursor.Reject(XmlError.Unexpected);
        return;
    }

    if (!IsSpace(cursor.Peek()) && !(cursor.Peek() == (byte)'?' && cursor.PeekAt(1u) == (byte)'>'))
    {
        cursor.Reject(XmlError.Unexpected);
        return;
    }

    if (!cursor.SkipPast("?>"))
        cursor.Reject(XmlError.UnclosedTag);
}

/// Whether a processing instruction's target spells `xml`, which the
/// specification reserves whatever its case.
bool IsReservedTarget(String target)
{
    if (target.ByteLength() != 3u)
        return false;
    return (target.GetByteAt(0u) | 0x20u) == (byte)'x'
        && (target.GetByteAt(1u) | 0x20u) == (byte)'m'
        && (target.GetByteAt(2u) | 0x20u) == (byte)'l';
}

/// The rest of a doctype, after `<!DOCTYPE`.
///
/// An internal subset is bracketed, and a literal, a comment or a processing
/// instruction inside one may hold a `]` or a `>` of its own, so each is
/// stepped over whole.
void SkipDoctype(Cursor cursor)
{
    nuint depth = 0u;

    while (!cursor.AtEnd)
    {
        if (depth > 0u && cursor.Take("<!--"))
        {
            SkipComment(cursor);
            if (cursor.Failed)
                return;
            continue;
        }

        if (depth > 0u && cursor.Take("<?"))
        {
            SkipInstruction(cursor);
            if (cursor.Failed)
                return;
            continue;
        }

        byte c = cursor.Peek();
        cursor.Skip();

        switch (c)
        {
            case (byte)'"':
            case (byte)'\'':
                while (!cursor.AtEnd && cursor.Peek() != c)
                    cursor.Skip();
                if (cursor.AtEnd)
                {
                    cursor.Reject(XmlError.UnclosedText);
                    return;
                }
                cursor.Skip();
                break;

            case (byte)'[':
                depth++;
                break;

            case (byte)']':
                if (depth > 0u)
                    depth--;
                break;

            case (byte)'>':
                if (depth == 0u)
                    return;
                break;
        }
    }

    cursor.Reject(XmlError.UnclosedTag);
}

/// One element, its attributes and everything inside it.
XmlNode ParseElement(Cursor cursor)
{
    if (cursor.Depth > MaxDepth)
    {
        cursor.Reject(XmlError.TooDeep);
        return new XmlNode("");
    }

    cursor.Skip();                              // past '<'

    var name = ParseName(cursor);
    if (cursor.Failed)
        return new XmlNode("");

    var node = new XmlNode(name);

    // --- attributes
    while (true)
    {
        // Whitespace MUST separate one attribute from what comes before it.
        bool spaced = IsSpace(cursor.Peek());
        SkipSpace(cursor);

        if (cursor.AtEnd)
        {
            cursor.Reject(XmlError.UnclosedTag);
            return node;
        }

        byte c = cursor.Peek();

        if (c == (byte)'>')
        {
            cursor.Skip();
            break;
        }

        if (c == (byte)'/')
        {
            cursor.Skip();
            if (cursor.Peek() != (byte)'>')
            {
                cursor.Reject(XmlError.Unexpected);
                return node;
            }
            cursor.Skip();
            return node;                        // <name ... /> has no content
        }

        if (!spaced)
        {
            cursor.Reject(XmlError.Unexpected);
            return node;
        }

        var key = ParseName(cursor);
        if (cursor.Failed)
            return node;

        SkipSpace(cursor);
        if (cursor.Peek() != (byte)'=')
        {
            cursor.Reject(XmlError.Unexpected);
            return node;
        }
        cursor.Skip();
        SkipSpace(cursor);

        byte quote = cursor.Peek();
        if (quote != (byte)'"' && quote != (byte)'\'')
        {
            cursor.Reject(XmlError.Unexpected);
            return node;
        }
        cursor.Skip();

        var value = ParseUntil(cursor, quote);
        if (cursor.Failed)
            return node;

        // XML forbids a repeated attribute on one element, and a document with
        // one means something its writer did not: which of the two is the
        // value is not a question with an answer.
        if (node.Attributes.Has(key))
        {
            cursor.Reject(XmlError.DuplicateAttribute);
            return node;
        }

        node.Attributes.Add(key, value);
    }

    // --- content
    cursor.Depth++;

    // Every run of text, and every run but the ones that are only whitespace
    // in the source. Which one the node keeps depends on whether it turns out
    // to have children -- see the note on XmlNode.
    var text = new StringBuilder();
    var kept = new StringBuilder();

    while (true)
    {
        if (cursor.AtEnd)
        {
            cursor.Reject(XmlError.UnexpectedEnd);
            break;
        }

        if (cursor.Peek() == (byte)'<')
        {
            if (cursor.PeekAt(1u) == (byte)'/')
            {
                cursor.Skip();
                cursor.Skip();

                var closing = ParseName(cursor);
                if (cursor.Failed)
                    break;

                if (closing != node.Name)
                {
                    cursor.Reject(XmlError.MismatchedEnd);
                    break;
                }

                SkipSpace(cursor);
                if (cursor.Peek() != (byte)'>')
                {
                    cursor.Reject(XmlError.Unexpected);
                    break;
                }
                cursor.Skip();
                break;
            }

            if (cursor.Take("<![CDATA["))
            {
                nuint start = cursor.At;

                if (!cursor.SkipPast("]]>"))
                {
                    cursor.Reject(XmlError.UnclosedTag);
                    break;
                }

                // Everything between, with no entities expanded, which is what
                // a CDATA section is for.
                var section = cursor.Source.Substring(start, cursor.At - start - 3u);
                text.Append(section);
                kept.Append(section);
                continue;
            }

            if (SkipAside(cursor))
            {
                if (cursor.Failed)
                    break;
                continue;
            }

            var child = ParseElement(cursor);
            if (cursor.Failed)
                break;

            node.Add(child);
            continue;
        }

        nuint from = cursor.At;
        var run = ParseUntil(cursor, (byte)'<');
        if (cursor.Failed)
            break;

        text.Append(run);
        if (!IsBlankSource(cursor.Source, from, cursor.At))
            kept.Append(run);
    }

    cursor.Depth--;
    node.Text = node.Children.Count > 0u ? kept.ToText() : text.ToText();
    return node;
}

/// Whether the source between two offsets is only whitespace.
bool IsBlankSource(String source, nuint from, nuint to)
{
    for (nuint i = from; i < to; i++)
    {
        if (!IsSpace(source.GetByteAt(i)))
            return false;
    }
    return true;
}

/// Reads text up to `stop`, expanding entities. The stop character is consumed
/// when it is a quote and left when it is `<`, because the caller needs to see
/// which tag follows.
///
/// Inside a quoted value `<` is refused, and a literal tab or line end is read
/// as a space (§3.3.3); a character reference keeps its character. In content
/// `]]>` is refused, since only a CDATA section may end with it.
String ParseUntil(Cursor cursor, byte stop)
{
    bool quoted = stop != (byte)'<';
    var text = new StringBuilder();
    nuint run = cursor.At;

    while (true)
    {
        if (cursor.AtEnd)
        {
            // Running out inside a quoted value is an error; running out of
            // content is the caller's to notice.
            if (quoted)
                cursor.Reject(XmlError.UnclosedText);
            break;
        }

        byte c = cursor.Source.GetByteAt(cursor.At);

        if (c == stop)
        {
            if (cursor.At > run)
            {
                text.Append(cursor.Source.Substring(run, cursor.At - run));
            }
            if (quoted)
                cursor.Skip();
            break;
        }

        if (quoted && c == (byte)'<')
        {
            cursor.Reject(XmlError.Unexpected);
            break;
        }

        if (quoted && IsSpace(c) && c != (byte)' ')
        {
            if (cursor.At > run)
            {
                text.Append(cursor.Source.Substring(run, cursor.At - run));
            }
            text.Append(" ");
            cursor.Skip();
            run = cursor.At;
            continue;
        }

        if (!quoted && c == (byte)']' && cursor.PeekAt(1u) == (byte)']' && cursor.PeekAt(2u) == (byte)'>')
        {
            cursor.Reject(XmlError.Unexpected);
            break;
        }

        if (c != (byte)'&')
        {
            cursor.Skip();
            continue;
        }

        if (cursor.At > run)
        {
            text.Append(cursor.Source.Substring(run, cursor.At - run));
        }

        text.Append(ParseEntity(cursor));
        if (cursor.Failed)
            break;

        run = cursor.At;
    }

    return text.ToText();
}

/// One `&...;`: the five XML predefines, or a numeric character reference.
String ParseEntity(Cursor cursor)
{
    if (cursor.Take("&amp;"))
        return "&";
    if (cursor.Take("&lt;"))
        return "<";
    if (cursor.Take("&gt;"))
        return ">";
    if (cursor.Take("&quot;"))
        return "\"";
    if (cursor.Take("&apos;"))
        return "'";

    // The hexadecimal form is spelled with a lower-case `x` only.
    if (cursor.Take("&#x"))
        return ParseCharacterReference(cursor, 16u);
    if (cursor.Take("&#"))
        return ParseCharacterReference(cursor, 10u);

    // A document's own entity would have been declared in a DTD, and the DTD
    // was skipped -- so this is honest about not knowing rather than dropping
    // the reference silently.
    cursor.Reject(XmlError.BadEntity);
    return "";
}

String ParseCharacterReference(Cursor cursor, uint radix)
{
    uint value = 0u;
    nuint digits = 0u;

    while (!cursor.AtEnd)
    {
        byte c = cursor.Peek();
        uint digit = 0u;

        if (c >= (byte)'0' && c <= (byte)'9')
        {
            digit = (uint)(c - (byte)'0');
        }
        else if (radix == 16u && c >= (byte)'a' && c <= (byte)'f')
        {
            digit = (uint)(c - (byte)'a' + 10);
        }
        else if (radix == 16u && c >= (byte)'A' && c <= (byte)'F')
        {
            digit = (uint)(c - (byte)'A' + 10);
        }
        else
        {
            break;
        }

        // Leading zeros are allowed however many there are, so the digits
        // are not counted; a value past the last code point stops growing,
        // which keeps it from wrapping back into range.
        if (value <= 0x10FFFFu)
            value = value * radix + digit;
        digits++;
        cursor.Skip();
    }

    if (digits == 0u || cursor.Peek() != (byte)';')
    {
        cursor.Reject(XmlError.BadEntity);
        return "";
    }
    cursor.Skip();

    // A reference MUST name a character XML allows, which a reference is not
    // a way around.
    if (!IsXmlChar(value))
    {
        cursor.Reject(XmlError.BadEntity);
        return "";
    }

    return Text.FromChar((char32)value);
}

/// Whether a code point is one XML 1.0 allows in a document at all (§2.2).
bool IsXmlChar(uint value)
{
    if (value < 0x20u)
        return value == 0x9u || value == 0xAu || value == 0xDu;
    if (value <= 0xD7FFu)
        return true;
    if (value >= 0xE000u && value <= 0xFFFDu)
        return true;
    return value >= 0x10000u && value <= 0x10FFFFu;
}

/// Whether the source holds a control character other than tab, LF and CR,
/// none of which XML 1.0 allows even by reference.
bool ContainsForbiddenControl(String source)
{
    for (nuint i = 0u; i < source.ByteLength(); i++)
    {
        byte c = source.GetByteAt(i);
        if (c < 0x20u && c != (byte)'\t' && c != (byte)'\n' && c != (byte)'\r')
            return true;
    }
    return false;
}

/// The source with every CR LF pair and every lone CR made LF. A source with
/// no CR in it is answered as it is.
String NormalizeLineEnds(String source)
{
    var text = new StringBuilder();
    nuint run = 0u;
    nuint size = source.ByteLength();

    for (nuint i = 0u; i < size; i++)
    {
        if (source.GetByteAt(i) != (byte)'\r')
            continue;

        if (i > run)
            text.Append(source.Substring(run, i - run));
        text.Append("\n");

        if (i + 1u < size && source.GetByteAt(i + 1u) == (byte)'\n')
            i++;
        run = i + 1u;
    }

    if (run == 0u)
        return source;
    if (size > run)
        text.Append(source.Substring(run, size - run));
    return text.ToText();
}

/// Steps over a UTF-8 byte order mark at the very start, which Appendix F
/// allows in front of the declaration.
void SkipByteOrderMark(Cursor cursor)
{
    if (cursor.Source.ByteLength() < 3u)
        return;
    if (cursor.Source.GetByteAt(0u) == 0xEFu
     && cursor.Source.GetByteAt(1u) == 0xBBu
     && cursor.Source.GetByteAt(2u) == 0xBFu)
    {
        cursor.At = 3u;
    }
}

/// Reads a whole document and answers with its root element.
///
/// Line ends are normalized first (§2.11): a CR LF pair or a lone CR is read
/// as LF everywhere, CDATA included. A control character XML does not allow
/// is refused wherever it is. A UTF-8 byte order mark at the start is skipped.
public Result<XmlNode, XmlError> Parse(String source)
{
    if (ContainsForbiddenControl(source))
        return Fail(XmlError.Unexpected);

    var cursor = new Cursor(NormalizeLineEnds(source));
    SkipByteOrderMark(cursor);

    // The declaration, which MUST be the very first thing when it is there.
    // Anything else spelled `<?xml` is an instruction, read as one below.
    if (cursor.Take("<?xml"))
    {
        if (!IsSpace(cursor.Peek()))
        {
            cursor.At = cursor.At - 5u;
        }
        else if (!cursor.SkipPast("?>"))
        {
            return Fail(XmlError.UnclosedTag);
        }
    }

    // Anything else before the root: comments, instructions, one doctype.
    bool doctype = false;
    while (true)
    {
        SkipSpace(cursor);
        if (cursor.AtEnd)
            return Fail(XmlError.NoRoot);

        if (cursor.Peek() != (byte)'<')
            return Fail(XmlError.Unexpected);

        if (cursor.Take("<!DOCTYPE"))
        {
            if (doctype)
                return Fail(XmlError.Unexpected);
            doctype = true;

            SkipDoctype(cursor);
            if (cursor.Failed)
                return Fail(cursor.Failure);
            continue;
        }

        if (!SkipAside(cursor))
            break;
        if (cursor.Failed)
            return Fail(cursor.Failure);
    }

    if (cursor.PeekAt(1u) == (byte)'/')
        return Fail(XmlError.Unexpected);

    var root = ParseElement(cursor);
    if (cursor.Failed)
        return Fail(cursor.Failure);

    // And anything after it, which may only be more of the same.
    while (true)
    {
        SkipSpace(cursor);
        if (cursor.AtEnd)
            break;

        if (cursor.Peek() != (byte)'<')
            return Fail(XmlError.TrailingContent);
        if (!SkipAside(cursor))
            return Fail(XmlError.TrailingContent);
        if (cursor.Failed)
            return Fail(cursor.Failure);
    }

    return Ok(root);
}

// ------------------------------------------------------------------ writing

/// The element as text, on one line.
public String Write(XmlNode node)
{
    var text = new StringBuilder();
    WriteInto(text, node, 0u, false);
    return text.ToText();
}

/// The same, indented two spaces a level. An element with text in it is still
/// written on one line, children and all, because the whitespace an indent
/// adds would become part of that text when it was read back. The indentation
/// between the children of any other element is dropped by the reader -- see
/// the note on XmlNode -- so writing what was read back gives the same text.
public String WriteIndented(XmlNode node)
{
    var text = new StringBuilder();
    WriteInto(text, node, 0u, true);
    return text.ToText();
}

/// The declaration and the element under it, which is what a whole file wants.
public String WriteDocument(XmlNode node)
{
    return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" + WriteIndented(node);
}

void WriteInto(StringBuilder text, XmlNode node, nuint depth, bool pretty)
{
    if (pretty)
    {
        for (nuint i = 0u; i < depth; i++)
            text.Append("  ");
    }

    text.Append("<");
    text.Append(node.Name);

    for (nuint i = 0u; i < node.Attributes.Count; i++)
    {
        text.Append(" ");
        text.Append(node.Attributes.NameAt(i));
        text.Append("=\"");
        WriteEscaped(text, node.Attributes.ValueAt(i), true);
        text.Append("\"");
    }

    bool empty = node.Children.Count == 0u && node.Text.ByteLength() == 0u;
    if (empty)
    {
        text.Append("/>");
        return;
    }

    text.Append(">");

    // Text first, then the children, which is the order this model can
    // represent -- see the note on XmlNode.
    WriteEscaped(text, node.Text, false);

    // Indentation beside text would become part of it when read back.
    bool indent = pretty && node.Text.ByteLength() == 0u;

    for (nuint i = 0u; i < node.Children.Count; i++)
    {
        if (indent)
            text.Append("\n");
        WriteInto(text, node.Children[i], depth + 1u, indent);
    }

    if (indent && node.Children.Count > 0u)
    {
        text.Append("\n");
        for (nuint i = 0u; i < depth; i++)
            text.Append("  ");
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
void WriteEscaped(StringBuilder text, String value, bool inAttribute)
{
    nuint run = 0u;

    for (nuint i = 0u; i < value.ByteLength(); i++)
    {
        byte c = value.GetByteAt(i);
        String escaped = "";

        if (c == (byte)'&')
        {
            escaped = "&amp;";
        }
        else if (c == (byte)'<')
        {
            escaped = "&lt;";
        }
        else if (c == (byte)'>')
        {
            escaped = "&gt;";
        }
        else if (c == (byte)'"' && inAttribute)
        {
            escaped = "&quot;";
        }
        else if (c == (byte)'\n' && inAttribute)
        {
            escaped = "&#10;";
        }
        else if (c == (byte)'\t' && inAttribute)
        {
            escaped = "&#9;";
        }
        else if (c == (byte)'\r')
        {
            escaped = "&#13;";
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
public XmlNode ToNode<T>(T value, String name)
{
    return NodeOfInstance((byte*)value, typeof(T), name);
}

/// The element as text.
public String Serialize<T>(T value, String name) => Write(ToNode(value, name));

/// The same, with a declaration and indentation.
public String SerializeDocument<T>(T value, String name)
{
    return WriteDocument(ToNode(value, name));
}

XmlNode NodeOfInstance(byte* instance, Type type, String name)
{
    var node = new XmlNode(name);
    if (instance == null)
        return node;

    var text = new StringBuilder();

    for (nuint i = 0u; i < type.FieldCount; i++)
    {
        var field = type.FieldAt(i);
        if (field.Has("XmlIgnore"))
            continue;

        var fieldName = NameOf(field);

        if (field.IsWalkable)
        {
            byte* nested = Reflection.ReadAggregate(instance, field);
            if (nested == null)
                continue;

            node.Add(NodeOfInstance(nested, field.TypeOf(), fieldName));
            continue;
        }

        // An array is repeated children of one name, which is how XML says a
        // sequence. A `List<T>` still cannot be walked -- its own fields are
        // its private storage -- and is left out rather than misstated.
        if (WalksAsArray(field))
        {
            AddArray(node, instance, field, fieldName);
            continue;
        }

        if (!field.IsSimple)
            continue;

        var written = TextOfField(instance, field);

        if (field.Has("XmlAttribute"))
        {
            node.Attributes.Add(fieldName, written);
            continue;
        }

        var child = new XmlNode(fieldName);
        child.Text = written;
        node.Add(child);
    }

    return node;
}

String NameOf(Field field)
{
    if (field.Has("XmlName"))
        return field.Get("XmlName").AsText(0u);
    return field.Name;
}

/// An array whose elements this can write and read back.
bool WalksAsArray(Field field)
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

    if (kind == KindClass || kind == KindStruct)
    {
        var inner = field.ElementType;
        return inner.Exists && inner.Has("Reflect");
    }

    return false;
}

/// One child element per element of the array, all of the same name.
///
/// A null array writes nothing at all, which reads back as an array left
/// alone -- the same answer an absent element gives, and the right one, since
/// an object without the array is not an object with an empty one.
void AddArray(XmlNode node, byte* instance, Field field, String name)
{
    byte* array = Reflection.ReadArray(instance, field);
    if (array == null)
        return;

    int kind = field.ElementKind;

    for (nuint i = 0u; i < Reflection.ArrayLength(array); i++)
    {
        byte* at = Reflection.ElementAt(array, field, i);

        if (kind == KindClass || kind == KindStruct)
        {
            byte* nested = Reflection.ReadAggregateAt(at, field);
            if (nested == null)
                continue;
            node.Add(NodeOfInstance(nested, field.ElementType, name));
            continue;
        }

        var child = new XmlNode(name);
        child.Text = TextOfElement(at, field);
        node.Add(child);
    }
}

String TextOfElement(byte* at, Field field)
{
    int kind = field.ElementKind;

    if (kind == KindString)
        return Reflection.ReadTextAt(at);
    if (kind == KindBool)
        return Text.FromBool(Reflection.ReadBoolAt(at));
    if (kind == KindFloat || kind == KindDouble)
    {
        return FormatXmlDouble(Reflection.ReadDoubleAt(at, field));
    }
    return Text.FromInteger(Reflection.ReadIntegerAt(at, field));
}

String TextOfField(byte* instance, Field field)
{
    if (field.Kind == KindString)
        return Reflection.ReadText(instance, field);
    if (field.Kind == KindBool)
        return Text.FromBool(Reflection.ReadBool(instance, field));
    if (field.IsFloating)
        return FormatXmlDouble(Reflection.ReadDouble(instance, field));
    if (field.IsInteger)
        return Text.FromInteger(Reflection.ReadInteger(instance, field));
    return "";
}

/// Fills an object's fields from an element.
///
/// The object is the program's, for the reason `Json.Populate` takes one: its
/// constructor has run, so a field the document does not mention keeps the
/// value the type promised rather than a zero.
public XmlError Populate<T>(T value, String source)
{
    var parsed = Parse(source);
    if (!parsed.Ok)
        return parsed.Error;

    return PopulateFrom(value, parsed.Value);
}

/// The same, from an element already parsed.
public XmlError PopulateFrom<T>(T value, XmlNode node)
{
    var type = typeof(T);
    if (type.FieldCount == 0u)
        return XmlError.NotReflected;

    FillInstance((byte*)value, type, node);
    return XmlError.None;
}

void FillInstance(byte* instance, Type type, XmlNode node)
{
    for (nuint i = 0u; i < type.FieldCount; i++)
    {
        var field = type.FieldAt(i);
        if (field.Has("XmlIgnore"))
            continue;

        var name = NameOf(field);

        if (field.IsWalkable)
        {
            var child = node.Child(name);
            if (child == null)
                continue;

            byte* nested = Reflection.ReadAggregate(instance, field);
            if (nested == null && field.Has("XmlCreate"))
            {
                nested = Reflection.MakeInto(instance, field);
            }

            if (nested != null)
                FillInstance(nested, field.TypeOf(), child);
            continue;
        }

        if (WalksAsArray(field))
        {
            FillArray(instance, field, node.ChildrenNamed(name));
            continue;
        }

        if (!field.IsSimple)
            continue;

        // An attribute first, then a child element of the name: a document
        // that writes one is read by whichever the type asked for, and one
        // that writes both is read the way the type is marked.
        if (field.Has("XmlAttribute"))
        {
            // A call result cannot carry a narrowing -- it could answer
            // differently the second time -- so the name is what holds it.
            if (node.Attributes.IndexOf(name) is Some at)
            {
                FillField(instance, field, node.Attributes.ValueAt(at.Value));
            }
            continue;
        }

        var element = node.Child(name);
        if (element != null)
            FillField(instance, field, element.Text);
    }
}

/// Fills an array field from the children of that name, as far as both go.
///
/// The array is not replaced: its length is the one the constructor chose, for
/// the reason `Standard.Json` gives -- allocating from the document is how a
/// message becomes a memory bill.
void FillArray(byte* instance, Field field, List<XmlNode> found)
{
    byte* array = Reflection.ReadArray(instance, field);
    if (array == null)
        return;

    nuint length = Reflection.ArrayLength(array);
    int kind = field.ElementKind;

    for (nuint i = 0u; i < found.Count && i < length; i++)
    {
        byte* at = Reflection.ElementAt(array, field, i);

        if (kind == KindClass || kind == KindStruct)
        {
            byte* nested = Reflection.ReadAggregateAt(at, field);
            if (nested != null)
                FillInstance(nested, field.ElementType, found[i]);
            continue;
        }

        FillElement(at, field, found[i].Text);
    }
}

void FillElement(byte* at, Field field, String written)
{
    int kind = field.ElementKind;

    if (kind == KindString)
    {
        Reflection.WriteTextAt(at, written);
        return;
    }

    // Anything but a String is read without the whitespace around it, which
    // is where an indented document puts its line ends.
    var value = written.Trim();

    if (kind == KindBool)
    {
        Reflection.WriteBoolAt(at, IsXmlTrue(value));
        return;
    }

    if (kind == KindFloat || kind == KindDouble)
    {
        if (ParseXmlDouble(value) is Some parsed)
            Reflection.WriteDoubleAt(at, field, parsed.Value);
        return;
    }

    var whole = Convert.ToLong(value);
    if (whole.Ok)
        Reflection.WriteIntegerAt(at, field, whole.Value);
}

void FillField(byte* instance, Field field, String written)
{
    if (field.Kind == KindString)
    {
        Reflection.WriteText(instance, field, written);
        return;
    }

    // As in FillElement: a value that is not text is read trimmed.
    var value = written.Trim();

    if (field.Kind == KindBool)
    {
        Reflection.WriteBool(instance, field, IsXmlTrue(value));
        return;
    }

    if (field.IsFloating)
    {
        if (ParseXmlDouble(value) is Some parsed)
            Reflection.WriteDouble(instance, field, parsed.Value);
        return;
    }

    if (field.IsInteger)
    {
        var parsed = Convert.ToLong(value);
        if (parsed.Ok)
            Reflection.WriteInteger(instance, field, parsed.Value);
        return;
    }
}

/// `true` and `1` both, which is what documents in the wild contain.
bool IsXmlTrue(String value) => value == "true" || value == "1";

/// A double as text, with XML Schema's spellings for the three values that
/// have no digits: `INF`, `-INF` and `NaN`. `ParseXmlDouble` reads them back.
String FormatXmlDouble(double value)
{
    if (Math.IsNaN(value))
        return "NaN";
    if (Math.IsInfinite(value))
        return value > 0.0 ? "INF" : "-INF";
    return Text.FromDouble(value);
}

/// A double from text: a finite numeral, or one of the spellings
/// `FormatXmlDouble` writes. A numeral too large for a double is refused
/// rather than read as an infinity nobody wrote.
Optional<double> ParseXmlDouble(String value)
{
    switch (value)
    {
        case "INF": return Some(1.0 / 0.0);
        case "-INF": return Some(-1.0 / 0.0);
        case "NaN": return Some(0.0 / 0.0);
    }

    var parsed = Convert.ToDouble(value);
    if (!parsed.Ok || !Math.IsFinite(parsed.Value))
        return None;
    return Some(parsed.Value);
}
