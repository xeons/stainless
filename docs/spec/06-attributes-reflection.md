<sub>[Stainless](../../README.md) &rsaquo; [Language specification](index.md)</sub>

# 6. Attributes and reflection

Reflection in a natively compiled language is not a virtual machine feature. It
is **tables in the binary**: the compiler writes down a type's fields, and a
library reads them. Swift and Go work the same way. The only cost is size, and
only for types that ask.

## 6.1 Attributes

An attribute is its own kind of declaration, holding fields and nothing else:

```csharp
public attribute JsonName { String Name; }
public attribute JsonIgnore { }
```

It is written in brackets before a declaration, with **constant** arguments —
they are stored in the binary, not evaluated (SL0344):

```csharp
[JsonName("full_name")] public String Name;
```

An attribute type is never a value: it cannot be instantiated, named as a type,
or passed around.

### Positional and named arguments

The arguments fill the fields in the order they were declared. Past those, a
field is set by name, with `=`:

```csharp
public attribute Column { String Name; int Width; bool Hidden; }

[Column("full_name", Width = 32)]      // one positional, one named
[Column(Name = "age", Hidden = true)]  // all named, and one left out
[Column("zip", 5, false)]              // all positional
```

`=` rather than the `name:` a call uses (SL0727), because an attribute is a
value being built and not a call being made: what stands to the left of the
sign is a field, and the line reads as the assignment it is. It is also what C#
writes, so the shape is one a reader already knows.

**The positional arguments come first** (SL0726). Letting the two orders mix
would mean counting past the named ones to work out which field a later bare
value belongs to, which is the work naming them was supposed to remove. Each
field may be given once (SL0725), by either route, and a name the attribute
does not declare is an error (SL0724) rather than a value that goes nowhere.

**A field given neither way keeps its type's default** — a zero, `false`, or
nothing at all for a `String`. That is what makes a field optional without an
attribute declaration having to say which of its fields are: every one of them
is. Reflection reports the value's kind as `KindNone`, so a reader can tell a
field that was left out from one written as `0`.

### Where an attribute may go

On a type, an enum, a field, a property, an event, and a `static`. Anywhere
else is an error (SL0728) rather than a line the compiler drops: an attribute
may decide something — `[Embed]`
([§8.7](08-interop-libraries.md#87-embedding-a-file)) decides what a static
holds — and a declaration that quietly ignored one would compile to a
declaration that does not have it, with nothing in the output to say which had
happened.

A method is not on that list, and that is the one absence worth a word: methods
carry no metadata, so there is no table for a reader to find an attribute in and
nothing an attribute on one could ever be read back from
([§6.4.2](#642-finding-a-type-by-name) has what that costs). An attribute on a
`static` is bound and checked like any other, though nothing reflects over
statics either — there is no instance to read one from.

## 6.2 `[Reflect]` opts a type in

```csharp
[Reflect]
public class Person {
    [JsonName("full_name")] public String Name;
    [JsonName("age")]       public int    Years;
    [JsonIgnore]            public int    Internal;
}
```

Only a type marked `[Reflect]` carries field metadata. Everything else emits
nothing at all, and `typeof` on it is an error:

```
error[SL0346]: 'Plain' carries no metadata, so 'typeof' cannot name it; mark
its declaration '[Reflect]'
```

## 6.3 `typeof` and `Standard.Reflection`

`typeof(T)` yields a `Type` — a one-pointer handle to static data, so it costs
a constant and no work:

```csharp
import Standard.Reflection;

var type = typeof(Person);
type.Name;                         // "App.Person"
type.FieldCount;

var field = type.FieldAt(0);
field.Name;                        // "Name"
field.Offset;                      // 24, past the object header
field.Kind;                        // KindString
field.Has("JsonName");
field.Get("JsonName").AsText(0);   // "full_name"
```

Values are read from an instance by offset. That needs the object as a raw
pointer, which is an explicit cast — the result is uncounted, so the reference
must outlive it:

```csharp
var raw = (byte*)person;
ReadText(raw, field);
ReadInteger(raw, field);
ReadDouble(raw, field);
ReadBool(raw, field);
```

## 6.4 A serializer, written once

Because `T` is concrete by the time a generic is compiled, `typeof(T)` inside
one is still a constant:

```csharp
public String ToJson<T>(T value) {
    var type = typeof(T);
    var text = new StringBuilder();
    ...
    for (nuint i = 0; i < type.FieldCount; i++) {
        var field = type.FieldAt(i);
        if (field.Has("JsonIgnore")) { continue; }
        ...
    }
}
```

See [samples/json.sl](../../samples/json.sl) for the whole thing.

### 6.4.1 Properties, which are not fields

A field is an offset, so writing one stores bytes. **A property is a pair of
functions, so writing one runs the setter** — and which of those is right
depends on what is being filled. A serializer filling plain data wants the
field: it is cheaper and a plain object's setter does nothing a store does
not. A form loader setting a control's `Left` wants the property, because the
setter is what re-runs the layout.

So the two are described separately:

```csharp
var type = typeof(Control);
type.PropertyCount;

var left = type.FindProperty("Left");
left.Kind;                         // KindInt
left.CanRead;                      // true
left.CanWrite;                     // false for 'int Right { get; }'

SetInteger(raw, left, 42);         // calls the setter
GetInteger(raw, left);             // calls the getter
```

with `SetText`, `SetBool`, `SetDouble` and `SetAggregate` beside them, and the
matching readers. Setting through the wrong one does nothing rather than
writing the wrong bytes, and so does setting a property with no setter.

**An automatic property's storage is a field named after the property**, which
is why `Field.IsPropertyStorage` exists: without it a walk over the field
table cannot tell `Name` the storage from `Name` the property, and writing it
goes straight past the accessor. A field the type actually declared answers
false.

Two things are deliberately absent. An **indexer** has accessors that take
arguments nothing could supply, and a **static property** has no instance to
pass. Neither appears in the table.

One limit worth knowing: the accessors recorded are the ones the type itself
has. A virtual property overridden further down answers correctly through the
derived type's own table, but reaching an object through `typeof(Base)` and
setting a property the derived class overrode calls the **base's** setter,
where `.Left = x` in the language would not. Reflection here reads a table; it
does not dispatch.

### 6.4.2 Finding a type by name

`typeof(T)` resolves to a constant, which is what makes reflection free and
also what stops it serving a document that says which type it wants. That is
the other direction, and it is a search:

```csharp
var type = FindType("App.Button");        // the qualified name
if (type.Exists) {
    byte* made = Make(type);
    SetInteger(made, type.FindProperty("Left"), 40);
}
```

Every `[Reflect]` type in a binary is in a table sorted by name, registered
before `Main` runs, and a library the program loaded contributes its own — so
the lookup is a binary search per binary and the answer is the same constant
`typeof` would have produced.

**Only reflected types are findable**, and the name must be the qualified one.
A program that could name any type at run time would be a program whose linker
could drop nothing, which is the trade `[Reflect]` exists to make explicit.

Together with [§6.4.1](#641-properties-which-are-not-fields) that is enough to build an object graph from data: a
document names a type, this finds it, `Make` allocates one and the property
table sets it up. What is still missing is a method — an event handler named
by a document has nothing to resolve against, because methods carry no
metadata.

## 6.5 What is emitted

A reflected type's `TypeInfo` gains six entries — a field count and table, an
attribute count and table, and a property count and table — and each
`SlFieldInfo` records a name, offset, kind, nested type, its own attributes and
a flag saying whether it is property storage. Each `SlPropertyInfo` records a
name, kind, nested type, its getter and setter, and its attributes. All of it
is `const`, so it lands in read-only data and is shared, never allocated. See
[abi.md](../abi.md).

A struct has no object header, so its metadata is reachable only through
`typeof`, never from an instance.

## 6.6 Writing a field

Reading tells you what an object holds; writing is what a deserializer needs,
and the two are symmetric:

```csharp
byte* raw = (byte*)person;
var type = typeof(Person);

Reflection.WriteText(raw, type.FindField("Name"), "Ada Lovelace");
Reflection.WriteInteger(raw, type.FindField("Years"), 36);
```

Each writer **narrows to the field's own width**, so a value too large for it
wraps there rather than reaching the field beside it — C's rule for an
assignment of the same shape, and the only one that cannot corrupt an object
silently. A writer whose kind does not match the field does nothing.

`WriteText` releases what the field held and retains what replaces it, which is
why it is a runtime call rather than a store: ownership is the runtime's job,
and the four lines that do it live in one place. The bytes cross rather than
the `String`, so no counted reference is ever in the ABI — the same bargain
`ReadText` makes coming back.

**A nested object is reached rather than copied.** `Field.TypeOf()` is the type
of what a field holds and `ReadAggregate` is its address, so a walk continues
into a class or a struct without either being typed:

```csharp
var field = type.FindField("Where");
byte* nested = Reflection.ReadAggregate(raw, field);
Reflection.WriteText(nested, field.TypeOf().FindField("City"), "London");
```

**An array's elements are described too.** A field of type `T[]` records what
its elements are and how far apart they sit, which is what makes a walk over
one possible without knowing `T` at compile time:

```csharp
byte* array = Reflection.ReadArray(raw, field);

for (nuint i = 0u; i < Reflection.ArrayLength(array); i++) {
    byte* at = Reflection.ElementAt(array, field, i);
    Console.WriteLine(Reflection.ReadTextAt(at));
}
```

`ElementAt` is the data pointer plus the stride times the index, bounds
checked. The read and write pairs beside it take an address and a kind rather
than an instance and a field, because an element has no `SlFieldInfo` of its
own. A **slice** is deliberately not described: it is three words rather than a
reference, so its elements are not where this arithmetic would look, and
answering as though they were would be worse than answering nothing.

`Reflection.Make(type)` allocates a zeroed instance and `MakeInto(instance,
field)` puts one straight into a class field, for a reader that has a document
and a field holding nothing. **Every reference in what comes back starts
null**, including one whose type says it cannot be — so it is safe to fill and
unsafe to hand out until it has been. There is deliberately no cast from
`byte*` to a typed reference: that would be a hole available everywhere, to
solve a problem that only exists inside a deserializer.

## 6.7 What is not there yet

- **No method or interface metadata** — fields and their elements only. It is
  what stops a reader filling a `List<T>`: the storage is private and the way
  in is `Add`, which nothing here can call.
- **No enumeration of types**: `FindType` answers for a name, but nothing lists
  the types a binary holds.
- **No slice element metadata**, for the reason above: a slice is not a reference to
  its elements.

---

<sub>[&larr; The standard library](05-standard-library.md) &nbsp;&middot;&nbsp; [Functions and members &rarr;](07-functions-members.md)</sub>
