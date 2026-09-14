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
in the language reads the extra arguments -- there is no `va_list` -- so the
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

The compiler emits whichever the target uses, and `STAINLESS_CPP_ABI` overrides
the choice so that the scheme a host does not use can still be checked against a
real compiler.

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
library, so both sides count against the same allocator. That is not done yet.

## 8.4 A Stainless library consumed by Stainless

Stainless has no headers, and inside one compilation it needs none: every
declaration is visible because every file is compiled together. A library is
where that stops. The consumer is a separate compilation with no access to the
source, so something has to carry what the source would have said.

```
stainless build lib --shared -o build/shapes.dll --metadata build/shapes.slmod
stainless build app.sl --reference build/shapes.slmod build/shapes.lib -o app.exe
```

The `.slmod` is generated, never edited, and cannot drift from the library
because it is written from the same bound program. It describes the public
surface: layouts, field offsets, signatures, and the linker names to call.

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

**What does not cross, and why.** Both are consequences of the language
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
rather than part of the standard library, which is compiled into everything --
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

---

<sub>[&larr; Functions and members](07-functions-members.md) &nbsp;&middot;&nbsp; [Statements and expressions &rarr;](09-statements-expressions.md)</sub>
