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

**Functions** &nbsp; [Describe](#describe-function) &middot; [Parse](#parse-function) &middot; [Populate](#populate-function) &middot; [PopulateFrom](#populatefrom-function) &middot; [Serialize](#serialize-function) &middot; [SerializeDocument](#serializedocument-function) &middot; [ToNode](#tonode-function) &middot; [Write](#write-function) &middot; [WriteDocument](#writedocument-function) &middot; [WriteIndented](#writeindented-function)

**Constants** &nbsp; [MaxDepth](#maxdepth-constant)

## Types

### XmlAttribute *attribute*

```
attribute XmlAttribute
```

Writes the field as an attribute of its element rather than as a child.

<sub>[stdlib/Xml.sl:892](../../stdlib/Xml.sl#L892)</sub>

### XmlAttributes *class*

```
class XmlAttributes
```

An element's attributes, in the order they were written.

The same `OrderedDictionary` a JSON object's members are, and for the same
reason: an attribute list that came back reordered is a document nobody
wrote.

<sub>[stdlib/Xml.sl:121](../../stdlib/Xml.sl#L121)</sub>

#### Count *property*

```
nuint Count { get; }
```

How many attributes there are.

<sub>[stdlib/Xml.sl:129](../../stdlib/Xml.sl#L129)</sub>

#### NameAt *method*

```
String NameAt(nuint index)
```

The name at a position, in the order they were written.

<sub>[stdlib/Xml.sl:132](../../stdlib/Xml.sl#L132)</sub>

#### ValueAt *method*

```
String ValueAt(nuint index)
```

The value at a position, pairing with `NameAt` at the same index.

<sub>[stdlib/Xml.sl:135](../../stdlib/Xml.sl#L135)</sub>

#### Add *method*

```
void Add(String name, String value)
```

Appends an attribute without looking for the name first. A parsed
document cannot reach here with a repeat -- that is
`XmlError.DuplicateAttribute` -- so this is for building one.

<sub>[stdlib/Xml.sl:140](../../stdlib/Xml.sl#L140)</sub>

#### Set *method*

```
void Set(String name, String value)
```

Sets the value of a name, adding it if it is new. A replaced name keeps
the position it had.

<sub>[stdlib/Xml.sl:144](../../stdlib/Xml.sl#L144)</sub>

#### IndexOf *method*

```
Optional<nuint> IndexOf(String name)
```

Where a name is, or `None`.

<sub>[stdlib/Xml.sl:147](../../stdlib/Xml.sl#L147)</sub>

#### Has *method*

```
bool Has(String name)
```

Whether an attribute of that name is there.

<sub>[stdlib/Xml.sl:150](../../stdlib/Xml.sl#L150)</sub>

#### Find *method*

```
String Find(String name, String fallback)
```

The value of an attribute, or the fallback when it is not there.

<sub>[stdlib/Xml.sl:153](../../stdlib/Xml.sl#L153)</sub>

#### Remove *method*

```
bool Remove(String name)
```

Removes an attribute, answering whether it was there.

<sub>[stdlib/Xml.sl:156](../../stdlib/Xml.sl#L156)</sub>

### XmlCreate *attribute*

```
attribute XmlCreate
```

Lets a reader make this field's object when the element is there and the
field is null. The same opt-in, and the same hazard, as `[JsonCreate]`.

<sub>[stdlib/Xml.sl:899](../../stdlib/Xml.sl#L899)</sub>

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

<sub>[stdlib/Xml.sl:48](../../stdlib/Xml.sl#L48)</sub>

#### Unexpected *case*

```
Unexpected
```

A character that cannot appear here.

<sub>[stdlib/Xml.sl:51](../../stdlib/Xml.sl#L51)</sub>

#### UnclosedTag *case*

```
UnclosedTag
```

A `<` with no `>`.

<sub>[stdlib/Xml.sl:54](../../stdlib/Xml.sl#L54)</sub>

#### UnclosedText *case*

```
UnclosedText
```

A quoted attribute value with no closing quote.

<sub>[stdlib/Xml.sl:57](../../stdlib/Xml.sl#L57)</sub>

#### MismatchedEnd *case*

```
MismatchedEnd
```

An end tag naming a different element than the start tag it closes.

<sub>[stdlib/Xml.sl:60](../../stdlib/Xml.sl#L60)</sub>

#### UnexpectedEnd *case*

```
UnexpectedEnd
```

The document stopped inside something.

<sub>[stdlib/Xml.sl:63](../../stdlib/Xml.sl#L63)</sub>

#### BadName *case*

```
BadName
```

A tag or attribute name that is not one.

<sub>[stdlib/Xml.sl:66](../../stdlib/Xml.sl#L66)</sub>

#### BadEntity *case*

```
BadEntity
```

An `&` that is not an entity this reads. The five XML entities and
numeric character references are what it reads; a DTD's own are not.

<sub>[stdlib/Xml.sl:70](../../stdlib/Xml.sl#L70)</sub>

#### NoRoot *case*

```
NoRoot
```

Nothing but whitespace and comments -- no root element.

<sub>[stdlib/Xml.sl:73](../../stdlib/Xml.sl#L73)</sub>

#### TrailingContent *case*

```
TrailingContent
```

A second root element. XML allows exactly one.

<sub>[stdlib/Xml.sl:76](../../stdlib/Xml.sl#L76)</sub>

#### TooDeep *case*

```
TooDeep
```

Nesting past `MaxDepth`.

<sub>[stdlib/Xml.sl:79](../../stdlib/Xml.sl#L79)</sub>

#### DuplicateAttribute *case*

```
DuplicateAttribute
```

One element naming an attribute twice.

<sub>[stdlib/Xml.sl:82](../../stdlib/Xml.sl#L82)</sub>

#### NotReflected *case*

```
NotReflected
```

A type with no field metadata to map onto.

<sub>[stdlib/Xml.sl:85](../../stdlib/Xml.sl#L85)</sub>

### XmlIgnore *attribute*

```
attribute XmlIgnore
```

Leaves the field out entirely, in both directions.

<sub>[stdlib/Xml.sl:895](../../stdlib/Xml.sl#L895)</sub>

### XmlName *attribute*

```
attribute XmlName
```

The element name a field is written as, when it differs from the field's.

<sub>[stdlib/Xml.sl:889](../../stdlib/Xml.sl#L889)</sub>

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

<sub>[stdlib/Xml.sl:169](../../stdlib/Xml.sl#L169)</sub>

#### Name *field*

```
String Name
```

The tag name, without any namespace prefix being separated out -- a
prefix arrives as part of the name, since nothing here resolves one.

<sub>[stdlib/Xml.sl:173](../../stdlib/Xml.sl#L173)</sub>

#### Attributes *field*

```
XmlAttributes Attributes
```

The attributes, in the order they were written. Never null; an element
with none has an empty list.

<sub>[stdlib/Xml.sl:177](../../stdlib/Xml.sl#L177)</sub>

#### Children *field*

```
List<XmlNode> Children
```

The child elements, in document order. Never null.

<sub>[stdlib/Xml.sl:180](../../stdlib/Xml.sl#L180)</sub>

#### Text *field*

```
String Text
```

Every character run inside this element, joined. Where each run sat
relative to the children is not kept -- see the note above.

<sub>[stdlib/Xml.sl:184](../../stdlib/Xml.sl#L184)</sub>

#### Child *method*

```
XmlNode? Child(String name)
```

The first child of that name, or null.

<sub>[stdlib/Xml.sl:196](../../stdlib/Xml.sl#L196)</sub>

#### ChildrenNamed *method*

```
List<XmlNode> ChildrenNamed(String name)
```

Every child of that name, in order.

<sub>[stdlib/Xml.sl:208](../../stdlib/Xml.sl#L208)</sub>

#### TextOf *method*

```
String TextOf(String name, String fallback)
```

The text of the first child of that name, or the fallback.

<sub>[stdlib/Xml.sl:221](../../stdlib/Xml.sl#L221)</sub>

#### Add *method*

```
void Add(XmlNode child)
```

Appends a child element. Nothing checks for a cycle, so do not add a
node to one of its own descendants: writing the tree would not end.

<sub>[stdlib/Xml.sl:231](../../stdlib/Xml.sl#L231)</sub>

## Functions

### Describe *function*

```
String Describe(XmlError error)
```

A sentence describing an error, for a message a person will read.

<sub>[stdlib/Xml.sl:89](../../stdlib/Xml.sl#L89)</sub>

### Parse *function*

```
Result<XmlNode, XmlError> Parse(String source)
```

Reads a whole document and answers with its root element.

<sub>[stdlib/Xml.sl:705](../../stdlib/Xml.sl#L705)</sub>

### Populate *function*

```
XmlError Populate<T>(T value, String source)
```

Fills an object's fields from an element.

The object is the program's, for the reason `Json.Populate` takes one: its
constructor has run, so a field the document does not mention keeps the
value the type promised rather than a zero.

<sub>[stdlib/Xml.sl:1071](../../stdlib/Xml.sl#L1071)</sub>

### PopulateFrom *function*

```
XmlError PopulateFrom<T>(T value, XmlNode node)
```

The same, from an element already parsed.

<sub>[stdlib/Xml.sl:1081](../../stdlib/Xml.sl#L1081)</sub>

### Serialize *function*

```
String Serialize<T>(T value, String name)
```

The element as text.

<sub>[stdlib/Xml.sl:912](../../stdlib/Xml.sl#L912)</sub>

### SerializeDocument *function*

```
String SerializeDocument<T>(T value, String name)
```

The same, with a declaration and indentation.

<sub>[stdlib/Xml.sl:915](../../stdlib/Xml.sl#L915)</sub>

### ToNode *function*

```
XmlNode ToNode<T>(T value, String name)
```

A value as an element, with each field a child element under it.

A field marked `[XmlAttribute]` becomes an attribute instead, which is what
makes the output look like XML a person would have written rather than a
JSON document with angle brackets.

<sub>[stdlib/Xml.sl:906](../../stdlib/Xml.sl#L906)</sub>

### Write *function*

```
String Write(XmlNode node)
```

The element as text, on one line.

<sub>[stdlib/Xml.sl:752](../../stdlib/Xml.sl#L752)</sub>

### WriteDocument *function*

```
String WriteDocument(XmlNode node)
```

The declaration and the element under it, which is what a whole file wants.

<sub>[stdlib/Xml.sl:770](../../stdlib/Xml.sl#L770)</sub>

### WriteIndented *function*

```
String WriteIndented(XmlNode node)
```

The same, indented two spaces a level. An element with text in it is still
written on one line, because the whitespace an indent adds would become
part of that text when it was read back.

<sub>[stdlib/Xml.sl:762](../../stdlib/Xml.sl#L762)</sub>

## Constants

### MaxDepth *constant*

```
const nuint MaxDepth = 128
```

How far the parser will nest, for the reason `Json.MaxDepth` exists: the
nesting is recursion, and a hostile document is one long line.

<sub>[stdlib/Xml.sl:112](../../stdlib/Xml.sl#L112)</sub>

