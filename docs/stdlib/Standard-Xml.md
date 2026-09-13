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

**Types** &nbsp; [XmlAttribute](#xmlattribute) &middot; [XmlAttributes](#xmlattributes) &middot; [XmlCreate](#xmlcreate) &middot; [XmlError](#xmlerror) &middot; [XmlIgnore](#xmlignore) &middot; [XmlName](#xmlname) &middot; [XmlNode](#xmlnode)

**Functions** &nbsp; [Describe](#describe) &middot; [Parse](#parse) &middot; [Populate](#populate) &middot; [PopulateFrom](#populatefrom) &middot; [Serialize](#serialize) &middot; [SerializeDocument](#serializedocument) &middot; [ToNode](#tonode) &middot; [Write](#write) &middot; [WriteDocument](#writedocument) &middot; [WriteIndented](#writeindented)

**Constants** &nbsp; [MaxDepth](#maxdepth)

## Types

### XmlAttribute *attribute*

```
attribute XmlAttribute
```

Writes the field as an attribute of its element rather than as a child.

<sub>[stdlib/Xml.sl:723](../../stdlib/Xml.sl#L723)</sub>

### XmlAttributes *class*

```
class XmlAttributes
```

An element's attributes, in the order they were written.

The same `OrderedDictionary` a JSON object's members are, and for the same
reason: an attribute list that came back reordered is a document nobody
wrote.

<sub>[stdlib/Xml.sl:118](../../stdlib/Xml.sl#L118)</sub>

#### Count *method*

```
nuint Count()
```

How many attributes there are.

<sub>[stdlib/Xml.sl:125](../../stdlib/Xml.sl#L125)</sub>

#### NameAt *method*

```
String NameAt(nuint index)
```

The name at a position, in the order they were written.

<sub>[stdlib/Xml.sl:128](../../stdlib/Xml.sl#L128)</sub>

#### ValueAt *method*

```
String ValueAt(nuint index)
```

The value at a position, pairing with `NameAt` at the same index.

<sub>[stdlib/Xml.sl:131](../../stdlib/Xml.sl#L131)</sub>

#### Add *method*

```
void Add(String name, String value)
```

Appends an attribute without looking for the name first. A parsed
document cannot reach here with a repeat -- that is
`XmlError.DuplicateAttribute` -- so this is for building one.

<sub>[stdlib/Xml.sl:136](../../stdlib/Xml.sl#L136)</sub>

#### Set *method*

```
void Set(String name, String value)
```

Sets the value of a name, adding it if it is new. A replaced name keeps
the position it had.

<sub>[stdlib/Xml.sl:140](../../stdlib/Xml.sl#L140)</sub>

#### IndexOf *method*

```
Optional<nuint> IndexOf(String name)
```

Where a name is, or `None`.

<sub>[stdlib/Xml.sl:143](../../stdlib/Xml.sl#L143)</sub>

#### Has *method*

```
bool Has(String name)
```

Whether an attribute of that name is there.

<sub>[stdlib/Xml.sl:146](../../stdlib/Xml.sl#L146)</sub>

#### Find *method*

```
String Find(String name, String fallback)
```

The value of an attribute, or the fallback when it is not there.

<sub>[stdlib/Xml.sl:149](../../stdlib/Xml.sl#L149)</sub>

#### Remove *method*

```
bool Remove(String name)
```

Removes an attribute, answering whether it was there.

<sub>[stdlib/Xml.sl:152](../../stdlib/Xml.sl#L152)</sub>

### XmlCreate *attribute*

```
attribute XmlCreate
```

Lets a reader make this field's object when the element is there and the
field is null. The same opt-in, and the same hazard, as `[JsonCreate]`.

<sub>[stdlib/Xml.sl:730](../../stdlib/Xml.sl#L730)</sub>

### XmlError *enum*

```
enum XmlError
```

Why a document could not be read.

<sub>[stdlib/Xml.sl:45](../../stdlib/Xml.sl#L45)</sub>

#### None *case*

```
None
```

Nothing went wrong.

<sub>[stdlib/Xml.sl:47](../../stdlib/Xml.sl#L47)</sub>

#### Unexpected *case*

```
Unexpected
```

A character that cannot appear here.

<sub>[stdlib/Xml.sl:50](../../stdlib/Xml.sl#L50)</sub>

#### UnclosedTag *case*

```
UnclosedTag
```

A `<` with no `>`.

<sub>[stdlib/Xml.sl:53](../../stdlib/Xml.sl#L53)</sub>

#### UnclosedText *case*

```
UnclosedText
```

A quoted attribute value with no closing quote.

<sub>[stdlib/Xml.sl:56](../../stdlib/Xml.sl#L56)</sub>

#### MismatchedEnd *case*

```
MismatchedEnd
```

An end tag naming a different element than the start tag it closes.

<sub>[stdlib/Xml.sl:59](../../stdlib/Xml.sl#L59)</sub>

#### UnexpectedEnd *case*

```
UnexpectedEnd
```

The document stopped inside something.

<sub>[stdlib/Xml.sl:62](../../stdlib/Xml.sl#L62)</sub>

#### BadName *case*

```
BadName
```

A tag or attribute name that is not one.

<sub>[stdlib/Xml.sl:65](../../stdlib/Xml.sl#L65)</sub>

#### BadEntity *case*

```
BadEntity
```

An `&` that is not an entity this reads. The five XML entities and
numeric character references are what it reads; a DTD's own are not.

<sub>[stdlib/Xml.sl:69](../../stdlib/Xml.sl#L69)</sub>

#### NoRoot *case*

```
NoRoot
```

Nothing but whitespace and comments -- no root element.

<sub>[stdlib/Xml.sl:72](../../stdlib/Xml.sl#L72)</sub>

#### TrailingContent *case*

```
TrailingContent
```

A second root element. XML allows exactly one.

<sub>[stdlib/Xml.sl:75](../../stdlib/Xml.sl#L75)</sub>

#### TooDeep *case*

```
TooDeep
```

Nesting past `MaxDepth`.

<sub>[stdlib/Xml.sl:78](../../stdlib/Xml.sl#L78)</sub>

#### DuplicateAttribute *case*

```
DuplicateAttribute
```

One element naming an attribute twice.

<sub>[stdlib/Xml.sl:81](../../stdlib/Xml.sl#L81)</sub>

#### NotReflected *case*

```
NotReflected
```

A type with no field metadata to map onto.

<sub>[stdlib/Xml.sl:84](../../stdlib/Xml.sl#L84)</sub>

### XmlIgnore *attribute*

```
attribute XmlIgnore
```

Leaves the field out entirely, in both directions.

<sub>[stdlib/Xml.sl:726](../../stdlib/Xml.sl#L726)</sub>

### XmlName *attribute*

```
attribute XmlName
```

The element name a field is written as, when it differs from the field's.

<sub>[stdlib/Xml.sl:720](../../stdlib/Xml.sl#L720)</sub>

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

<sub>[stdlib/Xml.sl:165](../../stdlib/Xml.sl#L165)</sub>

#### Name *field*

```
String Name
```

The tag name, without any namespace prefix being separated out -- a
prefix arrives as part of the name, since nothing here resolves one.

<sub>[stdlib/Xml.sl:168](../../stdlib/Xml.sl#L168)</sub>

#### Attributes *field*

```
XmlAttributes Attributes
```

The attributes, in the order they were written. Never null; an element
with none has an empty list.

<sub>[stdlib/Xml.sl:172](../../stdlib/Xml.sl#L172)</sub>

#### Children *field*

```
List<XmlNode> Children
```

The child elements, in document order. Never null.

<sub>[stdlib/Xml.sl:175](../../stdlib/Xml.sl#L175)</sub>

#### Text *field*

```
String Text
```

Every character run inside this element, joined. Where each run sat
relative to the children is not kept -- see the note above.

<sub>[stdlib/Xml.sl:179](../../stdlib/Xml.sl#L179)</sub>

#### Child *method*

```
XmlNode? Child(String name)
```

The first child of that name, or null.

<sub>[stdlib/Xml.sl:190](../../stdlib/Xml.sl#L190)</sub>

#### ChildrenNamed *method*

```
List<XmlNode> ChildrenNamed(String name)
```

Every child of that name, in order.

<sub>[stdlib/Xml.sl:199](../../stdlib/Xml.sl#L199)</sub>

#### TextOf *method*

```
String TextOf(String name, String fallback)
```

The text of the first child of that name, or the fallback.

<sub>[stdlib/Xml.sl:209](../../stdlib/Xml.sl#L209)</sub>

#### Add *method*

```
void Add(XmlNode child)
```

Appends a child element. Nothing checks for a cycle, so do not add a
node to one of its own descendants: writing the tree would not end.

<sub>[stdlib/Xml.sl:217](../../stdlib/Xml.sl#L217)</sub>

## Functions

### Describe *function*

```
String Describe(XmlError error)
```

A sentence describing an error, for a message a person will read.

<sub>[stdlib/Xml.sl:88](../../stdlib/Xml.sl#L88)</sub>

### Parse *function*

```
Result<XmlNode, XmlError> Parse(String source)
```

Reads a whole document and answers with its root element.

<sub>[stdlib/Xml.sl:589](../../stdlib/Xml.sl#L589)</sub>

### Populate *function*

```
XmlError Populate<T>(T value, String source)
```

Fills an object's fields from an element.

The object is the program's, for the reason `Json.Populate` takes one: its
constructor has run, so a field the document does not mention keeps the
value the type promised rather than a zero.

<sub>[stdlib/Xml.sl:868](../../stdlib/Xml.sl#L868)</sub>

### PopulateFrom *function*

```
XmlError PopulateFrom<T>(T value, XmlNode node)
```

The same, from an element already parsed.

<sub>[stdlib/Xml.sl:876](../../stdlib/Xml.sl#L876)</sub>

### Serialize *function*

```
String Serialize<T>(T value, String name)
```

The element as text.

<sub>[stdlib/Xml.sl:742](../../stdlib/Xml.sl#L742)</sub>

### SerializeDocument *function*

```
String SerializeDocument<T>(T value, String name)
```

The same, with a declaration and indentation.

<sub>[stdlib/Xml.sl:745](../../stdlib/Xml.sl#L745)</sub>

### ToNode *function*

```
XmlNode ToNode<T>(T value, String name)
```

A value as an element, with each field a child element under it.

A field marked `[XmlAttribute]` becomes an attribute instead, which is what
makes the output look like XML a person would have written rather than a
JSON document with angle brackets.

<sub>[stdlib/Xml.sl:737](../../stdlib/Xml.sl#L737)</sub>

### Write *function*

```
String Write(XmlNode node)
```

The element as text, on one line.

<sub>[stdlib/Xml.sl:623](../../stdlib/Xml.sl#L623)</sub>

### WriteDocument *function*

```
String WriteDocument(XmlNode node)
```

The declaration and the element under it, which is what a whole file wants.

<sub>[stdlib/Xml.sl:639](../../stdlib/Xml.sl#L639)</sub>

### WriteIndented *function*

```
String WriteIndented(XmlNode node)
```

The same, indented two spaces a level. An element with text in it is still
written on one line, because the whitespace an indent adds would become
part of that text when it was read back.

<sub>[stdlib/Xml.sl:632](../../stdlib/Xml.sl#L632)</sub>

## Constants

### MaxDepth *constant*

```
const nuint MaxDepth = 128
```

How far the parser will nest, for the reason `Json.MaxDepth` exists: the
nesting is recursion, and a hostile document is one long line.

<sub>[stdlib/Xml.sl:109](../../stdlib/Xml.sl#L109)</sub>

