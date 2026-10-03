# Standard.Reflection

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

Reading the metadata the compiler laid down.

There is no runtime machinery behind this: a reflected type's fields and
attributes are `const` tables in the binary, and everything below is a typed
view over them. That is why reflection works in a natively compiled language
at all -- it is a layout agreement, not a virtual machine.

A type carries metadata only when it is marked [Reflect]. Nothing else does,
so nothing else pays for it.

**Nothing here makes a value its type does not allow** (§2.16). An object
is made only the way `new C()` makes one, by running its public
parameterless constructor, so every field that constructor writes holds a
value. What the constructor leaves to its caller -- a `required` member --
and the elements of a new array are the maker's to fill: the overloads
taking `fill` hand the new storage to it, then check that no field or
element whose type has no zero value is still null, and release the lot
and answer null if one is. A zeroed object is not on offer at all, and a
writer refuses a null for a field that is never null.

The accessors still take a `byte*`, and what a program does with one is
its own affair: a pointer can be cast to anything.

## Contents

**Types** &nbsp; [Attribute](#attribute-struct) &middot; [Event](#event-struct) &middot; [Field](#field-struct) &middot; [Property](#property-struct) &middot; [Reflect](#reflect-attribute) &middot; [Type](#type-struct)

**Functions** &nbsp; [CreateArrayInto](#createarrayinto-function) &middot; [CreateArrayInto](#createarrayinto-function) &middot; [CreateElementAt](#createelementat-function) &middot; [CreateInstance](#createinstance-function) &middot; [CreateInstance](#createinstance-function) &middot; [CreateInstanceInto](#createinstanceinto-function) &middot; [CreateInstanceInto](#createinstanceinto-function) &middot; [FindType](#findtype-function) &middot; [GetAggregate](#getaggregate-function) &middot; [GetArrayLength](#getarraylength-function) &middot; [GetBool](#getbool-function) &middot; [GetDouble](#getdouble-function) &middot; [GetElementAddress](#getelementaddress-function) &middot; [GetInteger](#getinteger-function) &middot; [GetText](#gettext-function) &middot; [IsElementNull](#iselementnull-function) &middot; [IsFieldNull](#isfieldnull-function) &middot; [ReadAggregate](#readaggregate-function) &middot; [ReadAggregateAt](#readaggregateat-function) &middot; [ReadArray](#readarray-function) &middot; [ReadBool](#readbool-function) &middot; [ReadBoolAt](#readboolat-function) &middot; [ReadDouble](#readdouble-function) &middot; [ReadDoubleAt](#readdoubleat-function) &middot; [ReadInteger](#readinteger-function) &middot; [ReadIntegerAt](#readintegerat-function) &middot; [ReadText](#readtext-function) &middot; [ReadTextAt](#readtextat-function) &middot; [SetAggregate](#setaggregate-function) &middot; [SetBool](#setbool-function) &middot; [SetDouble](#setdouble-function) &middot; [SetInteger](#setinteger-function) &middot; [SetText](#settext-function) &middot; [WriteAggregate](#writeaggregate-function) &middot; [WriteBool](#writebool-function) &middot; [WriteBoolAt](#writeboolat-function) &middot; [WriteDouble](#writedouble-function) &middot; [WriteDoubleAt](#writedoubleat-function) &middot; [WriteInteger](#writeinteger-function) &middot; [WriteIntegerAt](#writeintegerat-function) &middot; [WriteText](#writetext-function) &middot; [WriteTextAt](#writetextat-function)

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

### Event *struct*

```
struct Event
```

A public event of a reflected class: its name, and the delegate a handler
has to match.

**Described, not raised or subscribed.** A handler is a method, and
methods are not described; what this is for is a tool that writes the
`+=` into source, such as a form designer.

**See also** &nbsp; [Type.GetEventAt](#geteventat-method)

<sub>[stdlib/Reflection/Event.sl:32](../../stdlib/Reflection/Event.sl#L32)</sub>

#### Type *field*

```
byte* Type
```

The class's runtime record, and which of its events this is.

<sub>[stdlib/Reflection/Event.sl:35](../../stdlib/Reflection/Event.sl#L35)</sub>

#### Index *field*

```
nuint Index
```

*No documentation.*

<sub>[stdlib/Reflection/Event.sl:36](../../stdlib/Reflection/Event.sl#L36)</sub>

#### Name *property*

```
String Name { get; }
```

The event's name.

<sub>[stdlib/Reflection/Event.sl:39](../../stdlib/Reflection/Event.sl#L39)</sub>

#### HandlerTypeName *property*

```
String HandlerTypeName { get; }
```

The delegate's name, qualified by its module: `Forms.EventHandler`.

<sub>[stdlib/Reflection/Event.sl:42](../../stdlib/Reflection/Event.sl#L42)</sub>

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

#### HasZeroValue *property*

```
bool HasZeroValue { get; }
```

True when zero bytes are a value of the field's type (§2.16).

False for a `String`, a class, an interface, an array or a closure that
is never null, and for a struct holding one. Reflection never leaves
such a field zero: `WriteAggregate` refuses a null for it, and an
object it makes has it written by the constructor or checked before it
is handed out.

**See also** &nbsp; `IsNullable`

<sub>[stdlib/Reflection/Field.sl:85](../../stdlib/Reflection/Field.sl#L85)</sub>

#### IsNullable *property*

```
bool IsNullable { get; }
```

True for a reference that may hold null: a `String?`, `C?`, `I?` or
`T[]?`. False for one that is never null, and for anything that is not
a reference.

<sub>[stdlib/Reflection/Field.sl:90](../../stdlib/Reflection/Field.sl#L90)</sub>

#### IsRequired *property*

```
bool IsRequired { get; }
```

True when whoever makes an instance MUST give this field a value: it is
`required`, or is the storage of a `required` property, and the
constructor `CreateInstance` runs is not `[SetsRequiredMembers]`.

Only a required field whose type has no zero value can be checked, by
asking whether it is null. One of a value type is the maker's word.

<sub>[stdlib/Reflection/Field.sl:113](../../stdlib/Reflection/Field.sl#L113)</sub>

#### ElementHasZeroValue *property*

```
bool ElementHasZeroValue { get; }
```

True for an array field whose elements have a zero value, so an array
made for it by `CreateArrayInto` is complete before anything is written.
True for a field that is not an array.

<sub>[stdlib/Reflection/Field.sl:118](../../stdlib/Reflection/Field.sl#L118)</sub>

#### HasAttribute *method*

```
bool HasAttribute(String name)
```

True when an attribute of this name is written on the field.

<sub>[stdlib/Reflection/Field.sl:121](../../stdlib/Reflection/Field.sl#L121)</sub>

#### GetAttribute *method*

```
Attribute GetAttribute(String name)
```

The named attribute, if it is present. Check Has first.

<sub>[stdlib/Reflection/Field.sl:132](../../stdlib/Reflection/Field.sl#L132)</sub>

#### IsInteger *property*

```
bool IsInteger { get; }
```

True for a field whose value can be read as a whole number.

The two code unit kinds were added after the numbering was fixed, so
they sit past KindArray rather than beside KindChar and a range test
alone no longer reaches them.

<sub>[stdlib/Reflection/Field.sl:148](../../stdlib/Reflection/Field.sl#L148)</sub>

#### IsFloating *property*

```
bool IsFloating { get; }
```

True for a field whose value can be read as a `double` -- a `float` or
a `double`. An integer field is not one: `ReadDouble` on it answers
zero rather than converting.

<sub>[stdlib/Reflection/Field.sl:162](../../stdlib/Reflection/Field.sl#L162)</sub>

#### IsSimple *property*

```
bool IsSimple { get; }
```

True for a field this module can read and write by value: a number, a
bool or a String. Everything else is an aggregate, reached through
`FieldType` and walked rather than copied.

<sub>[stdlib/Reflection/Field.sl:167](../../stdlib/Reflection/Field.sl#L167)</sub>

#### FieldType *property*

```
Type FieldType { get; }
```

The type of a field that holds one, or a handle of null.

Set for a class, an interface and a struct; null for a primitive, whose
`Kind` is the whole of what there is to know. It is what makes a
nested object reachable: with the address of the field and the type of
what is in it, the walk continues without any of it being typed.

<sub>[stdlib/Reflection/Field.sl:181](../../stdlib/Reflection/Field.sl#L181)</sub>

#### IsAggregate *property*

```
bool IsAggregate { get; }
```

True when this field holds something with fields of its own.

<sub>[stdlib/Reflection/Field.sl:192](../../stdlib/Reflection/Field.sl#L192)</sub>

#### ElementKind *property*

```
int ElementKind { get; }
```

What an array field's elements are. `KindNone` for anything else.

<sub>[stdlib/Reflection/Field.sl:202](../../stdlib/Reflection/Field.sl#L202)</sub>

#### ElementType *property*

```
Type ElementType { get; }
```

The type of an array's elements, when they have one.

<sub>[stdlib/Reflection/Field.sl:205](../../stdlib/Reflection/Field.sl#L205)</sub>

#### ElementSize *property*

```
nuint ElementSize { get; }
```

How far apart an array's elements sit, in bytes. Zero for a field that
is not an array.

<sub>[stdlib/Reflection/Field.sl:217](../../stdlib/Reflection/Field.sl#L217)</sub>

#### IsArray *property*

```
bool IsArray { get; }
```

True when this field is an array whose elements can be read one by one.

A slice answers false: it is three words rather than a reference, so
its elements are not where this arithmetic would look.

<sub>[stdlib/Reflection/Field.sl:223](../../stdlib/Reflection/Field.sl#L223)</sub>

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

<sub>[stdlib/Reflection/Field.sl:232](../../stdlib/Reflection/Field.sl#L232)</sub>

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

#### IsPublic *property*

```
bool IsPublic { get; }
```

Whether any code may reach it, rather than its own class and module
only. The table lists both.

<sub>[stdlib/Reflection/Property.sl:61](../../stdlib/Reflection/Property.sl#L61)</sub>

#### HasZeroValue *property*

```
bool HasZeroValue { get; }
```

True when zero bytes are a value of the property's type. False for a
reference that is never null, and `SetAggregate` refuses a null for
one.

<sub>[stdlib/Reflection/Property.sl:66](../../stdlib/Reflection/Property.sl#L66)</sub>

#### CanRead *property*

```
bool CanRead { get; }
```

False for a write-only property, and for one whose getter this build
did not emit.

<sub>[stdlib/Reflection/Property.sl:70](../../stdlib/Reflection/Property.sl#L70)</sub>

#### CanWrite *property*

```
bool CanWrite { get; }
```

False for a read-only property -- `public int Left { get; }` -- which
is worth checking before a loader decides a document was ignored.

<sub>[stdlib/Reflection/Property.sl:74](../../stdlib/Reflection/Property.sl#L74)</sub>

#### PropertyType *property*

```
Type PropertyType { get; }
```

The type of an aggregate property, for walking into it. A handle of
null for a primitive.

<sub>[stdlib/Reflection/Property.sl:78](../../stdlib/Reflection/Property.sl#L78)</sub>

#### AttributeCount *property*

```
nuint AttributeCount { get; }
```

How many attributes are written on the property.

<sub>[stdlib/Reflection/Property.sl:89](../../stdlib/Reflection/Property.sl#L89)</sub>

#### GetAttributeAt *method*

```
Attribute GetAttributeAt(nuint index)
```

The attribute at `index`, in the order they were written.

<sub>[stdlib/Reflection/Property.sl:92](../../stdlib/Reflection/Property.sl#L92)</sub>

#### HasAttribute *method*

```
bool HasAttribute(String name)
```

True when an attribute of this name is written on the property.

<sub>[stdlib/Reflection/Property.sl:100](../../stdlib/Reflection/Property.sl#L100)</sub>

#### IsInteger *property*

```
bool IsInteger { get; }
```

The same three questions a `Field` answers about its kind.

**Value** &nbsp; true for a property whose value can be read as a whole number

**See also** &nbsp; [Field.IsInteger](#isinteger-property)

<sub>[stdlib/Reflection/Property.sl:114](../../stdlib/Reflection/Property.sl#L114)</sub>

#### IsFloating *property*

```
bool IsFloating { get; }
```

True for a `float` or a `double` property.

<sub>[stdlib/Reflection/Property.sl:126](../../stdlib/Reflection/Property.sl#L126)</sub>

#### IsText *property*

```
bool IsText { get; }
```

True for a `String` property.

<sub>[stdlib/Reflection/Property.sl:129](../../stdlib/Reflection/Property.sl#L129)</sub>

### Reflect *attribute*

```
attribute Reflect
```

Marks a class or struct to carry field metadata in the binary.

<sub>[stdlib/Reflection/Reflect.sl:25](../../stdlib/Reflection/Reflect.sl#L25)</sub>

### Type *struct*

```
struct Type
```

One type, and the way into everything it declares.

Got from `typeof(T)`, from `FindType` by name, or from a field's `FieldType` or a
property's `PropertyType`. Only a class or struct marked `[Reflect]` carries
metadata, and what it carries is its fields, properties, public events and
attributes; methods are not described, so there is nothing here to call.

**An enum is described where a reflected field or property names it**: its
members, and its attributes, which is where `[Flags]` is read.

**See also** &nbsp; [FindType](#findtype-function)

<sub>[stdlib/Reflection/Type.sl:37](../../stdlib/Reflection/Type.sl#L37)</sub>

#### Handle *field*

```
byte* Handle
```

The runtime's record for this type, or null for one that was looked up
and not found. `Exists` is the check.

<sub>[stdlib/Reflection/Type.sl:41](../../stdlib/Reflection/Type.sl#L41)</sub>

#### Name *property*

```
String Name { get; }
```

The type's name, qualified by its module.

<sub>[stdlib/Reflection/Type.sl:44](../../stdlib/Reflection/Type.sl#L44)</sub>

#### Size *property*

```
nuint Size { get; }
```

How many bytes an instance occupies -- the struct's own size, or for a
class the size of the object including its header.

<sub>[stdlib/Reflection/Type.sl:48](../../stdlib/Reflection/Type.sl#L48)</sub>

#### FieldCount *property*

```
nuint FieldCount { get; }
```

How many fields the type has, inherited ones included, and automatic
properties' storage among them.

<sub>[stdlib/Reflection/Type.sl:52](../../stdlib/Reflection/Type.sl#L52)</sub>

#### GetFieldAt *method*

```
Field GetFieldAt(nuint index)
```

The field at `index`, in declaration order with inherited fields first.

<sub>[stdlib/Reflection/Type.sl:55](../../stdlib/Reflection/Type.sl#L55)</sub>

#### AttributeCount *property*

```
nuint AttributeCount { get; }
```

How many attributes are written on the type.

<sub>[stdlib/Reflection/Type.sl:63](../../stdlib/Reflection/Type.sl#L63)</sub>

#### GetAttributeAt *method*

```
Attribute GetAttributeAt(nuint index)
```

The attribute at `index`, in the order they were written.

<sub>[stdlib/Reflection/Type.sl:66](../../stdlib/Reflection/Type.sl#L66)</sub>

#### Exists *property*

```
bool Exists { get; }
```

True when this handle names a type at all. A `FieldType` on a primitive
field answers false.

<sub>[stdlib/Reflection/Type.sl:75](../../stdlib/Reflection/Type.sl#L75)</sub>

#### CanCreateInstance *property*

```
bool CanCreateInstance { get; }
```

True when `CreateInstance` can make one: a reflected class that is not
abstract, with a public parameterless constructor or none at all.

**See also** &nbsp; [CreateInstance](#createinstance-function)

<sub>[stdlib/Reflection/Type.sl:81](../../stdlib/Reflection/Type.sl#L81)</sub>

#### FindField *method*

```
Field FindField(String name)
```

The field of that name, or a handle of null. Names are compared whole,
so a serializer looking up what a document named does one pass.

<sub>[stdlib/Reflection/Type.sl:85](../../stdlib/Reflection/Type.sl#L85)</sub>

#### HasAttribute *method*

```
bool HasAttribute(String name)
```

True when the type carries an attribute of that name.

<sub>[stdlib/Reflection/Type.sl:100](../../stdlib/Reflection/Type.sl#L100)</sub>

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

<sub>[stdlib/Reflection/Type.sl:118](../../stdlib/Reflection/Type.sl#L118)</sub>

#### GetPropertyAt *method*

```
Property GetPropertyAt(nuint index)
```

The property at `index`. An overridden property appears once, at the
position the base gave it, carrying the derived accessors.

<sub>[stdlib/Reflection/Type.sl:122](../../stdlib/Reflection/Type.sl#L122)</sub>

#### IsEnum *property*

```
bool IsEnum { get; }
```

Whether this is an enum, whose members `EnumMemberCount` and the two
after it describe.

<sub>[stdlib/Reflection/Type.sl:131](../../stdlib/Reflection/Type.sl#L131)</sub>

#### EnumMemberCount *property*

```
nuint EnumMemberCount { get; }
```

How many members an enum has; zero for anything else.

<sub>[stdlib/Reflection/Type.sl:134](../../stdlib/Reflection/Type.sl#L134)</sub>

#### GetEnumMemberName *method*

```
String GetEnumMemberName(nuint index)
```

An enum member's name, in declaration order.

<sub>[stdlib/Reflection/Type.sl:137](../../stdlib/Reflection/Type.sl#L137)</sub>

#### GetEnumMemberValue *method*

```
long GetEnumMemberValue(nuint index)
```

An enum member's value. A property of the enum's type is read and
written with `GetInteger` and `SetInteger`.

<sub>[stdlib/Reflection/Type.sl:142](../../stdlib/Reflection/Type.sl#L142)</sub>

#### EventCount *property*

```
nuint EventCount { get; }
```

How many public events a class has, inherited ones included.

<sub>[stdlib/Reflection/Type.sl:145](../../stdlib/Reflection/Type.sl#L145)</sub>

#### GetEventAt *method*

```
Event GetEventAt(nuint index)
```

The event at `index`, a base's before its derived class's.

<sub>[stdlib/Reflection/Type.sl:148](../../stdlib/Reflection/Type.sl#L148)</sub>

#### FindProperty *method*

```
Property FindProperty(String name)
```

The property of that name, or a handle of null.

<sub>[stdlib/Reflection/Type.sl:157](../../stdlib/Reflection/Type.sl#L157)</sub>

## Functions

### CreateArrayInto *function*

```
byte* CreateArrayInto(byte* instance, Field field, nuint count)
```

Makes an array of `count` elements for an array field and stores it there,
answering its address.

The elements are zero, so this is only for elements that have a zero
value (`Field.ElementHasZeroValue`): numbers, `bool`s, nullable references.
For anything else it answers null, and the overload taking `fill` is the
one to use.

**It stores the array rather than handing it over.** The reference an
allocation answers with is owned by whoever received it, and this module
keeps `sl_release` to itself; writing it into the field here and dropping
the allocation's reference leaves the field the only owner and the caller
nothing to remember.

Null for a field that is not an array, and for one whose array type the
build recorded nothing for.

**See also** &nbsp; [CreateInstanceInto](#createinstanceinto-function) &middot; [WriteAggregate](#writeaggregate-function)

<sub>[stdlib/Reflection/Reflection.sl:635](../../stdlib/Reflection/Reflection.sl#L635)</sub>

### CreateArrayInto *function*

```
byte* CreateArrayInto(byte* instance, Field field, nuint count, Func<byte*, bool> fill)
```

Makes an array of `count` elements, hands it to `fill`, and stores it in
the field only if every element then holds a value of its type.

The elements start as zero bytes. `fill` writes them -- `WriteTextAt`,
`CreateElementAt`, or through `ReadAggregateAt` for a struct element --
and answers whether it could. Then every element whose type has no zero
value is asked whether it is still null, walking into a struct element's
fields; if one is, or `fill` answered false, the array is released and the
field keeps what it had. `fill` MUST NOT keep the address it is given.

**Parameters**

- `instance` -- the object holding the field
- `field` -- an array field
- `count` -- how many elements
- `fill` -- writes every element, and answers whether it could

**Returns** &nbsp; the array, now owned by the field, or null

**See also** &nbsp; [CreateElementAt](#createelementat-function)

<sub>[stdlib/Reflection/Reflection.sl:659](../../stdlib/Reflection/Reflection.sl#L659)</sub>

### CreateElementAt *function*

```
byte* CreateElementAt(byte* address, Field field, Func<byte*, bool> fill)
```

Makes an object for a class element of an array, as `CreateInstance`
does, and stores it at `address`, releasing what the element held.

**Parameters**

- `address` -- where the element sits, from `GetElementAddress`
- `field` -- the array field, whose element type is what is made
- `fill` -- writes what the constructor left, and answers whether it could

**Returns** &nbsp; the object, now owned by the array, or null with the element untouched

**See also** &nbsp; [CreateArrayInto](#createarrayinto-function)

<sub>[stdlib/Reflection/Reflection.sl:586](../../stdlib/Reflection/Reflection.sl#L586)</sub>

### CreateInstance *function*

```
byte* CreateInstance(Type type)
```

Makes an instance of a reflected class as `new T()` would: allocated, its
events given empty lists, and its public parameterless constructor run.

Null when `type` cannot be made that way (`Type.CanCreateInstance`
answers which), and when it has a member `IsRequired` says the maker
MUST supply, since `new T()` with nothing to supply it would be refused
too. The overload taking `fill` is the one for that.

The caller owns the answer's reference, and nothing here takes it back:
`WriteAggregate` takes a reference of its own and leaves this one owed.
`CreateInstanceInto` is the form that leaves nothing to release.

    var type = FindType("App.Button");
    byte* made = CreateInstance(type);

**See also** &nbsp; [Type.CanCreateInstance](#cancreateinstance-property) &middot; [CreateInstanceInto](#createinstanceinto-function)

<sub>[stdlib/Reflection/Reflection.sl:472](../../stdlib/Reflection/Reflection.sl#L472)</sub>

### CreateInstance *function*

```
byte* CreateInstance(Type type, Func<byte*, bool> fill)
```

Makes an instance as `new T()` would, hands it to `fill`, and answers it
only if it is then complete.

Complete means `fill` answered true and no member the maker MUST supply
whose type has no zero value is still null. Otherwise the object is
released and the answer is null, so nothing half-made is ever handed out.
A required member of a value type cannot be asked, and is `fill`'s word.

`fill` MUST NOT keep the address it is given: an object that does not come
out complete is gone when this returns.

**Parameters**

- `type` -- the class to make
- `fill` -- writes what the constructor left, and answers whether it could

**Returns** &nbsp; the object, which the caller owns, or null

**See also** &nbsp; [CreateInstanceInto](#createinstanceinto-function)

<sub>[stdlib/Reflection/Reflection.sl:494](../../stdlib/Reflection/Reflection.sl#L494)</sub>

### CreateInstanceInto *function*

```
byte* CreateInstanceInto(byte* instance, Field field)
```

Makes an object of a class field's own type as `CreateInstance` does,
stores it in that field, and answers its address. Null, with the field
untouched, when the field is not a class or its type cannot be made.

The field owns the object; the caller has nothing to release.

**See also** &nbsp; [CreateInstance](#createinstance-function)

<sub>[stdlib/Reflection/Reflection.sl:539](../../stdlib/Reflection/Reflection.sl#L539)</sub>

### CreateInstanceInto *function*

```
byte* CreateInstanceInto(byte* instance, Field field, Func<byte*, bool> fill)
```

The same, with `fill` run and the object checked before it is stored, as
`CreateInstance(type, fill)` does. The field is written only with an object
that is complete, so a failed fill leaves it as it was.

**Parameters**

- `instance` -- the object holding the field
- `field` -- a class field, whose type is what is made
- `fill` -- writes what the constructor left, and answers whether it could

**Returns** &nbsp; the object, now owned by the field, or null

**See also** &nbsp; [CreateInstance](#createinstance-function)

<sub>[stdlib/Reflection/Reflection.sl:557](../../stdlib/Reflection/Reflection.sl#L557)</sub>

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

<sub>[stdlib/Reflection/Reflection.sl:448](../../stdlib/Reflection/Reflection.sl#L448)</sub>

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

<sub>[stdlib/Reflection/Reflection.sl:250](../../stdlib/Reflection/Reflection.sl#L250)</sub>

### GetArrayLength *function*

```
nuint GetArrayLength(byte* array)
```

How many elements an array has. Zero for null.

<sub>[stdlib/Reflection/Reflection.sl:693](../../stdlib/Reflection/Reflection.sl#L693)</sub>

### GetBool *function*

```
bool GetBool(byte* instance, Property property)
```

Calls the getter of a `bool` property. False when it cannot be read, or
when its kind is not `KindBool` -- which is indistinguishable from a real
false, so check `CanRead` and `Kind` where it matters.

<sub>[stdlib/Reflection/Reflection.sl:219](../../stdlib/Reflection/Reflection.sl#L219)</sub>

### GetDouble *function*

```
double GetDouble(byte* instance, Property property)
```

Calls the getter of a `float` or `double` property. Zero when it cannot be
read, or when its kind is not a floating one.

<sub>[stdlib/Reflection/Reflection.sl:211](../../stdlib/Reflection/Reflection.sl#L211)</sub>

### GetElementAddress *function*

```
byte* GetElementAddress(byte* array, Field field, nuint index)
```

The address of one element, or null when the array is null or the index is
past its end. Checked rather than trusted: the caller is walking metadata,
and an index that came from a document is not the program's.

**Parameters**

- `array` -- the array itself, as `ReadArray` answers it
- `field` -- the array field, which supplies the stride between elements
- `index` -- which element, counted from zero

<sub>[stdlib/Reflection/Reflection.sl:707](../../stdlib/Reflection/Reflection.sl#L707)</sub>

### GetInteger *function*

```
long GetInteger(byte* instance, Property property)
```

Calls the getter. Zero when the property cannot be read, or when its kind
is not a whole number -- rather than reading the wrong four bytes.

<sub>[stdlib/Reflection/Reflection.sl:204](../../stdlib/Reflection/Reflection.sl#L204)</sub>

### GetText *function*

```
String GetText(byte* instance, Property property)
```

Calls the getter of a String property, and answers a copy of what it gave.
Empty when the property cannot be read or its kind is not `KindString`.

<sub>[stdlib/Reflection/Reflection.sl:226](../../stdlib/Reflection/Reflection.sl#L226)</sub>

### IsElementNull *function*

```
bool IsElementNull(byte* address, Field field)
```

True when a reference element holds null, which only an element of a
nullable type can. `ReadTextAt` answers `""` for such a String.

**Parameters**

- `address` -- where the element sits, from `GetElementAddress`
- `field` -- the array field, which supplies the element kind

<sub>[stdlib/Reflection/Reflection.sl:743](../../stdlib/Reflection/Reflection.sl#L743)</sub>

### IsFieldNull *function*

```
bool IsFieldNull(byte* instance, Field field)
```

True when a reference field holds null, which only a nullable one can.
`ReadText` answers `""` for such a String, so this is how to tell.

<sub>[stdlib/Reflection/Reflection.sl:346](../../stdlib/Reflection/Reflection.sl#L346)</sub>

### ReadAggregate *function*

```
byte* ReadAggregate(byte* instance, Field field)
```

The address of a field that holds an aggregate, for walking into it.

A class field holds a reference, so the address is what it points at; a
struct field *is* its bytes, so the address is where it sits. Null for a
class field holding nothing, which is the one case a caller has to check.

**See also** &nbsp; [WriteAggregate](#writeaggregate-function)

<sub>[stdlib/Reflection/Reflection.sl:374](../../stdlib/Reflection/Reflection.sl#L374)</sub>

### ReadAggregateAt *function*

```
byte* ReadAggregateAt(byte* address, Field field)
```

The address of an aggregate element: what a class element points at, or
where a struct element sits.

<sub>[stdlib/Reflection/Reflection.sl:768](../../stdlib/Reflection/Reflection.sl#L768)</sub>

### ReadArray *function*

```
byte* ReadArray(byte* instance, Field field)
```

The array a field holds, or null. The instance still owns it.

<sub>[stdlib/Reflection/Reflection.sl:609](../../stdlib/Reflection/Reflection.sl#L609)</sub>

### ReadBool *function*

```
bool ReadBool(byte* instance, Field field)
```

Reads a `bool` field from an instance. False when the field's kind is not
`KindBool`, which reads the same as a real false.

**See also** &nbsp; [WriteBool](#writebool-function)

<sub>[stdlib/Reflection/Reflection.sl:324](../../stdlib/Reflection/Reflection.sl#L324)</sub>

### ReadBoolAt *function*

```
bool ReadBoolAt(byte* address)
```

Reads an element of a `bool` array. Takes no field, a `bool` being one byte
whatever array it is in.

<sub>[stdlib/Reflection/Reflection.sl:736](../../stdlib/Reflection/Reflection.sl#L736)</sub>

### ReadDouble *function*

```
double ReadDouble(byte* instance, Field field)
```

Reads a `float` or `double` field from an instance. Zero when the field's
kind is not a floating one -- no conversion from an integer field.

**See also** &nbsp; [WriteDouble](#writedouble-function)

<sub>[stdlib/Reflection/Reflection.sl:315](../../stdlib/Reflection/Reflection.sl#L315)</sub>

### ReadDoubleAt *function*

```
double ReadDoubleAt(byte* address, Field field)
```

Reads an element of a floating array. `field` supplies the element kind,
which is what says whether the four or the eight bytes at `address` are the
value.

<sub>[stdlib/Reflection/Reflection.sl:729](../../stdlib/Reflection/Reflection.sl#L729)</sub>

### ReadInteger *function*

```
long ReadInteger(byte* instance, Field field)
```

Reads a whole-number field from an instance.

**Returns** &nbsp; the value widened to a `long`, sign-extended from a signed kind and zero-extended from an unsigned one. Zero for a field whose kind is not a whole number. A `ulong` past the range of `long` comes back negative, with its bits unchanged.

**See also** &nbsp; [WriteInteger](#writeinteger-function)

<sub>[stdlib/Reflection/Reflection.sl:306](../../stdlib/Reflection/Reflection.sl#L306)</sub>

### ReadIntegerAt *function*

```
long ReadIntegerAt(byte* address, Field field)
```

Reads an element of a whole-number array.

**Parameters**

- `address` -- where the element sits, from `GetElementAddress`
- `field` -- the array field, which supplies the element kind

**See also** &nbsp; [WriteIntegerAt](#writeintegerat-function)

<sub>[stdlib/Reflection/Reflection.sl:721](../../stdlib/Reflection/Reflection.sl#L721)</sub>

### ReadText *function*

```
String ReadText(byte* instance, Field field)
```

Reads a String field, as a copy of all its bytes. Empty when the field's
kind is not `KindString`.

**See also** &nbsp; [WriteText](#writetext-function)

<sub>[stdlib/Reflection/Reflection.sl:333](../../stdlib/Reflection/Reflection.sl#L333)</sub>

### ReadTextAt *function*

```
String ReadTextAt(byte* address)
```

Reads a String element, as a copy of all its bytes.

<sub>[stdlib/Reflection/Reflection.sl:758](../../stdlib/Reflection/Reflection.sl#L758)</sub>

### SetAggregate *function*

```
void SetAggregate(byte* instance, Property property, byte* value)
```

Points a class or interface property at an object, on the same terms.

<sub>[stdlib/Reflection/Reflection.sl:292](../../stdlib/Reflection/Reflection.sl#L292)</sub>

### SetBool *function*

```
void SetBool(byte* instance, Property property, bool value)
```

Calls the setter of a `bool` property. Does nothing when there is no
setter, which `CanWrite` is how to find out in advance.

<sub>[stdlib/Reflection/Reflection.sl:277](../../stdlib/Reflection/Reflection.sl#L277)</sub>

### SetDouble *function*

```
void SetDouble(byte* instance, Property property, double value)
```

Calls the setter of a floating property, narrowing to `float` where that
is its width. Does nothing when there is no setter.

<sub>[stdlib/Reflection/Reflection.sl:270](../../stdlib/Reflection/Reflection.sl#L270)</sub>

### SetInteger *function*

```
void SetInteger(byte* instance, Property property, long value)
```

Calls the setter, narrowing to the property's own width. Does nothing when
there is no setter, which `CanWrite` is how to find out in advance.

<sub>[stdlib/Reflection/Reflection.sl:263](../../stdlib/Reflection/Reflection.sl#L263)</sub>

### SetText *function*

```
void SetText(byte* instance, Property property, String value)
```

Calls the setter of a String property.

The setter retains what it stores, so the caller still owns `value`
afterwards.

<sub>[stdlib/Reflection/Reflection.sl:286](../../stdlib/Reflection/Reflection.sl#L286)</sub>

### WriteAggregate *function*

```
void WriteAggregate(byte* instance, Field field, byte* value)
```

Points a reference field at an object, releasing whatever it held. The
field takes a reference of its own, so the caller still owns theirs.

**A null for a field that is never null is refused**, and the field keeps
what it had: `Field.HasZeroValue` says which those are.

**See also** &nbsp; [CreateInstance](#createinstance-function) &middot; [ReadAggregate](#readaggregate-function)

<sub>[stdlib/Reflection/Reflection.sl:527](../../stdlib/Reflection/Reflection.sl#L527)</sub>

### WriteBool *function*

```
void WriteBool(byte* instance, Field field, bool value)
```

Writes a `bool` field.

**See also** &nbsp; [ReadBool](#readbool-function)

<sub>[stdlib/Reflection/Reflection.sl:416](../../stdlib/Reflection/Reflection.sl#L416)</sub>

### WriteBoolAt *function*

```
void WriteBoolAt(byte* address, bool value)
```

Writes an element of a `bool` array.

<sub>[stdlib/Reflection/Reflection.sl:794](../../stdlib/Reflection/Reflection.sl#L794)</sub>

### WriteDouble *function*

```
void WriteDouble(byte* instance, Field field, double value)
```

Writes a floating field, narrowed to `float` where that is its width.

**See also** &nbsp; [ReadDouble](#readdouble-function)

<sub>[stdlib/Reflection/Reflection.sl:408](../../stdlib/Reflection/Reflection.sl#L408)</sub>

### WriteDoubleAt *function*

```
void WriteDoubleAt(byte* address, Field field, double value)
```

Writes an element of a floating array, narrowed to the element's width.

<sub>[stdlib/Reflection/Reflection.sl:788](../../stdlib/Reflection/Reflection.sl#L788)</sub>

### WriteInteger *function*

```
void WriteInteger(byte* instance, Field field, long value)
```

Writes a whole-number field.

**See also** &nbsp; [ReadInteger](#readinteger-function)

<sub>[stdlib/Reflection/Reflection.sl:400](../../stdlib/Reflection/Reflection.sl#L400)</sub>

### WriteIntegerAt *function*

```
void WriteIntegerAt(byte* address, Field field, long value)
```

Writes an element of a whole-number array, narrowed to its width.

**See also** &nbsp; [ReadIntegerAt](#readintegerat-function)

<sub>[stdlib/Reflection/Reflection.sl:782](../../stdlib/Reflection/Reflection.sl#L782)</sub>

### WriteText *function*

```
void WriteText(byte* instance, Field field, String value)
```

Writes a String field, releasing whatever it held.

The bytes cross rather than the String, which is what keeps a counted
reference out of the runtime's ABI -- the same bargain `ReadText` makes in
the other direction. The field ends up owning a copy.

**See also** &nbsp; [ReadText](#readtext-function)

<sub>[stdlib/Reflection/Reflection.sl:428](../../stdlib/Reflection/Reflection.sl#L428)</sub>

### WriteTextAt *function*

```
void WriteTextAt(byte* address, String value)
```

Writes a String element, releasing whatever it held.

<sub>[stdlib/Reflection/Reflection.sl:797](../../stdlib/Reflection/Reflection.sl#L797)</sub>

## Constants

### KindArray *constant*

```
const int KindArray = 20
```

An array. `ElementKind` says what is in it.

<sub>[stdlib/Reflection/Reflection.sl:191](../../stdlib/Reflection/Reflection.sl#L191)</sub>

### KindBool *constant*

```
const int KindBool = 1
```

A `bool`.

<sub>[stdlib/Reflection/Reflection.sl:149](../../stdlib/Reflection/Reflection.sl#L149)</sub>

### KindByte *constant*

```
const int KindByte = 8
```

A `byte`.

<sub>[stdlib/Reflection/Reflection.sl:163](../../stdlib/Reflection/Reflection.sl#L163)</sub>

### KindChar *constant*

```
const int KindChar = 2
```

A `char`: one UTF-8 code unit.

<sub>[stdlib/Reflection/Reflection.sl:151](../../stdlib/Reflection/Reflection.sl#L151)</sub>

### KindChar16 *constant*

```
const int KindChar16 = 21
```

A `char16`: one UTF-16 code unit. Numbered past
`KindArray` because it was added after the numbering was fixed, which is
why `IsInteger` tests it separately.

<sub>[stdlib/Reflection/Reflection.sl:195](../../stdlib/Reflection/Reflection.sl#L195)</sub>

### KindChar32 *constant*

```
const int KindChar32 = 22
```

A `char32`: one Unicode scalar, with the same
numbering story as `KindChar16`.

<sub>[stdlib/Reflection/Reflection.sl:198](../../stdlib/Reflection/Reflection.sl#L198)</sub>

### KindClass *constant*

```
const int KindClass = 17
```

A class reference. `FieldType` gives the type to walk
into, and the value can be null.

<sub>[stdlib/Reflection/Reflection.sl:184](../../stdlib/Reflection/Reflection.sl#L184)</sub>

### KindDouble *constant*

```
const int KindDouble = 14
```

A `double`.

<sub>[stdlib/Reflection/Reflection.sl:175](../../stdlib/Reflection/Reflection.sl#L175)</sub>

### KindFloat *constant*

```
const int KindFloat = 13
```

A `float`.

<sub>[stdlib/Reflection/Reflection.sl:173](../../stdlib/Reflection/Reflection.sl#L173)</sub>

### KindInt *constant*

```
const int KindInt = 5
```

An `int`.

<sub>[stdlib/Reflection/Reflection.sl:157](../../stdlib/Reflection/Reflection.sl#L157)</sub>

### KindInterface *constant*

```
const int KindInterface = 18
```

An interface reference, walked like a class.

<sub>[stdlib/Reflection/Reflection.sl:186](../../stdlib/Reflection/Reflection.sl#L186)</sub>

### KindLong *constant*

```
const int KindLong = 6
```

A `long`.

<sub>[stdlib/Reflection/Reflection.sl:159](../../stdlib/Reflection/Reflection.sl#L159)</sub>

### KindNInt *constant*

```
const int KindNInt = 7
```

An `nint`: pointer-wide and signed.

<sub>[stdlib/Reflection/Reflection.sl:161](../../stdlib/Reflection/Reflection.sl#L161)</sub>

### KindNUInt *constant*

```
const int KindNUInt = 12
```

An `nuint`: pointer-wide and unsigned.

<sub>[stdlib/Reflection/Reflection.sl:171](../../stdlib/Reflection/Reflection.sl#L171)</sub>

### KindNone *constant*

```
const int KindNone = 0
```

What a field holds. Kept in step with enum SlKind in the runtime.

<sub>[stdlib/Reflection/Reflection.sl:147](../../stdlib/Reflection/Reflection.sl#L147)</sub>

### KindPointer *constant*

```
const int KindPointer = 15
```

A raw pointer. Nothing here follows one -- what it
points at carries no metadata.

<sub>[stdlib/Reflection/Reflection.sl:178](../../stdlib/Reflection/Reflection.sl#L178)</sub>

### KindSByte *constant*

```
const int KindSByte = 3
```

An `sbyte`.

<sub>[stdlib/Reflection/Reflection.sl:153](../../stdlib/Reflection/Reflection.sl#L153)</sub>

### KindShort *constant*

```
const int KindShort = 4
```

A `short`.

<sub>[stdlib/Reflection/Reflection.sl:155](../../stdlib/Reflection/Reflection.sl#L155)</sub>

### KindString *constant*

```
const int KindString = 16
```

A `String`. Read and written by value, through
`ReadText` and `WriteText`.

<sub>[stdlib/Reflection/Reflection.sl:181](../../stdlib/Reflection/Reflection.sl#L181)</sub>

### KindStruct *constant*

```
const int KindStruct = 19
```

A struct, stored inline rather than referenced -- so
its address is where it sits, and it is never null.

<sub>[stdlib/Reflection/Reflection.sl:189](../../stdlib/Reflection/Reflection.sl#L189)</sub>

### KindUInt *constant*

```
const int KindUInt = 10
```

A `uint`.

<sub>[stdlib/Reflection/Reflection.sl:167](../../stdlib/Reflection/Reflection.sl#L167)</sub>

### KindULong *constant*

```
const int KindULong = 11
```

A `ulong`.

<sub>[stdlib/Reflection/Reflection.sl:169](../../stdlib/Reflection/Reflection.sl#L169)</sub>

### KindUShort *constant*

```
const int KindUShort = 9
```

A `ushort`.

<sub>[stdlib/Reflection/Reflection.sl:165](../../stdlib/Reflection/Reflection.sl#L165)</sub>

