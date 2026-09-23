# Standard.Xml

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

XML, in the two layers `Standard.Json` has: a document that needs no type,
and a mapping onto one that reads a `[Reflect]` type's field tables.

**What this reads.** Elements, attributes, text, CDATA, comments, the five
predefined entities and numeric character references, and an optional
declaration or doctype at the front. That is the shape of a configuration
file, a document a program exchanges, and most of what XML is used for now.

**What it does not.** Namespaces are not resolved: `<x:name>` is an element
whose name is the whole of `x:name`, and `xmlns` is an ordinary attribute. A
DTD is skipped rather than applied, so no entity a document declares for
itself is expanded and no default attribute appears. Both are refusals to
half-implement something: a program that needs them needs all of them, and
what is here says so rather than working until it does not.

## Contents

**Types** &nbsp; [XmlAttribute](#xmlattribute-attribute) &middot; [XmlAttributes](#xmlattributes-class) &middot; [XmlCreate](#xmlcreate-attribute) &middot; [XmlError](#xmlerror-enum) &middot; [XmlIgnore](#xmlignore-attribute) &middot; [XmlName](#xmlname-attribute) &middot; [XmlNode](#xmlnode-class)

**Functions** &nbsp; [DescribeXmlError](#describexmlerror-function) &middot; [Parse](#parse-function) &middot; [PopulateObject](#populateobject-function) &middot; [PopulateObject](#populateobject-function) &middot; [Serialize](#serialize-function) &middot; [SerializeDocument](#serializedocument-function) &middot; [ToXmlDocumentText](#toxmldocumenttext-function) &middot; [ToXmlNode](#toxmlnode-function) &middot; [ToXmlText](#toxmltext-function) &middot; [ToXmlTextIndented](#toxmltextindented-function)

**Constants** &nbsp; [MaxDepth](#maxdepth-constant)

## Types

### XmlAttribute *attribute*

```
attribute XmlAttribute
```

Writes the field as an attribute of its element rather than as a child.

<sub>[stdlib/Xml.sl:1200](../../stdlib/Xml.sl#L1200)</sub>

### XmlAttributes *class*

```
class XmlAttributes
```

An element's attributes, in the order they were written.

The same `OrderedDictionary` a JSON object's members are, and for the same
reason: an attribute list that came back reordered is a document nobody
wrote.

<sub>[stdlib/Xml.sl:126](../../stdlib/Xml.sl#L126)</sub>

#### Count *property*

```
nuint Count { get; }
```

How many attributes there are.

<sub>[stdlib/Xml.sl:134](../../stdlib/Xml.sl#L134)</sub>

#### GetNameAt *method*

```
String GetNameAt(nuint index)
```

The name at a position, in the order they were written.

<sub>[stdlib/Xml.sl:137](../../stdlib/Xml.sl#L137)</sub>

#### GetValueAt *method*

```
String GetValueAt(nuint index)
```

The value at a position, pairing with `GetNameAt` at the same index.

**See also** &nbsp; [XmlAttributes.GetNameAt](#getnameat-method)

<sub>[stdlib/Xml.sl:142](../../stdlib/Xml.sl#L142)</sub>

#### Add *method*

```
void Add(String name, String value)
```

Appends an attribute without looking for the name first. A parsed
document cannot reach here with a repeat -- that is
`XmlError.DuplicateAttribute` -- so this is for building one.

**Parameters**

- `name` — the attribute name
- `value` — the text it carries, unescaped

**See also** &nbsp; [XmlError.DuplicateAttribute](#duplicateattribute-case)

<sub>[stdlib/Xml.sl:151](../../stdlib/Xml.sl#L151)</sub>

#### SetValue *method*

```
void SetValue(String name, String value)
```

Sets the value of a name, adding it if it is new. A replaced name keeps
the position it had.

**Parameters**

- `name` — the attribute name
- `value` — the text it is to carry, unescaped

<sub>[stdlib/Xml.sl:158](../../stdlib/Xml.sl#L158)</sub>

#### IndexOf *method*

```
Optional<nuint> IndexOf(String name)
```

Where a name is, or `None`.

<sub>[stdlib/Xml.sl:161](../../stdlib/Xml.sl#L161)</sub>

#### ContainsKey *method*

```
bool ContainsKey(String name)
```

Whether an attribute of that name is there.

<sub>[stdlib/Xml.sl:164](../../stdlib/Xml.sl#L164)</sub>

#### Find *method*

```
String Find(String name, String fallback)
```

The value of an attribute, or the fallback when it is not there.

**Parameters**

- `name` — the attribute to look for
- `fallback` — what to answer when there is no such attribute

<sub>[stdlib/Xml.sl:170](../../stdlib/Xml.sl#L170)</sub>

#### Remove *method*

```
bool Remove(String name)
```

Removes an attribute, answering whether it was there.

<sub>[stdlib/Xml.sl:173](../../stdlib/Xml.sl#L173)</sub>

### XmlCreate *attribute*

```
attribute XmlCreate
```

Lets a reader make this field's object when the element is there and the
field is null. The same opt-in, and the same hazard, as `[JsonCreate]`.

<sub>[stdlib/Xml.sl:1207](../../stdlib/Xml.sl#L1207)</sub>

### XmlError *enum*

```
enum XmlError
```

Why a document could not be read.

<sub>[stdlib/Xml.sl:46](../../stdlib/Xml.sl#L46)</sub>

#### None *case*

```
None
```

Nothing went wrong.

<sub>[stdlib/Xml.sl:49](../../stdlib/Xml.sl#L49)</sub>

#### Unexpected *case*

```
Unexpected
```

A character that cannot appear here.

<sub>[stdlib/Xml.sl:52](../../stdlib/Xml.sl#L52)</sub>

#### UnclosedTag *case*

```
UnclosedTag
```

A `<` with no `>`.

<sub>[stdlib/Xml.sl:55](../../stdlib/Xml.sl#L55)</sub>

#### UnclosedText *case*

```
UnclosedText
```

A quoted attribute value with no closing quote.

<sub>[stdlib/Xml.sl:58](../../stdlib/Xml.sl#L58)</sub>

#### MismatchedEnd *case*

```
MismatchedEnd
```

An end tag naming a different element than the start tag it closes.

<sub>[stdlib/Xml.sl:61](../../stdlib/Xml.sl#L61)</sub>

#### UnexpectedEnd *case*

```
UnexpectedEnd
```

The document stopped inside something.

<sub>[stdlib/Xml.sl:64](../../stdlib/Xml.sl#L64)</sub>

#### BadName *case*

```
BadName
```

A tag or attribute name that is not one.

<sub>[stdlib/Xml.sl:67](../../stdlib/Xml.sl#L67)</sub>

#### BadEntity *case*

```
BadEntity
```

An `&` that is not an entity this reads. The five XML entities and
numeric character references are what it reads; a DTD's own are not,
and nor is a reference to a character XML does not allow.

<sub>[stdlib/Xml.sl:72](../../stdlib/Xml.sl#L72)</sub>

#### NoRoot *case*

```
NoRoot
```

Nothing but whitespace and comments -- no root element.

<sub>[stdlib/Xml.sl:75](../../stdlib/Xml.sl#L75)</sub>

#### TrailingContent *case*

```
TrailingContent
```

A second root element. XML allows exactly one.

<sub>[stdlib/Xml.sl:78](../../stdlib/Xml.sl#L78)</sub>

#### TooDeep *case*

```
TooDeep
```

Nesting past `MaxDepth`.

<sub>[stdlib/Xml.sl:81](../../stdlib/Xml.sl#L81)</sub>

#### DuplicateAttribute *case*

```
DuplicateAttribute
```

One element naming an attribute twice.

<sub>[stdlib/Xml.sl:84](../../stdlib/Xml.sl#L84)</sub>

#### NotReflected *case*

```
NotReflected
```

A type with no field metadata to map onto.

<sub>[stdlib/Xml.sl:87](../../stdlib/Xml.sl#L87)</sub>

### XmlIgnore *attribute*

```
attribute XmlIgnore
```

Leaves the field out entirely, in both directions.

<sub>[stdlib/Xml.sl:1203](../../stdlib/Xml.sl#L1203)</sub>

### XmlName *attribute*

```
attribute XmlName
```

The element name a field is written as, when it differs from the field's.

<sub>[stdlib/Xml.sl:1197](../../stdlib/Xml.sl#L1197)</sub>

### XmlNode *class*

```
class XmlNode
```

One element: a name, its attributes, its child elements and its text.

**Text is gathered rather than interleaved.** A node's `Text` is every
character run inside it joined together, which loses where each sat between
the children. That is the wrong model for a document with mixed content --
a paragraph with `<em>` inside it -- and the right one for the data XML is
mostly used to carry. `Children` and `Text` together are what a
configuration file has.

**Whitespace between elements is formatting.** In an element with child
elements, a run of text that is only whitespace in the source is dropped:
it is the indentation a person or `ToXmlTextIndented` put there. A run with
anything else in it is kept whole, as is a CDATA section or a character
reference, and an element with no children keeps all of its text.

<sub>[stdlib/Xml.sl:192](../../stdlib/Xml.sl#L192)</sub>

#### Name *field*

```
String Name
```

The tag name, without any namespace prefix being separated out -- a
prefix arrives as part of the name, since nothing here resolves one.

<sub>[stdlib/Xml.sl:196](../../stdlib/Xml.sl#L196)</sub>

#### Attributes *field*

```
XmlAttributes Attributes
```

The attributes, in the order they were written. Never null; an element
with none has an empty list.

<sub>[stdlib/Xml.sl:200](../../stdlib/Xml.sl#L200)</sub>

#### Children *field*

```
List<XmlNode> Children
```

The child elements, in document order. Never null.

<sub>[stdlib/Xml.sl:203](../../stdlib/Xml.sl#L203)</sub>

#### Text *field*

```
String Text
```

Every character run inside this element, joined. Where each run sat
relative to the children is not kept -- see the note above.

<sub>[stdlib/Xml.sl:207](../../stdlib/Xml.sl#L207)</sub>

#### FindChild *method*

```
XmlNode? FindChild(String name)
```

The first child of that name, or null.

<sub>[stdlib/Xml.sl:219](../../stdlib/Xml.sl#L219)</sub>

#### FindChildren *method*

```
List<XmlNode> FindChildren(String name)
```

Every child of that name, in order.

<sub>[stdlib/Xml.sl:231](../../stdlib/Xml.sl#L231)</sub>

#### FindChildText *method*

```
String FindChildText(String name, String fallback)
```

The text of the first child of that name, or the fallback.

**Parameters**

- `name` — the child element to look for
- `fallback` — what to answer when there is no such child

<sub>[stdlib/Xml.sl:247](../../stdlib/Xml.sl#L247)</sub>

#### Add *method*

```
void Add(XmlNode child)
```

Appends a child element. Nothing checks for a cycle, so do not add a
node to one of its own descendants: writing the tree would not end.

<sub>[stdlib/Xml.sl:257](../../stdlib/Xml.sl#L257)</sub>

## Functions

### DescribeXmlError *function*

```
String DescribeXmlError(XmlError error)
```

A sentence describing an error, for a message a person will read.

<sub>[stdlib/Xml.sl:91](../../stdlib/Xml.sl#L91)</sub>

### Parse *function*

```
Result<XmlNode, XmlError> Parse(String source)
```

Reads a whole document and answers with its root element.

Line ends are normalized first (§2.11): a CR LF pair or a lone CR is read
as LF everywhere, CDATA included. A control character XML does not allow
is refused wherever it is. A UTF-8 byte order mark at the start is skipped.

**Fails with**

- [XmlError.Unexpected](#unexpected-case) — a character that cannot appear where it is
- [XmlError.UnclosedTag](#unclosedtag-case) — a `<` with no `>`
- [XmlError.UnclosedText](#unclosedtext-case) — a quoted value with no closing quote
- [XmlError.MismatchedEnd](#mismatchedend-case) — an end tag naming another element
- [XmlError.UnexpectedEnd](#unexpectedend-case) — the document stopped inside an element
- [XmlError.BadName](#badname-case) — a tag or attribute name that is not one
- [XmlError.BadEntity](#badentity-case) — an `&` that is not one of the five predefines or a character reference XML allows
- [XmlError.NoRoot](#noroot-case) — nothing but whitespace and comments
- [XmlError.TrailingContent](#trailingcontent-case) — a second root element
- [XmlError.TooDeep](#toodeep-case) — nesting past `MaxDepth`
- [XmlError.DuplicateAttribute](#duplicateattribute-case) — one element names an attribute twice

**See also** &nbsp; [Xml.ToXmlText](#toxmltext-function)

<sub>[stdlib/Xml.sl:968](../../stdlib/Xml.sl#L968)</sub>

### PopulateObject *function*

```
XmlError PopulateObject<T>(T value, String source)
```

Fills an object's fields from an element.

The object is the program's, for the reason `Json.PopulateObject` takes one: its
constructor has run, so a field the document does not mention keeps the
value the type promised rather than a zero.

**Type parameters**

- `T` — a `[Reflect]` type, whose field tables say what there is to fill

**Fails with**

- [XmlError.Unexpected](#unexpected-case) — a character that cannot appear where it is
- [XmlError.UnclosedTag](#unclosedtag-case) — a `<` with no `>`
- [XmlError.UnclosedText](#unclosedtext-case) — a quoted value with no closing quote
- [XmlError.MismatchedEnd](#mismatchedend-case) — an end tag naming another element
- [XmlError.UnexpectedEnd](#unexpectedend-case) — the document stopped inside an element
- [XmlError.BadName](#badname-case) — a tag or attribute name that is not one
- [XmlError.BadEntity](#badentity-case) — an `&` that is not one of the five predefines or a character reference XML allows
- [XmlError.NoRoot](#noroot-case) — nothing but whitespace and comments
- [XmlError.TrailingContent](#trailingcontent-case) — a second root element
- [XmlError.TooDeep](#toodeep-case) — nesting past `MaxDepth`
- [XmlError.DuplicateAttribute](#duplicateattribute-case) — one element names an attribute twice
- [XmlError.NotReflected](#notreflected-case) — `T` carries no field tables

**See also** &nbsp; [Xml.Serialize](#serialize-function)

<sub>[stdlib/Xml.sl:1410](../../stdlib/Xml.sl#L1410)</sub>

### PopulateObject *function*

```
XmlError PopulateObject<T>(T value, XmlNode node)
```

The same, from an element already parsed.

**Type parameters**

- `T` — a `[Reflect]` type, whose field tables say what there is to fill

**Fails with**

- [XmlError.NotReflected](#notreflected-case) — `T` carries no field tables

**See also** &nbsp; [Xml.Serialize](#serialize-function)

<sub>[stdlib/Xml.sl:1424](../../stdlib/Xml.sl#L1424)</sub>

### Serialize *function*

```
String Serialize<T>(T value, String name)
```

The element as text.

**Parameters**

- `value` — the object to read the fields of
- `name` — the tag name of the root element

**Type parameters**

- `T` — a `[Reflect]` type

**See also** &nbsp; [Xml.PopulateObject](#populateobject-function)

<sub>[stdlib/Xml.sl:1230](../../stdlib/Xml.sl#L1230)</sub>

### SerializeDocument *function*

```
String SerializeDocument<T>(T value, String name)
```

The same, with a declaration and indentation.

**Parameters**

- `value` — the object to read the fields of
- `name` — the tag name of the root element

**Type parameters**

- `T` — a `[Reflect]` type

**See also** &nbsp; [Xml.Serialize](#serialize-function)

<sub>[stdlib/Xml.sl:1238](../../stdlib/Xml.sl#L1238)</sub>

### ToXmlDocumentText *function*

```
String ToXmlDocumentText(XmlNode node)
```

The declaration and the element under it, which is what a whole file wants.

**See also** &nbsp; [Xml.ToXmlTextIndented](#toxmltextindented-function)

<sub>[stdlib/Xml.sl:1075](../../stdlib/Xml.sl#L1075)</sub>

### ToXmlNode *function*

```
XmlNode ToXmlNode<T>(T value, String name)
```

A value as an element, with each field a child element under it.

A field marked `[XmlAttribute]` becomes an attribute instead, which is what
makes the output look like XML a person would have written rather than a
JSON document with angle brackets.

**Parameters**

- `value` — the object to read the fields of
- `name` — the tag name of the element they go under

**Type parameters**

- `T` — a `[Reflect]` type, whose field tables say what there is to write

**See also** &nbsp; [Xml.Serialize](#serialize-function)

<sub>[stdlib/Xml.sl:1219](../../stdlib/Xml.sl#L1219)</sub>

### ToXmlText *function*

```
String ToXmlText(XmlNode node)
```

The element as text, on one line.

**See also** &nbsp; [Xml.Parse](#parse-function) &middot; [Xml.ToXmlTextIndented](#toxmltextindented-function)

<sub>[stdlib/Xml.sl:1050](../../stdlib/Xml.sl#L1050)</sub>

### ToXmlTextIndented *function*

```
String ToXmlTextIndented(XmlNode node)
```

The same, indented two spaces a level. An element with text in it is still
written on one line, children and all, because the whitespace an indent
adds would become part of that text when it was read back. The indentation
between the children of any other element is dropped by the reader -- see
the note on XmlNode -- so writing what was read back gives the same text.

**See also** &nbsp; [Xml.ToXmlText](#toxmltext-function) &middot; [XmlNode](#xmlnode-class)

<sub>[stdlib/Xml.sl:1065](../../stdlib/Xml.sl#L1065)</sub>

## Constants

### MaxDepth *constant*

```
const nuint MaxDepth = 128
```

How far the parser will nest, for the reason `Json.MaxDepth` exists: the
nesting is recursion, and a hostile document is one long line.

**Value** &nbsp; 128 levels.

**See also** &nbsp; [XmlError.TooDeep](#toodeep-case)

<sub>[stdlib/Xml.sl:117](../../stdlib/Xml.sl#L117)</sub>

