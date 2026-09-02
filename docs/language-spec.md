# Stainless Language Specification (v0.1 draft)

Stainless is a systems language with C++'s performance model and C#'s syntax.

**Design pillars**

1. **No header files.** One file is one module. Declarations are order-independent
   within and across modules; the compiler resolves the whole program graph before
   checking any body. There is no preprocessor, no `#include`, no include guards,
   no forward declarations, no ODR.
2. **Native code via LLVM.** No VM, no JIT, no runtime startup cost beyond a
   small ARC runtime.
3. **ARC, not GC.** Reference types are reference-counted and destroyed
   deterministically. No collector, no pauses, no tracing thread.
4. **C/C++ ABI compatible.** `struct` types use the platform C layout,
   `extern "C"` functions use the platform calling convention, and Stainless
   functions are callable from C. Interop needs no marshalling layer.

If you write C#, you can read Stainless on sight. The differences are all
about what happens underneath: values instead of objects, refcounts instead
of a collector, a linker instead of an assembly loader.

---

## 1. Modules

```csharp
module App.Math;          // optional; inferred from path if omitted

import Std.IO;            // brings Std.IO's public members into scope
import Std.IO as Term;    // aliased
```

A module is exactly one source file. A file with no `module` declaration takes
its module name from its path relative to the package root
(`src/App/Math.sl` -> `App.Math`).

> Stainless says `module`, not `namespace`, because the two differ: a C#
> namespace may span any number of files, while a Stainless module *is* a
> file. That one-to-one rule is what lets the compiler retire header files.

Top-level declarations are private to their module unless marked `public`:

```csharp
public double Area(double r) { return 3.14159 * r * r; }
double Helper() { return 1; }        // module-private
```

Because there are no headers, `public` is the *only* thing that controls
visibility, and a module's public surface is derived from its own source.
Order never matters:

```csharp
int Main() {
    return Later();     // fine: Later is declared below
}

int Later() { return 0; }
```

## 2. Types

### 2.1 Primitives

Names and sizes match C# exactly.

| Stainless | Size | C equivalent |
|---|---|---|
| `sbyte` `short` `int` `long` | 1/2/4/8 | `int8_t` … `int64_t` |
| `byte` `ushort` `uint` `ulong` | 1/2/4/8 | `uint8_t` … `uint64_t` |
| `nint` `nuint` | pointer | `intptr_t` / `size_t` |
| `float` `double` | 4/8 | `float` / `double` |
| `bool` | 1 | `bool` |
| `char` | 1 | `char` (a UTF-8 code unit, not UTF-16) |
| `void` | 0 | `void` |

### 2.2 `struct` — value type, C layout

```csharp
public struct Point {
    public double X;
    public double Y;

    public double LengthSquared() { return X * X + Y * Y; }
}
```

Structs are values: copied on assignment, passed per the platform C ABI, laid
out with C field order and padding. A Stainless `struct` and the corresponding
C `struct` are the same bytes, always. Structs are **not** reference counted.

### 2.3 `class` — reference type, ARC managed

```csharp
public class Buffer {
    byte* data;
    nuint length;

    public Buffer(nuint n) {
        data = Malloc(n);
        length = n;
    }

    ~Buffer() { Free(data); }        // destructor, runs at refcount 0

    public nuint Length() { return length; }
}
```

A class value is a pointer to a heap object preceded by an object header
(see [abi.md](abi.md)). Assignment copies the *reference* and retains it.
`new Buffer(64)` allocates, runs the constructor, and yields a reference with
a count of 1.

### 2.4 Pointers and nullability

| Syntax | Meaning |
|---|---|
| `T*` | raw pointer, unmanaged, C-compatible, nullable, unsafe to dereference |
| `C` (class) | strong reference, never null, ARC-managed |
| `C?` | optional strong reference, may be null |
| `weak C?` | non-owning reference; becomes null when the object dies |

## 3. Functions and members

```csharp
public int Add(int a, int b) { return a + b; }

void NoReturn() { }
```

Top-level functions are permitted — a module is a scope, so there is no need
to wrap free functions in a static class the way C# requires.

## 4. C interoperability

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

## 5. Statements and expressions

```csharp
int x = 10;             // explicitly typed local
var y = x + 1;          // inferred
const int Limit = 64;   // compile-time constant

if (y > 10) { ... } else { ... }
while (y > 0) { y = y - 1; }
for (int i = 0; i < 10; i = i + 1) { ... }
return y;
```

Operators, by descending precedence: unary `- ! ~ * &` · `* / %` · `+ -` ·
`<< >>` · `< <= > >=` · `== !=` · `&` · `^` · `|` · `&&` · `||` · assignment.

Conditions must be `bool`; there is no implicit int-to-bool conversion.
There are no implicit narrowing conversions. Widening integer conversions and
`int` -> `float`/`double` are implicit, as in C#; everything else needs a
cast: `(byte)x`.

A string literal has type `byte*` and points at NUL-terminated UTF-8 storage
with static lifetime, so it passes straight to a C function.
