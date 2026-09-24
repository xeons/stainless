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

**Functions** &nbsp; [CreateArrayInto](#createarrayinto-function) &middot; [CreateInstance](#createinstance-function) &middot; [CreateInstanceInto](#createinstanceinto-function) &middot; [FindType](#findtype-function) &middot; [GetAggregate](#getaggregate-function) &middot; [GetArrayLength](#getarraylength-function) &middot; [GetBool](#getbool-function) &middot; [GetDouble](#getdouble-function) &middot; [GetElementAddress](#getelementaddress-function) &middot; [GetInteger](#getinteger-function) &middot; [GetText](#gettext-function) &middot; [ReadAggregate](#readaggregate-function) &middot; [ReadAggregateAt](#readaggregateat-function) &middot; [ReadArray](#readarray-function) &middot; [ReadBool](#readbool-function) &middot; [ReadBoolAt](#readboolat-function) &middot; [ReadDouble](#readdouble-function) &middot; [ReadDoubleAt](#readdoubleat-function) &middot; [ReadInteger](#readinteger-function) &middot; [ReadIntegerAt](#readintegerat-function) &middot; [ReadText](#readtext-function) &middot; [ReadTextAt](#readtextat-function) &middot; [SetAggregate](#setaggregate-function) &middot; [SetBool](#setbool-function) &middot; [SetDouble](#setdouble-function) &middot; [SetInteger](#setinteger-function) &middot; [SetText](#settext-function) &middot; [WriteAggregate](#writeaggregate-function) &middot; [WriteBool](#writebool-function) &middot; [WriteBoolAt](#writeboolat-function) &middot; [WriteDouble](#writedouble-function) &middot; [WriteDoubleAt](#writedoubleat-function) &middot; [WriteInteger](#writeinteger-function) &middot; [WriteIntegerAt](#writeintegerat-function) &middot; [WriteText](#writetext-function) &middot; [WriteTextAt](#writetextat-function)

**Constants** &nbsp; [KindArray](#kindarray-constant) &middot; [KindBool](#kindbool-constant) &middot; [KindByte](#kindbyte-constant) &middot; [KindChar](#kindchar-constant) &middot; [KindChar16](#kindchar16-constant) &middot; [KindChar32](#kindchar32-constant) &middot; [KindClass](#kindclass-constant) &middot; [KindDouble](#kinddouble-constant) &middot; [KindFloat](#kindfloat-constant) &middot; [KindInt](#kindint-constant) &middot; [KindInterface](#kindinterface-constant) &middot; [KindLong](#kindlong-constant) &middot; [KindNInt](#kindnint-constant) &middot; [KindNUInt](#kindnuint-constant) &middot; [KindNone](#kindnone-constant) &middot; [KindPointer](#kindpointer-constant) &middot; [KindSByte](#kindsbyte-constant) &middot; [KindShort](#kindshort-constant) &middot; [KindString](#kindstring-constant) &middot; [KindStruct](#kindstruct-constant) &middot; [KindUInt](#kinduint-constant) &middot; [KindULong](#kindulong-constant) &middot; [KindUShort](#kindushort-constant)

## Types

### Attribute *struct*

```
struct Attribute
```

One attribute as written on a declaration, with the constants it was given.

<sub>[stdlib/Reflection/Attribute.sl:27](../../stdlib/Reflection/Attribute.sl#L27)</sub>

#### Handle *field*

```
byte* Handle
```

The runtime's record for this attribute. Owned by the metadata, which
lives as long as the program, so it never has to be freed.

<sub>[stdlib/Reflection/Attribute.sl:31](../../stdlib/Reflection/Attribute.sl#L31)</sub>

#### Name *property*

```
String Name { get; }
```

The attribute's name, without the brackets.

<sub>[stdlib/Reflection/Attribute.sl:34](../../stdlib/Reflection/Attribute.sl#L34)</sub>

#### ValueCount *property*

```
nuint ValueCount { get; }
```

How many constants were written in the brackets.

<sub>[stdlib/Reflection/Attribute.sl:37](../../stdlib/Reflection/Attribute.sl#L37)</sub>

#### GetValueKind *method*

```
int GetValueKind(nuint index)
```

Which kind the value at `index` is -- one of the `Kind` constants --
so a reader knows whether to call `GetText` or `GetNumber`.

<sub>[stdlib/Reflection/Attribute.sl:41](../../stdlib/Reflection/Attribute.sl#L41)</sub>

#### GetText *method*

```
String GetText(nuint index)
```

The value as text. Only meaningful when GetValueKind is KindString.

<sub>[stdlib/Reflection/Attribute.sl:44](../../stdlib/Reflection/Attribute.sl#L44)</sub>

#### GetNumber *method*

```
long GetNumber(nuint index)
```

The value as a whole number. Meaningful for the integer kinds and for
`KindBool`, where one is true; zero for anything else, including a
string, rather than a reinterpretation of its pointer.

<sub>[stdlib/Reflection/Attribute.sl:52](../../stdlib/Reflection/Attribute.sl#L52)</sub>

### Field *struct*

```
struct Field
```

One field of a type: where it sits, what it holds, and what was written on
it.

A field is the storage. Writing one goes straight past any setter, which is
what a serializer filling plain data wants and what a type with behaviour in
its accessors does not -- see `IsPropertyStorage` and `Type.FindProperty`.

**See also** &nbsp; [Type.FindProperty](#findproperty-method) &middot; [Property](#property-struct)

<sub>[stdlib/Reflection/Field.sl:35](../../stdlib/Reflection/Field.sl#L35)</sub>

#### Handle *field*

```
byte* Handle
```

The runtime's record for this field, or null for one that was looked up
and not found. `Type.FindField` is what answers with a null one.

<sub>[stdlib/Reflection/Field.sl:39](../../stdlib/Reflection/Field.sl#L39)</sub>

#### Name *property*

```
String Name { get; }
```

The field's name. For an automatic property's storage this is the
property's name, which is why `IsPropertyStorage` has to exist.

<sub>[stdlib/Reflection/Field.sl:43](../../stdlib/Reflection/Field.sl#L43)</sub>

#### Offset *property*

```
nuint Offset { get; }
```

How many bytes from the start of the instance the field sits. Add it to
an instance pointer to reach the storage directly.

<sub>[stdlib/Reflection/Field.sl:47](../../stdlib/Reflection/Field.sl#L47)</sub>

#### Kind *property*

```
int Kind { get; }
```

What the field holds, as one of the `Kind` constants.

<sub>[stdlib/Reflection/Field.sl:50](../../stdlib/Reflection/Field.sl#L50)</sub>

#### AttributeCount *property*

```
nuint AttributeCount { get; }
```

How many attributes are written on the field.

<sub>[stdlib/Reflection/Field.sl:53](../../stdlib/Reflection/Field.sl#L53)</sub>

#### GetAttributeAt *method*

```
Attribute GetAttributeAt(nuint index)
```

The attribute at `index`, in the order they were written.

<sub>[stdlib/Reflection/Field.sl:56](../../stdlib/Reflection/Field.sl#L56)</sub>

#### IsPropertyStorage *property*

```
bool IsPropertyStorage { get; }
```

True when this field is an automatic property's storage rather than a
field the type declared.

**It is named after the property**, so without this a walk over the
field table cannot tell `Left` the storage from `Left` the property,
and writing it goes straight past the setter. Which one is right
depends on what is being filled: plain data wants the field, and
anything whose setter does work -- a control that re-lays-out when it
moves -- wants `Type.FindProperty` instead.

**See also** &nbsp; [Type.FindProperty](#findproperty-method)

<sub>[stdlib/Reflection/Field.sl:74](../../stdlib/Reflection/Field.sl#L74)</sub>

#### HasAttribute *method*

```
bool HasAttribute(String name)
```

True when an attribute of this name is written on the field.

<sub>[stdlib/Reflection/Field.sl:77](../../stdlib/Reflection/Field.sl#L77)</sub>

#### GetAttribute *method*

```
Attribute GetAttribute(String name)
```

The named attribute, if it is present. Check Has first.

<sub>[stdlib/Reflection/Field.sl:88](../../stdlib/Reflection/Field.sl#L88)</sub>

#### IsInteger *property*

```
bool IsInteger { get; }
```

True for a field whose value can be read as a whole number.

The two code unit kinds were added after the numbering was fixed, so
they sit past KindArray rather than beside KindChar and a range test
alone no longer reaches them.

<sub>[stdlib/Reflection/Field.sl:104](../../stdlib/Reflection/Field.sl#L104)</sub>

#### IsFloating *property*

```
bool IsFloating { get; }
```

True for a field whose value can be read as a `double` -- a `float` or
a `double`. An integer field is not one: `ReadDouble` on it answers
zero rather than converting.

<sub>[stdlib/Reflection/Field.sl:118](../../stdlib/Reflection/Field.sl#L118)</sub>

#### IsSimple *property*

```
bool IsSimple { get; }
```

True for a field this module can read and write by value: a number, a
bool or a String. Everything else is an aggregate, reached through
`FieldType` and walked rather than copied.

<sub>[stdlib/Reflection/Field.sl:123](../../stdlib/Reflection/Field.sl#L123)</sub>

#### FieldType *property*

```
Type FieldType { get; }
```

The type of a field that holds one, or a handle of null.

Set for a class, an interface and a struct; null for a primitive, whose
`Kind` is the whole of what there is to know. It is what makes a
nested object reachable: with the address of the field and the type of
what is in it, the walk continues without any of it being typed.

<sub>[stdlib/Reflection/Field.sl:137](../../stdlib/Reflection/Field.sl#L137)</sub>

#### IsAggregate *property*

```
bool IsAggregate { get; }
```

True when this field holds something with fields of its own.

<sub>[stdlib/Reflection/Field.sl:148](../../stdlib/Reflection/Field.sl#L148)</sub>

#### ElementKind *property*

```
int ElementKind { get; }
```

What an array field's elements are. `KindNone` for anything else.

<sub>[stdlib/Reflection/Field.sl:158](../../stdlib/Reflection/Field.sl#L158)</sub>

#### ElementType *property*

```
Type ElementType { get; }
```

The type of an array's elements, when they have one.

<sub>[stdlib/Reflection/Field.sl:161](../../stdlib/Reflection/Field.sl#L161)</sub>

#### ElementSize *property*

```
nuint ElementSize { get; }
```

How far apart an array's elements sit, in bytes. Zero for a field that
is not an array.

<sub>[stdlib/Reflection/Field.sl:173](../../stdlib/Reflection/Field.sl#L173)</sub>

#### IsArray *property*

```
bool IsArray { get; }
```

True when this field is an array whose elements can be read one by one.

A slice answers false: it is three words rather than a reference, so
its elements are not where this arithmetic would look.

<sub>[stdlib/Reflection/Field.sl:179](../../stdlib/Reflection/Field.sl#L179)</sub>

#### IsWalkable *property*

```
bool IsWalkable { get; }
```

True when this field can be walked into: it holds an aggregate, and
that aggregate carries field metadata of its own.

The second half is what tells a `[Reflect]` type from a `List<T>`.
Both are classes; only one has anything to walk, and a walk into the
other finds no fields and reports an empty object -- which is a lie
about a list that had things in it.

<sub>[stdlib/Reflection/Field.sl:188](../../stdlib/Reflection/Field.sl#L188)</sub>

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

**See also** &nbsp; [Field](#field-struct) &middot; [Type.FindProperty](#findproperty-method)

<sub>[stdlib/Reflection/Property.sl:43](../../stdlib/Reflection/Property.sl#L43)</sub>

#### Handle *field*

```
byte* Handle
```

The runtime's record for this property, or null for one that was looked
up and not found. `Exists` is the check.

<sub>[stdlib/Reflection/Property.sl:47](../../stdlib/Reflection/Property.sl#L47)</sub>

#### Name *property*

```
String Name { get; }
```

The property's name.

<sub>[stdlib/Reflection/Property.sl:50](../../stdlib/Reflection/Property.sl#L50)</sub>

#### Kind *property*

```
int Kind { get; }
```

What the property's type is, as one of the `Kind` constants.

<sub>[stdlib/Reflection/Property.sl:53](../../stdlib/Reflection/Property.sl#L53)</sub>

#### Exists *property*

```
bool Exists { get; }
```

True when this handle names a property at all; `FindProperty` answers
with a null one when there is no such name.

<sub>[stdlib/Reflection/Property.sl:57](../../stdlib/Reflection/Property.sl#L57)</sub>

#### CanRead *property*

```
bool CanRead { get; }
```

False for a write-only property, and for one whose getter this build
did not emit.

<sub>[stdlib/Reflection/Property.sl:61](../../stdlib/Reflection/Property.sl#L61)</sub>

#### CanWrite *property*

```
bool CanWrite { get; }
```

False for a read-only property -- `public int Left { get; }` -- which
is worth checking before a loader decides a document was ignored.

<sub>[stdlib/Reflection/Property.sl:65](../../stdlib/Reflection/Property.sl#L65)</sub>

#### PropertyType *property*

```
Type PropertyType { get; }
```

The type of an aggregate property, for walking into it. A handle of
null for a primitive.

<sub>[stdlib/Reflection/Property.sl:69](../../stdlib/Reflection/Property.sl#L69)</sub>

#### AttributeCount *property*

```
nuint AttributeCount { get; }
```

How many attributes are written on the property.

<sub>[stdlib/Reflection/Property.sl:80](../../stdlib/Reflection/Property.sl#L80)</sub>

#### GetAttributeAt *method*

```
Attribute GetAttributeAt(nuint index)
```

The attribute at `index`, in the order they were written.

<sub>[stdlib/Reflection/Property.sl:83](../../stdlib/Reflection/Property.sl#L83)</sub>

#### HasAttribute *method*

```
bool HasAttribute(String name)
```

True when an attribute of this name is written on the property.

<sub>[stdlib/Reflection/Property.sl:91](../../stdlib/Reflection/Property.sl#L91)</sub>

#### IsInteger *property*

```
bool IsInteger { get; }
```

The same three questions a `Field` answers about its kind.

**Value** &nbsp; true for a property whose value can be read as a whole number

**See also** &nbsp; [Field.IsInteger](#isinteger-property)

<sub>[stdlib/Reflection/Property.sl:105](../../stdlib/Reflection/Property.sl#L105)</sub>

#### IsFloating *property*

```
bool IsFloating { get; }
```

True for a `float` or a `double` property.

<sub>[stdlib/Reflection/Property.sl:117](../../stdlib/Reflection/Property.sl#L117)</sub>

#### IsText *property*

```
bool IsText { get; }
```

True for a `String` property.

<sub>[stdlib/Reflection/Property.sl:120](../../stdlib/Reflection/Property.sl#L120)</sub>

### Reflect *attribute*

```
attribute Reflect
```

Marks a class or struct to carry field metadata in the binary.

<sub>[stdlib/Reflection/Reflection.sl:34](../../stdlib/Reflection/Reflection.sl#L34)</sub>

### Type *struct*

```
struct Type
```

One type, and the way into everything it declares.

Got from `typeof(T)`, from `FindType` by name, or from a field's `FieldType` or a
property's `PropertyType`. Only a class or struct marked `[Reflect]` carries
metadata, and what it carries is its fields, properties and attributes;
methods are not described, so there is nothing here to call.

**See also** &nbsp; [FindType](#findtype-function)

<sub>[stdlib/Reflection/Type.sl:34](../../stdlib/Reflection/Type.sl#L34)</sub>

#### Handle *field*

```
byte* Handle
```

The runtime's record for this type, or null for one that was looked up
and not found. `Exists` is the check.

<sub>[stdlib/Reflection/Type.sl:38](../../stdlib/Reflection/Type.sl#L38)</sub>

#### Name *property*

```
String Name { get; }
```

The type's name, qualified by its module.

<sub>[stdlib/Reflection/Type.sl:41](../../stdlib/Reflection/Type.sl#L41)</sub>

#### Size *property*

```
nuint Size { get; }
```

How many bytes an instance occupies -- the struct's own size, or for a
class the size of the object including its header.

<sub>[stdlib/Reflection/Type.sl:45](../../stdlib/Reflection/Type.sl#L45)</sub>

#### FieldCount *property*

```
nuint FieldCount { get; }
```

How many fields the type has, inherited ones included, and automatic
properties' storage among them.

<sub>[stdlib/Reflection/Type.sl:49](../../stdlib/Reflection/Type.sl#L49)</sub>

#### GetFieldAt *method*

```
Field GetFieldAt(nuint index)
```

The field at `index`, in declaration order with inherited fields first.

<sub>[stdlib/Reflection/Type.sl:52](../../stdlib/Reflection/Type.sl#L52)</sub>

#### AttributeCount *property*

```
nuint AttributeCount { get; }
```

How many attributes are written on the type.

<sub>[stdlib/Reflection/Type.sl:60](../../stdlib/Reflection/Type.sl#L60)</sub>

#### GetAttributeAt *method*

```
Attribute GetAttributeAt(nuint index)
```

The attribute at `index`, in the order they were written.

<sub>[stdlib/Reflection/Type.sl:63](../../stdlib/Reflection/Type.sl#L63)</sub>

#### Exists *property*

```
bool Exists { get; }
```

True when this handle names a type at all. A `FieldType` on a primitive
field answers false.

<sub>[stdlib/Reflection/Type.sl:72](../../stdlib/Reflection/Type.sl#L72)</sub>

#### FindField *method*

```
Field FindField(String name)
```

The field of that name, or a handle of null. Names are compared whole,
so a serializer looking up what a document named does one pass.

<sub>[stdlib/Reflection/Type.sl:76](../../stdlib/Reflection/Type.sl#L76)</sub>

#### HasAttribute *method*

```
bool HasAttribute(String name)
```

True when the type carries an attribute of that name.

<sub>[stdlib/Reflection/Type.sl:91](../../stdlib/Reflection/Type.sl#L91)</sub>

#### PropertyCount *property*

```
nuint PropertyCount { get; }
```

How many properties the type has, inherited ones included.

A derived class lists everything it inherited, and a virtual property
it overrode appears once, at the position the base gave it, with the
**derived** accessors. What that does not do is dispatch: reaching an
object through `typeof(Base)` and setting a property the derived class
overrode calls the base's setter, where `.Left = x` in the language
would not.

<sub>[stdlib/Reflection/Type.sl:109](../../stdlib/Reflection/Type.sl#L109)</sub>

#### GetPropertyAt *method*

```
Property GetPropertyAt(nuint index)
```

The property at `index`. An overridden property appears once, at the
position the base gave it, carrying the derived accessors.

<sub>[stdlib/Reflection/Type.sl:113](../../stdlib/Reflection/Type.sl#L113)</sub>

#### FindProperty *method*

```
Property FindProperty(String name)
```

The property of that name, or a handle of null.

<sub>[stdlib/Reflection/Type.sl:121](../../stdlib/Reflection/Type.sl#L121)</sub>

## Functions

### CreateArrayInto *function*

```
byte* CreateArrayInto(byte* instance, Field field, nuint count)
```

Makes an array of `count` elements for an array field and stores it there,
answering its address.

**The one thing about an array that could not be done here.** Elements
could be read and written, and the stride made that possible without
knowing the element type -- but there was no way to *make* one, so a
document that said how many elements it had could only be read into an
array that already happened to be that long. That is the whole of why a
reader could round-trip an array and not fill one.

The elements are zero, which for a reference means null, so the array is
safe to write into in any order and safe to abandon half-filled.

**It stores the array rather than handing it over**, for the reason
`CreateInstanceInto` does: the reference an allocation answers with is
owned by whoever received it, this module keeps `sl_release` to itself, and
so a caller outside it had no way to let go of what `CreateArray` gave
them. Writing it into the field here, and dropping the allocation's
reference here, leaves the field the only owner and the caller nothing to
remember.

Null for a field that is not an array, and for one whose array type the
build recorded nothing for.

**See also** &nbsp; [CreateInstanceInto](#createinstanceinto-function) &middot; [WriteAggregate](#writeaggregate-function)

<sub>[stdlib/Reflection/Reflection.sl:517](../../stdlib/Reflection/Reflection.sl#L517)</sub>

### CreateInstance *function*

```
byte* CreateInstance(Type type)
```

Makes a zeroed instance of a type, for a reader that has a type and no
constructor to call.

**Every reference field starts null**, including one whose type says it
cannot be. What comes back is safe to fill and unsafe to hand out until it
has been: prefer making the object the ordinary way and filling it, which
is what `Json.PopulateObject` does and why it is the one that needs no warning.

**See also** &nbsp; [CreateInstanceInto](#createinstanceinto-function)

<sub>[stdlib/Reflection/Reflection.sl:423](../../stdlib/Reflection/Reflection.sl#L423)</sub>

### CreateInstanceInto *function*

```
byte* CreateInstanceInto(byte* instance, Field field)
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
the object already: `Json.PopulateObject` fills in place and only reaches for
this where a field is marked to say so.

**See also** &nbsp; [CreateInstance](#createinstance-function)

<sub>[stdlib/Reflection/Reflection.sl:455](../../stdlib/Reflection/Reflection.sl#L455)</sub>

### FindType *function*

```
Type FindType(String name)
```

The type of that **qualified** name -- "App.Button", as `Type.Name`
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
    if (type.Exists) { byte* made = CreateInstance(type); }

<sub>[stdlib/Reflection/Reflection.sl:407](../../stdlib/Reflection/Reflection.sl#L407)</sub>

### GetAggregate *function*

```
byte* GetAggregate(byte* instance, Property property)
```

The object a class or interface property holds, for walking into it.
Null where it holds nothing, which a caller has to check.

The answer is borrowed from the instance, as `ReadAggregate`'s is. The
property MUST be one that holds its object: a getter that makes a new
object on each call answers one nothing else owns, and it is freed before
this returns.

**See also** &nbsp; [ReadAggregate](#readaggregate-function) &middot; [SetAggregate](#setaggregate-function)

<sub>[stdlib/Reflection/Reflection.sl:225](../../stdlib/Reflection/Reflection.sl#L225)</sub>

### GetArrayLength *function*

```
nuint GetArrayLength(byte* array)
```

How many elements an array has. Zero for null.

<sub>[stdlib/Reflection/Reflection.sl:534](../../stdlib/Reflection/Reflection.sl#L534)</sub>

### GetBool *function*

```
bool GetBool(byte* instance, Property property)
```

Calls the getter of a `bool` property. False when it cannot be read, or
when its kind is not `KindBool` -- which is indistinguishable from a real
false, so check `CanRead` and `Kind` where it matters.

<sub>[stdlib/Reflection/Reflection.sl:194](../../stdlib/Reflection/Reflection.sl#L194)</sub>

### GetDouble *function*

```
double GetDouble(byte* instance, Property property)
```

Calls the getter of a `float` or `double` property. Zero when it cannot be
read, or when its kind is not a floating one.

<sub>[stdlib/Reflection/Reflection.sl:186](../../stdlib/Reflection/Reflection.sl#L186)</sub>

### GetElementAddress *function*

```
byte* GetElementAddress(byte* array, Field field, nuint index)
```

The address of one element, or null when the array is null or the index is
past its end. Checked rather than trusted: the caller is walking metadata,
and an index that came from a document is not the program's.

**Parameters**

- `array` — the array itself, as `ReadArray` answers it
- `field` — the array field, which supplies the stride between elements
- `index` — which element, counted from zero

<sub>[stdlib/Reflection/Reflection.sl:548](../../stdlib/Reflection/Reflection.sl#L548)</sub>

### GetInteger *function*

```
long GetInteger(byte* instance, Property property)
```

Calls the getter. Zero when the property cannot be read, or when its kind
is not a whole number -- rather than reading the wrong four bytes.

<sub>[stdlib/Reflection/Reflection.sl:179](../../stdlib/Reflection/Reflection.sl#L179)</sub>

### GetText *function*

```
String GetText(byte* instance, Property property)
```

Calls the getter of a String property, and answers a copy of what it gave.
Empty when the property cannot be read or its kind is not `KindString`.

<sub>[stdlib/Reflection/Reflection.sl:201](../../stdlib/Reflection/Reflection.sl#L201)</sub>

### ReadAggregate *function*

```
byte* ReadAggregate(byte* instance, Field field)
```

The address of a field that holds an aggregate, for walking into it.

A class field holds a reference, so the address is what it points at; a
struct field *is* its bytes, so the address is where it sits. Null for a
class field holding nothing, which is the one case a caller has to check.

**See also** &nbsp; [WriteAggregate](#writeaggregate-function)

<sub>[stdlib/Reflection/Reflection.sl:333](../../stdlib/Reflection/Reflection.sl#L333)</sub>

### ReadAggregateAt *function*

```
byte* ReadAggregateAt(byte* address, Field field)
```

The address of an aggregate element: what a class element points at, or
where a struct element sits.

<sub>[stdlib/Reflection/Reflection.sl:590](../../stdlib/Reflection/Reflection.sl#L590)</sub>

### ReadArray *function*

```
byte* ReadArray(byte* instance, Field field)
```

The array a field holds, or null. The instance still owns it.

<sub>[stdlib/Reflection/Reflection.sl:484](../../stdlib/Reflection/Reflection.sl#L484)</sub>

### ReadBool *function*

```
bool ReadBool(byte* instance, Field field)
```

Reads a `bool` field from an instance. False when the field's kind is not
`KindBool`, which reads the same as a real false.

**See also** &nbsp; [WriteBool](#writebool-function)

<sub>[stdlib/Reflection/Reflection.sl:299](../../stdlib/Reflection/Reflection.sl#L299)</sub>

### ReadBoolAt *function*

```
bool ReadBoolAt(byte* address)
```

Reads an element of a `bool` array. Takes no field, a `bool` being one byte
whatever array it is in.

<sub>[stdlib/Reflection/Reflection.sl:577](../../stdlib/Reflection/Reflection.sl#L577)</sub>

### ReadDouble *function*

```
double ReadDouble(byte* instance, Field field)
```

Reads a `float` or `double` field from an instance. Zero when the field's
kind is not a floating one -- no conversion from an integer field.

**See also** &nbsp; [WriteDouble](#writedouble-function)

<sub>[stdlib/Reflection/Reflection.sl:290](../../stdlib/Reflection/Reflection.sl#L290)</sub>

### ReadDoubleAt *function*

```
double ReadDoubleAt(byte* address, Field field)
```

Reads an element of a floating array. `field` supplies the element kind,
which is what says whether the four or the eight bytes at `address` are the
value.

<sub>[stdlib/Reflection/Reflection.sl:570](../../stdlib/Reflection/Reflection.sl#L570)</sub>

### ReadInteger *function*

```
long ReadInteger(byte* instance, Field field)
```

Reads a whole-number field from an instance.

**Returns** &nbsp; the value widened to a `long`, sign-extended from a signed kind and zero-extended from an unsigned one. Zero for a field whose kind is not a whole number. A `ulong` past the range of `long` comes back negative, with its bits unchanged.

**See also** &nbsp; [WriteInteger](#writeinteger-function)

<sub>[stdlib/Reflection/Reflection.sl:281](../../stdlib/Reflection/Reflection.sl#L281)</sub>

### ReadIntegerAt *function*

```
long ReadIntegerAt(byte* address, Field field)
```

Reads an element of a whole-number array.

**Parameters**

- `address` — where the element sits, from `GetElementAddress`
- `field` — the array field, which supplies the element kind

**See also** &nbsp; [WriteIntegerAt](#writeintegerat-function)

<sub>[stdlib/Reflection/Reflection.sl:562](../../stdlib/Reflection/Reflection.sl#L562)</sub>

### ReadText *function*

```
String ReadText(byte* instance, Field field)
```

Reads a String field, as a copy of all its bytes. Empty when the field's
kind is not `KindString`.

**See also** &nbsp; [WriteText](#writetext-function)

<sub>[stdlib/Reflection/Reflection.sl:308](../../stdlib/Reflection/Reflection.sl#L308)</sub>

### ReadTextAt *function*

```
String ReadTextAt(byte* address)
```

Reads a String element, as a copy of all its bytes.

<sub>[stdlib/Reflection/Reflection.sl:580](../../stdlib/Reflection/Reflection.sl#L580)</sub>

### SetAggregate *function*

```
void SetAggregate(byte* instance, Property property, byte* value)
```

Points a class or interface property at an object, on the same terms.

<sub>[stdlib/Reflection/Reflection.sl:267](../../stdlib/Reflection/Reflection.sl#L267)</sub>

### SetBool *function*

```
void SetBool(byte* instance, Property property, bool value)
```

Calls the setter of a `bool` property. Does nothing when there is no
setter, which `CanWrite` is how to find out in advance.

<sub>[stdlib/Reflection/Reflection.sl:252](../../stdlib/Reflection/Reflection.sl#L252)</sub>

### SetDouble *function*

```
void SetDouble(byte* instance, Property property, double value)
```

Calls the setter of a floating property, narrowing to `float` where that
is its width. Does nothing when there is no setter.

<sub>[stdlib/Reflection/Reflection.sl:245](../../stdlib/Reflection/Reflection.sl#L245)</sub>

### SetInteger *function*

```
void SetInteger(byte* instance, Property property, long value)
```

Calls the setter, narrowing to the property's own width. Does nothing when
there is no setter, which `CanWrite` is how to find out in advance.

<sub>[stdlib/Reflection/Reflection.sl:238](../../stdlib/Reflection/Reflection.sl#L238)</sub>

### SetText *function*

```
void SetText(byte* instance, Property property, String value)
```

Calls the setter of a String property.

The setter retains what it stores, so the caller still owns `value`
afterwards.

<sub>[stdlib/Reflection/Reflection.sl:261](../../stdlib/Reflection/Reflection.sl#L261)</sub>

### WriteAggregate *function*

```
void WriteAggregate(byte* instance, Field field, byte* value)
```

Points a reference field at an object made by `CreateInstance`, releasing whatever it
held. The field takes a reference of its own, so the caller still owns
theirs.

**See also** &nbsp; [CreateInstance](#createinstance-function) &middot; [ReadAggregate](#readaggregate-function)

<sub>[stdlib/Reflection/Reflection.sl:434](../../stdlib/Reflection/Reflection.sl#L434)</sub>

### WriteBool *function*

```
void WriteBool(byte* instance, Field field, bool value)
```

Writes a `bool` field.

**See also** &nbsp; [ReadBool](#readbool-function)

<sub>[stdlib/Reflection/Reflection.sl:375](../../stdlib/Reflection/Reflection.sl#L375)</sub>

### WriteBoolAt *function*

```
void WriteBoolAt(byte* address, bool value)
```

Writes an element of a `bool` array.

<sub>[stdlib/Reflection/Reflection.sl:616](../../stdlib/Reflection/Reflection.sl#L616)</sub>

### WriteDouble *function*

```
void WriteDouble(byte* instance, Field field, double value)
```

Writes a floating field, narrowed to `float` where that is its width.

**See also** &nbsp; [ReadDouble](#readdouble-function)

<sub>[stdlib/Reflection/Reflection.sl:367](../../stdlib/Reflection/Reflection.sl#L367)</sub>

### WriteDoubleAt *function*

```
void WriteDoubleAt(byte* address, Field field, double value)
```

Writes an element of a floating array, narrowed to the element's width.

<sub>[stdlib/Reflection/Reflection.sl:610](../../stdlib/Reflection/Reflection.sl#L610)</sub>

### WriteInteger *function*

```
void WriteInteger(byte* instance, Field field, long value)
```

Writes a whole-number field.

**See also** &nbsp; [ReadInteger](#readinteger-function)

<sub>[stdlib/Reflection/Reflection.sl:359](../../stdlib/Reflection/Reflection.sl#L359)</sub>

### WriteIntegerAt *function*

```
void WriteIntegerAt(byte* address, Field field, long value)
```

Writes an element of a whole-number array, narrowed to its width.

**See also** &nbsp; [ReadIntegerAt](#readintegerat-function)

<sub>[stdlib/Reflection/Reflection.sl:604](../../stdlib/Reflection/Reflection.sl#L604)</sub>

### WriteText *function*

```
void WriteText(byte* instance, Field field, String value)
```

Writes a String field, releasing whatever it held.

The bytes cross rather than the String, which is what keeps a counted
reference out of the runtime's ABI -- the same bargain `ReadText` makes in
the other direction. The field ends up owning a copy.

**See also** &nbsp; [ReadText](#readtext-function)

<sub>[stdlib/Reflection/Reflection.sl:387](../../stdlib/Reflection/Reflection.sl#L387)</sub>

### WriteTextAt *function*

```
void WriteTextAt(byte* address, String value)
```

Writes a String element, releasing whatever it held.

<sub>[stdlib/Reflection/Reflection.sl:619](../../stdlib/Reflection/Reflection.sl#L619)</sub>

## Constants

### KindArray *constant*

```
const int KindArray = 20
```

An array. `ElementKind` says what is in it.

<sub>[stdlib/Reflection/Reflection.sl:166](../../stdlib/Reflection/Reflection.sl#L166)</sub>

### KindBool *constant*

```
const int KindBool = 1
```

A `bool`.

<sub>[stdlib/Reflection/Reflection.sl:124](../../stdlib/Reflection/Reflection.sl#L124)</sub>

### KindByte *constant*

```
const int KindByte = 8
```

A `byte`.

<sub>[stdlib/Reflection/Reflection.sl:138](../../stdlib/Reflection/Reflection.sl#L138)</sub>

### KindChar *constant*

```
const int KindChar = 2
```

A `char`: one UTF-8 code unit.

<sub>[stdlib/Reflection/Reflection.sl:126](../../stdlib/Reflection/Reflection.sl#L126)</sub>

### KindChar16 *constant*

```
const int KindChar16 = 21
```

A `char16`: one UTF-16 code unit. Numbered past
`KindArray` because it was added after the numbering was fixed, which is
why `IsInteger` tests it separately.

<sub>[stdlib/Reflection/Reflection.sl:170](../../stdlib/Reflection/Reflection.sl#L170)</sub>

### KindChar32 *constant*

```
const int KindChar32 = 22
```

A `char32`: one Unicode scalar, with the same
numbering story as `KindChar16`.

<sub>[stdlib/Reflection/Reflection.sl:173](../../stdlib/Reflection/Reflection.sl#L173)</sub>

### KindClass *constant*

```
const int KindClass = 17
```

A class reference. `FieldType` gives the type to walk
into, and the value can be null.

<sub>[stdlib/Reflection/Reflection.sl:159](../../stdlib/Reflection/Reflection.sl#L159)</sub>

### KindDouble *constant*

```
const int KindDouble = 14
```

A `double`.

<sub>[stdlib/Reflection/Reflection.sl:150](../../stdlib/Reflection/Reflection.sl#L150)</sub>

### KindFloat *constant*

```
const int KindFloat = 13
```

A `float`.

<sub>[stdlib/Reflection/Reflection.sl:148](../../stdlib/Reflection/Reflection.sl#L148)</sub>

### KindInt *constant*

```
const int KindInt = 5
```

An `int`.

<sub>[stdlib/Reflection/Reflection.sl:132](../../stdlib/Reflection/Reflection.sl#L132)</sub>

### KindInterface *constant*

```
const int KindInterface = 18
```

An interface reference, walked like a class.

<sub>[stdlib/Reflection/Reflection.sl:161](../../stdlib/Reflection/Reflection.sl#L161)</sub>

### KindLong *constant*

```
const int KindLong = 6
```

A `long`.

<sub>[stdlib/Reflection/Reflection.sl:134](../../stdlib/Reflection/Reflection.sl#L134)</sub>

### KindNInt *constant*

```
const int KindNInt = 7
```

An `nint`: pointer-wide and signed.

<sub>[stdlib/Reflection/Reflection.sl:136](../../stdlib/Reflection/Reflection.sl#L136)</sub>

### KindNUInt *constant*

```
const int KindNUInt = 12
```

An `nuint`: pointer-wide and unsigned.

<sub>[stdlib/Reflection/Reflection.sl:146](../../stdlib/Reflection/Reflection.sl#L146)</sub>

### KindNone *constant*

```
const int KindNone = 0
```

What a field holds. Kept in step with enum SlKind in the runtime.

<sub>[stdlib/Reflection/Reflection.sl:122](../../stdlib/Reflection/Reflection.sl#L122)</sub>

### KindPointer *constant*

```
const int KindPointer = 15
```

A raw pointer. Nothing here follows one -- what it
points at carries no metadata.

<sub>[stdlib/Reflection/Reflection.sl:153](../../stdlib/Reflection/Reflection.sl#L153)</sub>

### KindSByte *constant*

```
const int KindSByte = 3
```

An `sbyte`.

<sub>[stdlib/Reflection/Reflection.sl:128](../../stdlib/Reflection/Reflection.sl#L128)</sub>

### KindShort *constant*

```
const int KindShort = 4
```

A `short`.

<sub>[stdlib/Reflection/Reflection.sl:130](../../stdlib/Reflection/Reflection.sl#L130)</sub>

### KindString *constant*

```
const int KindString = 16
```

A `String`. Read and written by value, through
`ReadText` and `WriteText`.

<sub>[stdlib/Reflection/Reflection.sl:156](../../stdlib/Reflection/Reflection.sl#L156)</sub>

### KindStruct *constant*

```
const int KindStruct = 19
```

A struct, stored inline rather than referenced -- so
its address is where it sits, and it is never null.

<sub>[stdlib/Reflection/Reflection.sl:164](../../stdlib/Reflection/Reflection.sl#L164)</sub>

### KindUInt *constant*

```
const int KindUInt = 10
```

A `uint`.

<sub>[stdlib/Reflection/Reflection.sl:142](../../stdlib/Reflection/Reflection.sl#L142)</sub>

### KindULong *constant*

```
const int KindULong = 11
```

A `ulong`.

<sub>[stdlib/Reflection/Reflection.sl:144](../../stdlib/Reflection/Reflection.sl#L144)</sub>

### KindUShort *constant*

```
const int KindUShort = 9
```

A `ushort`.

<sub>[stdlib/Reflection/Reflection.sl:140](../../stdlib/Reflection/Reflection.sl#L140)</sub>

