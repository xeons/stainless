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

**What it makes inside that object, it makes as `new` would.** A nested
object the document describes and the field lacks, and each object element
of an array it allocates, is made by `Reflection.CreateInstance`, which
runs the type's public parameterless constructor. The document then fills
it, and it is stored only if it is complete: every `required` member named
by the document with a value of its type, and nothing whose type has no
zero value left null. Otherwise the whole call fails with
`JsonError.MissingMember`, and what was made is released rather than left
reachable.

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
is what knows whether the document may decide the object is there. It is
made as `new T()` would make it and then filled, so its type needs a
public parameterless constructor. A `required` field needs no mark: the
document MUST supply it, so it is always made.

<sub>[stdlib/Json/Json.sl:970](../../stdlib/Json/Json.sl#L970)</sub>

### JsonError *enum*

```
enum JsonError
```

Why a document could not be read.

<sub>[stdlib/Json/JsonError.sl:32](../../stdlib/Json/JsonError.sl#L32)</sub>

#### None *case*

```
None
```

Nothing went wrong.

<sub>[stdlib/Json/JsonError.sl:35](../../stdlib/Json/JsonError.sl#L35)</sub>

#### Unexpected *case*

```
Unexpected
```

A character that cannot start what is expected here, or a control
character inside a string that was not escaped.

<sub>[stdlib/Json/JsonError.sl:39](../../stdlib/Json/JsonError.sl#L39)</sub>

#### UnterminatedText *case*

```
UnterminatedText
```

A string with no closing quote.

<sub>[stdlib/Json/JsonError.sl:42](../../stdlib/Json/JsonError.sl#L42)</sub>

#### BadEscape *case*

```
BadEscape
```

A backslash followed by something that is not an escape.

<sub>[stdlib/Json/JsonError.sl:45](../../stdlib/Json/JsonError.sl#L45)</sub>

#### BadNumber *case*

```
BadNumber
```

Digits that are not a JSON number.

<sub>[stdlib/Json/JsonError.sl:48](../../stdlib/Json/JsonError.sl#L48)</sub>

#### BadLiteral *case*

```
BadLiteral
```

Something that started like `true`, `false` or `null` and was not.

<sub>[stdlib/Json/JsonError.sl:51](../../stdlib/Json/JsonError.sl#L51)</sub>

#### TrailingContent *case*

```
TrailingContent
```

A second value after the first. A JSON document is one value.

<sub>[stdlib/Json/JsonError.sl:54](../../stdlib/Json/JsonError.sl#L54)</sub>

#### TooDeep *case*

```
TooDeep
```

Nesting past `MaxDepth`.

<sub>[stdlib/Json/JsonError.sl:57](../../stdlib/Json/JsonError.sl#L57)</sub>

#### NotAnObject *case*

```
NotAnObject
```

A document that is not the object a type wants. Only reflection-based
reading raises this; parsing to a `JsonValue` takes any value.

<sub>[stdlib/Json/JsonError.sl:61](../../stdlib/Json/JsonError.sl#L61)</sub>

#### NotReflected *case*

```
NotReflected
```

A type with no field tables to map onto.

<sub>[stdlib/Json/JsonError.sl:64](../../stdlib/Json/JsonError.sl#L64)</sub>

#### MissingMember *case*

```
MissingMember
```

Something the reader made -- a nested object, or an array and its
elements -- lacks a value its type cannot do without: a `required`
member the document does not give a value of its type, or a member or
element whose type is never null that nothing filled. What was made is
discarded.

<sub>[stdlib/Json/JsonError.sl:71](../../stdlib/Json/JsonError.sl#L71)</sub>

#### NotCreatable *case*

```
NotCreatable
```

The document needs an object made, and its type has no public
parameterless constructor to make it with.

<sub>[stdlib/Json/JsonError.sl:75](../../stdlib/Json/JsonError.sl#L75)</sub>

### JsonIgnore *attribute*

```
attribute JsonIgnore
```

Leaves the field out of the document entirely, in both directions.

<sub>[stdlib/Json/Json.sl:960](../../stdlib/Json/Json.sl#L960)</sub>

### JsonName *attribute*

```
attribute JsonName
```

The name this field has in the document, when it differs from the field's.

<sub>[stdlib/Json/Json.sl:957](../../stdlib/Json/Json.sl#L957)</sub>

### JsonObject *class*

```
class JsonObject
```

The members of a JSON object, in the order they were written.

An `OrderedDictionary` rather than a `Dictionary`: order is what makes a
document read back the way it was written, which matters for a file a
person edits. The cost is that a lookup is a scan -- see the note there.

<sub>[stdlib/Json/JsonObject.sl:36](../../stdlib/Json/JsonObject.sl#L36)</sub>

#### Count *property*

```
nuint Count { get; }
```

How many members there are. Members rather than distinct names: a
repeated name is kept, so this can exceed the number of names.

<sub>[stdlib/Json/JsonObject.sl:45](../../stdlib/Json/JsonObject.sl#L45)</sub>

#### GetNameAt *method*

```
String GetNameAt(nuint index)
```

The name at a position, in the order the document wrote them.

<sub>[stdlib/Json/JsonObject.sl:48](../../stdlib/Json/JsonObject.sl#L48)</sub>

#### GetValueAt *method*

```
JsonValue GetValueAt(nuint index)
```

The value at a position, pairing with `GetNameAt` at the same index.

**See also** &nbsp; [JsonObject.GetNameAt](#getnameat-method)

<sub>[stdlib/Json/JsonObject.sl:53](../../stdlib/Json/JsonObject.sl#L53)</sub>

#### Add *method*

```
void Add(String name, JsonValue value)
```

Adds a member. A repeated name is kept rather than replaced, because
that is what the document said; `GetValueOrNull` answers with the first.

**See also** &nbsp; [JsonObject.GetValueOrNull](#getvalueornull-method)

<sub>[stdlib/Json/JsonObject.sl:59](../../stdlib/Json/JsonObject.sl#L59)</sub>

#### SetValue *method*

```
void SetValue(String name, JsonValue value)
```

Replaces the value of a name, or adds it.

<sub>[stdlib/Json/JsonObject.sl:62](../../stdlib/Json/JsonObject.sl#L62)</sub>

#### IndexOf *method*

```
Optional<nuint> IndexOf(String name)
```

Where a name is, or `None`. One lookup rather than the two that asking
whether it is there and then asking for it would cost.

<sub>[stdlib/Json/JsonObject.sl:66](../../stdlib/Json/JsonObject.sl#L66)</sub>

#### ContainsKey *method*

```
bool ContainsKey(String name)
```

Whether a member of that name is there. A scan, so `IndexOf` once
beats this followed by a lookup.

**See also** &nbsp; [JsonObject.IndexOf](#indexof-method)

<sub>[stdlib/Json/JsonObject.sl:72](../../stdlib/Json/JsonObject.sl#L72)</sub>

#### GetValueOrNull *method*

```
JsonValue GetValueOrNull(String name)
```

The value of a name, or `Null` when it is not there. A document that
does not mention a field and one that says `null` are the same thing to
a reader that has a default already.

<sub>[stdlib/Json/JsonObject.sl:77](../../stdlib/Json/JsonObject.sl#L77)</sub>

#### Remove *method*

```
bool Remove(String name)
```

Removes the first member of that name, answering whether there was one.

<sub>[stdlib/Json/JsonObject.sl:81](../../stdlib/Json/JsonObject.sl#L81)</sub>

### JsonValue *variant*

```
variant JsonValue
```

A JSON document, or any part of one.

Exactly the six things the grammar has. A variant rather than a class with
a kind field, so reading the wrong one is a compile error rather than a
null: `case Text t:` is the only way to reach `t.Value`.

<sub>[stdlib/Json/JsonValue.sl:36](../../stdlib/Json/JsonValue.sl#L36)</sub>

#### Null *case*

```
Null
```

The literal `null`. Also what `JsonObject.GetValueOrNull` answers for a name the
document does not mention, since a reader with a default cannot tell
the two apart and neither should have to.

<sub>[stdlib/Json/JsonValue.sl:41](../../stdlib/Json/JsonValue.sl#L41)</sub>

#### Bool *case*

```
Bool(bool Value)
```

`true` or `false`.

<sub>[stdlib/Json/JsonValue.sl:44](../../stdlib/Json/JsonValue.sl#L44)</sub>

#### Number *case*

```
Number(double Value)
```

A number. JSON has only the one numeric type and it is a double, so an
integer past 2^53 has already lost precision by the time it is here.
A parsed one is always finite; `ToJsonText` says what becomes of one that
is not.

<sub>[stdlib/Json/JsonValue.sl:50](../../stdlib/Json/JsonValue.sl#L50)</sub>

#### Text *case*

```
Text(String Value)
```

A string, decoded: the escapes are gone and the text is what they meant.

<sub>[stdlib/Json/JsonValue.sl:53](../../stdlib/Json/JsonValue.sl#L53)</sub>

#### Array *case*

```
Array(List<JsonValue> Items)
```

An array, in document order.

<sub>[stdlib/Json/JsonValue.sl:56](../../stdlib/Json/JsonValue.sl#L56)</sub>

#### Object *case*

```
Object(JsonObject Members)
```

An object, in the order its members were written.

<sub>[stdlib/Json/JsonValue.sl:59](../../stdlib/Json/JsonValue.sl#L59)</sub>

## Functions

### CreateJsonArray *function*

```
JsonValue CreateJsonArray()
```

An empty array, ready to add to.

<sub>[stdlib/Json/Json.sl:89](../../stdlib/Json/Json.sl#L89)</sub>

### CreateJsonNumber *function*

```
JsonValue CreateJsonNumber(long value)
```

A whole number as a JSON number, which has only the one numeric type.

Not `FromInteger`: `Standard.Text` is imported everywhere and has one of
those, and two functions of a name reached without a prefix is an ambiguity
at every call rather than at this declaration.

<sub>[stdlib/Json/Json.sl:99](../../stdlib/Json/Json.sl#L99)</sub>

### CreateJsonObject *function*

```
JsonValue CreateJsonObject()
```

An empty object, ready to add to.

<sub>[stdlib/Json/Json.sl:92](../../stdlib/Json/Json.sl#L92)</sub>

### DescribeJsonError *function*

```
String DescribeJsonError(JsonError error)
```

A sentence describing an error, for a message a person will read.

<sub>[stdlib/Json/Json.sl:58](../../stdlib/Json/Json.sl#L58)</sub>

### GetBoolOrDefault *function*

```
bool GetBoolOrDefault(JsonValue value, bool fallback)
```

The value of a `Bool`, or the fallback. A `Number` of 1 is not true here;
only the JSON literals are.

<sub>[stdlib/Json/Json.sl:146](../../stdlib/Json/Json.sl#L146)</sub>

### GetIntegerOrDefault *function*

```
long GetIntegerOrDefault(JsonValue value, long fallback)
```

The value of a `Number` truncated toward zero, or the fallback.

Truncation, not rounding: `3.9` is 3. JSON has one number type, so this is
how a field that is conceptually an integer is read back. A value past what
a `long` holds answers the fallback, as a value of the wrong type does.

<sub>[stdlib/Json/Json.sl:130](../../stdlib/Json/Json.sl#L130)</sub>

### GetItems *function*

```
List<JsonValue> GetItems(JsonValue value)
```

The elements of an `Array`, or an empty list.

<sub>[stdlib/Json/Json.sl:165](../../stdlib/Json/Json.sl#L165)</sub>

### GetMembers *function*

```
JsonObject GetMembers(JsonValue value)
```

The members of an `Object`, or an empty one.

<sub>[stdlib/Json/Json.sl:157](../../stdlib/Json/Json.sl#L157)</sub>

### GetNumberOrDefault *function*

```
double GetNumberOrDefault(JsonValue value, double fallback)
```

The value of a `Number`, or the fallback for anything else. A JSON number
is a double, so a large integer has already lost precision by here.

<sub>[stdlib/Json/Json.sl:118](../../stdlib/Json/Json.sl#L118)</sub>

### GetTextOrDefault *function*

```
String GetTextOrDefault(JsonValue value, String fallback)
```

The text of a `Text`, or the fallback for anything else.

<sub>[stdlib/Json/Json.sl:109](../../stdlib/Json/Json.sl#L109)</sub>

### IsNull *function*

```
bool IsNull(JsonValue value)
```

True for the one case that carries nothing.

<sub>[stdlib/Json/Json.sl:154](../../stdlib/Json/Json.sl#L154)</sub>

### Parse *function*

```
Result<JsonValue, JsonError> Parse(String text)
```

Reads a whole document. Trailing content is an error rather than ignored,
because a document with a second value in it is a document the writer meant
something else by.

**Fails with**

- [JsonError.Unexpected](#unexpected-case) -- a character that cannot start what is expected, or an unescaped control character in a string
- [JsonError.UnterminatedText](#unterminatedtext-case) -- a string with no closing quote
- [JsonError.BadEscape](#badescape-case) -- a backslash followed by something that is not an escape
- [JsonError.BadNumber](#badnumber-case) -- digits that are not a JSON number, or one too large for a double
- [JsonError.BadLiteral](#badliteral-case) -- something that started like `true`, `false` or `null` and was not
- [JsonError.TooDeep](#toodeep-case) -- nesting past `MaxDepth`
- [JsonError.TrailingContent](#trailingcontent-case) -- a second value after the first

**See also** &nbsp; [Json.ToJsonText](#tojsontext-function)

<sub>[stdlib/Json/Json.sl:734](../../stdlib/Json/Json.sl#L734)</sub>

### PopulateObject *function*

```
JsonError PopulateObject<T>(T value, String text)
```

Fills an object's fields from a document.

The object is the program's, made the ordinary way, so its constructor has
already run and its invariants already hold. A field the document does not
mention is left alone, which is what makes this safe: the value that stays
is the one the constructor chose. A member of the wrong type is skipped the
same way, and a `null` clears a field whose type allows one.

A nested object is filled in place and never replaced, for the same reason.
A document naming a nested object the constructor left null is skipped,
unless the field is `[JsonCreate]` or `required`; then the object is made
as `new` would make it, filled, and stored only once it is complete.

**A failure part-way leaves what was already written.** Every field the
object holds is still a value of its type, but not every one the document
named has been read. Nothing the call made and could not complete is
reachable from it.

**Type parameters**

- `T` -- a `[Reflect]` type, whose field tables say what there is to fill

**Fails with**

- [JsonError.Unexpected](#unexpected-case) -- a character that cannot start what is expected, or an unescaped control character in a string
- [JsonError.UnterminatedText](#unterminatedtext-case) -- a string with no closing quote
- [JsonError.BadEscape](#badescape-case) -- a backslash followed by something that is not an escape
- [JsonError.BadNumber](#badnumber-case) -- digits that are not a JSON number, or one too large for a double
- [JsonError.BadLiteral](#badliteral-case) -- something that started like `true`, `false` or `null` and was not
- [JsonError.TooDeep](#toodeep-case) -- nesting past `MaxDepth`
- [JsonError.TrailingContent](#trailingcontent-case) -- a second value after the first
- [JsonError.NotAnObject](#notanobject-case) -- the document is not an object
- [JsonError.NotReflected](#notreflected-case) -- `T` carries no field tables
- [JsonError.MissingMember](#missingmember-case) -- something made here lacks a value its type needs
- [JsonError.NotCreatable](#notcreatable-case) -- the document needs an object of a type with no public parameterless constructor

**See also** &nbsp; [Json.Serialize](#serialize-function)

<sub>[stdlib/Json/Json.sl:1187](../../stdlib/Json/Json.sl#L1187)</sub>

### PopulateObject *function*

```
JsonError PopulateObject<T>(T value, JsonValue document)
```

The same, from a document already parsed.

`required` members of `value` itself are not asked for: the `new` that
made it was refused unless it gave them values.

**Type parameters**

- `T` -- a `[Reflect]` type, whose field tables say what there is to fill

**Fails with**

- [JsonError.NotAnObject](#notanobject-case) -- the document is not an object
- [JsonError.NotReflected](#notreflected-case) -- `T` carries no field tables
- [JsonError.MissingMember](#missingmember-case) -- something made here lacks a value its type needs
- [JsonError.NotCreatable](#notcreatable-case) -- the document needs an object of a type with no public parameterless constructor

**See also** &nbsp; [Json.Serialize](#serialize-function)

<sub>[stdlib/Json/Json.sl:1208](../../stdlib/Json/Json.sl#L1208)</sub>

### Serialize *function*

```
String Serialize<T>(T value)
```

The document as text.

**Type parameters**

- `T` -- a `[Reflect]` type

**See also** &nbsp; [Json.PopulateObject](#populateobject-function)

<sub>[stdlib/Json/Json.sl:989](../../stdlib/Json/Json.sl#L989)</sub>

### SerializeIndented *function*

```
String SerializeIndented<T>(T value)
```

The same, indented.

**Type parameters**

- `T` -- a `[Reflect]` type

**See also** &nbsp; [Json.Serialize](#serialize-function)

<sub>[stdlib/Json/Json.sl:995](../../stdlib/Json/Json.sl#L995)</sub>

### ToJsonText *function*

```
String ToJsonText(JsonValue value)
```

The document as text, on one line.

A `Number` that is infinite or NaN is written as `null`, since JSON has no
spelling for either. `JSON.stringify` does the same, and it reads back as a
value absent rather than as some other number.

**See also** &nbsp; [Json.Parse](#parse-function) &middot; [Json.ToJsonTextIndented](#tojsontextindented-function)

<sub>[stdlib/Json/Json.sl:760](../../stdlib/Json/Json.sl#L760)</sub>

### ToJsonTextIndented *function*

```
String ToJsonTextIndented(JsonValue value)
```

The document as text, indented two spaces a level.

**See also** &nbsp; [Json.ToJsonText](#tojsontext-function)

<sub>[stdlib/Json/Json.sl:770](../../stdlib/Json/Json.sl#L770)</sub>

### ToJsonValue *function*

```
JsonValue ToJsonValue<T>(T value)
```

The document a value would produce, as a `JsonValue`.

Reads the field tables of `[Reflect] T`, walking into a nested class or
struct rather than stopping at it. A field of a kind with no JSON spelling
-- a pointer, a delegate, an array -- is left out rather than guessed at.

**Type parameters**

- `T` -- a `[Reflect]` type, whose field tables say what there is to write

**See also** &nbsp; [Json.Serialize](#serialize-function)

<sub>[stdlib/Json/Json.sl:980](../../stdlib/Json/Json.sl#L980)</sub>

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

<sub>[stdlib/Json/Json.sl:86](../../stdlib/Json/Json.sl#L86)</sub>

