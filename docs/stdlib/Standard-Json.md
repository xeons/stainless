# Standard.Json

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

JSON, in two layers.

The lower one is a document: `Json.Parse` gives a `JsonValue`, a variant that
is exactly one of the six things JSON has, and `Write` puts one back. Nothing
about it needs a type, so it handles a document whose shape a program learns
at run time -- which is most of them.

The upper one maps a document onto a type, through the field tables a
`[Reflect]` type carries (§6). `Serialize` reads an object's fields and
`Populate` writes them.

**Why the mapping fills an object rather than making one.** A constructor is
what establishes a type's invariants, and a deserializer that allocated
zeroed memory would produce an object whose non-nullable fields were null --
a hole in the type system rather than a value. So `Populate` takes an
instance the program made, and `Deserialize<T>` calls `new T()` first, which
is what `where T : new()` is there to guarantee.

## Contents

**Types** &nbsp; [JsonCreate](#jsoncreate-attribute) &middot; [JsonError](#jsonerror-enum) &middot; [JsonIgnore](#jsonignore-attribute) &middot; [JsonName](#jsonname-attribute) &middot; [JsonObject](#jsonobject-class) &middot; [JsonValue](#jsonvalue-variant)

**Functions** &nbsp; [BoolOr](#boolor-function) &middot; [Describe](#describe-function) &middot; [IntegerOr](#integeror-function) &middot; [IsNull](#isnull-function) &middot; [ItemsOf](#itemsof-function) &middot; [MembersOf](#membersof-function) &middot; [NewArray](#newarray-function) &middot; [NewObject](#newobject-function) &middot; [NumberOf](#numberof-function) &middot; [NumberOr](#numberor-function) &middot; [Parse](#parse-function) &middot; [Populate](#populate-function) &middot; [PopulateFrom](#populatefrom-function) &middot; [Serialize](#serialize-function) &middot; [SerializeIndented](#serializeindented-function) &middot; [TextOr](#textor-function) &middot; [ToValue](#tovalue-function) &middot; [Write](#write-function) &middot; [WriteIndented](#writeindented-function)

**Constants** &nbsp; [MaxDepth](#maxdepth-constant)

## Types

### JsonCreate *attribute*

```
attribute JsonCreate
```

Lets a reader make this field's object when the document has one and the
field is null.

Off by default, and opt-in per field rather than per call, because the type
is what knows whether it is safe. An object made this way is **zeroed**:
every reference in it starts null, and only the document fills them. Mark a
field with this when the document is what decides whether the object is
there, and leave it alone when the constructor already made one.

<sub>[stdlib/Json.sl:804](../../stdlib/Json.sl#L804)</sub>

### JsonError *enum*

```
enum JsonError
```

Why a document could not be read.

<sub>[stdlib/Json.sl:48](../../stdlib/Json.sl#L48)</sub>

#### None *case*

```
None
```

Nothing went wrong.

<sub>[stdlib/Json.sl:50](../../stdlib/Json.sl#L50)</sub>

#### Unexpected *case*

```
Unexpected
```

A character that cannot start what is expected here.

<sub>[stdlib/Json.sl:53](../../stdlib/Json.sl#L53)</sub>

#### UnterminatedText *case*

```
UnterminatedText
```

A string with no closing quote.

<sub>[stdlib/Json.sl:56](../../stdlib/Json.sl#L56)</sub>

#### BadEscape *case*

```
BadEscape
```

A backslash followed by something that is not an escape.

<sub>[stdlib/Json.sl:59](../../stdlib/Json.sl#L59)</sub>

#### BadNumber *case*

```
BadNumber
```

Digits that are not a JSON number.

<sub>[stdlib/Json.sl:62](../../stdlib/Json.sl#L62)</sub>

#### BadLiteral *case*

```
BadLiteral
```

Something that started like `true`, `false` or `null` and was not.

<sub>[stdlib/Json.sl:65](../../stdlib/Json.sl#L65)</sub>

#### TrailingContent *case*

```
TrailingContent
```

A second value after the first. A JSON document is one value.

<sub>[stdlib/Json.sl:68](../../stdlib/Json.sl#L68)</sub>

#### TooDeep *case*

```
TooDeep
```

Nesting past `MaxDepth`.

<sub>[stdlib/Json.sl:71](../../stdlib/Json.sl#L71)</sub>

#### NotAnObject *case*

```
NotAnObject
```

A document that is not the object a type wants. Only reflection-based
reading raises this; parsing to a `JsonValue` takes any value.

<sub>[stdlib/Json.sl:75](../../stdlib/Json.sl#L75)</sub>

#### NotReflected *case*

```
NotReflected
```

A type with no field tables to map onto.

<sub>[stdlib/Json.sl:78](../../stdlib/Json.sl#L78)</sub>

### JsonIgnore *attribute*

```
attribute JsonIgnore
```

Leaves the field out of the document entirely, in both directions.

<sub>[stdlib/Json.sl:794](../../stdlib/Json.sl#L794)</sub>

### JsonName *attribute*

```
attribute JsonName
```

The name this field has in the document, when it differs from the field's.

<sub>[stdlib/Json.sl:791](../../stdlib/Json.sl#L791)</sub>

### JsonObject *class*

```
class JsonObject
```

The members of a JSON object, in the order they were written.

An `OrderedDictionary` rather than a `Dictionary`: order is what makes a
document read back the way it was written, which matters for a file a
person edits. The cost is that a lookup is a scan -- see the note there.

<sub>[stdlib/Json.sl:112](../../stdlib/Json.sl#L112)</sub>

#### Count *method*

```
nuint Count()
```

How many members there are. Members rather than distinct names: a
repeated name is kept, so this can exceed the number of names.

<sub>[stdlib/Json.sl:120](../../stdlib/Json.sl#L120)</sub>

#### NameAt *method*

```
String NameAt(nuint index)
```

The name at a position, in the order the document wrote them.

<sub>[stdlib/Json.sl:123](../../stdlib/Json.sl#L123)</sub>

#### ValueAt *method*

```
JsonValue ValueAt(nuint index)
```

The value at a position, pairing with `NameAt` at the same index.

<sub>[stdlib/Json.sl:126](../../stdlib/Json.sl#L126)</sub>

#### Add *method*

```
void Add(String name, JsonValue value)
```

Adds a member. A repeated name is kept rather than replaced, because
that is what the document said; `Find` answers with the first.

<sub>[stdlib/Json.sl:130](../../stdlib/Json.sl#L130)</sub>

#### Set *method*

```
void Set(String name, JsonValue value)
```

Replaces the value of a name, or adds it.

<sub>[stdlib/Json.sl:133](../../stdlib/Json.sl#L133)</sub>

#### IndexOf *method*

```
Optional<nuint> IndexOf(String name)
```

Where a name is, or `None`. One lookup rather than the two that asking
whether it is there and then asking for it would cost.

<sub>[stdlib/Json.sl:137](../../stdlib/Json.sl#L137)</sub>

#### Has *method*

```
bool Has(String name)
```

Whether a member of that name is there. A scan, so `IndexOf` once
beats this followed by a lookup.

<sub>[stdlib/Json.sl:141](../../stdlib/Json.sl#L141)</sub>

#### Find *method*

```
JsonValue Find(String name)
```

The value of a name, or `Null` when it is not there. A document that
does not mention a field and one that says `null` are the same thing to
a reader that has a default already.

<sub>[stdlib/Json.sl:146](../../stdlib/Json.sl#L146)</sub>

#### Remove *method*

```
bool Remove(String name)
```

Removes the first member of that name, answering whether there was one.

<sub>[stdlib/Json.sl:149](../../stdlib/Json.sl#L149)</sub>

### JsonValue *variant*

```
variant JsonValue
```

A JSON document, or any part of one.

Exactly the six things the grammar has. A variant rather than a class with
a kind field, so reading the wrong one is a compile error rather than a
null: `case Text t:` is the only way to reach `t.Value`.

<sub>[stdlib/Json.sl:159](../../stdlib/Json.sl#L159)</sub>

#### Null *case*

```
Null
```

The literal `null`. Also what `JsonObject.Find` answers for a name the
document does not mention, since a reader with a default cannot tell
the two apart and neither should have to.

<sub>[stdlib/Json.sl:163](../../stdlib/Json.sl#L163)</sub>

#### Bool *case*

```
Bool(bool Value)
```

`true` or `false`.

<sub>[stdlib/Json.sl:166](../../stdlib/Json.sl#L166)</sub>

#### Number *case*

```
Number(double Value)
```

A number. JSON has only the one numeric type and it is a double, so an
integer past 2^53 has already lost precision by the time it is here.

<sub>[stdlib/Json.sl:170](../../stdlib/Json.sl#L170)</sub>

#### Text *case*

```
Text(String Value)
```

A string, decoded: the escapes are gone and the text is what they meant.

<sub>[stdlib/Json.sl:173](../../stdlib/Json.sl#L173)</sub>

#### Array *case*

```
Array(List<JsonValue> Items)
```

An array, in document order.

<sub>[stdlib/Json.sl:176](../../stdlib/Json.sl#L176)</sub>

#### Object *case*

```
Object(JsonObject Members)
```

An object, in the order its members were written.

<sub>[stdlib/Json.sl:179](../../stdlib/Json.sl#L179)</sub>

## Functions

### BoolOr *function*

```
bool BoolOr(JsonValue value, bool fallback)
```

The value of a `Bool`, or the fallback. A `Number` of 1 is not true here;
only the JSON literals are.

<sub>[stdlib/Json.sl:227](../../stdlib/Json.sl#L227)</sub>

### Describe *function*

```
String Describe(JsonError error)
```

A sentence describing an error, for a message a person will read.

<sub>[stdlib/Json.sl:82](../../stdlib/Json.sl#L82)</sub>

### IntegerOr *function*

```
long IntegerOr(JsonValue value, long fallback)
```

The value of a `Number` truncated toward zero, or the fallback.

Truncation, not rounding: `3.9` is 3. JSON has one number type, so this is
how a field that is conceptually an integer is read back, and a value past
what a `long` holds is not detected.

<sub>[stdlib/Json.sl:220](../../stdlib/Json.sl#L220)</sub>

### IsNull *function*

```
bool IsNull(JsonValue value)
```

True for the one case that carries nothing.

<sub>[stdlib/Json.sl:233](../../stdlib/Json.sl#L233)</sub>

### ItemsOf *function*

```
List<JsonValue> ItemsOf(JsonValue value)
```

The elements of an `Array`, or an empty list.

<sub>[stdlib/Json.sl:242](../../stdlib/Json.sl#L242)</sub>

### MembersOf *function*

```
JsonObject MembersOf(JsonValue value)
```

The members of an `Object`, or an empty one.

<sub>[stdlib/Json.sl:236](../../stdlib/Json.sl#L236)</sub>

### NewArray *function*

```
JsonValue NewArray()
```

An empty array, ready to add to.

<sub>[stdlib/Json.sl:183](../../stdlib/Json.sl#L183)</sub>

### NewObject *function*

```
JsonValue NewObject()
```

An empty object, ready to add to.

<sub>[stdlib/Json.sl:186](../../stdlib/Json.sl#L186)</sub>

### NumberOf *function*

```
JsonValue NumberOf(long value)
```

A whole number as a JSON number, which has only the one numeric type.

Not `FromInteger`: `Standard.Text` is imported everywhere and has one of
those, and two functions of a name reached without a prefix is an ambiguity
at every call rather than at this declaration.

<sub>[stdlib/Json.sl:193](../../stdlib/Json.sl#L193)</sub>

### NumberOr *function*

```
double NumberOr(JsonValue value, double fallback)
```

The value of a `Number`, or the fallback for anything else. A JSON number
is a double, so a large integer has already lost precision by here.

<sub>[stdlib/Json.sl:210](../../stdlib/Json.sl#L210)</sub>

### Parse *function*

```
Result<JsonValue, JsonError> Parse(String text)
```

Reads a whole document. Trailing content is an error rather than ignored,
because a document with a second value in it is a document the writer meant
something else by.

<sub>[stdlib/Json.sl:639](../../stdlib/Json.sl#L639)</sub>

### Populate *function*

```
JsonError Populate<T>(T value, String text)
```

Fills an object's fields from a document.

The object is the program's, made the ordinary way, so its constructor has
already run and its invariants already hold. A field the document does not
mention is left alone, which is what makes this safe: the value that stays
is the one the constructor chose.

A nested object is filled in place and never replaced, for the same reason.
A document naming a nested object the constructor left null is skipped
rather than allocated into, since nothing here could give the rest of that
object's fields a value.

<sub>[stdlib/Json.sl:943](../../stdlib/Json.sl#L943)</sub>

### PopulateFrom *function*

```
JsonError PopulateFrom<T>(T value, JsonValue document)
```

The same, from a document already parsed.

<sub>[stdlib/Json.sl:951](../../stdlib/Json.sl#L951)</sub>

### Serialize *function*

```
String Serialize<T>(T value)
```

The document as text.

<sub>[stdlib/Json.sl:816](../../stdlib/Json.sl#L816)</sub>

### SerializeIndented *function*

```
String SerializeIndented<T>(T value)
```

The same, indented.

<sub>[stdlib/Json.sl:819](../../stdlib/Json.sl#L819)</sub>

### TextOr *function*

```
String TextOr(JsonValue value, String fallback)
```

The text of a `Text`, or the fallback for anything else.

<sub>[stdlib/Json.sl:203](../../stdlib/Json.sl#L203)</sub>

### ToValue *function*

```
JsonValue ToValue<T>(T value)
```

The document a value would produce, as a `JsonValue`.

Reads the field tables of `[Reflect] T`, walking into a nested class or
struct rather than stopping at it. A field of a kind with no JSON spelling
-- a pointer, a delegate, an array -- is left out rather than guessed at.

<sub>[stdlib/Json.sl:811](../../stdlib/Json.sl#L811)</sub>

### Write *function*

```
String Write(JsonValue value)
```

The document as text, on one line.

<sub>[stdlib/Json.sl:654](../../stdlib/Json.sl#L654)</sub>

### WriteIndented *function*

```
String WriteIndented(JsonValue value)
```

The document as text, indented two spaces a level.

<sub>[stdlib/Json.sl:661](../../stdlib/Json.sl#L661)</sub>

## Constants

### MaxDepth *constant*

```
const nuint MaxDepth = 128
```

How far in the parser will nest before giving up.

A document is nested by recursion, so the limit is really about the stack.
It exists because a hostile document is one line -- ten thousand `[` -- and
the alternative to a limit is a crash that looks like a compiler bug.

<sub>[stdlib/Json.sl:103](../../stdlib/Json.sl#L103)</sub>

