<!-- SPDX-License-Identifier: 0BSD -->
# A COM server, written in Stainless and called from C++

```
build.cmd            (Windows)
./build.sh           (elsewhere)
```

```
[host]      loading build\greeter.dll
[host]      got the class factory
[stainless] Greeter constructed
[host]      created a Greeter, factory released
[stainless] Greet(3) -> 3
[host]      Greet(3)  -> 3
[stainless] Greet(4) -> 7
[host]      Greet(4)  -> 7
[host]      Total()   -> 7
[host]      QueryInterface(ICounter) ok, a different pointer
[host]      IUnknown identity holds: yes
[stainless] Reset
[host]      Total() after Reset -> 0
[host]      releasing the Greeter
[stainless] Greeter destroyed
[host]      released
[host]      DllCanUnloadNow -> S_FALSE (declines)
```

Three files, and none of them is generated:

| | |
|---|---|
| [greeter.sl](greeter.sl) | the server: two `com interface`s, one `com class`, and the two exports that make it a server |
| [greeter.h](greeter.h) | what C++ sees — hand-written, the way a COM consumer writes it or MIDL writes it from an `.idl` |
| [host.cpp](host.cpp) | an ordinary C++ program that activates the class and uses it |

## What is actually being shown

**The destructor line lands between "releasing" and "released".** That is the
whole sample in one detail. C++ calls `Release()`, the count reaches zero, and
`~Greeter()` — Stainless code, holding Stainless fields — runs right there,
before the next line of C++. Nobody wrote a `Release`; ARC emitted it, and the
object's count and COM's are the same count.

**A second interface is a second address, and `IUnknown` is not.**
`QueryInterface(ICounter)` hands back a pointer that differs from the `IGreeter`
one, because the object carries a tear-off per interface and a COM pointer must
point at a vtable pointer. Asking either of them for `IUnknown` returns the
*same* address, which is how COM says "these are one object" — and the sample
checks it.

**Nothing marshals.** `IGreeter` in `greeter.h` is a C++ class with two virtual
methods after `IUnknown`'s three; `com interface IGreeter` in `greeter.sl` is
the same five slots. The `GUID`s are the same sixteen bytes. There is no
interop layer between them because there is nothing for one to do.

## Activation, and what a CLSID is for

An IID names an interface; a **CLSID names a class**. The difference is who is
asking. A caller that already holds an object asks it for an interface. A caller
that holds *nothing* — which is the host here, at startup — has only a CLSID,
and needs someone to turn that into an object.

That someone is `DllGetClassObject`, and it is the reason
[`[Guid]` on a `com class`](../../docs/spec/08-interop-libraries.md#85-com)
exists at all:

```csharp
[Guid("5a1c8e30-2b47-4d16-a9f3-c04e7b81d629")]
public com class Greeter : IGreeter, ICounter { ... }

export "C" int DllGetClassObject(Guid* clsid, Guid* iid, byte** result) {
    return Com.GetClassObject(clsid, iid, result);
}
```

The compiler collects every `com class` carrying a `[Guid]` into a table paired
with a function that makes one, and `Com.GetClassObject` answers from it with an
`IClassFactory`. So **adding a class to this server is declaring one** — there is
no registration call to remember and no factory to hand-write.

Activation supplies no arguments, so an activatable class needs a constructor
taking none; a class that has constructors and no empty one is refused (SL0611)
where it is declared rather than where it fails to be made.

## The registry, and why this does not use it

Real `CoCreateInstance` looks a CLSID up in the registry, finds a path, loads
that module and calls `DllGetClassObject` on it. This host does the last two
steps and skips the first, which is why it needs no `regsvr32` and no admin
rights. Everything after `LoadLibrary` is the genuine article — the same entry
point, the same `IClassFactory`, the same vtables.

To go the rest of the way on Windows, write the two registry keys COM reads:

```
HKEY_CURRENT_USER\Software\Classes\CLSID\{5A1C8E30-2B47-4D16-A9F3-C04E7B81D629}
    (default)              = "Stainless Greeter"
HKEY_CURRENT_USER\Software\Classes\CLSID\{5A1C8E30-2B47-4D16-A9F3-C04E7B81D629}\InprocServer32
    (default)              = "<full path to>\greeter.dll"
    ThreadingModel         = "Both"
```

then `CoCreateInstance(CLSID_Greeter, nullptr, CLSCTX_INPROC_SERVER,
IID_IGreeter, ...)` reaches the same object. `HKEY_CURRENT_USER` rather than
`HKEY_LOCAL_MACHINE` is what keeps it out of admin's way.

## Limits, stated rather than discovered

- **In-process and free-threaded only.** No apartments, no marshalling, no
  proxies or stubs, no `IDispatch`, no aggregation — `CreateInstance` refuses a
  non-null outer with `CLASS_E_NOAGGREGATION` rather than half-supporting it.
- **`DllCanUnloadNow` always declines.** Answering it honestly needs a count of
  live objects, and ARC owns those lifetimes with no hook that says "and that
  was the last one". A server that is never unloaded before the process exits
  is correct; one that unloads while a caller still holds a vtable pointer is a
  jump into freed pages.
- **On 32-bit x86 the export is `__cdecl` here**, which is what this host
  expects and what makes the sample run as written on both. A server that
  Windows' *own* loader will call wants `__stdcall` with the name left
  undecorated, and undecorating it needs a `.def` file the compiler cannot
  write yet. The interface methods are already `__stdcall` on x86 — the
  compiler stamps that on every COM vtable slot — so only the two exports are
  affected.

## See also

- [§8.5 of the specification](../../docs/spec/08-interop-libraries.md#85-com) —
  `com interface`, `com class`, tear-offs, and where ARC and COM disagree
- [§2.9 of the ABI notes](../../docs/abi.md#29-com) — the layouts both sides agree on
- [tests/cases/com-activation](../../tests/cases/com-activation) — the same
  ground as a test, in one binary
- [tests/cases/com-native](../../tests/cases/com-native) — COM across a C
  boundary in both directions
