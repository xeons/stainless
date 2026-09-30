# TODO

What is coming next, and what is known to be wrong. Not a wishlist —
[docs/status.md's "What does not exist yet"](docs/status.md#what-does-not-exist-yet) is the
honest full inventory of edges, and this is the subset with an intention behind
it.

Each entry says what it is, why it matters, and what it touches. An entry with
no "why" is one that should be deleted rather than done.

---

## Next

### `Reflection.CreateInstance` hands out a reference nobody can give back

It answers with a `byte*` the caller owns, and the module keeps `sl_release`
to itself -- which is the whole reason `CreateArrayInto` exists:

> **It stores the array rather than handing it over.** The reference an
> allocation answers with is owned by whoever received it, and this module
> keeps `sl_release` to itself; writing it into the field here and dropping
> the allocation's reference leaves the field the only owner and the caller
> nothing to remember.

`CreateInstanceInto` is the same treatment for an object. `CreateInstance` is
not, and its own block suggests `WriteAggregate`, which takes a reference of
its own and leaves the caller's where it was. So `tests/cases/type-by-name`
leaks the two objects it builds and no caller could do otherwise. Either the
module offers the way back, or `CreateInstance` goes the way `CreateArray`
went.

### An event holds its subscriber unless the handler is bound to `this`

Not a bug. The rule is written down in
[Binder.Expressions.cs](src/Stainless.Compiler/Binding/Binder.Expressions.cs) --
`IsBoundToThis` -- and `runtime/arc.c` states it: an object never keeps itself
alive through its own subscriptions. It is emitted, it is taken, and the shape
it is for is clean:

```csharp
Ok.Clicked += this.OnOk;        // weak: the form does not hold itself
```

The gap is the same cycle wired by somebody else. `a.Changed += b.OnChanged`
takes the strong path, so if `b` also holds `a` neither is ever freed:

```csharp
l.Watching = s;
s.Changed += l.OnChanged;       // strong: nothing frees either
```

`tests/cases/events` records 3 for this. Widening the rule is not obviously
right: a handler must be held by *something*, and the receiver of a lambda is
a capture object the event is the only owner of -- hold that weakly and the
handler is freed before it is ever called. The narrow version, and the one
worth measuring first, is to take the weak path when the receiver is a plain
read of storage the caller already holds -- a local, a parameter, a field --
and keep the strong one for anything freshly made.

### Bring the comments to §4

Most of the tree predates [docs/style.md](docs/style.md) section 4, and three things
it forbids are everywhere:

- **Narration.** Bold lead-ins, rhetorical questions, and paragraphs arguing a
  case that the declaration under them already makes.
- **History.** Comments describing a bug that was fixed, an earlier shape of
  the code, or how long something took to find. That belongs in `git log`,
  attached to the change, where nobody has to keep it true.
- **Obligations in plain words.** "must be called from the thread that
  attached" rather than "MUST be called from the thread that attached", which
  is the difference between a remark and a rule.

It wants reading rather than a script: deciding whether a comment earns its
place is the part a regular expression cannot do, and §4.1's own rule is that
a comment restating the code is worse than none. One module at a time, each
its own commit, so that a rewrite never travels with a change of behaviour.

`debug/`, `ide/src/Debug/`, `stdlib/Path.sl` and the `--debug-format` changes
are written to it already.

### What the debugger still wants from the compiler

`debug/` reads what `-g` emits. One thing it does not emit is measured rather
than guessed; [docs/dwarf.md](docs/dwarf.md) has the numbers.

- **`DW_AT_language` is `DW_LANG_C_plus_plus`.** We are not C++, and a consumer
  that demangles by language does the wrong thing with a `_SL` name.

One more, not in the emitter:

- **`--debug-format dwarf` on Windows does not rebuild the C runtime.** Its
  objects are compiled for the MSVC target and carry CodeView, so a DWARF PE
  describes the Stainless module alone and stepping into `sl_retain` there is
  not a thing that can be switched on.

*Touches:* `src/Stainless.Compiler/Emit/DebugInfo.cs`,
`src/Stainless.Compiler/Driver/Compilation.cs`. Each wants its own commit and a
`debug.txt` case.

### `stainless format`

[docs/style.md](docs/style.md) is the house style and there is nothing that
applies it. The C# half is partly enforced — `.editorconfig` plus
`EnforceCodeStyleInBuild`, so the build warns on a naming violation, though not
on brace placement or spacing — and the Stainless
half is enforced by review, which is the weaker half of a rule that exists
because review kept missing this.

The tree was brought to the standard by a throwaway script that masked strings
and comments, moved braces, and checked that nothing but layout had changed. A
real one belongs in the CLI next to `stainless doc`, reading the same syntax
tree rather than guessing at it with a regular expression. It wants: the brace
and one-statement-body rules (§3.1–3.3), `i++` (§3.4), the whitespace and
column-alignment rules (§3.5), and a `--check` mode a build can run.

**Why it matters**: the two halves of this repository disagreed about brace
style for months, and nothing said so. What a reviewer should be spending
attention on is §1.4 and §2.1 — whether a name promises the right thing, whether
a method should have been a property — and neither of those is mechanical.

### `export "C" __stdcall` in the suite

`samples/com` built with `--target x86` exports `DllGetClassObject` and
`DllCanUnloadNow` as `__stdcall`, the compiler writes the `.def` that names
them undecorated, and a 32-bit C++ host calls both. No case does:
`x86-conventions` calls `__stdcall` functions C defined, and `x86-com` reaches
Stainless-defined `__stdcall` slots through a vtable, by address. The
decorated symbol and the `.def` that undoes it are checked by hand and nothing
else.

*Touches:* `Mangler`, `ModuleDefinition`, `tests/cases/x86-conventions`.

### Cross-compiling to another operating system

`--target x64-linux` on a Windows box does everything the compiler itself
controls: `#if WINDOWS` is off and `UNIX` is on, a project's `linux` overlay is
the one that applies, clang is told the triple, the runtime's objects are named
for the target rather than colliding with the host's, and the whole of a GTK
program compiles. It stops at `stdio.h`, because cross-compiling wants the
target's headers and libraries and this machine has none.

**Three things are still host-based, and they are the ones that name files**:

- `Toolchain.ExecutableExtension` and `SharedLibraryExtension`, which decide
  `.exe` against nothing and `.dll` against `.so`;
- `SharedLibraryFileName`, which decides the `lib` prefix;
- the runtime's own shared-library name, built from both.

They are not wrong today for any build that can complete, because a build that
would expose them cannot get past the sysroot. They are listed because the next
person to hit this will hit them immediately after, and because `ExecutableExtension`
is reached from `ProjectFile.OutputPath()` -- which has no target in scope, and
that is the actual work: threading one there, or moving the decision to where
the target is known.

**What would make any of it testable** is a sysroot: clang's `--sysroot` plus a
Linux `/usr/include` and `/usr/lib` copied onto the Windows box, or the reverse.
`geekom-a7` is the other half of that pair and can already build for Linux
natively, so the question this answers is narrower than it looks -- it is
whether one machine can produce both, not whether both platforms work.

*Touches:* `Toolchain`, `ProjectFile.OutputPath`.

---

### What is next for `forms/`

`forms/` has two backends, Win32 and GTK 3, behind one seam, `IWidgetSet`. A
self-test reads back what it set -- a caption, an index, a count -- and proves
nothing reached the screen; a screenshot is what does, and
[forms/README.md](forms/README.md) has what screenshots found under *What
running it found*.

The full roadmap is in [forms/README.md](forms/README.md). The short version:
**DPI awareness**, because both backends turn points into pixels at a
hard-coded 96; **owner drawing**, which list, combo and button want and only
menus and toolbars have; and `grids.pas`, which is 14,000 lines that neither
platform has a widget for.

*Touches:* `forms/src`.

---

## Interop, in the order writing the Win32 bindings wanted them

### An enum that crosses `extern "C"`

A `[Flags] enum : uint` will not pass to a `uint` parameter without a cast,
which is why [bindings/win32](bindings/win32) spells 964 constants as bare
`const uint` rather than as the typed sets they are. Letting an enum widen to
its underlying type in interop position would let a binding be typed without a
cast on every line.

### Portable COM activation

The server half is done. `[Guid]` on a `com class` is a CLSID, the compiler
collects every class carrying one into a factory table, and
`Com.GetClassObject` answers it with an `IClassFactory` — so a `--shared` build
exporting `DllGetClassObject` is a real in-process COM server, which
[samples/com](samples/com) is, called from C++ and checked by
[tests/cases/com-activation](tests/cases/com-activation).

What is still missing is the **client** half away from Windows: `Com.Create`,
taking a CLSID and reaching an object without the caller knowing where it came
from. That wants `dlopen`/`LoadLibrary` of a module exporting
`DllGetClassObject`, the in-process table first, and a fall-through to the real
`CoCreateInstance` on Windows so one source reaches the actual shell.

In-process and free-threaded only, stated as a limit rather than discovered as
one — no apartments, no marshalling, no proxies, no `IDispatch`. The value is
in the interface discipline, and XPCOM is what pretending otherwise looks
like.

*Touches:* `runtime/com.c`, `bindings/win32/Com.sl`.

### Direct3D 12

`Win32.Dxgi`, `Win32.D3D11` and `Win32.D3DCompiler` are bound, and
`Windows.DirectX11` is the layer over them: a device and a swap chain on an
`HWND`, a depth buffer, meshes, materials, constant buffers, alpha blending,
and `SaveFrame` to read the back buffer out as a picture.
[samples/directx](samples/directx) renders a triangle and a lit, rotating,
shadow-casting cube with it.

**Direct3D 12 is not bound.** It is not more of the same: the device makes
nothing that draws, a command list is recorded and submitted to a queue, memory
is the program's to place and to keep alive across frames, and a fence is how
it knows when the GPU is finished. The binding is mechanical -- the generator
that read `ID3D11DeviceContext`'s hundred and eight slots out of the header's
own `Vtbl` structs reads `ID3D12GraphicsCommandList` just as well -- and the
*layer* is not, because a `Windows.DirectX12` that hid the queue and the fence
would be hiding the only two things D3D12 exists to expose.

**Why it matters**: nothing today needs it. D3D11 draws, and the machines that
require D3D12 are the ones a renderer would be written for rather than a
binding. What it would buy is the honest test of whether the COM story here
scales to an API whose resource lifetimes are not reference counts.

*Touches:* `bindings/win32/api`, a new `Windows.DirectX12`.

### What DirectX 11 does not cover yet

The layer is the six objects every program makes, and three things a second
program would want are missing:

- **Textures.** `CreateShaderResourceView` and `CreateSamplerState` are bound
  and nothing wraps them, so a mesh can have colours and not a picture. It is
  the smallest of the three and the most often wanted.
- **A shadow map.** [samples/directx/cube.sl](samples/directx/cube.sl)
  projects the cube onto the floor with a matrix, which is exact for a flat
  floor and wrong for anything else. A real one renders depth from the light
  into a texture and samples it, which needs render-to-texture -- and therefore
  the textures above.
- **Multisampling.** The swap chain is flip-discard, which takes none, so
  anti-aliasing means rendering to a multisampled target and resolving.
  `ResolveSubresource` is bound.

*Touches:* `bindings/win32/DirectX11.sl`.

### More Windows COM interfaces

A binding rather than a project, now that the language part is done and the
shell's half is written. In rough order of what a program actually wants:

- **WIC** -- `IWICImagingFactory` and four interfaces under it.
  `Standard.Drawing` reads PNG and JPEG through GDI+ on Windows and libgd
  elsewhere, so what WIC adds is what GDI+ is worse at -- a decoder for a format
  GDI+ has none for, and frame-by-frame access to an animated one.
- **The Property System** -- `IShellItem2`'s slots are declared, with a
  `PROPERTYKEY` passed as a `byte*`; `IPropertyStore`, `PROPERTYKEY` and
  `PROPVARIANT` are not.
- **`ITaskbarList3`** — progress in the taskbar button, which is thirty lines
  and very visible.
- **Direct2D and DirectWrite**, which are large and want a render loop, and are
  the real test of whether this scales.

*Touches:* `bindings/win32/api`, `bindings/win32`.

### What resources left open

A `.rc` compiles into the binary on every target, `Standard.Resources`
reads one anywhere, and `Bitmap.FromResource` works on both widget backends. Two
things around it are still open:

**A dialog built from its template.** `CreateDialogParamW`, `DialogBoxParamW`
and `EndDialog` are bound and an `RT_DIALOG` in a script works today through the
raw layer; what is missing is a `forms/` control that wraps one. It matters
because a dialog template is how every Windows program has laid out a dialog for
thirty years -- the layout is data, so it can be edited by a resource editor and
translated without recompiling, neither of which is true of the `SetBounds`
calls `forms/` uses now. Windows-only by nature: the template is a format the OS
itself interprets.

**Mach-O has no answer yet.** The blob goes in a section named `.rsrc`, which is
ELF's spelling. Mach-O wants `__SEGMENT,__section` and is not a target, so
nothing is wrong today -- but the `section` attribute in `ResourceBlob` is the
line that would have to learn about it.

*Touches:* `src/Stainless.Compiler/Emit`, `forms/src`.

---

## Language

### Narrowing a field

`if (x != null)` narrows a local or a parameter and not `node.Next`, because a
field or a call result may be a different value by the time it is read — the
rule variants follow, stated once for both (SL0248, SL0285). A local is the
fix and usually what the code meant.

What would make it sound for a field is knowing that nothing between the check
and the use could have written it, which is a real analysis rather than a
lookup: any call, any `ref`, any store through a pointer takes the proof away.
Worth doing only if the local turns out to be a genuine irritation in practice.

There is a way to say it where the type can be named: `if (node.Payload is
Circle c)` for a variant's case, and `if (node.Next is Node n)` for a `C?`,
which asks about the null and the class at once. Both take the value once and
name what the test found, so the field is read exactly where it was checked.
What is still missing is the plain `if (node.Next != null)` reading as a
narrowing -- and that is the analysis above, not a shape.

*Touches:* `Binder.NarrowableSubject`, `Binder.InvalidateVariantFact`.

### `Deserialize<T>`

Fields and properties can be read and written through reflection, which is
what `Standard.Json` and `Standard.Xml` are built on, and
`Reflection.CreateInstance` makes an object as `new T()` would. A nested
object is made that way, through `CreateInstanceInto`; the top-level one is
not, so `PopulateObject<T>(T
value, String text)` is the shape and there is no `Deserialize<T>(String)`
answering a fresh `T`.

### Definition-site constraint checking

A `where` clause is checked where it is written, and a template's body where
the generic is *used*: an uninstantiated template is never checked, and a
mistake inside one is reported against its use. Checking the body once needs
constraints on operators too.

### A borrowed slice

`Span<T>` retains the array it came from, which is what makes it impossible to
dangle and also what makes it cost a reference count per copy and keep a large
array alive for a small view. A raw `(pointer, length)` view would do neither
and needs a lifetime story the language does not have.

---

## Runtime and libraries

### A reachability pass from `Main`

Only the standard-library modules a program reaches are compiled, but within
one every non-generic function is bound, lowered and emitted, and the three
always reached — `Standard`, `Standard.Text` and `Standard.Collections` — are
most of the library a hello-world pays for. LLVM deletes what nothing
references in an optimised build, because it is internal; a debug build hands
all of it to the linker.

It is also the honest explanation for a number that gets quoted about ARC:
counting `sl_retain`/`sl_release` in a module counts mostly calls in functions
nothing invokes. Fixing this shrinks that count without touching a single
instruction the program executes.

The walk is from `Main`, plus every `export "C"`, every static initializer, and
everything a dispatch table names — a virtual table, an interface table, a COM
vtable and the reflection metadata are all roots, and a pass that forgot one
would delete a method that is only ever called through a pointer. That last
part is the whole difficulty; the walk itself is a worklist.

*Touches:* a new pass between binding and emission, and `LlvmEmitter`'s
decision about what to write.

### Public-key cryptography

`Standard.Security.Cryptography`'s symmetric half is complete: MD5,
SHA-1, SHA-256, SHA-384, SHA-512, BLAKE2b, HMAC over any of them, PBKDF2, HKDF,
scrypt, Argon2id, AES in ECB, CBC, CFB and CTR, AES-GCM, ChaCha20-Poly1305, the
platform's entropy, and a constant-time comparison. Every answer is pinned
against a published vector by `tests/cases/cryptography`, `crypto-aes`,
`crypto-chacha` and `crypto-kdf`.

**Curve25519 is there**: `X25519` for key agreement and `Ed25519` for
signatures, constant time on secrets, pinned against RFC 7748 and RFC 8032 by
`tests/cases/crypto-25519` on x64 and x86. Its field is five 51-bit limbs over
`Bits.MultiplyHigh`.

**`ECDsa` and `ECDiffieHellman` are done, for P-256 and P-384.** They needed
no bignum: a curve's numbers are a fixed width, so the arithmetic is four or six
64-bit limbs held inline, constant time wherever a secret is involved, and
pinned by `tests/cases/crypto-ecc` against RFC 6979, NIST's CDH vectors,
Wycheproof and OpenSSL. What is left on that side:

- **P-521.** Nine limbs and a field whose prime is a Mersenne number, so it
  wants a reduction of its own rather than the Montgomery one.
- **A precomputed table for the generator.** Signing and key generation
  multiply the base point, which never changes, and a fixed table of its
  multiples would make them roughly four times faster.

**RSA is done**: `Rsa` generates keys, signs and verifies with PKCS #1 v1.5
and PSS, encrypts with OAEP and PKCS #1 v1.5 (decrypting the latter with
implicit rejection), and reads and writes PKCS #1, PKCS #8, X.509 and PEM. It
stands on `Limbs` and `MontgomeryModulus`, a constant-time bignum of 64-bit
limbs, and `tests/cases/crypto-rsa` pins it against Wycheproof and OpenSSL.

What is left on the RSA side:

- **Encrypted PKCS #8** (PBES2 over PBKDF2 or scrypt, with AES-CBC), which
  `ImportFromPem` refuses as `Unsupported`; and multi-prime keys, which are
  refused the same way.
- **Speed.** Half of a private operation is inverting the blinding factor by
  Fermat modulo each prime; a pair kept and squared between uses, as OpenSSL
  does, would take that away at the cost of a lock. A dedicated squaring saves
  about a quarter of each exponentiation, and 32-bit limbs on a 32-bit target
  would spare x86, at twice x64's time, its emulated 64-bit products.

**X.509 is done**: `Standard.Security.Cryptography.X509Certificates` reads
certificates strictly, matches host names by RFC 6125, builds and validates
chains through cross-signed and alternative issuers, reads the platform's
roots, and makes certificates signed by any of the three key types, pinned by
`tests/cases/x509` against OpenSSL's reading of the same files. What is left:

- **Revocation.** No CRL is fetched or read and no OCSP responder is asked,
  and neither is OCSP stapling looked at; a chain asked for revocation says it
  could not check. CRLite-style pushed revocation would suit a library with
  no network cache better than either.
- **Policies.** Certificate policies are read past and never required, so
  `policyConstraints`, `policyMappings` and `inhibitAnyPolicy` are unsupported
  when critical, as RFC 5280 then requires.
- **Name constraints beyond DNS and IP.** Directory-name, e-mail and URI
  subtrees are read and not enforced, and only the leaf's alternative names
  are checked against them.
- **PKCS #10 and PKCS #12.** `CertificateRequest` makes certificates and not
  signing requests, and there is no reading of a `.pfx`.

### Case mapping beyond ASCII

`ToUpperAscii` and `ToLowerAscii` say what they do. The real thing is a table
of several thousand entries with locale exceptions -- Turkish dotless i, German
sharp s uppercasing to two characters, Greek final sigma -- and none of it fits
in a runtime that is about 8,000 lines of C. There is also no collation:
`CompareTo` orders by bytes, which orders by code point and resembles no
language's idea of alphabetical.

The honest options are to link ICU, to generate the tables from
UnicodeData.txt, or to keep saying `Ascii` in the name. The third is what is
happening.

### Audio that is not PCM

`Standard.Media.Audio` plays and records interleaved PCM through WASAPI on
Windows and ALSA elsewhere, and reads and writes WAV. Three things around it
are open:

- **A decoder.** WAV is the only container, so a program with an MP3, an Ogg or
  a FLAC has nothing. Each is a real piece of work and a separate module;
  saying so is better than a half-written one.
- **Mixing.** One device, one stream: a second sound needs a second device,
  which the platform may refuse. `Win32.Sound` is the mixer on Windows, over
  XAudio2, and Linux has no equivalent here.
- **ALSA has been compiled and not run.** The Windows half has played and
  recorded on this machine; the ALSA half is written against the same seam and
  has never opened a device. `geekom-a7` is where that gets answered, and until
  it is, half of this module is a claim rather than a fact.

### Cancellation that skips queued work

A cancelled `TaskScope` could drop the tasks it has not started. When a search
answers from the first chunk while ninety more sit in the queue, that is most of
the work saved — a flag on `SlScope` and one check in the worker loop. Reaching
it from inside a job is the harder half; see
[concurrency.md §9.3](docs/concurrency.md).

---

## Smaller items

### Method metadata, and invoke-by-name

Reflection describes types, fields, properties and public events, and stops
there. A form file does not need this: it wires handlers in generated code
rather than by name at run time
([docs/slfm.md](docs/slfm.md#5-what-was-rejected)). What still wants it is a
deserializer filling a `List<T>`, which is the one shape `Standard.Json` cannot
represent.

### A registry, or a decision not to have one

Package resolution unifies sources rather than searching versions, because a
path and a git tag each pin exactly one version and nothing can offer an
alternative. That is honest, and it is also why two packages needing
incompatible versions of a third is a hard error with no way out. The search
belongs in `PackageResolver.Visit` when there is something to search. Deciding
there will never be a registry is an equally good outcome; what is not good is
leaving the question open in a comment.

### Pin the test count against the suite

`README.md` states how many end-to-end cases there are, and it drifts on every
commit that adds one. A unit test asserting the number against `tests/cases`
is an hour and ends it.

### The +0/+1 dataflow pass

Within a statement the emitter moves what it owns rather than counting it. A
borrowed value kept in a local is still retained and, at the end of its scope,
released, around a reference the caller holds throughout; removing that pair
is a pass across statements. Nothing is wrong, and everything pays for it.

### `List<T>` has no `Remove(T)`

`IndexOf` and `RemoveFirst` want `IEquatable<T>`, which a closure is not.
`RemoveWhere` takes a predicate for exactly this reason, and a list of
callbacks is usually an `event`, but `Remove(T)` is still the obvious method
that is not there.

### `samples/shop` does not use the operators it could

`Money` in `samples/shop` is added with `AddMoney`. `Standard.Time` has had this
pass and reads better for it.

## Deliberately not doing

Kept here so the reasoning does not have to be rediscovered.

- **Multiple inheritance.** Single inheritance is implemented and rests on the
  base subobject starting at the derived object's own address. With two bases a
  `Derived*` and a `Base2*` are different addresses, so an upcast becomes
  pointer arithmetic and reference identity stops being pointer identity.
  `sl_retain` takes the object pointer and interface references *are* object
  pointers; both assumptions would go.
  Virtual inheritance is worse again — base offsets resolved at run time, a
  hidden constructor parameter, and two ABIs that disagree completely about how.
  Interfaces already give multiple types without multiple state.
- **Exceptions.** Unwinding needs metadata on every frame and a personality
  routine, and a failure that travels invisibly through code that did not
  mention it is the thing `Result<T, TError>` exists to refuse.
- **A C-style preprocessor.** `#if` and its relatives exist because choosing
  between two platforms is a real question. Macros and `#include` are not: a
  name always means itself.
