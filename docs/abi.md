# Stainless ABI (x86-64, Windows / MSVC-compatible)

## 1. Value layout

Primitives and `struct`s use the **platform C ABI verbatim**. Field order is
declaration order; alignment and padding follow the C rules for the target.
A Stainless `struct Point { double X; double Y; }` is bit-identical to the C
`struct Point { double X; double Y; };` and is passed and returned by the
same rules (on Win64: by hidden pointer, since it exceeds 8 bytes).

This is a hard guarantee, not a best effort. It is also why `struct` is not
reference counted: adding a header would break it.

### 1.1 `[Packed]` and `[Align]`

`[Packed]` lays a struct out with no padding between fields and none at the end,
and gives it an alignment of one. `[Align(N)]` raises the alignment to N, which
must be a power of two and at most 16 — `max_align_t`, and so what `malloc`
guarantees for anything the type ends up inside. The two combine.

In the IR a packed struct is spelled `<{ }>`, which is how LLVM is told to put
the fields where the C rules with no padding put them; without it LLVM would
insert its own and every offset after the first would disagree with the one the
binder computed. Alignment is not part of an LLVM struct type at all, so it is
stated at each `alloca` and each global instead.

A generated C header writes `#pragma pack(push, 1)` around a packed struct and
`__declspec(align(n))` or `__attribute__((aligned(n)))` — behind an `SL_ALIGN`
macro — for an aligned one. Both spellings go after the `struct` keyword, which
is the one position MSVC, gcc and clang all accept.

### 1.2 Bit-fields

A bit-field is stored in a unit of its declared type, and which unit is the
target's decision. The two C ABIs disagree, and not only in corners:

| Declared | Microsoft | Itanium |
|---|---|---|
| `int a : 1; byte b : 1;` | 8 | 4 |
| `int a : 3; short b : 4;` | 8 | 4 |
| `int a : 30; int b : 4;` | 8 | 8 |
| `uint a : 3; uint b : 5; uint c : 24;` | 4 | 4 |

**Microsoft** keeps one open storage unit, sized by the type that opened it, and
starts a new one when the next field will not fit *or* is declared with a type of
a different size. **Itanium** allocates at the next free bit and moves to the
next boundary of the declared type only when the field would straddle one. An
ordinary field closes whatever was being filled, under both.

Both are implemented and both are checked against clang built for the matching
target. `--abi microsoft|itanium` selects one; the default is the host's, and it
governs C++ name mangling as well.

**`--abi` does not select a calling convention.** Struct passing is Win64
whichever ABI is named, because the SysV classifier is not written (§3). Naming
Itanium on Windows therefore gives Itanium bit-fields and Win64 argument
passing: self-consistent within one program, and not a cross-compilation.

A struct containing bit-fields is emitted as bytes — `%struct.Header = type
{ [4 x i8] }` — because its fields do not line up with LLVM's when several share
a unit. Every field of such a struct is then reached by its byte offset rather
than by a structural index.

Reading a bit-field is a load of the unit, a shift and a mask; a signed one is
shifted left and arithmetic-shifted right so it sign-extends from its own width
rather than the unit's. Writing is a load, a splice and a store, which is what
leaves the neighbours sharing the unit alone. A bit-field has no address, so it
cannot be passed by `ref`.

In DWARF a bit-field is a member with `DIFlagBitField`, a `size` in bits, an
`offset` in bits from the start of the value, and `extraData` giving the start of
the storage unit — the third being what a debugger needs to know which bytes to
load before shifting.

## 2. Object header (class instances)

Reference types are heap blocks laid out as:

```
offset 0   +----------------------+
           | strong  : nuint      |   strong reference count
offset 8   +----------------------+
           | weak    : nuint      |   weak reference count + liveness bit
offset 16  +----------------------+
           | type    : TypeInfo*  |   destructor + size, for dynamic release
offset 24  +----------------------+
           | field 0              |
           | field 1              |   fields, laid out with C rules
           | ...                  |
           +----------------------+
```

A class reference is a pointer to **offset 0** (the header). The header is
24 bytes on 64-bit targets. `TypeInfo` is a static, per-class constant:

```c
struct TypeInfo {
    size_t              size;
    void              (*destroy)(void* obj);
    const char         *name;
    const void *const  *interfaces;   /* indexed by interface id; may be NULL */

    size_t              fieldCount;   /* zero unless the type is [Reflect] */
    const SlFieldInfo  *fields;
    size_t              attributeCount;
    const SlAttribute  *attributes;
};

struct SlFieldInfo {
    const char        *name;
    size_t             offset;        /* from the start of the object or value */
    uint32_t           kind;
    const SlTypeInfo  *type;          /* for aggregates; NULL for primitives */
    size_t             attributeCount;
    const SlAttribute *attributes;
};
```

The last four entries are why reflection needs no runtime: a `[Reflect]` type's
fields are `const` tables the linker places in read-only data, and reading one
is address arithmetic. A type without the marker carries four zeroes.

Because a class reference is a plain pointer, it can cross the C boundary as
`void*` — but C code must call `sl_retain` / `sl_release` to participate in
ownership.

### 2.1 Immortal objects

A strong count of `SIZE_MAX` marks an object the compiler placed in static
storage. `sl_retain` and `sl_release` return immediately for such objects, so a
statically allocated instance costs neither an allocation nor any reference
traffic. String literals are emitted this way.

### 2.2 Enums, delegates and closures

An **enum** is exactly its underlying integer — `int` unless another is named.
There is no wrapper and no tag, which is what lets it line up with the C enum
or integer it corresponds to. `[Flags]` changes what the compiler will let you
write and nothing about the bytes, so a flags enum is the same integer a C
bitmask is.

A **delegate** is one pointer using the platform C calling convention: it *is*
a C function pointer, and a generated header declares it as one. It carries no
context, so it holds no reference count and may live inside a `struct`.

A **closure** is an ordinary class instance, generated by the compiler, with one
field per captured value and one method implementing the interface it was
converted to. It therefore uses the object header above, the interface dispatch
of §2.8, and the ownership rules of §5, with nothing added.

A **property** is a pair of ordinary methods named `get_Name` and `set_Name`,
mangled and dispatched like any other. An automatic one also has a field, laid
out at the position the property was declared in and named after it, so a type's
layout is the same whether a member was written as a field or as a property.
There is no property record anywhere in the binary and no metadata describing
one: what the linker sees is two methods and a field.

### 2.3 Variant layout

A `variant` is a value, laid out by the same C rules as a struct: a one-byte tag
first, then storage wide enough and aligned well enough for the widest case.

```
  offset 0    tag        uint8_t, the case's position in the declaration
  offset A    payload    the case's fields, as a struct of them
```

`A` is whatever the alignment of the widest payload puts it at — 8 for a case
holding a double or a reference, 1 for one holding only bytes. The payload's
size is the widest case's, rounded up to that alignment, so `Circle(double)` and
`Rect(double, double)` together give a 24-byte type rather than a 32-byte one.

Every case's fields are read from the one payload address, each through a struct
of that case's own fields. That is what overlapping means here, and it is why
nothing may read a payload without the tag having been checked (§2.6 of the
language spec): the bytes are real for exactly one case at a time.

**The tag is one byte, so a variant is capped at 255 cases** (SL0432). A variant
no case of which carries anything is therefore one byte, and reads like an enum.

**In C**, a variant appears in a generated header as its shape rather than its
cases, because C has no way to state that the payloads overlap in a checked way:

```c
/* variant Lib.Shape:
     0 = Circle(double Radius)
     1 = Rect(double Width, double Height)
     2 = Empty
   The payload is that case's fields, laid out as a struct.
   Read it by checking the tag first; there is no other way. */
typedef struct Lib_Shape {
    uint8_t tag;
    uint64_t payload[2];
} Lib_Shape;
```

The payload is an array of the integer the alignment demands rather than of
bytes with an alignment attribute, because that spelling means the same thing in
C and in C++ and the two do not share one for alignment. A variant reaches C at
all only when no case holds a reference; one that does is refused at the
boundary like any other struct that does (SL0284).

**Reference counting consults the tag.** For a variant some case of which holds
a counted reference, the compiler emits two functions — one to retain and one to
release — each a `switch` on the tag that touches only the case actually there.
They are what a copy and a drop of such a variant call, in place of the field
walk a struct gets, and they are why the payloads may overlap: nothing ever
counts through the bytes of a case that is not present. A variant holding no
references gets neither function and copies as plain bytes.

### 2.4 Union layout

Every member of a `union` is at offset zero. Its size is the widest member
rounded up to its alignment, and its alignment is the strictest of them — the
same arithmetic C does, and compared against the target's own compiler by a test
that builds values on both sides.

LLVM has no union type, so what it is given is storage: as many integers of the
union's alignment as it takes to cover the widest member.

```llvm
%union.Library_Unions_Word = type { [1 x i32] }
%union.Library_Unions_Wide = type { [1 x i64] }
```

A member is then read at the union's own address with the member's own type,
which is what makes the access one load rather than a load and a mask. There is
no `getelementptr` at all: every member is at offset zero, so there is nothing
to index.

No member may hold a counted reference, and that is a rule about what a union
can answer rather than one added for safety — see §2.7 of the language spec.

### 2.5 Slice layout

A `T[:]` is three words, and a struct like any other:

```
  offset 0    array     T[], the object the elements live in
  offset 8    offset    size_t, where in it this slice starts
  offset 16   length    size_t, how many elements it runs for
```

So 24 bytes, aligned to 8. The array field is an ordinary reference-carrying
struct field, which is the whole of the lifetime story: a copy of the slice
retains it, a drop releases it, and the elements cannot outlive the slices that
name them.

An element's address is the array's data, past the slice's own offset:

```
  &s[i]  =  (uint8_t*)array + 32 + (offset + i) * sizeof(T)
```

with `i` checked against the slice's length rather than the array's. Slicing a
slice adds the offsets and stores the same array, so this stays one indirection
however many times a slice has been cut.

`sl_slice_bounds_fail(from, to, length)` reports a bad slice, and distinguishes
one that runs backwards from one that runs off the end.

A slice holds a reference, so it does not cross `extern "C"` (SL0284). What
crosses instead is what C already has: the pointer and the length, passed
separately.

### 2.6 String layout

`Standard.Text.String` is a reference counted object whose bytes follow the
header inline, always NUL terminated:

```
offset 0   strong      : size_t         SIZE_MAX for a literal
offset 8   weak        : size_t
offset 16  type        : TypeInfo*      &sl_string_type_info
offset 24  byteLength  : size_t         not counting the NUL
offset 32  bytes       : uint8_t[n + 1] UTF-8
```

The trailing NUL is what makes `ToPointer()` free rather than a copy: the
pointer it returns is `object + 32`, which is a valid `const char *` for any C
function that stops at a NUL. `Utf16String` has the same shape with
`uint16_t` units.

The compiler emits no `TypeInfo` or destroy hook for these two types; the
runtime defines `sl_string_type_info` and `sl_utf16_string_type_info` itself.

### 2.7 Array layout

An array is the same kind of object, with its elements inline after a length:

```
offset 0   strong / 8 weak / 16 type
offset 24  length              element count, not bytes
offset 32  elements[length]
```

The element type is deliberately not recorded. The compiler emits one TypeInfo
per array type, and that type's destroy hook already knows whether its elements
are counted and how to walk them — so `int[]` gets an empty hook the optimiser
deletes, and `String[]` gets a release loop.

### 2.8 Interface dispatch

An interface reference is a plain object pointer, identical in every way to a
class reference. Nothing is carried alongside it, so ARC, optionals, weak
references and the calling convention need no special case.

The implementation is found through the object instead:

```
object ──+16──▶ TypeInfo ──+24──▶ interfaces ──[id]──▶ vtable ──[slot]──▶ function
```

Interface ids are assigned across the whole program, so `interfaces` is a flat
array indexed directly: a dispatch is four constant-offset loads and an
indirect call, with no search and no branch. It is one load more than a C++
virtual call, which is the price of leaving the object header at 24 bytes and
letting a class implement any number of interfaces at no per-object cost.

The compiler emits, per implementing class, one vtable per interface plus the
`interfaces` array; a class implementing none stores `NULL`.

```llvm
@_SLvt_App_Circle_App_Shape = internal constant [2 x ptr] [ptr @..Area.., ptr @..Describe..]
@_SLitab_App_Circle         = internal constant [2 x ptr] [ptr @_SLvt_App_Circle_App_Shape, ptr null]
```

## 3. Calling convention

| Declaration | Symbol name | Convention |
|---|---|---|
| `int Add(int, int)` in module `App.Math` | `_SL3App4Math3AddiiEi` | platform C |
| `extern "C" int puts(byte*)` | `puts` | platform C |
| `export "C" int sl_add(int, int)` | `sl_add` | platform C |
| `extern "C++" int add(int, int)` | `_Z3addii` or `?add@@YAHHH@Z` | platform C |
| `export "C++" double shapes::Area(double)` | `_ZN6shapes4AreaEd` or `?Area@shapes@@YANN@Z` | platform C |

Every function uses the platform C calling convention. The mangling scheme
distinguishes *names* only, never argument passing, so any Stainless function
can be called from C given the mangled symbol — and `export "C"` removes even
that friction.

### 3.1 Name mangling grammar

```
mangled  := "_SL" path targs? params "z"? "E" ret
path     := (len ident)+                    ; module segments, then the name
targs    := "G" count type+                 ; an instantiated generic's arguments
params   := type* | "v"                     ; "v" when there are none
type     := prim
          | "P" type                        ; pointer
          | "A" type                        ; array
          | "O" type                        ; optional
          | "W" type                        ; weak
          | "C" len ident                   ; class
          | "S" len ident                   ; struct
          | "I" len ident                   ; interface
          | "E" len ident                   ; enum
          | "D" len ident                   ; delegate
prim     := a  sbyte    s  short    i  int      l  long
          | h  byte     t  ushort   j  uint     m  ulong
          | n  nint     y  nuint    f  float    d  double
          | b  bool     c  char     v  void
```

`len` is the decimal length of the identifier that follows, so the grammar
needs no separators: `App.Math.Add` becomes `3App4Math3Add`. A constructor is
named `4ctor` and a destructor `4dtor`. A variadic function has `z` before the
terminator.

`E` is both the enum prefix and the terminator before the return type, and the
two never collide: an enum is always followed by a decimal length, and the
terminator is always followed by a type code, which is never a digit.

An instantiated generic carries its type arguments, so `Box<int>` and
`Box<String>` produce different symbols even where the parameters alone would
not tell their methods apart. A class's simple name arrives here as
`Box<int>`, which a linker symbol may not contain, so every non-alphanumeric
character in a qualified name becomes `_`.

### 3.2 C++ names

C++ has no ABI of its own. The platform specifies how C-shaped things work and
says nothing about mangling, vtables or unwinding, so the compilers filled it in
separately and two schemes resulted: Itanium's, used by gcc and clang, and
Microsoft's, used by MSVC and by clang when it targets MSVC. They agree on
nothing — not the prefix, not the order of the qualifiers, not whether the
return type is encoded, not how a repeated type is abbreviated.

| Declaration | Itanium | Microsoft |
|---|---|---|
| `int add(int, int)` | `_Z3addii` | `?add@@YAHHH@Z` |
| `void nothing()` | `_Z7nothingv` | `?nothing@@YAXXZ` |
| `int deref(int*, int*)` | `_Z5derefPiS_` | `?deref@@YAHPEAH0@Z` |
| `geometry::area(double, double)` | `_ZN8geometry4areaEdd` | `?area@geometry@@YANNN@Z` |
| `geometry::mix(int*, double*, int*)` | `_ZN8geometry3mixEPiPdS0_` | `?mix@geometry@@YAHPEAHPEAN0@Z` |

Two details are worth stating because they are the ones easy to get wrong.
Itanium counts each *enclosing namespace* as a substitution candidate before any
parameter, which is why the repeated `int*` in the last row is `S0_` and not
`S_` — the namespace took `S_`, and the same function at global scope would use
`S_`. And a Stainless `long` is a fixed 64 bits, which is C++'s `long long`
rather than its `long`: C++'s `long` is 32 bits on Windows.

Both schemes are checked against clang rather than against a reading of the
specification. `STAINLESS_CPP_ABI` forces one, so the scheme a host does not use
can still be compared with what a real compiler emits for the same declarations.

A C++ mangled name is mostly characters an LLVM identifier may not contain, so
every function symbol is quoted in the IR when it needs to be.

### 3.3 `ref` and `in` parameters

A `ref T` or `in T` parameter is one pointer, and the classifier is not
consulted for it: there is nothing to classify, and a struct that would
otherwise go `byval` must not be copied on the way in — copying it is exactly
what the mode exists to avoid.

So a `ref T` is a `T*`, in both directions:

```
  void Bump(ref int n)        ->  define void @Bump(ptr %arg.n)
  Bump(ref count)             ->  call void @Bump(ptr %count.s0)
```

Inside the callee the incoming pointer *is* the parameter's slot. Every
parameter already lives behind a pointer — the emitter gives each one a stack
slot so it can be assigned like a local — so a by-reference parameter is the
case where that slot is the caller's rather than a copy of it, and reading and
writing it need no new code at all.

A C header writes the two as `T*` and `const T*`. A C++ name mangles the first
as a pointer rather than as a C++ reference, because an address is what crosses
and `T*` is what C++ calls that.

## 4. Static storage

A `static readonly` becomes one zeroed global per declaration. A single
generated function, `_SLstatics`, runs every initializer in dependency order and
is called from `main` before anything else.

There is no lazy guard and no once-flag: the whole program is compiled together,
so the order is computed at compile time rather than discovered at run time. A
reference is passed to `sl_make_immortal` as it is stored, so a static costs no
reference traffic for the rest of the program and is never destroyed.

A `--shared` library has no entry point to call `_SLstatics` from, so a static
in one is rejected at compile time rather than left zeroed.

## 5. Ownership convention

Both counts are **atomic** — a relaxed increment, an acquire/release decrement,
and a compare-exchange loop in `sl_weak_load`. That is the same choice Swift
makes, and for the same reason: an object reachable from two threads has its
count touched by both, and no rule about what may be *shared* prevents a
reference escaping a lock. It costs about 5.7ns per retain/release pair, which
makes removing redundant pairs worth considerably more than it used to be.

Stainless follows a **borrowed-parameter / owned-return** convention, the same
choice Swift makes, because it eliminates most retain/release traffic:

- **Parameters are borrowed.** The caller guarantees the argument stays alive
  for the duration of the call. The callee does not retain on entry or release
  on exit. Passing a reference costs nothing.
- **Except a parameter the body writes to**, which is retained on entry and
  released on exit. The exception is forced: `p = other;` releases what the
  slot held, and what it held is the caller's, so a borrowed parameter that is
  assigned to would free an object the caller still owns and leak the one it
  was given. Writing to a parameter makes it the private copy the write already
  treated it as. Writing *through* one — `p[i] = x`, or a field of a class it
  refers to — reaches the caller's object rather than the parameter, and is
  still borrowed.
- **Returns are owned (+1).** A function returning a class reference transfers
  a +1 count to the caller, which is responsible for releasing it. A struct
  holding references is returned the same way, field by field.
- **Locals are owned.** Storing into a local retains; the local is released at
  scope exit, including on every early return. A struct local owns whatever is
  inside it, and copying one retains each reference it holds.
- **Fields are owned.** Assigning to a field retains the new value and releases
  the old, in that order, so self-assignment is safe. The same order applies to
  a whole struct assigned over another.

## 6. Across a library boundary

A `--shared` build produces a library, and what may cross into it depends on who
is on the other side.

**A C or C++ consumer** gets plain values: primitives, pointers, and structs of
plain data. Those are the ABI guarantee and they hold across a DLL exactly as
they hold inside one binary. A managed reference appears in the generated header
as `void*` — a handle to pass back in, not something to dereference or free —
and a struct that holds a reference is refused at the boundary outright
(SL0284), because the other side would copy its bytes and leave the count
behind.

**A Stainless consumer** is a different matter, because the compiler can
describe one side to the other. `--metadata` writes a `.slmod` describing the
library's public surface — layouts, field offsets, signatures, and linker names
— and `--reference` binds another compilation against it. Classes then cross
with their fields, properties, methods, constructors and destructors.

What makes that sound rather than merely linkable is where the TypeInfo comes
from. A class is allocated with `sl_alloc(TypeInfo*)`, and the consumer uses the
*library's* table, imported by name:

```llvm
@_SLtiLibrary_Shapes_Counter = external dllimport constant %SlTypeInfo
```

so the object carries the destroy hook the library compiled for the layout the
library chose. Rebuilding a table on the consumer's side would produce an object
whose destructor came from one compilation and whose fields were laid out by
another. Reference counting then works unchanged: `sl_retain` and `sl_release`
only touch the header, and the destructor reached through TypeInfo is the right
one whichever binary calls it.

Windows needs `dllimport` on that declaration specifically because it is data. A
function the linker can reach through a generated thunk; a constant it cannot,
because the address has to come from the import address table.

**Two things do not cross**, and neither is a gap in the metadata format:

- a **generic**, because a template emits nothing until it is instantiated, and
  a consumer holding only the binary has nothing to instantiate;
- a **class implementing an interface**, because a dispatch table is indexed by
  an interface id assigned across a whole program (§2.8), and a library and its
  consumer are two different programs. Closing it means either ids that are
  stable across compilations — which the dense directly-indexed table exists to
  avoid — or registering tables when the library loads.

Both are reported where the library is built, as SL0419 and SL0420.

**The runtime is still linked statically into each binary.** Both sides
therefore have their own allocator and their own C stdio buffer, so text written
inside a library and text written by its consumer do not interleave in the order
they were written. Shipping the runtime as its own shared library would close
both, and is not done.


## 7. Debug information

`-g` describes the program to a debugger. Nothing about the code changes; the
description is metadata attached to it, and a build without `-g` emits none of
it at all.

It is written as ordinary LLVM debug metadata, so the format is whatever the
target uses: CodeView and a `.pdb` on Windows, DWARF elsewhere. The compiler
emits a `DICompileUnit` per program and, hanging off it:

| Node | What it describes |
|---|---|
| `DISubprogram` | one function, by source name and by linker name |
| `DILocation` | one point in the source, attached to every instruction |
| `DILocalVariable` | a local or a parameter, with its type and its stack slot |
| `DIBasicType` | a primitive, with the signedness a debugger prints it by |
| `DICompositeType` | a struct, a class body, or an enum with its members |
| `DIDerivedType` | a field at its offset, or a pointer to something |

A function's name is what the source called it — `Circle.Area`, not
`_SL6Circle4AreavEd` — and its `linkageName` is the mangled symbol, so a
debugger can match a frame to a source line either way. Locations sit at
statement granularity: an expression spread over four lines belongs to the
statement a debugger stops on.

**A class body includes its header.** A field's offset is measured from the
start of the fields area (§2), and DWARF wants it measured from the start of the
allocation, so the 24 bytes in front are described as a member named `__header`
and every field offset is shifted past it. Without it a debugger reads every
field of every object 24 bytes early.

**Optional, weak and strong references share one description.** `C`, `C?` and
`weak C?` are the same machine value; what separates them is what the compiler
will let you write, and DWARF has no way to say that. A weak reference therefore
prints as the pointer it is, including after the object it named has died —
`sl_weak_load` is what makes it read as null, and a debugger does not call it.

**An array knows where its length is and not how long it is.** `T[]` is
described as the object header, then the `length` field at offset 24. The
elements live inline after that, and DWARF can only express an array whose bound
it knows statically, so they are left undescribed rather than described wrongly.
`String` is the same shape and the same story. Reading either means taking the
address and the length and going from there.

**The standard library is written out to be stepped into.** It is compiled from
inside the compiler's own assembly, so with `-g` the driver writes its sources to
`obj/stdlib/` first and parses them from there. Otherwise every frame in
`List.Add` would name a file that does not exist. The runtime's C is compiled
`-O0 -g` for the same reason, so `sl_retain` and `sl_release` are steppable
frames rather than addresses.

**`-O2` is still the default.** Debug information survives optimization, but the
code it describes has been rearranged, and stepping through it is confusing in
the ordinary way. The driver says so once and builds what was asked for; `-O0`
is the flag for stepping through code as it was written.
