<sub>[Stainless](../../README.md) &rsaquo; [Language specification](index.md)</sub>

# 8. Interoperability and libraries

```csharp
extern "C" int puts(byte* s);

extern "C" {
    byte* malloc(nuint n);
    void  free(byte* p);
}
```

`extern "C"` declarations are not name-mangled and use the C calling
convention. Conversely, a Stainless function marked `export "C"` is emitted
with an unmangled name so C and C++ can call it:

```csharp
export "C" int stainless_add(int a, int b) { return a + b; }
```

**A declaration joins the module it was written in**, as an ordinary member,
and so is private to that module unless it says `public`. That is what a binding
library is made of: a module of `public extern "C"` declarations is one another
module can call by the real names, with no forwarding layer in between.

```csharp
public extern "C" {
    int   GetSystemMetrics(int index);
    void* CreateWindowExW(uint extendedStyle, char16* className, /* ... */);
}
```

A modifier written before the block belongs to every declaration in it, which is
the point of writing one there; `public` may also be written on a single member
inside. Two modules may declare the same C function, because a declaration names
a symbol rather than defining one — but only one of them should make it
`public`, or a file importing both has an ambiguous name.

**A `...` may be called and not written.** `printf` is bound with one and works;
a function this program *defines* may not have one, whatever its linkage. Nothing
in the language reads the extra arguments — there is no `va_list` — so the
definition would ignore them while the generated header promised the variadic
convention, which on Win64 wants floating-point arguments duplicated into the
integer registers and on SysV wants `al` to carry a vector-register count. The
integer arguments would survive and the floating-point ones would not, silently.

```
error[SL0493]: 'log_line' cannot be variadic; '...' may only be written on an
'extern "C"' declaration, because there is no 'va_list' to read the extra
arguments with. Take an array, a slice, or a count and a pointer
```

**`"C"` and `"C++"` are the conventions there are.** The string is checked, and
anything else is rejected:

```
error[SL0102]: unsupported linkage convention "Rust"; "C" and "C++" are supported
```

C++ linkage is [§8.1](#81-c-linkage).

**What a signature may carry.** Plain C values — primitives, pointers, and
structs of plain data — cross freely. A struct that holds a reference does not,
in either direction, because C would copy its bytes and leave the count behind
([§2.2](02-types.md#22-struct--value-type-c-layout)):

```
error[SL0284]: 'Holder' holds a reference, so parameter 'h' cannot cross
extern "C"; C would copy its bytes and leave the count behind. Pass a struct of
plain data, or a raw pointer
```

**A variable may cross too.** A C library's surface is not only its entry
points: `environ`, `optarg`, `timezone` and `stdin` are storage, and a language
that speaks the platform C ABI should be able to name one without a shim whose
whole content is a getter. So `extern "C"` on a variable declares storage
defined elsewhere, and `export "C"` defines storage C can reach:

```csharp
extern "C" int   probe_counter;     // defined in C; read and written here
extern "C" byte* environ;

export "C" int stainless_depth = 0; // defined here; read and written by C
```

There is **one global**, not two. Nothing is copied and nothing is marshalled:
the name on each side is the same address, so a write on either side is what
the other reads. An imported one has no initializer, because the storage is not
this program's to define:

```
error[SL0702]: 'already_there' is declared 'extern "C"', so it is defined
elsewhere and cannot be given a value here
```

This is the *only* variable allowed at module scope. An ordinary one is still
refused (SL0204), because a mutable global with no boundary to justify it is
state every thread reaches and nothing declares — what `static` inside a type
is for, with the thread-safety question SL0377 asks of it.

**Two things to get right, and the compiler can check neither**, because it
never sees the C declaration:

*The width has to match.* A Stainless `long` is a fixed 64 bits — C's `long
long` — and C's own `long` is 32 bits on Windows ([§2.1](02-types.md#21-primitives)). On a function a
mismatch is an argument that arrives wrong; on a variable it is a silent
8-byte load from a 4-byte global, which reads whatever follows it.

*Many C "variables" are not variables.* `errno` is the famous one: every C
library defines it as a macro over a function, so that each thread gets its
own — `_errno()` in the UCRT, `__errno_location()` in glibc. Stainless has no
preprocessor to see through a macro, so `extern "C" int errno;` is a promise
nothing keeps and the linker says so. Reach it through the function the macro
hides:

```csharp
#if WINDOWS
extern "C" int* _errno();
#else
extern "C" int* __errno_location();
#endif
```

That failure is a link error naming the symbol, which is the good kind: the
alternative would have been reading a plausible wrong number.

**A C++ variable is not supported.** Neither ABI mangles a global the way it
mangles a function, and none of that is written:

```
error[SL0701]: 'cpp_global' is a variable, and a C++ variable's name is mangled
by rules this compiler does not implement; declare it 'extern "C"', or reach it
through a C++ function that returns its address
```

## 8.1 C++ linkage

A C++ function is reached by mangling its signature the way the target's
compiler does, with no shim and no `extern "C"` on either side:

```csharp
extern "C++" int cpp_add(int a, int b);
extern "C++" double geometry::area(double w, double h);

export "C++" int Doubled(int n) { return n * 2; }
export "C++" double shapes::Perimeter(double w, double h) { return 2.0 * (w + h); }
```

A namespace is written on the declaration with `::`. It decides the linker name
and nothing else: the function joins the module it was declared in, so it is
called by its plain name — `area(3.0, 4.0)`, not `geometry.area(...)`. An
`export "C++"` with no namespace written takes the module's, because a module is
what Stainless calls a namespace, so `Doubled` above is `Interop::Doubled`.

**There are two C++ ABIs and they share nothing.** C++ has none of its own: the
platform specifies how C-shaped things work and says nothing about mangling,
vtables or unwinding, so the compilers each filled it in. gcc and clang use the
Itanium scheme; MSVC, and clang when it targets MSVC, use Microsoft's. The two
disagree about the prefix, the order of the qualifiers, whether the return type
is encoded at all, and how a repeated type is abbreviated:

| Declaration | Itanium | Microsoft |
|---|---|---|
| `int add(int, int)` | `_Z3addii` | `?add@@YAHHH@Z` |
| `void nothing()` | `_Z7nothingv` | `?nothing@@YAXXZ` |
| `int deref(int*, int*)` | `_Z5derefPiS_` | `?deref@@YAHPEAH0@Z` |
| `geometry::area(double, double)` | `_ZN8geometry4areaEdd` | `?area@geometry@@YANNN@Z` |
| `geometry::mix(int*, double*, int*)` | `_ZN8geometry3mixEPiPdS0_` | `?mix@geometry@@YAHPEAHPEAN0@Z` |

The compiler emits whichever the target uses. `--abi microsoft` or `--abi
itanium` overrides the choice, as does `STAINLESS_CPP_ABI`, so that the scheme a
host does not use can still be checked against a real compiler.

Both schemes are stable, which is what makes this worth writing: Itanium has
been for far longer, and Microsoft's since Visual Studio 2015, whose v140
through v143 toolsets interoperate. What is *not* stable is the standard
library, whose types and templates are where the churn actually lives — which is
why nothing here touches them.

**How the fixed-width types map.** Stainless integers have exact sizes and C++'s
do not, so `long` is spelled as whatever is 64 bits on the target:

| Stainless | C++ |
|---|---|
| `sbyte` `byte` `short` `ushort` `int` `uint` | `signed char` `unsigned char` `short` `unsigned short` `int` `unsigned int` |
| `long` `ulong` | `long long` `unsigned long long` — C++'s `long` is 32-bit on Windows |
| `nint` `nuint` | pointer-sized: `long` on Itanium, `__int64` on Microsoft |
| `char` | `char`; it is one byte, not UTF-16 |
| `char16` `char32` | `char16_t` `char32_t` |
| `bool` `float` `double` | `bool` `float` `double` |

**What is not there yet.** Free functions only. A C++ *class* cannot be named,
which is what would need object layout, vtable layout, and an answer for
constructors, destructors and exceptions crossing a boundary Stainless does not
unwind through. Templates are not addressed and will not be by mangling alone: a
template has no symbol until something instantiates it.

## 8.2 Building a shared library

```
stainless build src --shared -o build/math.dll --header build/math.h
```

produces `math.dll`, the import library `math.lib`, and a C header. A
`--shared` build needs no `Main`.

**The export table is exactly the `export "C"` functions.** Nothing else is
reachable from outside, and that is the only control there is:

| Declaration | In the library |
|---|---|
| `export "C" int Add(int, int)` | exported, unmangled, as `Add` |
| `public int Helper()` | visible to other Stainless modules, **not** exported |
| `int Secret()` | module-private |

`public` deliberately does not export. It answers a different question — which
modules may see this — and a library's surface should be stated once,
deliberately, rather than falling out of visibility rules.

**Exactly** means the name too, which takes work on one target. A calling
convention decorates a symbol on 32-bit x86 — `export "C" __stdcall int
DllGetClassObject(...)` is `_DllGetClassObject@12` in the object file — and an
export table built from symbols would carry that rather than what the source
said. So a Windows build writes a **module definition file** beside the object
naming those exports under their declared names, and hands it to the linker.
It is what every C++ COM server has done since 1993, and it is written only
where a name would otherwise be wrong: on x64 nothing is decorated, and there
is no file. The convention itself is untouched — only the name is, because the
convention is what the caller will use and the name is what it looks up.

`--def <path>` supplies one of these by hand, for the names a declaration
cannot state: an alias, an ordinal, a data export. It is added to whatever the
compiler needed rather than replacing it, since a `.def` may hold more than one
`EXPORTS` section and dropping the compiler's half would make a decorated
export unreachable under its own name.

The generated header restates what the ABI already guarantees:

```c
typedef struct Library_Math_Point { double X; double Y; } Library_Math_Point;

int32_t            Add(int32_t a, int32_t b);
Library_Math_Point Scale(Library_Math_Point p, double by);
```

so a consumer is an ordinary C program:

```c
#include "math.h"
int main(void) { return Add(40, 2) == 42 ? 0 : 1; }
```

```
clang consumer.c build/math.lib -o consumer.exe
```

## 8.3 What may cross a library boundary

Plain C values — primitives, pointers and `struct`s — cross freely. That is the
ABI guarantee, and it holds across a DLL exactly as it does within one binary.

**Managed objects are a different matter.** A `String`, class instance or array
carries a reference count, and each binary that links Stainless gets its own
copy of the runtime. An object allocated inside the library and released by the
caller therefore crosses two copies of `malloc` and `free`. It happens to work
when both sides are built by the same toolchain against the same C runtime, but
it is not something to rely on.

The rule is: **hand C types across a library boundary, and keep managed objects
on one side of it.** A managed reference appears in a generated header as
`void*` for that reason — it is a handle to pass back in, not something to
dereference or free.

Lifting that restriction means shipping the Stainless runtime as its own shared
library, so both sides count against the same allocator. `--runtime shared` does
that, and is the default where two Stainless binaries meet
([§8.4](#84-a-stainless-library-consumed-by-stainless)).

## 8.4 A Stainless library consumed by Stainless

Stainless has no headers, and inside one compilation it needs none: every
declaration is visible because every file is compiled together. A library is
where that stops. The consumer is a separate compilation with no access to the
source, so something has to carry what the source would have said.

```
stainless build lib --shared -o build/shapes.dll --metadata build/shapes.slmod
stainless build app.sl --reference build/shapes.slmod -o app.exe
```

The `.slmod` is generated, never edited, and cannot drift from the library
because it is written from the same bound program. It describes the public
surface: layouts, field offsets, signatures, and the linker names to call.

The metadata names its library, and **`--reference` links it** from beside the
`.slmod` — the import library on Windows, the shared object elsewhere. It used
to take the library as a second input, and leaving that off was a link error
about a name nobody had declared. A library moved away from its metadata is
still passed as an ordinary input.

```csharp
import Library.Shapes;                  // a module this compilation has no source for

int Main() {
    var counter = new Counter("clicks", tally);
    counter.Step = 3;                   // properties, fields and methods all work
    counter.Bump();
    Console.WriteLine(counter.Describe());
    return 0;
}
```

**What crosses.** Classes with their fields, properties, methods, constructors,
destructors and events; structs, unions, enums, aliases and free functions; and
`closure` and `delegate` types, which cross as their signatures — a closure's
two fields are the compiler's own, so the far side rebuilds them rather than
reading them.

A class from a library can also be **derived from** ([§2.4.3](02-types.md#243-inheritance)) and its events
**subscribed to** ([§2.14.2](02-types.md#2142-event--several-subscribers-behind-one-name)). Both work because what they need crosses: the
dispatch table slot by slot, the destroy hook, and the protected members for the
first; the closure type, the storage and the two subscription methods for the
second. The method that *raises* an event is private and does not cross, so
"only the declaring type may raise it" holds here by construction rather than by
a check on this side.

**Reference counting reaches across.** A class is allocated through the
library's own TypeInfo, so the object gets the destructor the library compiled
for it, and the consumer's `release` runs it at the right moment.

**`public` still does not export.** It answers which modules may see a
declaration, and a C library's surface is stated once with `export "C"`. Asking
for `--metadata` says something different — that another Stainless compilation
will bind against this — and that surface is exactly the public declarations the
metadata describes.

**What does not cross, and why.** Each is a consequence of the language
compiling a whole program at once, and the compiler says so where the library is
built rather than leaving the consumer to find a public type mysteriously
missing:

| | |
|---|---|
| a generic (SL0419) | a template emits nothing until it is instantiated, so a consumer with only the binary has nothing to instantiate. A generic crosses as source |
| a class implementing an interface (SL0420) | a dispatch table is indexed by an interface id assigned across a whole program, and a library and its consumer are two different programs |
| a variant (SL0441) | its cases are what a consumer would switch on, and the metadata carries layouts rather than cases |
| a slice, `T[:]` | it is a type the compiler builds on demand rather than one the source declared, so there is no name for a consumer to resolve |

**And anything reaching one of those through a field or a signature** is reported
the same way (SL0477). A public struct with a variant field would otherwise be
described happily, and the consumer would be the one to find that the field's
type is a name nothing can resolve — which is precisely the failure these
warnings exist to move to this side of the boundary.

**Both sides share one runtime.** A library built with `--metadata` and a
program built with `--reference` link the same `stainless-rt` shared library
rather than each compiling in a copy, so there is one allocator, one set of
reference counts and one C stdio buffer: an object made on one side and dropped
on the other is counted once, and output interleaves in the order it was
written. The compiler puts the runtime beside what it built.

A program with no library boundary keeps the copy compiled into it and stays a
single file, which is the default. `--runtime shared|static` says so explicitly,
and a library and a consumer that disagree are refused — two runtimes is exactly
the failure this closes, and it would otherwise be a silent one. See
[§6.1 of abi.md](../abi.md#61-one-runtime).

## 8.5 COM

COM is a calling convention, not a Windows service. An interface reference
points at a vtable pointer, and slots 0, 1 and 2 of that vtable are always
`QueryInterface`, `AddRef` and `Release`. None of that needs an operating
system — it is a pointer, an array of function pointers, and the platform C
calling convention — which is why `com` works on Linux and macOS as well.
What is Windows about COM is *activation*: `CoCreateInstance`, the registry,
apartments, marshalling. None of that is in the language.

```csharp
[Guid("43826d1e-e718-42ee-bc55-a1e261c37bfe")]
public com interface IShellItem {
    int BindToHandler(byte* bindContext, Guid* handler, Guid* iid, byte** result);
    int GetParent(byte** parent);
    int GetDisplayName(uint kind, char16** name);
    int GetAttributes(uint mask, uint* attributes);
    int Compare(byte* other, uint hint, int* order);
}
```

**A `com interface` is not an `interface`.** The two are different objects in
memory, and every difference follows from where the reference points:

| | reference points at | dispatch | needs |
|---|---|---|---|
| `interface` | the object header | `obj+16` → TypeInfo → `+24` → tables → `[id]` → `[slot]`, 4 loads | an object the runtime allocated |
| `com interface` | the vtable pointer | `this` → `[0]` → `[slot]`, 2 loads | nothing at all |

So a com interface can name an object another language made, which is the
point, and carries no Stainless header, which is the cost: it cannot be
compared for identity, reflected on, or held `weak`.

**Every slot is `__stdcall` on x86**, and a `com interface` does not say so:
the convention is stamped on when its table is numbered, the same way the slot
number is, because both belong to the table rather than to the declaration. It
is part of the binary contract rather than a Windows detail — a COM callee
removes its own arguments, so a caller that disagreed would unbalance the stack
with nothing to report it. There is one convention on every 64-bit target, so
`--target x86` is where this is the whole of the difference and everywhere else
it is nothing.

**Every com interface extends `IUnknown`**, written or not, so a declaration's
own first method is slot 3. Extension is **single**: a COM vtable is one array
and a reference is one pointer to it, so there is room for one chain (SL0530).
A derived interface's table is its base's with its own methods appended, which
is what makes an upcast free — the same property that makes a class upcast free
([§2.4.3](02-types.md#243-inheritance)), arrived at from the table side rather than the object side.

`[Guid("...")]` is required (SL0537) and is understood by the compiler rather
than stored as metadata: an IID is the interface's identity, not something a
library reads back. `iidof(IShellItem)` is its address as a `Guid*`, which is
what activation and `QueryInterface` take.

### ARC drives AddRef and Release

This is the reason `com` is in the language rather than being a struct of
`delegate`s. Mismatched `Release` is COM's defining bug, and the compiler
already knows where every reference is born, copied and dropped — so it emits
the calls:

```csharp
IShellItem Parent(IShellItem item) {
    byte* raw = null;
    if (item.GetParent(&raw) < 0) { ... }
    return (IShellItem)raw;             // adopts; nothing else to write
}
```

A cast from a raw pointer is how a reference that activation wrote through a
`void**` enters ARC's care. It is unchecked — a `byte*` says nothing about what
is behind it — and it *adopts*: the +1 the factory handed over becomes the one
the caller holds, and the release is emitted at the end of the scope.

### `is` and a cast are `QueryInterface`

```csharp
if (item is IShellItem2) {
    IShellItem2 richer = (IShellItem2)item;
    ...
}
```

Unlike a class downcast, the compiler cannot answer this from anything it laid
out: the object decides, at run time, in code that may not be ours. So `is` is
a call, and it is worth writing even upwards — there is no "always true"
warning here, because even that answer is the object's. A cast that the object
refuses ends the program, the same as a failed class downcast.

### `[NoUnknown]`: a vtable that is not COM

Some C libraries hand out the other thing: a bare array of function pointers,
with no `QueryInterface`, no `AddRef` and no `Release` at the front of it. The
binary shape is the same — a pointer to a vtable pointer — and everything COM
adds is absent.

```csharp
[NoUnknown]
public com interface IXAudio2Voice {
    void GetVoiceDetails(VoiceDetails* details);       // slot 0, not slot 3
    int  SetOutputVoices(VoiceSends* sends);
    ...
    void DestroyVoice();
}
```

XAudio2's voices are the example the attribute exists for. `IXAudio2Voice`
derives from nothing, its own first method is slot **0**, and a voice is ended
by calling `DestroyVoice` rather than by a count reaching zero. Reaching one
through an ordinary `com interface` would call `SetOutputVoices` where ARC
expected `AddRef`, and the failure would be silent.

Two things follow, and both are consequences rather than choices:

- **The numbering starts at zero**, because there is nothing in front of it.
- **ARC leaves it alone**, because the two slots ARC calls are not there. Such
  a reference is a pointer that has methods: copying it counts nothing,
  dropping it releases nothing, and how the object dies is the library's to
  say.

What the attribute costs is everything `IUnknown` was for. There is no `[Guid]`
(SL0624) — an IID names an interface *to QueryInterface*, and there is none to
ask. For the same reason nothing can ask what such a reference really is: there
is no cast to or from another com interface (SL0243), no `is` (SL0518) and no
type pattern (SL0619), whichever side the `[NoUnknown]` is on. And a chain is
all one kind or the other (SL0622): extending across would put `IUnknown` three
slots into the middle of one table. It may be written only on a
`com interface` (SL0623).

A cast from `byte*` still adopts the pointer, and adopting costs nothing here
because there was no `+1` to take over:

```csharp
byte* raw = null;
audio.CreateSourceVoice(&raw, &format, 0u, 2.0f, null, null, null);
var voice = (IXAudio2SourceVoice)raw;
...
voice.DestroyVoice();                  // the library's rule, written out
```

### `com class`: being a COM object

```csharp
[Guid("2cd90691-12e2-11dc-9fed-001143a055f9")]
public com interface ILoudGreeter {
    int Greet(int times);
    int Shout();
}

public com class Greeter : ILoudGreeter {
    int count;
    public int Greet(int times) { count = count + times; return count; }
    public int Shout() { return count; }
}
```

An ordinary Stainless object — header, fields, destructor, ARC — that also
presents COM vtables. `QueryInterface`, `AddRef` and `Release` are the
compiler's and not the programmer's: they are the same three functions for
every com class, and a hand-written `AddRef` would put the object's count and
ARC's out of step.

The object carries one **tear-off** per interface it presents, laid out after
the fields: a vtable pointer and the distance back to the object. The distance
is what makes several interfaces possible at all — a COM pointer must point at
a vtable pointer, so an object presenting three has three addresses, and a
`Release` arriving through any of them has to find the one header. Each vtable
slot holds a one-instruction adjustor thunk that subtracts and tail-calls; C++
generates the same thing for the same reason.

Converting a com class to one of its interfaces is therefore the one COM
conversion that is not free: one add, at a constant offset.

### Where ARC and COM disagree

Once, and it is worth knowing. ARC releases at the end of a scope;
`CoUninitialize` is a call in the middle of one. So a reference held in the
same scope is released *after* the apartment it belongs to is gone, through a
vtable that is no longer there:

```csharp
Com.Initialize();
IFileOpenDialog dialog = ...;
Com.Uninitialize();                 // the object is still held
                                    // -> released here, into freed memory
```

In C both are statements and the programmer orders them. Here one of them is
emitted, so what orders them is the scope:

```csharp
Com.Initialize();
{
    IFileOpenDialog dialog = ...;   // released when this block ends
}
Com.Uninitialize();
```

This is the cost of the compiler owning the reference count, and it is a small
one against the class of bug it removes — but it is the one thing a COM
programmer knows that this does not do for them.

### `[Guid]` on a com class: being asked for

An IID names an interface and a CLSID names a class, and the difference is who
is asking. A caller holding an object asks it for an interface. A caller
holding *nothing* has only a CLSID, and needs the process to turn that into an
object. `[Guid]` on a `com class` is what makes the second possible:

```csharp
[Guid("5a1c8e30-2b47-4d16-a9f3-c04e7b81d629")]
public com class Greeter : IGreeter, ICounter { ... }

export "C" int DllGetClassObject(Guid* clsid, Guid* iid, byte** result) {
    return Com.GetClassObject(clsid, iid, result);
}
```

The compiler collects every com class carrying one into a table paired with a
function that makes it, and `Com.GetClassObject` answers that table with an
`IClassFactory`. **Adding a class to a server is declaring one** — there is no
registration call, and the factory is not written by hand.

Activation passes no arguments, so an activatable class needs a constructor
taking none. A class with no constructor at all is fine — its fields are the
zeroes the allocator wrote — but one that has constructors and no empty one is
refused where it is declared (SL0611) rather than where it could not be made.

`DllGetClassObject` is the whole of what an in-process server must export, and
`Com.CanUnloadNow` is the other half of the pair. It answers from a count the
module keeps of every com class object it has made against every one it has
destroyed, plus the class factories still held: S_FALSE while anything is
outstanding, S_OK at zero. Each object's own reference count is what decides
when it dies, and nothing sums those or lists the objects — so this one total
is kept alongside them, moved where an object is allocated and where its
destructor runs. It is emitted only in a module that has something to activate,
so a program presenting com interfaces and hosting nothing pays nothing.

The count is over objects rather than over what escaped, which makes it
conservative: one made inside the library and never handed out counts as well.
That errs toward refusing an unload that would have been fine, and never toward
allowing one that would not.

[samples/com](../../samples/com) is the whole of it: a server built `--shared`,
a C++ host that loads it and activates the class, and the destructor running
between the host's `Release()` and its next line.

### What is not there

- **The rest of activation.** In-process and free-threaded only, stated as a
  limit rather than discovered as one: no apartments, no marshalling, no
  proxies or stubs, no `IDispatch`, and no aggregation — `CreateInstance`
  refuses a non-null outer rather than half-supporting it. No registry either;
  a host either writes the two keys itself or opens the module directly, which
  is what the sample does. A program wanting `CoCreateInstance` declares it
  `extern "C"` like any other Windows API, as [bindings/win32](../../bindings/win32)
  does for the shell's half.
- **A com class cannot derive from a class** (SL0536): the tear-offs sit after
  the fields, and a derived class adds fields after those.
- **On 32-bit x86 an export is `__cdecl` unless it says otherwise.** Windows'
  loader calls `DllGetClassObject` as `__stdcall`, so a server writes
  `export "C" __stdcall` — and the name that reaches the export table is the
  one the source declared, because the compiler writes a module definition
  file for exactly this ([§8.2](#82-building-a-shared-library)). Every COM
  *slot* is already `__stdcall` there, stamped on when the table is numbered.

## 8.6 Linking a platform library

Object files, static archives and import libraries can be listed among the
source paths, and are handed to the linker as they are. A library the linker can
find for itself is named with `-l` instead:

```
stainless build gui.sl bindings/win32/api/User32.sl bindings/win32/Ui.sl -l user32
```

`-l user32` reaches the Windows SDK's `user32.lib` through the linker's own
search path, rather than through whichever SDK version happens to be installed.
The spelling is the one every C toolchain takes, `-l name` or `-lname`.

**A file can name its own library**, which is usually better: the module that
calls into user32 is the one that knows it needs user32, and saying so there
stops every program that compiles it from repeating the name.

```csharp
#pragma comment(lib, "user32")
```

This is MSVC's spelling, and it is the only pragma Stainless has. Both
`"user32"` and `"user32.lib"` are accepted — the linker wants the first and a C
programmer will type the second. A pragma inside a branch `#if` did not take
means nothing, as a declaration there would. The names are gathered from every
file and merged with any `-l`, so linking a library twice is not an error.

**A library is needed by the code that is compiled, not by the code that runs.**
An undefined symbol is an error before the dead-strip that would have removed
the function referring to it, so compiling a module full of `extern "C"`
declarations does not cost anything, but compiling a *wrapper* that calls one
makes its library necessary whether or not the program ever reaches it. That is
why [bindings/win32](../../bindings/win32) is source a program chooses to compile
rather than part of the standard library, which is compiled into everything —
and why it keeps its declarations in `Win32.<Dll>` modules apart from the
conveniences, so that importing the whole Windows API can stay free.

A linker failure says which of the two it is:

```
error: the linker could not find everything the program refers to:
lld-link: error: undefined symbol: GetSystemMetrics
A name declared 'extern "C"' has to come from somewhere. Link what defines it:
'-l <name>' for a library the linker can find on its own, or its path as an
ordinary input.
```

## 8.7 Embedding a file

```csharp
static readonly byte[] Logo = embed("logo.png");                        // read-only data
static readonly byte[] Table = embed("data/table.bin", access: "rw");   // writable
static readonly byte[] Stub = embed("stub.bin", section: ".stub", access: "rx");
```

`embed` makes a file's bytes part of the binary and names them as a `byte[]`.
Nothing is copied at run time and nothing is read from disk: the linker places
an array object holding the file, and the expression is its address. It is an
expression like any other, so a local may be given one as well as a static —
but a static is what it is for, because the object exists for the life of the
program whatever holds it.

This is what C does with `xxd -i` and a generated header, and what C23 does
with `#embed`. It is a keyword here, like `nameof` and `sizeof`, rather than a
function in the standard library, because what it produces is decided when the
program is built and no function runs then.

**Every argument is a string literal.** The path, the section and the access
each decide something about the binary, so none of them can be a value the
program computes (SL0704) — not a `static readonly String`, and not two
literals joined with `+`. A file whose name is known only at run time is a file
to read, and `Standard.File` reads it. The path comes first, and the other two
are named arguments ([§7.2.2](07-functions-members.md#722-named-arguments)),
each given once (SL0703).

### The path

**Relative to the source file that wrote the `embed`**, not to the directory
the build was started in. A source file and the data beside it move together,
and a build started from a project two directories up, from the test harness
or from an editor then finds the same bytes. It is the rule `llvm-rc` follows
for a resource script and the one `#include "..."` starts with, and for the
same reason: it is what makes a project relocatable. An absolute path is taken
as written.

The file is checked where the `embed` is bound, so a mistake is an error on the
literal that made it rather than an assembler failure later. A file that is not
there, a directory, a file that cannot be opened, and one larger than an array
on the target can describe are all SL0706:

```
error[SL0706]: there is no file at 'C:\src\game\assets\logo.png' to embed
```

A relative path also needs a file to be relative to. Source compiled from a
file always has one; the standard library, which the compiler holds as
resources, and text an editor or a test hands the compiler under a made-up
name do not, and a relative `embed` in either is refused rather than resolved
against whatever the working directory happens to be.

**Two identical embeds are one object.** The same file, placed in the same
section with the same access, is the same bytes, so a program that names it in
three places carries it once and all three are the same reference. Changing the
access or the section makes another object, because those are different memory.

### Access

`access:` is some of the letters `r`, `w` and `x`, each at most once, in any
order, and always including `r` (SL0707). The default is `"r"`.

| Access | Default section, PE | Default section, ELF | What it is for |
|---|---|---|---|
| `"r"` | `.rdata` | `.rodata` | data the program reads — the usual case |
| `"rw"` | `.data` | `.data` | a table the program also updates |
| `"rx"` | `.text` | `.text` | machine code to call |
| `"rwx"` | none | none | code written at run time; name a section |

**Writing to a read-only embed faults**, as writing to a string literal does in
C. Nothing checks it when the program is compiled — an element store looks the
same whatever array it is into — and nothing makes it silently work either:
the page is mapped read-only, and the store is an access violation or a
`SIGSEGV`. The optimiser is not told the bytes are constant, deliberately, so
that the fault is what happens rather than the store being deleted as
something that cannot occur. Ask for `"rw"` where the program writes.

**`"rwx"` has no default** (SL0708). Every target has a section for read-only
data, for writable data and for code, and none has one for memory that is both
writable and executable — the combination security hardening exists to remove.
Quietly making one would put it in a binary nobody asked for it in by name, so
it is asked for by name:

```csharp
static readonly byte[] Scratch = embed("trampoline.bin", section: ".jit", access: "rwx");
```

`"rx"` is how an embed becomes code. The first element is the first byte of the
file, and a pointer to it converts to a `delegate`
([§2.14](02-types.md#214-delegate--a-named-function-pointer)):

```csharp
public delegate int Answer();

static readonly byte[] Stub = embed("stub.bin", section: ".stub", access: "rx");
...
var answer = (Answer)(void*)&Stub[0];      // B8 2A 00 00 00 C3: mov eax, 42; ret
Console.WriteLine($"{answer()}");          // 42
```

### Sections

`section:` names where the object goes; without it the object goes where the
table above says. A name has to survive being written into an assembler
directive and named again by a linker script, so it may not be empty or hold a
quote, a backslash, a comma, whitespace or a control character (SL0709).

**A section already has its permissions, and an embed cannot give it others**
(SL0711). An assembler does not take flags for a section it knows: `.text`
asked for as read-only data is still executable, silently, on both object
formats — so an embed asking `.text` for `"r"` would get code. The same holds
for a name extending one of those (`.text.stub` on ELF, `.text$stub` on PE,
which the linker folds into `.text`), for `.bss`, which holds no bytes in the
file at all, and for a section this program defines: the first embed placed in
one decides its access, and a second asking for different access is refused
rather than left for the assembler to reject or, on PE, to ignore.

```
error[SL0711]: '.text' is always "rx" on x86_64-pc-linux-gnu, and the assembler
would keep that whatever an embed asked for, so "r" cannot be placed there; name
a section of its own
```

**A PE image keeps eight bytes of a section name.** An object file can hold a
longer one, and lld-link then cuts it short in the executable without a word —
`.embedded_logo` becomes `.embedde`. The bytes arrive either way, so this is a
warning rather than an error, and only for a Windows target (SL0710): what
breaks is a tool looking for the section by the name the source gave it.

### What is in the section

The section holds the whole array object — the header and then the file — so
that the address the program holds is an ordinary array reference and nothing
has to be built at startup:

```
word 0   strong count   all ones: SL_IMMORTAL
word 1   weak count     all ones
word 2   type           0
word 3   length         the file's size in bytes
word 4…  the file, byte for byte
```

A word is eight bytes on a 64-bit target and four on x86, and the object is
aligned to one. The cost is that the section is not only the file: a dump of it
shows the header in front — 32 bytes on a 64-bit target — and a tool reading
the section expecting the file alone has to skip them. `&Stub[0]` is the first
byte of the file.

**The object file has the section; the executable has what the linker made of
it.** A linker script decides which input sections become which output ones,
and the default one does not always keep a name: GNU ld's folds `.stub` into
`.text`, so on Linux the stub above runs from `.text` and `readelf -x .stub`
finds nothing, and the eight-byte limit above is the same kind of thing on
Windows. The permissions survive, because an output section has at least those
of everything folded into it. A name no default script mentions — `.jit`,
`.blob` — is one that reaches the executable as written.

**The type word is zero, where every other object has a pointer.** A pointer
there would be a relocation, and a relocation in a read-only or executable
section of a position-independent Linux executable is one the loader would have
to write to a page it is not allowed to: lld refuses to link it ("recompile with
-fPIC"), and GNU ld links it with a warning and a `DT_TEXTREL` that hardened
systems will not load. Zero is safe because
nothing reachable from a `byte[]` reads it. An immortal object's counts are
checked first by everything that would touch its header — retain, release,
their weak counterparts and `sl_make_immortal` all return before reading
further — so it is never destroyed and never asks its type how. The runtime
already treats a null type as no type wherever it does read one: a class test is
false, an interface test is false, and a failed cast's message calls it `null`.
And an array's type information has no dispatch table, no interfaces and no COM
layout, so no call on an array could have looked one up.

**The bytes are assembly, not an IR global.** An IR global can be given a
section but not the section's flags; on ELF, one placed in a section an
assembler directive also named becomes a second section of the same name with
the flags LLVM chose. So the compiler writes the directive, the header and an
`.incbin` of the file into the module's assembly, in the syntax of the target's
object format, and refers to the label from the IR. That also keeps the IR
small — a megabyte of image is one line rather than three megabytes of escaped
bytes — and means the compiler never holds the file in memory: the assembler
reads it. `.incbin` is given the length the file had when it was checked, so a
file that shrank in between is an assembler error rather than a length word
promising bytes that are not there.

### Rebuilding

**An embedded file is an input to the build**, as a source file is. A shared
dependency is rebuilt when one it embeds has changed, wherever the file is: its
build stamp records each embedded file and the digest of its bytes, and a stamp
whose files no longer match is a stamp that says nothing
([packages.md §7.1](../packages.md#71-what-gets-rebuilt)). They are kept beside
the stamp's other inputs rather than hashed with them, because every other
input is known before the build starts and which files a program embeds is not
known until it has been bound.

One thing it does not reach is the lock file. A package's `sourceDigest` is
taken over its own directory when dependencies are resolved, before anything is
bound, so an embed of a file outside the package changes what is built without
changing that digest. Keep what a package embeds inside the package.

### `embed` or a resource

[Resources](../packages.md#22-resources) are the other way to carry bytes, and
the two answer different questions.

A **resource** is found at run time, by a type and a number, through
`Standard.Resources`. It is how a Windows program carries what Windows itself
reads — an icon, a manifest, a dialog template, a version block — and a program
can enumerate what it has, look one up by an ID computed at run time, and
replace one in the binary afterwards with a resource editor. What that costs is
a lookup and an API.

An **`embed`** is found by the linker, by name. There is no lookup, no ID and
no API: the program holds the array from the moment it starts. It is the right
choice for data the program itself uses — a font, a shader, a lookup table, a
default configuration, a stub of machine code — and the only one of the two
that can be writable or executable. What it cannot do is be enumerated,
replaced after linking, or read by the operating system.

## 8.8 Inline assembly

```csharp
long Cycles()
{
    long low = 0;
    long high = 0;
    asm (out rax = low, out rdx = high)
    {
        rdtsc
    }
    return (high << 32) | low;
}
```

Some things a program needs are an instruction and not a function: `rdtsc`,
`cpuid`, a system register, a sequence a vectoriser will not find. C reaches
them through a compiler's intrinsics or a separate `.s` file, and a separate
file means a second toolchain, a calling convention written out by hand for
each target, and a call where one instruction was wanted. `asm` is the
instruction written where it is used.

**It is a statement, and only a statement.** `asm { ... }` or `asm (operands)
{ ... }` goes wherever a statement may — a loop, a lambda, a `for parallel`
body, a function `spawn` calls — and has no value, so it is never an
expression and never a constant. Two other forms were considered and left out.
A function whose whole body is assembly has to follow the calling convention
itself, once per target and by hand, which is precisely the work this form
takes away. Assembly at module level has no operands, so nothing about it can
be checked and everything about it is a symbol the program has to agree with
by name. Both remain possible with a `.s` file among the inputs, which is the
honest place for them.

It is **LLVM's inline assembly**, the construct clang lowers an MSVC `__asm`
block to: one `call ... asm` in the IR, with the operands as register
constraints. Nothing is called at run time — the instructions are placed in the
function, and the optimiser moves values into and out of the named registers
around them.

### 8.8.1 Operands

```csharp
asm (in rcx = count, in rsi = &buffer[0], inout rax = total, out rdx = carry)
{
    ...
}
```

| | |
|---|---|
| `in reg = value` | the value is placed in the register before the block |
| `out reg = place` | the register's value is stored into the place after it |
| `inout reg = place` | both: the place is read in, and written back |

`in` is the keyword it already was; `out` and `inout` are words, as `out` is at
a call ([§7.2.1](07-functions-members.md#721-out)), and stay names everywhere
else. An operand with no direction is SL0715, and the rest of it is still
checked. The value after `=` is read as an expression without assignment,
because the `=` is the operand's.

**Every operand is evaluated once, in the order written, before the block** —
an input's value, and an output's address — **and the outputs are stored in
the same order after it.** Taking the address first is what makes `inout rax =
counts[Next()]` call `Next` once rather than once to read and again to write. A
place is anything an assignment could write that has an address: a local, a
parameter, a field, an element, a dereference or a static. The checks an
assignment makes are made (SL0240, SL0448, SL0379), and a bit-field is refused
because it is the one place with no address (SL0722).

**An output is a write.** An `out` parameter written only by a block is written,
so SL0600 is satisfied by it; and an output to a variable declared outside a
`for parallel` body is the race an assignment to one is (SL0373).

**What may travel in a register** is plain data: an integer, a `bool`, a
character type, an enum, a pointer or a delegate in a general register, and a
`float` or a `double` in a vector register. A counted reference cannot — the
block could copy it anywhere, with nothing to count the copy — nor can a
struct, which is several values; pass the address instead (SL0719). A value of
one kind in the other kind of register is SL0721: an integer's bits in an `xmm`
register would have to be converted to mean anything, and a conversion belongs
before the block, where it can be seen.

**Widths.** A value wider than its register is an error (SL0720): `in eax =
aLong` has nowhere to put the upper half. A narrower one is allowed, and what
it means is fixed rather than left to the optimiser:

| | |
|---|---|
| a narrower value going in | extended to the register's width by its own signedness, so an `int` of -1 in `rcx` is -1 in all sixty-four bits |
| a narrower place coming out | the register's low bits |
| a `bool` going in | 0 or 1, extended |
| a `bool` coming out | whether the register is anything but zero |
| a `float` in `xmm0` or `v0` | the low 32 bits; the rest of the register is unspecified |

LLVM happens to zero-extend an `i32` handed to `{rcx}` today. Nothing promises
that, and a block reading the whole register would otherwise see whatever its
upper half last held — which is right until the day it is not, and then only
at one optimisation level. So the compiler extends explicitly, and the cost is
one `sext` or `zext` the optimiser folds away whenever the value was wide
already.

**A literal takes the register's width** where it fits, as it takes a
declaration's: `in al = 200` is a byte, and `in al = 256` is SL0720. An integer
literal given to a vector register is the floating-point number it names.

### 8.8.2 Registers

| Target | General | Vector |
|---|---|---|
| x64 | `rax`–`r15`, `eax`–`r15d`, `ax`–`r15w`, `al`–`r15b` (with `sil` and `dil`) | `xmm0`–`xmm15` |
| x86 | `eax`, `ebx`, `ecx`, `edx`, `esi`, `edi`; `ax`–`di`; `al`–`dl` | `xmm0`–`xmm7` |
| arm64 | `x0`–`x30`, `w0`–`w30`, `lr` | `v0`–`v31`, and `d0`–`d31`, `s0`–`s31` |

Names are case-insensitive. The table checked is the target's, so `x0` built for
x64 is SL0716, and the message names the architecture that was being built for
— which is most of the answer when a file meant for another one was compiled by
mistake. The high-byte registers `ah` to `dh` are not there: they are not the
low bits of anything, so none of the width rules above would mean anything for
them.

**Some registers cannot be operands** (SL0717): the stack pointer (`rsp`,
`esp`, `sp` and every width of them), because a block that moved it would leave
every local at the wrong address; the frame pointer (`rbp`, `ebp`, `x29`,
`fp`), which a function may address its locals through; and on Windows ARM64
`x18`, which holds the thread environment block. Linux leaves `x18` to be used,
so there it is an ordinary register.

**A register holds one value going in and one coming out**, so it may be named
by one `in` and one `out` — `in rcx = count, out rcx = left` puts `count` in and
stores what the block leaves in `left` — or by one `inout`, which is the same
thing with the two places the same. Anything more is SL0718, whatever the
names: `eax` is `rax`, and `d3` is `v3`.

On ARM64 a vector register is given to LLVM by the width of what it carries —
`s1` for a `float` and `d1` for a `double`, whether `v1`, `s1` or `d1` was
written — and `x30` is given as `lr`. Both are LLVM's rules: `{v0}` with a
`float` crashes its code generator, `{d0}` with one converts the value to a
double on the way in, and `{x30}` is refused as an operand and ignored as a
clobber. `d` names a register holding a double, so a `float` in it is the
narrower case above; `s` names one holding a float, so a `double` is too wide.

### 8.8.3 What a block may change

**A block may change every register a C call may change**, and every one of
them is declared changed to LLVM — the caller-saved set of the target, listed in
[§3.5 of the ABI notes](../abi.md#35-what-a-call-may-change). **A callee-saved
register it changes, it restores**, exactly as a C function would. The flags
are declared changed too.

```
call { i64, i64 } asm inteldialect "rdtsc", "={rax},={rdx},~{rax},~{rcx},~{rdx},
    ~{r8},~{r9},~{r10},~{r11},~{xmm0},~{xmm1},~{xmm2},~{xmm3},~{xmm4},~{xmm5},
    ~{dirflag},~{fpsr},~{flags}"()
```

The alternative is Rust's `asm!`, which makes the author list each clobbered
register, or declare the block to follow the C convention with
`clobber_abi("C")`. A list is precise: a value may stay in a register the block
did not touch, and nothing is moved. What it costs is that a list wrong by one
register is a miscompilation, and not a loud one — the optimiser reads a value
back from a register the block overwrote, which it does only when it chose that
register for something live across the block, which depends on the
optimisation level and on the code around it. A block can be right at `-O0` and
wrong at `-O2`, or right until the function around it changes. Making the C set
the rule means there is no list to get wrong. What *that* costs is that a value
live across a block cannot stay in a volatile register — it moves to a
callee-saved one or to the stack, just as it would across a call — and that
the rule is a fact to know rather than something written beside the block.
Rust's own escape hatch is the same trade, and it is the one most blocks want.

**An operand's register is always declared changed**, callee-saved or not.
LLVM reads an input register it was not told is clobbered as still holding its
value afterwards, and will take the value from there: a block that took
`{rcx}` and zeroed it had the zero added into its result, at `-O1`. Declaring
it costs nothing for a volatile register, and for a callee-saved one it is what
makes the function save and restore it — so a block may leave `rbx` changed
once `rbx` is an operand.

[tests/cases/asm-clobbers](../../tests/cases/asm-clobbers) is what holds the
rule: seven values live across a block that destroys every volatile register,
built optimised. With the vector registers left out of the clobbers it prints a
different number, and with the general ones left out it prints another; it runs
on Windows and on Linux, whose sets differ, and
[x86-asm](../../tests/cases/x86-asm) does the same for 32-bit x86.

### 8.8.4 The text

**Everything between the braces is the target assembler's**, handed to it as
written, line for line, less any carriage return. The compiler does not read
it: a misspelt instruction is found by LLVM as the program is built, and put
back on the line it was about.

```
error[SL0723]: the assembler rejected this line of an 'asm' block: invalid
instruction mnemonic 'bogus'
 --> clock.sl:9:9
  |
9 |         bogus rax
  |         ^^^^^^^^^
```

**x86 is Intel syntax** — `mov rax, rcx`, destination first, `qword ptr [rsi]`
— because it is what the processor's documentation and most of what is written
about x86 use. ARM has one syntax.

| | x86, x64 | arm64 |
|---|---|---|
| `// comment` and `/* comment */` | yes | yes |
| `# comment` | yes, anywhere on a line | only at the start of a line; elsewhere `#` is an immediate |
| `; comment` | **no** — `;` separates two instructions on one line | the same |
| a named label, `loop:` | yes, and a symbol of the whole object file | the same |
| a numbered label, `1:` | yes, reached forward as `1f`; `1b` reads as the binary number 1 | yes, `1f` and `1b` |

**`;` is not a comment**, which is the one thing a reader of MASM will expect it
to be. `mov rax, 1 ; set it` is two instructions, and the second is `set it`.

**A named label is a symbol of the object file**, not of the block, so two
blocks anywhere in a program may not both define `done`. A numbered label may
repeat, which is what makes it the one to reach for in a block; on x86 it can
only be jumped to forwards.

**Braces are counted**, comments and all, so a block may hold one only with its
partner. `vaddps zmm0 {k1}, zmm1, zmm2` is fine, and a comment reading `// }`
ends the block early. Recognising comments while looking for the end would mean
knowing which syntax the target has — `#` starts a comment on one and not the
other — and a rule that changed with `--target` would lex one file two ways. A
block that is never closed takes the rest of the file (SL0713), and an `asm`
with no braces after it has no block at all (SL0714).

**Nothing inside is a directive.** A line beginning `#if` is x86's comment
rather than a condition; `#if` goes around the whole statement:

```csharp
#if X64
    asm (out rax = low, out rdx = high) { rdtsc }
#elif ARM64
    asm (out x0 = low) { mrs x0, cntvct_el0 }
#endif
```

**`asm` is a keyword, not a contextual word.** The body has to be captured by
the lexer, since assembly is not Stainless tokens and the file is tokenized
before anything is parsed, and the lexer cannot see whether a word begins a
statement: `void asm(int x) { ... }` has exactly the shape of a block. Nothing
in this repository used the word as a name.

### 8.8.5 What is undefined

The compiler cannot see inside a block, so these are the programmer's to keep,
and breaking any of them is undefined behaviour rather than a diagnostic:

- **Leaving other than by the end.** A `ret`, or a jump to a label outside the
  block, skips the stores of the outputs and whatever the function had to
  release, and returns through a frame the block does not know the shape of.
- **Changing a callee-saved register that is not an operand** without putting
  it back, or the stack pointer, or the frame pointer.
- **Leaving state a call would not.** The direction flag clear, and on x86 the
  x87 stack empty, as the C ABI requires at every call.
- **Writing through an operand into storage the language manages** — a
  `String`'s bytes, an array past its length — which a pointer already allows
  and a block allows no more carefully.

### 8.8.6 Examples

```csharp
// Counts a buffer's set bits, whichever machine this is.
nuint Population(byte* bytes, nuint count)
{
    nuint total = 0;
#if X64
    asm (in rsi = bytes, in rcx = count, out rax = total)
    {
        xor eax, eax
        test rcx, rcx
        jz 2f
    population:
        movzx edx, byte ptr [rsi]
        popcnt edx, edx
        add rax, rdx
        inc rsi
        dec rcx
        jnz population
    2:
    }
#elif X86
    asm (in esi = bytes, in ecx = count, out eax = total)
    {
        xor eax, eax
        test ecx, ecx
        jz 2f
    population32:
        movzx edx, byte ptr [esi]
        popcnt edx, edx
        add eax, edx
        inc esi
        dec ecx
        jnz population32
    2:
    }
#elif ARM64
    asm (in x1 = bytes, in x2 = count, out x0 = total)
    {
        mov x0, #0
        cbz x2, 2f
    1:
        ldrb w3, [x1], #1
        fmov d0, x3
        cnt v0.8b, v0.8b
        umov w3, v0.b[0]
        add x0, x0, x3
        subs x2, x2, #1
        b.ne 1b
    2:
    }
#endif
    return total;
}
```

The x86 blocks name their loops because an Intel-syntax `1b` is a number, and
each name is a symbol of the whole program, so the two differ. `nuint` is the
register's width on every target, which is what lets one declaration serve all
three. The ARM64 block uses `x3` and `v0` without naming either: both are
caller-saved, so both are declared changed already.

---

<sub>[&larr; Functions and members](07-functions-members.md) &nbsp;&middot;&nbsp; [Statements and expressions &rarr;](09-statements-expressions.md)</sub>
