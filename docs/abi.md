# Stainless ABI (x86-64, Windows / MSVC-compatible)

## 1. Value layout

Primitives and `struct`s use the **platform C ABI verbatim**. Field order is
declaration order; alignment and padding follow the C rules for the target.
A Stainless `struct Point { double X; double Y; }` is bit-identical to the C
`struct Point { double X; double Y; };` and is passed and returned by the
same rules (on Win64: by hidden pointer, since it exceeds 8 bytes).

This is a hard guarantee, not a best effort. It is also why `struct` is not
reference counted: adding a header would break it.

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
struct TypeInfo { size_t size; void (*destroy)(void* obj); const char* name; };
```

Because a class reference is a plain pointer, it can cross the C boundary as
`void*` — but C code must call `sl_retain` / `sl_release` to participate in
ownership.

## 3. Calling convention

| Declaration | Symbol name | Convention |
|---|---|---|
| `int Add(int, int)` in module `App.Math` | `_SL3App4Math3AddiiEi` | platform C |
| `extern "C" int puts(byte*)` | `puts` | platform C |
| `export "C" int sl_add(int, int)` | `sl_add` | platform C |

Every function uses the platform C calling convention. The mangling scheme
distinguishes *names* only, never argument passing, so any Stainless function
can be called from C given the mangled symbol — and `export "C"` removes even
that friction.

### Name mangling grammar

```
mangled  := "_SL" path params "E" ret
path     := (len ident)+                    ; module segments, then the name
params   := type* | "v"                     ; "v" when there are none
type     := prim | "P" type | "C" len ident | "S" len ident
prim     := a  sbyte    s  short    i  int      l  long
          | h  byte     t  ushort   j  uint     m  ulong
          | n  nint     y  nuint    f  float    d  double
          | b  bool     c  char     v  void
```

`len` is the decimal length of the identifier that follows, so the grammar
needs no separators: `App.Math.Add` becomes `3App4Math3Add`.

## 4. Ownership convention

Stainless follows a **borrowed-parameter / owned-return** convention, the same
choice Swift makes, because it eliminates most retain/release traffic:

- **Parameters are borrowed.** The caller guarantees the argument stays alive
  for the duration of the call. The callee does not retain on entry or release
  on exit. Passing a reference costs nothing.
- **Returns are owned (+1).** A function returning a class reference transfers
  a +1 count to the caller, which is responsible for releasing it.
- **Locals are owned.** Storing into a local retains; the local is released at
  scope exit, including on every early return.
- **Fields are owned.** Assigning to a field retains the new value and releases
  the old, in that order, so self-assignment is safe.
