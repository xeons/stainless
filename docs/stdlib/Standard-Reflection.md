# Standard.Reflection

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

Reading the metadata the compiler laid down.

There is no runtime machinery behind this: a reflected type's fields and
attributes are `const` tables in the binary, and everything below is a typed
view over them. That is why reflection works in a natively compiled language
at all -- it is a layout agreement, not a virtual machine.

A type carries metadata only when it is marked [Reflect]. Nothing else does,
so nothing else pays for it.

## Contents

**Types** &nbsp; [Attribute](#attribute-struct) &middot; [Field](#field-struct) &middot; [Property](#property-struct) &middot; [Reflect](#reflect-attribute) &middot; [Type](#type-struct)

**Functions** &nbsp; [ArrayLength](#arraylength-function) &middot; [ElementAt](#elementat-function) &middot; [FindType](#findtype-function) &middot; [GetAggregate](#getaggregate-function) &middot; [GetBool](#getbool-function) &middot; [GetDouble](#getdouble-function) &middot; [GetInteger](#getinteger-function) &middot; [GetText](#gettext-function) &middot; [Make](#make-function) &middot; [MakeInto](#makeinto-function) &middot; [ReadAggregate](#readaggregate-function) &middot; [ReadAggregateAt](#readaggregateat-function) &middot; [ReadArray](#readarray-function) &middot; [ReadBool](#readbool-function) &middot; [ReadBoolAt](#readboolat-function) &middot; [ReadDouble](#readdouble-function) &middot; [ReadDoubleAt](#readdoubleat-function) &middot; [ReadInteger](#readinteger-function) &middot; [ReadIntegerAt](#readintegerat-function) &middot; [ReadText](#readtext-function) &middot; [ReadTextAt](#readtextat-function) &middot; [SetAggregate](#setaggregate-function) &middot; [SetBool](#setbool-function) &middot; [SetDouble](#setdouble-function) &middot; [SetInteger](#setinteger-function) &middot; [SetText](#settext-function) &middot; [WriteAggregate](#writeaggregate-function) &middot; [WriteBool](#writebool-function) &middot; [WriteBoolAt](#writeboolat-function) &middot; [WriteDouble](#writedouble-function) &middot; [WriteDoubleAt](#writedoubleat-function) &middot; [WriteInteger](#writeinteger-function) &middot; [WriteIntegerAt](#writeintegerat-function) &middot; [WriteText](#writetext-function) &middot; [WriteTextAt](#writetextat-function)

**Constants** &nbsp; [KindArray](#kindarray-constant) &middot; [KindBool](#kindbool-constant) &middot; [KindByte](#kindbyte-constant) &middot; [KindChar](#kindchar-constant) &middot; [KindChar16](#kindchar16-constant) &middot; [KindChar32](#kindchar32-constant) &middot; [KindClass](#kindclass-constant) &middot; [KindDouble](#kinddouble-constant) &middot; [KindFloat](#kindfloat-constant) &middot; [KindInt](#kindint-constant) &middot; [KindInterface](#kindinterface-constant) &middot; [KindLong](#kindlong-constant) &middot; [KindNInt](#kindnint-constant) &middot; [KindNUInt](#kindnuint-constant) &middot; [KindNone](#kindnone-constant) &middot; [KindPointer](#kindpointer-constant) &middot; [KindSByte](#kindsbyte-constant) &middot; [KindShort](#kindshort-constant) &middot; [KindString](#kindstring-constant) &middot; [KindStruct](#kindstruct-constant) &middot; [KindUInt](#kinduint-constant) &middot; [KindULong](#kindulong-constant) &middot; [KindUShort](#kindushort-constant)

## Types

### Attribute *struct*

```
struct Attribute
```

One attribute as written on a declaration, with the constants it was given.

<sub>[stdlib/Reflection.sl:174](../../stdlib/Reflection.sl#L174)</sub>

#### Handle *field*

```
byte* Handle
```

The runtime's record for this attribute. Owned by the metadata, which
lives as long as the program, so it never has to be freed.

<sub>[stdlib/Reflection.sl:178](../../stdlib/Reflection.sl#L178)</sub>

#### Name *method*

```
String Name()
```

The attribute's name, without the brackets.

<sub>[stdlib/Reflection.sl:181](../../stdlib/Reflection.sl#L181)</sub>

#### ValueCount *method*

```
nuint ValueCount()
```

How many constants were written in the brackets.

<sub>[stdlib/Reflection.sl:184](../../stdlib/Reflection.sl#L184)</sub>

#### ValueKind *method*

```
int ValueKind(nuint index)
```

Which kind the value at `index` is -- one of the `Kind` constants --
so a reader knows whether to call `AsText` or `Number`.

<sub>[stdlib/Reflection.sl:188](../../stdlib/Reflection.sl#L188)</sub>

#### AsText *method*

```
String AsText(nuint index)
```

The value as text. Only meaningful when ValueKind is KindString.

<sub>[stdlib/Reflection.sl:191](../../stdlib/Reflection.sl#L191)</sub>

#### Number *method*

```
long Number(nuint index)
```

The value as a whole number. Meaningful for the integer kinds and for
`KindBool`, where one is true; zero for anything else, including a
string, rather than a reinterpretation of its pointer.

<sub>[stdlib/Reflection.sl:199](../../stdlib/Reflection.sl#L199)</sub>

### Field *struct*

```
struct Field
```

One field of a type: where it sits, what it holds, and what was written on
it.

A field is the storage. Writing one goes straight past any setter, which is
what a serializer filling plain data wants and what a type with behaviour in
its accessors does not -- see `IsPropertyStorage` and `Type.FindProperty`.

<sub>[stdlib/Reflection.sl:210](../../stdlib/Reflection.sl#L210)</sub>

#### Handle *field*

```
byte* Handle
```

The runtime's record for this field, or null for one that was looked up
and not found. `Type.FindField` is what answers with a null one.

<sub>[stdlib/Reflection.sl:214](../../stdlib/Reflection.sl#L214)</sub>

#### Name *method*

```
String Name()
```

The field's name. For an automatic property's storage this is the
property's name, which is why `IsPropertyStorage` has to exist.

<sub>[stdlib/Reflection.sl:218](../../stdlib/Reflection.sl#L218)</sub>

#### Offset *method*

```
nuint Offset()
```

How many bytes from the start of the instance the field sits. Add it to
an instance pointer to reach the storage directly.

<sub>[stdlib/Reflection.sl:222](../../stdlib/Reflection.sl#L222)</sub>

#### Kind *method*

```
int Kind()
```

What the field holds, as one of the `Kind` constants.

<sub>[stdlib/Reflection.sl:225](../../stdlib/Reflection.sl#L225)</sub>

#### AttributeCount *method*

```
nuint AttributeCount()
```

How many attributes are written on the field.

<sub>[stdlib/Reflection.sl:228](../../stdlib/Reflection.sl#L228)</sub>

#### AttributeAt *method*

```
Attribute AttributeAt(nuint index)
```

The attribute at `index`, in the order they were written.

<sub>[stdlib/Reflection.sl:231](../../stdlib/Reflection.sl#L231)</sub>

#### IsPropertyStorage *method*

```
bool IsPropertyStorage()
```

True when this field is an automatic property's storage rather than a
field the type declared.

**It is named after the property**, so without this a walk over the
field table cannot tell `Left` the storage from `Left` the property,
and writing it goes straight past the setter. Which one is right
depends on what is being filled: plain data wants the field, and
anything whose setter does work -- a control that re-lays-out when it
moves -- wants `Type.FindProperty` instead.

<sub>[stdlib/Reflection.sl:247](../../stdlib/Reflection.sl#L247)</sub>

#### Has *method*

```
bool Has(String name)
```

True when an attribute of this name is written on the field.

<sub>[stdlib/Reflection.sl:250](../../stdlib/Reflection.sl#L250)</sub>

#### Get *method*

```
Attribute Get(String name)
```

The named attribute, if it is present. Check Has first.

<sub>[stdlib/Reflection.sl:261](../../stdlib/Reflection.sl#L261)</sub>

#### IsInteger *method*

```
bool IsInteger()
```

True for a field whose value can be read as a whole number.

The two code unit kinds were added after the numbering was fixed, so
they sit past KindArray rather than beside KindChar and a range test
alone no longer reaches them.

<sub>[stdlib/Reflection.sl:277](../../stdlib/Reflection.sl#L277)</sub>

#### IsFloating *method*

```
bool IsFloating()
```

True for a field whose value can be read as a `double` -- a `float` or
a `double`. An integer field is not one: `ReadDouble` on it answers
zero rather than converting.

<sub>[stdlib/Reflection.sl:288](../../stdlib/Reflection.sl#L288)</sub>

#### IsSimple *method*

```
bool IsSimple()
```

True for a field this module can read and write by value: a number, a
bool or a String. Everything else is an aggregate, reached through
`TypeOf()` and walked rather than copied.

<sub>[stdlib/Reflection.sl:293](../../stdlib/Reflection.sl#L293)</sub>

#### TypeOf *method*

```
Type TypeOf()
```

The type of a field that holds one, or a handle of null.

Set for a class, an interface and a struct; null for a primitive, whose
`Kind()` is the whole of what there is to know. It is what makes a
nested object reachable: with the address of the field and the type of
what is in it, the walk continues without any of it being typed.

<sub>[stdlib/Reflection.sl:304](../../stdlib/Reflection.sl#L304)</sub>

#### IsAggregate *method*

```
bool IsAggregate()
```

True when this field holds something with fields of its own.

<sub>[stdlib/Reflection.sl:312](../../stdlib/Reflection.sl#L312)</sub>

#### ElementKind *method*

```
int ElementKind()
```

What an array field's elements are. `KindNone` for anything else.

<sub>[stdlib/Reflection.sl:319](../../stdlib/Reflection.sl#L319)</sub>

#### ElementType *method*

```
Type ElementType()
```

The type of an array's elements, when they have one.

<sub>[stdlib/Reflection.sl:322](../../stdlib/Reflection.sl#L322)</sub>

#### ElementSize *method*

```
nuint ElementSize()
```

How far apart an array's elements sit, in bytes. Zero for a field that
is not an array.

<sub>[stdlib/Reflection.sl:331](../../stdlib/Reflection.sl#L331)</sub>

#### IsArray *method*

```
bool IsArray()
```

True when this field is an array whose elements can be read one by one.

A slice answers false: it is three words rather than a reference, so
its elements are not where this arithmetic would look.

<sub>[stdlib/Reflection.sl:337](../../stdlib/Reflection.sl#L337)</sub>

#### IsWalkable *method*

```
bool IsWalkable()
```

True when this field can be walked into: it holds an aggregate, and
that aggregate carries field metadata of its own.

The second half is what tells a `[Reflect]` type from a `List<T>`.
Both are classes; only one has anything to walk, and a walk into the
other finds no fields and reports an empty object -- which is a lie
about a list that had things in it.

<sub>[stdlib/Reflection.sl:346](../../stdlib/Reflection.sl#L346)</sub>

### Property *struct*

```
struct Property
```

A property: a name and a pair of functions, rather than a place.

This is the other half of what a type carries, and the difference from a
`Field` is the whole reason it exists. A field is an offset, so writing one
stores bytes. A property is its accessors, so writing one **runs the
setter** -- which is what a control that re-lays-out when it moves needs,
and what a serializer filling plain data does not.

Reading and writing go through `sl_property_*` in the runtime, where the
cast from a stored pointer to the prototype the kind implies lives. That
cast is the unsafe part of reflection and it is written once there.

**Indexers and static properties are not here.** An indexer's accessors
take arguments nothing could supply, and a static one has no instance.

<sub>[stdlib/Reflection.sl:371](../../stdlib/Reflection.sl#L371)</sub>

#### Handle *field*

```
byte* Handle
```

The runtime's record for this property, or null for one that was looked
up and not found. `Exists` is the check.

<sub>[stdlib/Reflection.sl:375](../../stdlib/Reflection.sl#L375)</sub>

#### Name *method*

```
String Name()
```

The property's name.

<sub>[stdlib/Reflection.sl:378](../../stdlib/Reflection.sl#L378)</sub>

#### Kind *method*

```
int Kind()
```

What the property's type is, as one of the `Kind` constants.

<sub>[stdlib/Reflection.sl:381](../../stdlib/Reflection.sl#L381)</sub>

#### Exists *method*

```
bool Exists()
```

True when this handle names a property at all; `FindProperty` answers
with a null one when there is no such name.

<sub>[stdlib/Reflection.sl:385](../../stdlib/Reflection.sl#L385)</sub>

#### CanRead *method*

```
bool CanRead()
```

False for a write-only property, and for one whose getter this build
did not emit.

<sub>[stdlib/Reflection.sl:389](../../stdlib/Reflection.sl#L389)</sub>

#### CanWrite *method*

```
bool CanWrite()
```

False for a read-only property -- `public int Left { get; }` -- which
is worth checking before a loader decides a document was ignored.

<sub>[stdlib/Reflection.sl:393](../../stdlib/Reflection.sl#L393)</sub>

#### TypeOf *method*

```
Type TypeOf()
```

The type of an aggregate property, for walking into it. A handle of
null for a primitive.

<sub>[stdlib/Reflection.sl:397](../../stdlib/Reflection.sl#L397)</sub>

#### AttributeCount *method*

```
nuint AttributeCount()
```

How many attributes are written on the property.

<sub>[stdlib/Reflection.sl:405](../../stdlib/Reflection.sl#L405)</sub>

#### AttributeAt *method*

```
Attribute AttributeAt(nuint index)
```

The attribute at `index`, in the order they were written.

<sub>[stdlib/Reflection.sl:408](../../stdlib/Reflection.sl#L408)</sub>

#### Has *method*

```
bool Has(String name)
```

True when an attribute of this name is written on the property.

<sub>[stdlib/Reflection.sl:416](../../stdlib/Reflection.sl#L416)</sub>

#### IsInteger *method*

```
bool IsInteger()
```

The same three questions a `Field` answers about its kind.

<sub>[stdlib/Reflection.sl:427](../../stdlib/Reflection.sl#L427)</sub>

#### IsFloating *method*

```
bool IsFloating()
```

True for a `float` or a `double` property.

<sub>[stdlib/Reflection.sl:436](../../stdlib/Reflection.sl#L436)</sub>

#### IsText *method*

```
bool IsText()
```

True for a `String` property.

<sub>[stdlib/Reflection.sl:439](../../stdlib/Reflection.sl#L439)</sub>

### Reflect *attribute*

```
attribute Reflect
```

Marks a class or struct to carry field metadata in the binary.

<sub>[stdlib/Reflection.sl:34](../../stdlib/Reflection.sl#L34)</sub>

### Type *struct*

```
struct Type
```

One type, and the way into everything it declares.

Got from `typeof(T)`, from `FindType` by name, or from a field's or
property's `TypeOf()`. Fields and interfaces carry metadata; methods do not,
so there is nothing here to call.

<sub>[stdlib/Reflection.sl:526](../../stdlib/Reflection.sl#L526)</sub>

#### Handle *field*

```
byte* Handle
```

The runtime's record for this type, or null for one that was looked up
and not found. `Exists` is the check.

<sub>[stdlib/Reflection.sl:530](../../stdlib/Reflection.sl#L530)</sub>

#### Name *method*

```
String Name()
```

The type's name, qualified by its module.

<sub>[stdlib/Reflection.sl:533](../../stdlib/Reflection.sl#L533)</sub>

#### Size *method*

```
nuint Size()
```

How many bytes an instance occupies -- the struct's own size, or for a
class the size of the object including its header.

<sub>[stdlib/Reflection.sl:537](../../stdlib/Reflection.sl#L537)</sub>

#### FieldCount *method*

```
nuint FieldCount()
```

How many fields the type has, inherited ones included, and automatic
properties' storage among them.

<sub>[stdlib/Reflection.sl:541](../../stdlib/Reflection.sl#L541)</sub>

#### FieldAt *method*

```
Field FieldAt(nuint index)
```

The field at `index`, in declaration order with inherited fields first.

<sub>[stdlib/Reflection.sl:544](../../stdlib/Reflection.sl#L544)</sub>

#### AttributeCount *method*

```
nuint AttributeCount()
```

How many attributes are written on the type.

<sub>[stdlib/Reflection.sl:552](../../stdlib/Reflection.sl#L552)</sub>

#### AttributeAt *method*

```
Attribute AttributeAt(nuint index)
```

The attribute at `index`, in the order they were written.

<sub>[stdlib/Reflection.sl:555](../../stdlib/Reflection.sl#L555)</sub>

#### Exists *method*

```
bool Exists()
```

True when this handle names a type at all. A `TypeOf()` on a primitive
field answers false.

<sub>[stdlib/Reflection.sl:564](../../stdlib/Reflection.sl#L564)</sub>

#### FindField *method*

```
Field FindField(String name)
```

The field of that name, or a handle of null. Names are compared whole,
so a serializer looking up what a document named does one pass.

<sub>[stdlib/Reflection.sl:568](../../stdlib/Reflection.sl#L568)</sub>

#### Has *method*

```
bool Has(String name)
```

True when the type carries an attribute of that name.

<sub>[stdlib/Reflection.sl:583](../../stdlib/Reflection.sl#L583)</sub>

#### PropertyCount *method*

```
nuint PropertyCount()
```

How many properties the type has, inherited ones included.

A derived class lists everything it inherited, and a virtual property
it overrode appears once, at the position the base gave it, with the
**derived** accessors. What that does not do is dispatch: reaching an
object through `typeof(Base)` and setting a property the derived class
overrode calls the base's setter, where `.Left = x` in the language
would not.

<sub>[stdlib/Reflection.sl:601](../../stdlib/Reflection.sl#L601)</sub>

#### PropertyAt *method*

```
Property PropertyAt(nuint index)
```

The property at `index`. An overridden property appears once, at the
position the base gave it, carrying the derived accessors.

<sub>[stdlib/Reflection.sl:605](../../stdlib/Reflection.sl#L605)</sub>

#### FindProperty *method*

```
Property FindProperty(String name)
```

The property of that name, or a handle of null.

<sub>[stdlib/Reflection.sl:613](../../stdlib/Reflection.sl#L613)</sub>

## Functions

### ArrayLength *function*

```
nuint ArrayLength(byte* array)
```

How many elements an array has. Zero for null.

<sub>[stdlib/Reflection.sl:808](../../stdlib/Reflection.sl#L808)</sub>

### ElementAt *function*

```
byte* ElementAt(byte* array, Field field, nuint index)
```

The address of one element, or null when the array is null or the index is
past its end. Checked rather than trusted: the caller is walking metadata,
and an index that came from a document is not the program's.

<sub>[stdlib/Reflection.sl:818](../../stdlib/Reflection.sl#L818)</sub>

### FindType *function*

```
Type FindType(String name)
```

The type of that **qualified** name -- "App.Button", as `Type.Name()`
spells it -- or a handle of null.

This is the one thing in reflection that is a search rather than a
constant, and it exists for the case `typeof` cannot serve: a document
naming the type it wants. Every `[Reflect]` type in the binary is in a
sorted table registered before `Main` runs, and each library the program
loaded contributes its own, so the lookup is a binary search per binary.

**Only reflected types are findable.** A program that could name any type
at run time would be a program whose linker could drop nothing, which is
the trade `[Reflect]` exists to make explicit.

    var type = FindType("App.Button");
    if (type.Exists()) { byte* made = Make(type); }

<sub>[stdlib/Reflection.sl:730](../../stdlib/Reflection.sl#L730)</sub>

### GetAggregate *function*

```
byte* GetAggregate(byte* instance, Property property)
```

The object a class or interface property holds, for walking into it.
Null where it holds nothing, which a caller has to check.

<sub>[stdlib/Reflection.sl:477](../../stdlib/Reflection.sl#L477)</sub>

### GetBool *function*

```
bool GetBool(byte* instance, Property property)
```

Calls the getter of a `bool` property. False when it cannot be read, or
when its kind is not `KindBool` -- which is indistinguishable from a real
false, so check `CanRead` and `Kind` where it matters.

<sub>[stdlib/Reflection.sl:461](../../stdlib/Reflection.sl#L461)</sub>

### GetDouble *function*

```
double GetDouble(byte* instance, Property property)
```

Calls the getter of a `float` or `double` property. Zero when it cannot be
read, or when its kind is not a floating one.

<sub>[stdlib/Reflection.sl:453](../../stdlib/Reflection.sl#L453)</sub>

### GetInteger *function*

```
long GetInteger(byte* instance, Property property)
```

Calls the getter. Zero when the property cannot be read, or when its kind
is not a whole number -- rather than reading the wrong four bytes.

<sub>[stdlib/Reflection.sl:446](../../stdlib/Reflection.sl#L446)</sub>

### GetText *function*

```
String GetText(byte* instance, Property property)
```

Calls the getter of a String property. The instance still owns the answer.

<sub>[stdlib/Reflection.sl:467](../../stdlib/Reflection.sl#L467)</sub>

### Make *function*

```
byte* Make(Type type)
```

Makes a zeroed instance of a type, for a reader that has a type and no
constructor to call.

**Every reference field starts null**, including one whose type says it
cannot be. What comes back is safe to fill and unsafe to hand out until it
has been: prefer making the object the ordinary way and filling it, which
is what `Json.Populate` does and why it is the one that needs no warning.

<sub>[stdlib/Reflection.sl:744](../../stdlib/Reflection.sl#L744)</sub>

### MakeInto *function*

```
byte* MakeInto(byte* instance, Field field)
```

Makes an object of a class field's own type and stores it in that field,
answering its address. Null when the field is not a class, or its type
carries no metadata.

**The object is zeroed**, so every reference field in it starts null --
including one whose type says it cannot be. That is the whole hazard: an
object made this way is not yet a value of its type, and is only safe once
whatever fills it has filled the fields that may not be null.

It exists because a deserializer holding a document for a nested object,
and a field holding nothing, otherwise has nowhere to put it. Use it where
the document is the thing that decides, and prefer a constructor that made
the object already: `Json.Populate` fills in place and only reaches for
this where a field is marked to say so.

<sub>[stdlib/Reflection.sl:771](../../stdlib/Reflection.sl#L771)</sub>

### ReadAggregate *function*

```
byte* ReadAggregate(byte* instance, Field field)
```

The address of a field that holds an aggregate, for walking into it.

A class field holds a reference, so the address is what it points at; a
struct field *is* its bytes, so the address is where it sits. Null for a
class field holding nothing, which is the one case a caller has to check.

<sub>[stdlib/Reflection.sl:664](../../stdlib/Reflection.sl#L664)</sub>

### ReadAggregateAt *function*

```
byte* ReadAggregateAt(byte* address, Field field)
```

The address of an aggregate element: what a class element points at, or
where a struct element sits.

<sub>[stdlib/Reflection.sl:856](../../stdlib/Reflection.sl#L856)</sub>

### ReadArray *function*

```
byte* ReadArray(byte* instance, Field field)
```

The array a field holds, or null. The instance still owns it.

<sub>[stdlib/Reflection.sl:800](../../stdlib/Reflection.sl#L800)</sub>

### ReadBool *function*

```
bool ReadBool(byte* instance, Field field)
```

Reads a `bool` field from an instance. False when the field's kind is not
`KindBool`, which reads the same as a real false.

<sub>[stdlib/Reflection.sl:645](../../stdlib/Reflection.sl#L645)</sub>

### ReadBoolAt *function*

```
bool ReadBoolAt(byte* address)
```

Reads an element of a `bool` array. Takes no field, a `bool` being one byte
whatever array it is in.

<sub>[stdlib/Reflection.sl:843](../../stdlib/Reflection.sl#L843)</sub>

### ReadDouble *function*

```
double ReadDouble(byte* instance, Field field)
```

Reads a `float` or `double` field from an instance. Zero when the field's
kind is not a floating one -- no conversion from an integer field.

<sub>[stdlib/Reflection.sl:638](../../stdlib/Reflection.sl#L638)</sub>

### ReadDoubleAt *function*

```
double ReadDoubleAt(byte* address, Field field)
```

Reads an element of a floating array. `field` supplies the element kind,
which is what says whether the four or the eight bytes at `address` are the
value.

<sub>[stdlib/Reflection.sl:836](../../stdlib/Reflection.sl#L836)</sub>

### ReadInteger *function*

```
long ReadInteger(byte* instance, Field field)
```

Reads a whole-number field from an instance.

<sub>[stdlib/Reflection.sl:631](../../stdlib/Reflection.sl#L631)</sub>

### ReadIntegerAt *function*

```
long ReadIntegerAt(byte* address, Field field)
```

Reads an element of a whole-number array.

<sub>[stdlib/Reflection.sl:828](../../stdlib/Reflection.sl#L828)</sub>

### ReadText *function*

```
String ReadText(byte* instance, Field field)
```

Reads a String field. The instance still owns it.

<sub>[stdlib/Reflection.sl:651](../../stdlib/Reflection.sl#L651)</sub>

### ReadTextAt *function*

```
String ReadTextAt(byte* address)
```

Reads a String element. The array still owns it.

<sub>[stdlib/Reflection.sl:846](../../stdlib/Reflection.sl#L846)</sub>

### SetAggregate *function*

```
void SetAggregate(byte* instance, Property property, byte* value)
```

Points a class or interface property at an object, on the same terms.

<sub>[stdlib/Reflection.sl:514](../../stdlib/Reflection.sl#L514)</sub>

### SetBool *function*

```
void SetBool(byte* instance, Property property, bool value)
```

Calls the setter of a `bool` property. Does nothing when there is no
setter, which `CanWrite` is how to find out in advance.

<sub>[stdlib/Reflection.sl:498](../../stdlib/Reflection.sl#L498)</sub>

### SetDouble *function*

```
void SetDouble(byte* instance, Property property, double value)
```

Calls the setter of a floating property, narrowing to `float` where that
is its width. Does nothing when there is no setter.

<sub>[stdlib/Reflection.sl:491](../../stdlib/Reflection.sl#L491)</sub>

### SetInteger *function*

```
void SetInteger(byte* instance, Property property, long value)
```

Calls the setter, narrowing to the property's own width. Does nothing when
there is no setter, which `CanWrite` is how to find out in advance.

<sub>[stdlib/Reflection.sl:484](../../stdlib/Reflection.sl#L484)</sub>

### SetText *function*

```
void SetText(byte* instance, Property property, String value)
```

Calls the setter of a String property.

The runtime retains before the call, because a setter takes a reference of
its own -- it releases what the property held and keeps what it was given.
So the caller still owns `value` afterwards.

<sub>[stdlib/Reflection.sl:508](../../stdlib/Reflection.sl#L508)</sub>

### WriteAggregate *function*

```
void WriteAggregate(byte* instance, Field field, byte* value)
```

Points a reference field at an object made by `Make`, releasing whatever it
held. The field takes a reference of its own, so the caller still owns
theirs.

<sub>[stdlib/Reflection.sl:752](../../stdlib/Reflection.sl#L752)</sub>

### WriteBool *function*

```
void WriteBool(byte* instance, Field field, bool value)
```

Writes a `bool` field.

<sub>[stdlib/Reflection.sl:700](../../stdlib/Reflection.sl#L700)</sub>

### WriteBoolAt *function*

```
void WriteBoolAt(byte* address, bool value)
```

Writes an element of a `bool` array.

<sub>[stdlib/Reflection.sl:880](../../stdlib/Reflection.sl#L880)</sub>

### WriteDouble *function*

```
void WriteDouble(byte* instance, Field field, double value)
```

Writes a floating field, narrowed to `float` where that is its width.

<sub>[stdlib/Reflection.sl:694](../../stdlib/Reflection.sl#L694)</sub>

### WriteDoubleAt *function*

```
void WriteDoubleAt(byte* address, Field field, double value)
```

Writes an element of a floating array, narrowed to the element's width.

<sub>[stdlib/Reflection.sl:874](../../stdlib/Reflection.sl#L874)</sub>

### WriteInteger *function*

```
void WriteInteger(byte* instance, Field field, long value)
```

Writes a whole-number field.

<sub>[stdlib/Reflection.sl:688](../../stdlib/Reflection.sl#L688)</sub>

### WriteIntegerAt *function*

```
void WriteIntegerAt(byte* address, Field field, long value)
```

Writes an element of a whole-number array, narrowed to its width.

<sub>[stdlib/Reflection.sl:868](../../stdlib/Reflection.sl#L868)</sub>

### WriteText *function*

```
void WriteText(byte* instance, Field field, String value)
```

Writes a String field, releasing whatever it held.

The bytes cross rather than the String, which is what keeps a counted
reference out of the runtime's ABI -- the same bargain `ReadText` makes in
the other direction. The field ends up owning a copy.

<sub>[stdlib/Reflection.sl:710](../../stdlib/Reflection.sl#L710)</sub>

### WriteTextAt *function*

```
void WriteTextAt(byte* address, String value)
```

Writes a String element, releasing whatever it held.

<sub>[stdlib/Reflection.sl:883](../../stdlib/Reflection.sl#L883)</sub>

## Constants

### KindArray *constant*

```
const int KindArray = 20
```

An array. `ElementKind` says what is in it.

<sub>[stdlib/Reflection.sl:162](../../stdlib/Reflection.sl#L162)</sub>

### KindBool *constant*

```
const int KindBool = 1
```

A `bool`.

<sub>[stdlib/Reflection.sl:120](../../stdlib/Reflection.sl#L120)</sub>

### KindByte *constant*

```
const int KindByte = 8
```

A `byte`.

<sub>[stdlib/Reflection.sl:134](../../stdlib/Reflection.sl#L134)</sub>

### KindChar *constant*

```
const int KindChar = 2
```

A `char`: one UTF-8 code unit.

<sub>[stdlib/Reflection.sl:122](../../stdlib/Reflection.sl#L122)</sub>

### KindChar16 *constant*

```
const int KindChar16 = 21
```

A `char16`: one UTF-16 code unit. Numbered past
`KindArray` because it was added after the numbering was fixed, which is
why `IsInteger` tests it separately.

<sub>[stdlib/Reflection.sl:166](../../stdlib/Reflection.sl#L166)</sub>

### KindChar32 *constant*

```
const int KindChar32 = 22
```

A `char32`: one Unicode scalar, with the same
numbering story as `KindChar16`.

<sub>[stdlib/Reflection.sl:169](../../stdlib/Reflection.sl#L169)</sub>

### KindClass *constant*

```
const int KindClass = 17
```

A class reference. `TypeOf()` gives the type to walk
into, and the value can be null.

<sub>[stdlib/Reflection.sl:155](../../stdlib/Reflection.sl#L155)</sub>

### KindDouble *constant*

```
const int KindDouble = 14
```

A `double`.

<sub>[stdlib/Reflection.sl:146](../../stdlib/Reflection.sl#L146)</sub>

### KindFloat *constant*

```
const int KindFloat = 13
```

A `float`.

<sub>[stdlib/Reflection.sl:144](../../stdlib/Reflection.sl#L144)</sub>

### KindInt *constant*

```
const int KindInt = 5
```

An `int`.

<sub>[stdlib/Reflection.sl:128](../../stdlib/Reflection.sl#L128)</sub>

### KindInterface *constant*

```
const int KindInterface = 18
```

An interface reference, walked like a class.

<sub>[stdlib/Reflection.sl:157](../../stdlib/Reflection.sl#L157)</sub>

### KindLong *constant*

```
const int KindLong = 6
```

A `long`.

<sub>[stdlib/Reflection.sl:130](../../stdlib/Reflection.sl#L130)</sub>

### KindNInt *constant*

```
const int KindNInt = 7
```

An `nint`: pointer-wide and signed.

<sub>[stdlib/Reflection.sl:132](../../stdlib/Reflection.sl#L132)</sub>

### KindNUInt *constant*

```
const int KindNUInt = 12
```

An `nuint`: pointer-wide and unsigned.

<sub>[stdlib/Reflection.sl:142](../../stdlib/Reflection.sl#L142)</sub>

### KindNone *constant*

```
const int KindNone = 0
```

What a field holds. Kept in step with enum SlKind in the runtime.

<sub>[stdlib/Reflection.sl:118](../../stdlib/Reflection.sl#L118)</sub>

### KindPointer *constant*

```
const int KindPointer = 15
```

A raw pointer. Nothing here follows one -- what it
points at carries no metadata.

<sub>[stdlib/Reflection.sl:149](../../stdlib/Reflection.sl#L149)</sub>

### KindSByte *constant*

```
const int KindSByte = 3
```

An `sbyte`.

<sub>[stdlib/Reflection.sl:124](../../stdlib/Reflection.sl#L124)</sub>

### KindShort *constant*

```
const int KindShort = 4
```

A `short`.

<sub>[stdlib/Reflection.sl:126](../../stdlib/Reflection.sl#L126)</sub>

### KindString *constant*

```
const int KindString = 16
```

A `String`. Read and written by value, through
`ReadText` and `WriteText`.

<sub>[stdlib/Reflection.sl:152](../../stdlib/Reflection.sl#L152)</sub>

### KindStruct *constant*

```
const int KindStruct = 19
```

A struct, stored inline rather than referenced -- so
its address is where it sits, and it is never null.

<sub>[stdlib/Reflection.sl:160](../../stdlib/Reflection.sl#L160)</sub>

### KindUInt *constant*

```
const int KindUInt = 10
```

A `uint`.

<sub>[stdlib/Reflection.sl:138](../../stdlib/Reflection.sl#L138)</sub>

### KindULong *constant*

```
const int KindULong = 11
```

A `ulong`.

<sub>[stdlib/Reflection.sl:140](../../stdlib/Reflection.sl#L140)</sub>

### KindUShort *constant*

```
const int KindUShort = 9
```

A `ushort`.

<sub>[stdlib/Reflection.sl:136](../../stdlib/Reflection.sl#L136)</sub>

