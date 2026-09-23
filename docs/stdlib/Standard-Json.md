# Standard.Json

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

JSON, in two layers.

The lower one is a document: `Json.Parse` gives a `JsonValue`, a variant that
is exactly one of the six things JSON has, and `ToJsonText` puts one back. Nothing
about it needs a type, so it handles a document whose shape a program learns
at run time -- which is most of them.

The upper one maps a document onto a type, through the field tables a
`[Reflect]` type carries (§6). `Serialize` reads an object's fields and
`PopulateObject` writes them.

**Why the mapping fills an object rather than making one.** A constructor is
what establishes a type's invariants, and a deserializer that allocated
zeroed memory would produce an object whose non-nullable fields were null --
a hole in the type system rather than a value. So `PopulateObject` takes an
instance the program made, and there is no `Deserialize<T>` that makes one:
the caller writes `new T()` itself, where the constructor it wants is in
reach.

## Contents

**Types** &nbsp; [JsonCreate](#jsoncreate-attribute) &middot; [JsonError](#jsonerror-enum) &middot; [JsonIgnore](#jsonignore-attribute) &middot; [JsonName](#jsonname-attribute) &middot; [JsonObject](#jsonobject-class) &middot; [JsonValue](#jsonvalue-variant)

**Functions** &nbsp; [CreateJsonArray](#createjsonarray-function) &middot; [CreateJsonNumber](#createjsonnumber-function) &middot; [CreateJsonObject](#createjsonobject-function) &middot; [DescribeJsonError](#describejsonerror-function) &middot; [GetBoolOrDefault](#getboolordefault-function) &middot; [GetIntegerOrDefault](#getintegerordefault-function) &middot; [GetItems](#getitems-function) &middot; [GetMembers](#getmembers-function) &middot; [GetNumberOrDefault](#getnumberordefault-function) &middot; [GetTextOrDefault](#gettextordefault-function) &middot; [IsNull](#isnull-function) &middot; [Parse](#parse-function) &middot; [PopulateObject](#populateobject-function) &middot; [PopulateObject](#populateobject-function) &middot; [Serialize](#serialize-function) &middot; [SerializeIndented](#serializeindented-function) &middot; [ToJsonText](#tojsontext-function) &middot; [ToJsonTextIndented](#tojsontextindented-function) &middot; [ToJsonValue](#tojsonvalue-function)

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

<sub>[stdlib/Json.sl:1083](../../stdlib/Json.sl#L1083)</sub>

### JsonError *enum*

```
enum JsonError
```

Why a document could not be read.

<sub>[stdlib/Json.sl:50](../../stdlib/Json.sl#L50)</sub>

#### None *case*

```
None
```

Nothing went wrong.

<sub>[stdlib/Json.sl:53](../../stdlib/Json.sl#L53)</sub>

#### Unexpected *case*

```
Unexpected
```

A character that cannot start what is expected here, or a control
character inside a string that was not escaped.

<sub>[stdlib/Json.sl:57](../../stdlib/Json.sl#L57)</sub>

#### UnterminatedText *case*

```
UnterminatedText
```

A string with no closing quote.

<sub>[stdlib/Json.sl:60](../../stdlib/Json.sl#L60)</sub>

#### BadEscape *case*

```
BadEscape
```

A backslash followed by something that is not an escape.

<sub>[stdlib/Json.sl:63](../../stdlib/Json.sl#L63)</sub>

#### BadNumber *case*

```
BadNumber
```

Digits that are not a JSON number.

<sub>[stdlib/Json.sl:66](../../stdlib/Json.sl#L66)</sub>

#### BadLiteral *case*

```
BadLiteral
```

Something that started like `true`, `false` or `null` and was not.

<sub>[stdlib/Json.sl:69](../../stdlib/Json.sl#L69)</sub>

#### TrailingContent *case*

```
TrailingContent
```

A second value after the first. A JSON document is one value.

<sub>[stdlib/Json.sl:72](../../stdlib/Json.sl#L72)</sub>

#### TooDeep *case*

```
TooDeep
```

Nesting past `MaxDepth`.

<sub>[stdlib/Json.sl:75](../../stdlib/Json.sl#L75)</sub>

#### NotAnObject *case*

```
NotAnObject
```

A document that is not the object a type wants. Only reflection-based
reading raises this; parsing to a `JsonValue` takes any value.

<sub>[stdlib/Json.sl:79](../../stdlib/Json.sl#L79)</sub>

#### NotReflected *case*

```
NotReflected
```

A type with no field tables to map onto.

<sub>[stdlib/Json.sl:82](../../stdlib/Json.sl#L82)</sub>

### JsonIgnore *attribute*

```
attribute JsonIgnore
```

Leaves the field out of the document entirely, in both directions.

<sub>[stdlib/Json.sl:1073](../../stdlib/Json.sl#L1073)</sub>

### JsonName *attribute*

```
attribute JsonName
```

The name this field has in the document, when it differs from the field's.

<sub>[stdlib/Json.sl:1070](../../stdlib/Json.sl#L1070)</sub>

### JsonObject *class*

```
class JsonObject
```

The members of a JSON object, in the order they were written.

An `OrderedDictionary` rather than a `Dictionary`: order is what makes a
document read back the way it was written, which matters for a file a
person edits. The cost is that a lookup is a scan -- see the note there.

<sub>[stdlib/Json.sl:121](../../stdlib/Json.sl#L121)</sub>

#### Count *property*

```
nuint Count { get; }
```

How many members there are. Members rather than distinct names: a
repeated name is kept, so this can exceed the number of names.

<sub>[stdlib/Json.sl:130](../../stdlib/Json.sl#L130)</sub>

#### GetNameAt *method*

```
String GetNameAt(nuint index)
```

The name at a position, in the order the document wrote them.

<sub>[stdlib/Json.sl:133](../../stdlib/Json.sl#L133)</sub>

#### GetValueAt *method*

```
JsonValue GetValueAt(nuint index)
```

The value at a position, pairing with `GetNameAt` at the same index.

**See also** &nbsp; [JsonObject.GetNameAt](#getnameat-method)

<sub>[stdlib/Json.sl:138](../../stdlib/Json.sl#L138)</sub>

#### Add *method*

```
void Add(String name, JsonValue value)
```

Adds a member. A repeated name is kept rather than replaced, because
that is what the document said; `Find` answers with the first.

**See also** &nbsp; [JsonObject.Find](#find-method)

<sub>[stdlib/Json.sl:144](../../stdlib/Json.sl#L144)</sub>

#### SetValue *method*

```
void SetValue(String name, JsonValue value)
```

Replaces the value of a name, or adds it.

<sub>[stdlib/Json.sl:147](../../stdlib/Json.sl#L147)</sub>

#### IndexOf *method*

```
Optional<nuint> IndexOf(String name)
```

Where a name is, or `None`. One lookup rather than the two that asking
whether it is there and then asking for it would cost.

<sub>[stdlib/Json.sl:151](../../stdlib/Json.sl#L151)</sub>

#### ContainsKey *method*

```
bool ContainsKey(String name)
```

Whether a member of that name is there. A scan, so `IndexOf` once
beats this followed by a lookup.

**See also** &nbsp; [JsonObject.IndexOf](#indexof-method)

<sub>[stdlib/Json.sl:157](../../stdlib/Json.sl#L157)</sub>

#### Find *method*

```
JsonValue Find(String name)
```

The value of a name, or `Null` when it is not there. A document that
does not mention a field and one that says `null` are the same thing to
a reader that has a default already.

<sub>[stdlib/Json.sl:162](../../stdlib/Json.sl#L162)</sub>

#### Remove *method*

```
bool Remove(String name)
```

Removes the first member of that name, answering whether there was one.

<sub>[stdlib/Json.sl:165](../../stdlib/Json.sl#L165)</sub>

### JsonValue *variant*

```
variant JsonValue
```

A JSON document, or any part of one.

Exactly the six things the grammar has. A variant rather than a class with
a kind field, so reading the wrong one is a compile error rather than a
null: `case Text t:` is the only way to reach `t.Value`.

<sub>[stdlib/Json.sl:175](../../stdlib/Json.sl#L175)</sub>

#### Null *case*

```
Null
```

The literal `null`. Also what `JsonObject.Find` answers for a name the
document does not mention, since a reader with a default cannot tell
the two apart and neither should have to.

<sub>[stdlib/Json.sl:180](../../stdlib/Json.sl#L180)</sub>

#### Bool *case*

```
Bool(bool Value)
```

`true` or `false`.

<sub>[stdlib/Json.sl:183](../../stdlib/Json.sl#L183)</sub>

#### Number *case*

```
Number(double Value)
```

A number. JSON has only the one numeric type and it is a double, so an
integer past 2^53 has already lost precision by the time it is here.
A parsed one is always finite; `ToJsonText` says what becomes of one that
is not.

<sub>[stdlib/Json.sl:189](../../stdlib/Json.sl#L189)</sub>

#### Text *case*

```
Text(String Value)
```

A string, decoded: the escapes are gone and the text is what they meant.

<sub>[stdlib/Json.sl:192](../../stdlib/Json.sl#L192)</sub>

#### Array *case*

```
Array(List<JsonValue> Items)
```

An array, in document order.

<sub>[stdlib/Json.sl:195](../../stdlib/Json.sl#L195)</sub>

#### Object *case*

```
Object(JsonObject Members)
```

An object, in the order its members were written.

<sub>[stdlib/Json.sl:198](../../stdlib/Json.sl#L198)</sub>

## Functions

### CreateJsonArray *function*

```
JsonValue CreateJsonArray()
```

An empty array, ready to add to.

<sub>[stdlib/Json.sl:202](../../stdlib/Json.sl#L202)</sub>

### CreateJsonNumber *function*

```
JsonValue CreateJsonNumber(long value)
```

A whole number as a JSON number, which has only the one numeric type.

Not `FromInteger`: `Standard.Text` is imported everywhere and has one of
those, and two functions of a name reached without a prefix is an ambiguity
at every call rather than at this declaration.

<sub>[stdlib/Json.sl:212](../../stdlib/Json.sl#L212)</sub>

### CreateJsonObject *function*

```
JsonValue CreateJsonObject()
```

An empty object, ready to add to.

<sub>[stdlib/Json.sl:205](../../stdlib/Json.sl#L205)</sub>

### DescribeJsonError *function*

```
String DescribeJsonError(JsonError error)
```

A sentence describing an error, for a message a person will read.

<sub>[stdlib/Json.sl:86](../../stdlib/Json.sl#L86)</sub>

### GetBoolOrDefault *function*

```
bool GetBoolOrDefault(JsonValue value, bool fallback)
```

The value of a `Bool`, or the fallback. A `Number` of 1 is not true here;
only the JSON literals are.

<sub>[stdlib/Json.sl:259](../../stdlib/Json.sl#L259)</sub>

### GetIntegerOrDefault *function*

```
long GetIntegerOrDefault(JsonValue value, long fallback)
```

The value of a `Number` truncated toward zero, or the fallback.

Truncation, not rounding: `3.9` is 3. JSON has one number type, so this is
how a field that is conceptually an integer is read back. A value past what
a `long` holds answers the fallback, as a value of the wrong type does.

<sub>[stdlib/Json.sl:243](../../stdlib/Json.sl#L243)</sub>

### GetItems *function*

```
List<JsonValue> GetItems(JsonValue value)
```

The elements of an `Array`, or an empty list.

<sub>[stdlib/Json.sl:278](../../stdlib/Json.sl#L278)</sub>

### GetMembers *function*

```
JsonObject GetMembers(JsonValue value)
```

The members of an `Object`, or an empty one.

<sub>[stdlib/Json.sl:270](../../stdlib/Json.sl#L270)</sub>

### GetNumberOrDefault *function*

```
double GetNumberOrDefault(JsonValue value, double fallback)
```

The value of a `Number`, or the fallback for anything else. A JSON number
is a double, so a large integer has already lost precision by here.

<sub>[stdlib/Json.sl:231](../../stdlib/Json.sl#L231)</sub>

### GetTextOrDefault *function*

```
String GetTextOrDefault(JsonValue value, String fallback)
```

The text of a `Text`, or the fallback for anything else.

<sub>[stdlib/Json.sl:222](../../stdlib/Json.sl#L222)</sub>

### IsNull *function*

```
bool IsNull(JsonValue value)
```

True for the one case that carries nothing.

<sub>[stdlib/Json.sl:267](../../stdlib/Json.sl#L267)</sub>

### Parse *function*

```
Result<JsonValue, JsonError> Parse(String text)
```

Reads a whole document. Trailing content is an error rather than ignored,
because a document with a second value in it is a document the writer meant
something else by.

**Fails with**

- [JsonError.Unexpected](#unexpected-case) — a character that cannot start what is expected, or an unescaped control character in a string
- [JsonError.UnterminatedText](#unterminatedtext-case) — a string with no closing quote
- [JsonError.BadEscape](#badescape-case) — a backslash followed by something that is not an escape
- [JsonError.BadNumber](#badnumber-case) — digits that are not a JSON number, or one too large for a double
- [JsonError.BadLiteral](#badliteral-case) — something that started like `true`, `false` or `null` and was not
- [JsonError.TooDeep](#toodeep-case) — nesting past `MaxDepth`
- [JsonError.TrailingContent](#trailingcontent-case) — a second value after the first

**See also** &nbsp; [Json.ToJsonText](#tojsontext-function)

<sub>[stdlib/Json.sl:847](../../stdlib/Json.sl#L847)</sub>

### PopulateObject *function*

```
JsonError PopulateObject<T>(T value, String text)
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

**Type parameters**

- `T` — a `[Reflect]` type, whose field tables say what there is to fill

**Fails with**

- [JsonError.Unexpected](#unexpected-case) — a character that cannot start what is expected, or an unescaped control character in a string
- [JsonError.UnterminatedText](#unterminatedtext-case) — a string with no closing quote
- [JsonError.BadEscape](#badescape-case) — a backslash followed by something that is not an escape
- [JsonError.BadNumber](#badnumber-case) — digits that are not a JSON number, or one too large for a double
- [JsonError.BadLiteral](#badliteral-case) — something that started like `true`, `false` or `null` and was not
- [JsonError.TooDeep](#toodeep-case) — nesting past `MaxDepth`
- [JsonError.TrailingContent](#trailingcontent-case) — a second value after the first
- [JsonError.NotAnObject](#notanobject-case) — the document is not an object
- [JsonError.NotReflected](#notreflected-case) — `T` carries no field tables

**See also** &nbsp; [Json.Serialize](#serialize-function)

<sub>[stdlib/Json.sl:1284](../../stdlib/Json.sl#L1284)</sub>

### PopulateObject *function*

```
JsonError PopulateObject<T>(T value, JsonValue document)
```

The same, from a document already parsed.

**Type parameters**

- `T` — a `[Reflect]` type, whose field tables say what there is to fill

**Fails with**

- [JsonError.NotAnObject](#notanobject-case) — the document is not an object
- [JsonError.NotReflected](#notreflected-case) — `T` carries no field tables

**See also** &nbsp; [Json.Serialize](#serialize-function)

<sub>[stdlib/Json.sl:1299](../../stdlib/Json.sl#L1299)</sub>

### Serialize *function*

```
String Serialize<T>(T value)
```

The document as text.

**Type parameters**

- `T` — a `[Reflect]` type

**See also** &nbsp; [Json.PopulateObject](#populateobject-function)

<sub>[stdlib/Json.sl:1102](../../stdlib/Json.sl#L1102)</sub>

### SerializeIndented *function*

```
String SerializeIndented<T>(T value)
```

The same, indented.

**Type parameters**

- `T` — a `[Reflect]` type

**See also** &nbsp; [Json.Serialize](#serialize-function)

<sub>[stdlib/Json.sl:1108](../../stdlib/Json.sl#L1108)</sub>

### ToJsonText *function*

```
String ToJsonText(JsonValue value)
```

The document as text, on one line.

A `Number` that is infinite or NaN is written as `null`, since JSON has no
spelling for either. `JSON.stringify` does the same, and it reads back as a
value absent rather than as some other number.

**See also** &nbsp; [Json.Parse](#parse-function) &middot; [Json.ToJsonTextIndented](#tojsontextindented-function)

<sub>[stdlib/Json.sl:873](../../stdlib/Json.sl#L873)</sub>

### ToJsonTextIndented *function*

```
String ToJsonTextIndented(JsonValue value)
```

The document as text, indented two spaces a level.

**See also** &nbsp; [Json.ToJsonText](#tojsontext-function)

<sub>[stdlib/Json.sl:883](../../stdlib/Json.sl#L883)</sub>

### ToJsonValue *function*

```
JsonValue ToJsonValue<T>(T value)
```

The document a value would produce, as a `JsonValue`.

Reads the field tables of `[Reflect] T`, walking into a nested class or
struct rather than stopping at it. A field of a kind with no JSON spelling
-- a pointer, a delegate, an array -- is left out rather than guessed at.

**Type parameters**

- `T` — a `[Reflect]` type, whose field tables say what there is to write

**See also** &nbsp; [Json.Serialize](#serialize-function)

<sub>[stdlib/Json.sl:1093](../../stdlib/Json.sl#L1093)</sub>

## Constants

### MaxDepth *constant*

```
const nuint MaxDepth = 128
```

How far in the parser will nest before giving up.

A document is nested by recursion, so the limit is really about the stack.
It exists because a hostile document is one line -- ten thousand `[` -- and
the alternative to a limit is a crash that looks like a compiler bug.

**Value** &nbsp; 128 levels.

**See also** &nbsp; [JsonError.TooDeep](#toodeep-case)

<sub>[stdlib/Json.sl:112](../../stdlib/Json.sl#L112)</sub>

