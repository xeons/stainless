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

// A watch expression: `a`, `a.b.c`, `a[3]`, `a[i]`, `*p`, and a number.
//
// **It is this small on purpose.** `fppascalparser.pas` is 263 KB because
// Lazarus promises that a watch is a whole Pascal expression; the promise here
// is much smaller and is kept. No arithmetic, no casts, no parentheses, and in
// particular **never a call into the debuggee**: calling into an ARC'd runtime
// from a process stopped inside the allocator's lock deadlocks the thing being
// inspected, which is where `fpdebug`'s hardest bugs live.
//
// **Parsing and evaluating are separate**, which is worth the extra type: a
// malformed expression is then a question that can be asked with no process,
// no binary and no frame -- so the self test covers the grammar, and the IDE
// can refuse a watch as it is typed rather than after the next stop.
//
// **`ide/src/Lang/Lexer.sl` is deliberately not reused.** It would make this
// engine unbuildable without the IDE's editor sources, and it is built for
// painting: a line at a time, stateful across lines, emitting whitespace and
// comment tokens a parser then has to filter. Eight token kinds is sixty
// lines. If a second consumer ever appears the answer is to lift `Ide.Lang`
// into a tree of its own, which is a refactor with its own justification.
//
// One limit worth stating rather than discovering: postfix binds tighter than
// `*`, as it does in C, so `*p.next` follows `p.next` and there is no way to
// write the other grouping. Parentheses are what that would need.
module Debugger;

import Standard.Collections;
import Standard.Text;

// ===================================================================== tokens

/// What a run of bytes in a watch expression is.
enum WatchKind
{
    /// The end of the expression. Always the last token, so a reader never has
    /// to check its position before looking at what is under it.
    End,
    Name,
    Number,
    Dot,
    Open,
    Close,
    Star,
    /// A byte that means nothing here, carried so the reader can name it.
    Bad,
}

/// One token, with whichever of the two payloads its kind uses.
class WatchWord
{
    public WatchKind Kind;
    public String Text;
    public ulong Number;

    public WatchWord(WatchKind kind, String text, ulong number)
    {
        Kind = kind;
        Text = text;
        Number = number;
    }
}

/// The tokens of one expression, and how far through them the parser is.
class WatchWords
{
    public List<WatchWord> Items;
    public nuint At;

    public WatchWords(List<WatchWord> items)
    {
        Items = items;
        At = 0u;
    }

    public WatchWord Here => Items[At];

    public void Step() => At++;
}

/// Cuts an expression into tokens.
///
/// A byte that means nothing here becomes one `Bad` token carrying itself,
/// rather than stopping the scan: naming what was not understood is most of
/// what a person wants back from a refused expression.
List<WatchWord> ScanWatch(String text)
{
    var words = new List<WatchWord>();
    nuint size = text.ByteLength();
    nuint at = 0u;

    while (at < size)
    {
        byte here = text.ByteAt(at);

        if (here == (byte)' ' || here == (byte)'\t')
        {
            at++;
            continue;
        }

        if (IsWatchNameStart(here))
        {
            nuint from = at;
            while (at < size && IsWatchNameByte(text.ByteAt(at)))
                at++;
            words.Add(new WatchWord(WatchKind.Name,
                                    text.Substring(from, at - from), 0u));
            continue;
        }

        if (IsWatchDigit(here))
        {
            nuint from = at;
            bool hex = here == (byte)'0' && at + 1u < size
                    && (text.ByteAt(at + 1u) == (byte)'x'
                        || text.ByteAt(at + 1u) == (byte)'X');
            at = at + (hex ? 2u : 1u);
            while (at < size && (hex ? IsWatchHexDigit(text.ByteAt(at))
                                     : IsWatchDigit(text.ByteAt(at))))
                at++;
            words.Add(new WatchWord(WatchKind.Number, "",
                                    ParseWatchNumber(text.Substring(from,
                                                                    at - from))));
            continue;
        }

        var kind = WatchKindOfByte(here);
        words.Add(new WatchWord(kind, OneByteText(here), 0u));
        at++;
    }

    words.Add(new WatchWord(WatchKind.End, "", 0u));
    return words;
}

WatchKind WatchKindOfByte(byte here)
{
    switch (here)
    {
        case (byte)'.': return WatchKind.Dot;
        case (byte)'[': return WatchKind.Open;
        case (byte)']': return WatchKind.Close;
        case (byte)'*': return WatchKind.Star;
        default: return WatchKind.Bad;
    }
}

bool IsWatchDigit(byte here) => here >= (byte)'0' && here <= (byte)'9';

bool IsWatchHexDigit(byte here)
    => IsWatchDigit(here)
    || (here >= (byte)'a' && here <= (byte)'f')
    || (here >= (byte)'A' && here <= (byte)'F');

bool IsWatchNameStart(byte here)
    => (here >= (byte)'a' && here <= (byte)'z')
    || (here >= (byte)'A' && here <= (byte)'Z')
    || here == (byte)'_';

bool IsWatchNameByte(byte here) => IsWatchNameStart(here) || IsWatchDigit(here);

String OneByteText(byte here)
{
    var made = new StringBuilder();
    made.AppendByte(here);
    return made.ToText();
}

/// Decimal, or hexadecimal after `0x`. The scanner has already decided which
/// bytes belong, so nothing here can fail.
ulong ParseWatchNumber(String text)
{
    nuint size = text.ByteLength();
    if (size > 2u && text.ByteAt(0u) == (byte)'0'
        && (text.ByteAt(1u) == (byte)'x' || text.ByteAt(1u) == (byte)'X'))
    {
        ulong value = 0u;
        for (nuint i = 2u; i < size; i++)
            value = value * 16u + WatchHexValue(text.ByteAt(i));
        return value;
    }

    ulong plain = 0u;
    for (nuint i = 0u; i < size; i++)
        plain = plain * 10u + (ulong)(text.ByteAt(i) - (byte)'0');
    return plain;
}

ulong WatchHexValue(byte here)
{
    if (IsWatchDigit(here))
        return (ulong)(here - (byte)'0');
    if (here >= (byte)'a' && here <= (byte)'f')
        return (ulong)(here - (byte)'a') + 10u;
    return (ulong)(here - (byte)'A') + 10u;
}

// ===================================================================== syntax

/// One step away from the root: a field, or an index.
public class WatchStep
{
    /// True for `.name`, false for `[...]`.
    public bool IsField;

    public String Field;

    /// The index, which is an expression of its own so that `a[i]` works.
    public WatchExpression? Index;

    public WatchStep(String field)
    {
        IsField = true;
        Field = field;
        Index = null;
    }

    public WatchStep(WatchExpression index)
    {
        IsField = false;
        Field = "";
        Index = index;
    }
}

/// A parsed watch expression: some stars, a root, and a chain of steps.
///
/// Flat rather than a tree of nodes because the grammar is flat. The steps are
/// applied to the root left to right and the stars afterwards, which is what
/// makes postfix bind tighter than `*`.
public class WatchExpression
{
    /// How many `*` are in front of it.
    public int Stars;

    /// The variable it starts from, or "" when it starts from a number.
    public String Root;

    public bool IsLiteral;
    public ulong Literal;

    public List<WatchStep> Steps;

    /// Why it is not an expression. Empty when it is one.
    public String Problem;

    public WatchExpression()
    {
        Stars = 0;
        Root = "";
        IsLiteral = false;
        Literal = 0u;
        Steps = new List<WatchStep>();
        Problem = "";
    }
}

/// Reads one expression, whole.
///
/// Needs no process, no binary and no frame, which is the point of it being
/// its own pass: a watch can be refused where it is typed.
public WatchExpression ParseWatch(String text)
{
    var words = new WatchWords(ScanWatch(text));
    var parsed = ParseWatchFrom(words);

    // What is left over says which refusal this is: a byte that means nothing
    // here is named, and anything else is a second expression. "Invalid
    // expression" would tell the person who typed it nothing about which half.
    if (parsed.Problem.ByteLength() == 0u && words.Here.Kind != WatchKind.End)
    {
        parsed.Problem = words.Here.Kind == WatchKind.Bad
                       ? "'" + words.Here.Text
                         + "' means nothing in a watch expression"
                       : "there is more here than one expression";
    }

    return parsed;
}

WatchExpression ParseWatchFrom(WatchWords words)
{
    var made = new WatchExpression();

    while (words.Here.Kind == WatchKind.Star)
    {
        made.Stars++;
        words.Step();
    }

    switch (words.Here.Kind)
    {
        case WatchKind.Number:
            made.IsLiteral = true;
            made.Literal = words.Here.Number;
            words.Step();
            break;

        case WatchKind.Name:
            made.Root = words.Here.Text;
            words.Step();
            break;

        case WatchKind.Bad:
            made.Problem = "'" + words.Here.Text
                         + "' means nothing in a watch expression";
            return made;

        case WatchKind.End:
            made.Problem = "there is nothing here to watch";
            return made;

        default:
            made.Problem = "a name or a number was expected here";
            return made;
    }

    return ParseWatchSteps(words, made);
}

WatchExpression ParseWatchSteps(WatchWords words, WatchExpression made)
{
    while (true)
    {
        if (words.Here.Kind == WatchKind.Dot)
        {
            words.Step();
            if (words.Here.Kind != WatchKind.Name)
            {
                made.Problem = "a '.' must be followed by a field name";
                return made;
            }
            made.Steps.Add(new WatchStep(words.Here.Text));
            words.Step();
            continue;
        }

        if (words.Here.Kind == WatchKind.Open)
        {
            words.Step();
            var index = ParseWatchFrom(words);
            if (index.Problem.ByteLength() != 0u)
            {
                made.Problem = index.Problem;
                return made;
            }
            if (words.Here.Kind != WatchKind.Close)
            {
                made.Problem = "this '[' has no ']'";
                return made;
            }
            words.Step();
            made.Steps.Add(new WatchStep(index));
            continue;
        }

        return made;
    }
}

// ================================================================== the value

/// Where a watch expression's answer lives.
///
/// The unit is carried with the type because a DWARF reference form resolves
/// through the unit that used it, so a type entry means nothing without one.
class Place
{
    public Unit InUnit;
    public DescribedType Type;

    /// Where it is in the target. A literal is nowhere, and says so.
    public nuint Address;
    public bool Addressed;

    /// The value itself, for a literal.
    public ulong Number;

    public Place(Unit unit, DescribedType type, nuint address)
    {
        InUnit = unit;
        Type = type;
        Address = address;
        Addressed = true;
        Number = 0u;
    }
}

/// A member, and how far into the structure it sits -- which is not its own
/// offset when it was reached through a base class.
class WatchMember
{
    public Die Entry;
    public nuint Offset;

    public WatchMember(Die entry, nuint offset)
    {
        Entry = entry;
        Offset = offset;
    }
}

/// An object whose elements follow a length: an array, a `String`, a
/// `Utf16String`.
class WatchArray
{
    public nuint LengthOffset;
    public nuint ElementsOffset;
    public DescribedType Element;

    public WatchArray(nuint lengthOffset, nuint elementsOffset,
                      DescribedType element)
    {
        LengthOffset = lengthOffset;
        ElementsOffset = elementsOffset;
        Element = element;
    }
}

/// One parsed expression, walked against one stopped frame.
class WatchReader
{
    Engine _engine;
    ITarget _target;
    Unit _unit;
    Die _owner;
    Registers _frame;

    /// Why there is no answer. Empty while there still might be one.
    public String Problem;

    public WatchReader(Engine engine, ITarget target, Unit unit, Die owner,
                       Registers frame)
    {
        _engine = engine;
        _target = target;
        _unit = unit;
        _owner = owner;
        _frame = frame;
        Problem = "";
    }

    /// The first refusal wins. A later one describes the wreckage of the first.
    void Refuse(String why)
    {
        if (Problem.ByteLength() == 0u)
            Problem = why;
    }

    public Place? Read(WatchExpression expression)
    {
        Place? value = expression.IsLiteral
                     ? LiteralPlace(expression.Literal)
                     : VariableNamed(expression.Root);

        for (nuint i = 0u; i < expression.Steps.Count && value != null; i++)
        {
            var step = expression.Steps[i];
            value = step.IsField
                  ? MemberOf((Place)value, step.Field)
                  : ElementOf((Place)value, (WatchExpression)step.Index);
        }

        for (int star = 0; star < expression.Stars && value != null; star++)
            value = Dereferenced((Place)value);

        return value;
    }

    Place LiteralPlace(ulong number)
    {
        var described = new DescribedType();
        described.Tag = TagBaseType;
        described.Name = "nuint";
        described.Size = 8u;
        described.Encoding = EncodingUnsigned;

        var made = new Place(_unit, described, 0u);
        made.Addressed = false;
        made.Number = number;
        return made;
    }

    /// The variable a name means: a parameter or local of this frame first,
    /// then a static of the same unit.
    ///
    /// **The unit's statics and not the program's.** Two units may each have a
    /// static of one name, and a debugger that picks between them is a debugger
    /// that picks wrong half the time.
    Place? VariableNamed(String name)
    {
        var locals = ChildrenOf(_unit, _owner);
        for (nuint i = 0u; i < locals.Count; i++)
        {
            var one = locals[i];
            if (one.Tag != TagFormalParameter && one.Tag != TagVariable)
                continue;
            if (one.Name == name)
                return Located(one);
        }

        var root = _unit.Root;
        if (root != null)
        {
            var statics = ChildrenOf(_unit, (Die)root);
            for (nuint i = 0u; i < statics.Count; i++)
            {
                var one = statics[i];
                if (one.Tag == TagVariable && one.Name == name)
                    return Located(one);
            }
        }

        Refuse("there is no '" + name + "' in scope here");
        return null;
    }

    Place? Located(Die variable)
    {
        nuint at = 0u;
        if (!LocationOf(_engine, _unit, variable, _owner, _frame, &at))
        {
            Refuse("'" + variable.Name + "' has no location a debugger can read");
            return null;
        }
        return new Place(_unit, DescribeType(_unit, variable), at);
    }

    /// A field of a structure, or of the object a reference points at.
    ///
    /// `.` goes through a reference by itself, which is what makes
    /// `node.Parent.Value` read the way it is written instead of wanting a
    /// `*` per step.
    Place? MemberOf(Place value, String name)
    {
        nuint at = value.Address;
        Die? structure = value.Type.Definition;

        if (value.Type.Tag == TagPointerType)
        {
            if (!Loaded(value.Address, &at))
                return null;
            if (at == 0u)
            {
                Refuse("'" + name + "' is a field of something that is null");
                return null;
            }
            structure = PointeeOf(value);
        }

        if (structure == null)
        {
            Refuse("nothing describes the inside of " + value.Type.Name);
            return null;
        }

        var body = (Die)structure;
        if (body.Tag != TagStructureType && body.Tag != TagClassType
            && body.Tag != TagUnionType)
        {
            Refuse(value.Type.Name + " has no fields");
            return null;
        }

        var found = MemberNamed(value.InUnit, body, name, 0u, 0);
        if (found == null)
        {
            Refuse(value.Type.Name + " has no field called '" + name + "'");
            return null;
        }

        var member = (WatchMember)found;

        // A bit field is a run of bits inside a word it shares, so reading it
        // means loading the word and shifting. Refused rather than read from
        // its byte, which would answer whatever its neighbours hold.
        if (member.Entry.Has(AtBitSize) || member.Entry.Has(AtDataBitOffset))
        {
            Refuse("'" + name + "' is a bit field, which a watch cannot read yet");
            return null;
        }

        return new Place(value.InUnit,
                         DescribeType(value.InUnit, member.Entry),
                         at + member.Offset);
    }

    /// One element of an inline array, of an array object, or of a pointer.
    Place? ElementOf(Place value, WatchExpression index)
    {
        var read = Read(index);
        if (read == null)
            return null;

        ulong which = 0u;
        if (!NumberFrom((Place)read, &which))
            return null;

        switch (value.Type.Tag)
        {
            case TagArrayType:
                return ElementInline(value, which);

            case TagPointerType:
                return ElementThroughPointer(value, which);

            default:
                Refuse(value.Type.Name + " cannot be indexed");
                return null;
        }
    }

    /// `int[4]`: the elements are where the variable is, and the bound is in
    /// the type.
    Place? ElementInline(Place value, ulong which)
    {
        var definition = value.Type.Definition;
        if (definition == null)
        {
            Refuse("nothing describes what is in this array");
            return null;
        }

        var element = DescribeType(value.InUnit, (Die)definition);
        if (element.Size == 0u)
        {
            Refuse("nothing says how wide one element of " + value.Type.Name + " is");
            return null;
        }

        ulong count = InlineArrayCount(value.InUnit, (Die)definition);
        if (count != 0u && which >= count)
        {
            Refuse("index " + WatchNumberText(which) + " is past the end of "
                   + value.Type.Name + ", which has " + WatchNumberText(count)
                   + " elements");
            return null;
        }

        return new Place(value.InUnit, element,
                         value.Address + (nuint)(which * (ulong)element.Size));
    }

    /// `a[i]` through a reference: an array object, or a plain `T*`.
    Place? ElementThroughPointer(Place value, ulong which)
    {
        nuint pointer = 0u;
        if (!Loaded(value.Address, &pointer))
            return null;
        if (pointer == 0u)
        {
            Refuse(value.Type.Name + " is null");
            return null;
        }

        var pointee = PointeeOf(value);
        if (pointee == null)
        {
            Refuse("nothing describes what " + value.Type.Name + " points at");
            return null;
        }

        var shape = ArrayShapeOf(value.InUnit, (Die)pointee);
        if (shape != null)
            return ElementInObject(value, (WatchArray)shape, pointer, which);

        // A plain pointer has no length beside it, so there is nothing to check
        // the index against -- exactly as there is nothing in the program.
        var element = DescribeType(value.InUnit, (Die)value.Type.Definition);
        if (element.Size == 0u)
        {
            Refuse("nothing says how wide one " + value.Type.Name + " element is");
            return null;
        }
        return new Place(value.InUnit, element,
                         pointer + (nuint)(which * (ulong)element.Size));
    }

    /// An array object, whose length is the word in front of its elements.
    Place? ElementInObject(Place value, WatchArray shape, nuint pointer,
                           ulong which)
    {
        if (shape.Element.Size == 0u)
        {
            Refuse("nothing says how wide one element of " + value.Type.Name + " is");
            return null;
        }

        nuint length = 0u;
        if (!Loaded(pointer + shape.LengthOffset, &length))
            return null;

        if (which >= (ulong)length)
        {
            Refuse("index " + WatchNumberText(which) + " is past the end of "
                   + value.Type.Name + ", which has "
                   + WatchNumberText((ulong)length) + " elements");
            return null;
        }

        return new Place(value.InUnit, shape.Element,
                         pointer + shape.ElementsOffset
                         + (nuint)(which * (ulong)shape.Element.Size));
    }

    /// `*p`: what a pointer points at.
    Place? Dereferenced(Place value)
    {
        if (value.Type.Tag != TagPointerType)
        {
            Refuse(value.Type.Name + " is not a pointer, so it cannot be followed");
            return null;
        }

        var definition = value.Type.Definition;
        if (definition == null)
        {
            Refuse("nothing describes what " + value.Type.Name + " points at");
            return null;
        }

        nuint pointer = 0u;
        if (!Loaded(value.Address, &pointer))
            return null;
        if (pointer == 0u)
        {
            Refuse("that pointer is null");
            return null;
        }

        return new Place(value.InUnit,
                         DescribeType(value.InUnit, (Die)definition), pointer);
    }

    Die? PointeeOf(Place value)
    {
        var definition = value.Type.Definition;
        return definition == null ? null : TypeEntryOf(value.InUnit, (Die)definition);
    }

    /// One word out of the target, naming the address when there is not one.
    bool Loaded(nuint at, nuint* into)
    {
        byte[] cell = new byte[8];
        if (!_target.ReadMemory(at, cell, 8u))
        {
            Refuse("0x" + FormatHexadecimal((ulong)at) + " cannot be read");
            return false;
        }
        *into = (nuint)LittleEndianWord(cell);
        return true;
    }

    /// A place as a number, which is what an index has to be.
    bool NumberFrom(Place value, ulong* number)
    {
        if (!value.Addressed)
        {
            *number = value.Number;
            return true;
        }

        nuint size = value.Type.Tag == TagPointerType ? 8u : value.Type.Size;
        if (size == 0u || size > 8u)
        {
            Refuse(value.Type.Name + " is not a number, so it cannot be an index");
            return false;
        }

        byte[] bytes = new byte[8];
        if (!_target.ReadMemory(value.Address, bytes, size))
        {
            Refuse("0x" + FormatHexadecimal((ulong)value.Address)
                   + " cannot be read");
            return false;
        }

        ulong raw = 0u;
        for (nuint i = 0u; i < size; i++)
            raw = raw | ((ulong)bytes[i] << (int)(i * 8u));

        // **A negative index is refused rather than widened.** An `int` holding
        // -1 read as an unsigned index is four billion elements along, which
        // passes every bounds check that compares the wrong way and reads
        // somebody else's memory.
        if (IsSignedWatchEncoding(value.Type.Encoding))
        {
            long signed2 = (long)raw;
            if (size < 8u)
            {
                int spare = (int)((8u - size) * 8u);
                signed2 = ((long)(raw << spare)) >> spare;
            }
            if (signed2 < 0)
            {
                Refuse("a negative index is not a place in anything");
                return false;
            }
            raw = (ulong)signed2;
        }

        *number = raw;
        return true;
    }
}

bool IsSignedWatchEncoding(ulong encoding)
    => encoding == EncodingSigned || encoding == EncodingSignedChar;

String WatchNumberText(ulong value) => Standard.Text.FromInteger((long)value);

/// A named member of a structure, with the offset from the structure's start.
///
/// Follows `DW_TAG_inheritance` into the base, whose subobject begins at the
/// offset the inheritance entry gives -- zero in this language, and read
/// rather than assumed.
WatchMember? MemberNamed(Unit unit, Die structure, String name, nuint from,
                         int depth)
{
    // A type graph with a cycle in it is a corrupt one, and following it for
    // ever is worse than saying so.
    if (depth > 8)
        return null;

    var members = ChildrenOf(unit, structure);
    for (nuint i = 0u; i < members.Count; i++)
    {
        var one = members[i];
        if (one.Tag == TagMember && one.Name == name)
            return new WatchMember(one,
                                   from + (nuint)one.NumberOf(AtDataMemberLoc, 0u));
    }

    for (nuint i = 0u; i < members.Count; i++)
    {
        var one = members[i];
        if (one.Tag != TagInheritance)
            continue;

        var body = TypeEntryOf(unit, one);
        if (body == null)
            continue;

        var found = MemberNamed(unit, (Die)body, name,
                                from + (nuint)one.NumberOf(AtDataMemberLoc, 0u),
                                depth + 1);
        if (found != null)
            return found;
    }

    return null;
}

/// How many elements an inline array holds, or zero when its type does not say.
///
/// Zero is also what the flexible member of an array object carries, which is
/// the same answer to the same question: the count is not in the type.
ulong InlineArrayCount(Unit unit, Die array)
{
    var bounds = ChildrenOf(unit, array);
    for (nuint i = 0u; i < bounds.Count; i++)
    {
        var one = bounds[i];
        if (one.Tag != TagSubrangeType)
            continue;
        if (one.Has(AtCount))
            return one.NumberOf(AtCount, 0u);
        if (one.Has(AtUpperBound))
            return one.NumberOf(AtUpperBound, 0u) + 1u;
    }
    return 0u;
}

/// The shape of an object whose elements follow a length.
///
/// Recognised by the member typed as an array rather than by its name:
/// `elements`, `bytes` and `units` are three names for one shape (docs/abi.md
/// §2.7 and §2.6), and the length is always the member in front of it.
WatchArray? ArrayShapeOf(Unit unit, Die body)
{
    if (body.Tag != TagStructureType && body.Tag != TagClassType)
        return null;

    var members = ChildrenOf(unit, body);
    for (nuint i = 0u; i < members.Count; i++)
    {
        var one = members[i];
        if (one.Tag != TagMember)
            continue;

        var described = TypeEntryOf(unit, one);
        if (described == null || ((Die)described).Tag != TagArrayType)
            continue;

        // Nothing in front of it is nothing to take the length from, which
        // makes this some other structure that happens to hold an array.
        if (i == 0u || members[i - 1u].Tag != TagMember)
            return null;

        return new WatchArray(
            (nuint)members[i - 1u].NumberOf(AtDataMemberLoc, 0u),
            (nuint)one.NumberOf(AtDataMemberLoc, 0u),
            DescribeType(unit, (Die)described));
    }

    return null;
}

// =============================================================== the one call

/// Reads one watch expression where the program is stopped.
///
/// The answer is text either way: a value, or the reason there is none. A
/// watch that cannot be read is a line in the pane saying so rather than an
/// error a session has to handle -- half the watches in a debugging session
/// are out of scope at any moment, and that is not a failure.
///
/// MUST be called on the session's own thread, like everything else that reads
/// a target.
public WatchLine ReadWatch(Engine engine, ITarget target, Unit unit, Die owner,
                           Registers frame, String expression)
{
    var parsed = ParseWatch(expression);
    if (parsed.Problem.ByteLength() != 0u)
        return new WatchLine(expression, "", parsed.Problem, false);

    var reader = new WatchReader(engine, target, unit, owner, frame);
    var value = reader.Read(parsed);

    if (value == null)
    {
        String why = reader.Problem.ByteLength() != 0u
                   ? reader.Problem
                   : "it could not be read";
        return new WatchLine(expression, "", why, false);
    }

    var place = (Place)value;
    if (!place.Addressed)
        return new WatchLine(expression, place.Type.Name,
                             WatchNumberText(place.Number), true);

    return new WatchLine(expression, place.Type.Name,
                         FormatAt(engine, target, place.InUnit, place.Type,
                                  place.Address),
                         true);
}
