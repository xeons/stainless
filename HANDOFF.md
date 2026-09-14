# Handoff

What the last runs built, what was learned that is not obvious from the code,
and what is worth doing next. Written to be read cold.

## State

```
dotnet build Stainless.slnx                     0 warnings
dotnet test tests/Stainless.UnitTests           835 pass, Windows and Linux
dotnet run --project tests/Stainless.Tests      284 pass, 2 skipped on Windows
                                                273 pass, 13 skipped on Linux
stainless doc --stdlib                          22 pages into docs/stdlib
samples/forms/build.ps1 -Test                   demo 21/21, common 43/43
forms on GTK 3, under broadwayd                 demo 21/21, common 43/43
```

**32-bit x86 now runs on both systems.** Four cases build as real 32-bit
binaries and are executed: `x86-abi`, `x86-conventions`, `x86-runtime` and
`x86-com`. The Linux half had been written off clang and never run, and running
it found two things -- see "What running Linux x86 found" below.

**ARM64 is classified and has never run**, which is a deliberate weaker claim:
`tests/cases/arm64-abi` and `arm64-abi-windows` stop at an object file, because
there is no ARM64 machine here and no ARM64 C library to link against. LLVM
verifies the module and lowers every instruction in it, and `ir.txt` pins each
signature against what clang writes for the same C. The suite calls such a case
"assembled for <triple>" rather than passing a program.

**`forms/` has a second backend.** GTK 3, beside Win32, and both samples pass
their whole self-test on both: `demo`'s 21 checks and `common`'s 43. The seam
was the point -- thirty interfaces written against Win32 and nothing in one of
them had to change -- and what it cost is written up in `forms/README.md` under
"The GTK backend, and what it found".

**The forms suite's one failure is fixed**, and the second backend is what
found it. "A tree node reads back its text" failed on Windows and *passed on
GTK*, which narrowed it from "the tree control is broken" to "something on the
Windows side is". It was one truncated literal -- `TVI_ROOT` is a negative
number and was written as a 32-bit one, so the Win32 tree had never actually
held an item. See "The tree view had never held an item" below. Both samples
now pass every check on both backends.

That Linux box (`ssh brandon@geekom-a7`) has GTK 3, the development packages,
Xvfb and `broadwayd`, so a GUI can be built *and run* there headlessly — see
`bindings/gtk/README.md`. The full suite and both forms samples have now been
run there and pass.

**GTK 2 was dropped**, bindings and all. It was behind `-D GTK2` and it went
the day this binding stopped being something a program merely calls and became
the thing `forms/` is built on: two toolkits behind one seam is two backends to
keep honest, and no current distribution ships the second.

`master` and `origin/master` are level.

## What was built, in order

| | |
|---|---|
| `58b5a9e` | an audit of the spec and README against the compiler |
| `d738588` | reflection writing; `Standard.Json` and `Standard.Xml` |
| `fe46084` | array element metadata, `OrderedDictionary`, `Option<T>` |
| `ae43b16` | the docs and this file brought back in line |
| `6c71390` | `is` with a binding; `Option` becomes `Optional` |
| `a0677cc` | GTK 2 and GTK 3 bindings, and a widget layer |
| `3ad68ec` | reflection sees properties, not just their storage |
| `98db181` | find a reflected type by name |
| `4fc1dde` | `closure`: a method and the object it belongs to |
| `b83260a` | the GTK layer moved onto closures; a user-control sample |
| `972c305` | generic types get their operators, statics and setup blocks |
| `f836364` | `++` `--`, `do..while`, `goto`, `nameof`, `checked` |
| `637b155` | `out` parameters and named arguments |
| `1a334c6` | closures become generic, and the library moves onto them |
| `22c863c` | `default(T)`, `String.Empty`, and `x.F(y)` meaning `F(x, y)` |
| `d438ec6` | `Standard.Process` |
| `93ca9f0` | `?.`, `??`, `??=` |
| `4902a3f` | types declared inside other types |
| `c6f92b8` | tuples |
| `b88a10a` | Linux terminal and event-loop bindings |
| `cc4152b` | projects, versioned packages, and the ABI digest |
| `9050177` | build stamps, and platform library names |
| `fcf8972` | deriving across a library boundary: SL0513 is lifted |
| `626e5d2` | `event`: several subscribers behind one name |
| `caaf3e5` | events, closures and delegates cross a library boundary |
| `25d7c7d` | an array's type info is named after its element's module |
| `971fed8` | `forms/`: the LCL's architecture under C#'s names |
| `fe6a18e` | menus and the common controls; interface-to-class narrowing |
| `dc8d36c` | the windowless controls; a generic no longer shrinks a struct |
| `755d002` | the composites, and `base` on a property stops dispatching |
| `908fb3a` | a hardening pass: nine bugs, found by probing rather than reading |
| `ce32e32` | indexers on the containers, and one less cascading diagnostic |
| `68a7403` | doubles that survive being written and read back |
| `24538c6` | the two allocations that could still wrap |
| `7708bce` | an abort keeps the output that explains it |
| `bbc04ba` | a missing key is an outcome rather than a crash |
| `cf82305` | `map[key]` answers an optional, as Swift's does |
| `6adca35` | the documentation caught up, and three entries for what it still lacks |
| `c0d9090` | a block on everything public in the standard library |
| `0fef32e` | `stainless doc`: the blocks read, and a reference written from them |
| `1563cbb` | the comments left describing the code, and the arguments moved out |
| `39f0448` | a pointer stops being eight bytes: `--target x86` |
| `034b2ae` | the x86 classifier, and the calling conventions a declaration names |
| `31d13fe` | the 32-bit build is run rather than claimed |
| `fb5ba19` | the documentation says x86 is a target |
| `8aa7853` | Linux x86 runs, COM reaches x86, and ARM64 is classified |
| `2c0e8b8` | GTK 2 goes, and `forms/` gets its second backend |
| `cc4a910` | a lambda capturing a member something else writes warns |
| `ad37dd4` | Windows resources, and the tree view that had never held an item |
| `e3d82f9` | a variable may cross `extern "C"`, not only a function |
| *this one* | resources stop being a Windows idea |

## Findings worth keeping

### Resources on a system that has no resource section

A `.rc` now works on every target. On Windows the linker fills the PE's resource
directory as before; everywhere else the compiler emits the compiled `.res` as a
constant in a section called `.rsrc`, and `Standard.Resources` walks it. The two
were checked against each other on the same script -- `tests/cases/
resources-portable` has one `expected.txt`, no `#if`, and passes on both.

**The experiment's two hacks both died on contact with integration.**
`llvm-objcopy -I binary` names its symbols after the input *file*
(`app.res` -> `_binary_app_res_start`), which is no basis for a stdlib module,
and it only emits ELF -- there is no `coff-x86-64` or `pei-x86-64`. Both went
away by emitting the bytes straight into the IR instead: the emitter already had
`RawBytes` for GUIDs, "sixteen bytes and not text", and a resource blob is the
second caller that is not text. Using `EscapeBytes` instead appends a NUL, which
made the extracted blob one byte longer than what `llvm-rc` wrote.

**A section costs one attribute and buys the tooling.** `section ".rsrc"` on the
global is the whole change. The *program* still finds its resources by symbol --
a section has no address a program can ask for without reading its own ELF
headers -- but everything outside the program can now work:
`llvm-objcopy --dump-section .rsrc=out.res` on a Linux binary gives back a file
byte-identical to what `llvm-rc` produced, which `llvm-readobj` then reads as a
resource script.

**The compiler defines what the stdlib declares.** `Standard.Resources` declares
`sl_resource_blob` with `extern "C"`, and "elsewhere" turns out to be the same
emitter -- so both wrote `@sl_resource_blob` and LLVM called it a redefinition.
`_definedGlobals` is the fix: the emitter records what it defines and
`StaticStorage` skips declaring those.

**SL0700 changed meaning and got better.** It used to say a script "was left out
of this build", which is no longer true. It now walks the compiled `.res` and
names only the types that need an OS to act on them -- `RT_MANIFEST`,
`RT_GROUP_ICON`, `RT_DIALOG` and the rest -- so a script of string tables and
RCDATA draws no warning at all, because nothing about it is lost.

**Two pre-existing bugs surfaced, neither caused by this work.**

*Integer-to-pointer casts were impossible on x86.* `Binder.Conversions` asked for
`Size: 8` rather than the target's pointer width, so `(char16*)(nuint)id` -- the
idiom `bindings/win32` is written in throughout, `CursorArrow`, `InvalidHandle`,
`TreeRoot` -- was a compile error for a 32-bit target, while `ulong`, which is
wider than the pointer it would be truncated into, was allowed. Confirmed on a
clean tree with none of this work present. The rule is `Size >=
PointerWidth` now, and `bindings/win32` compiles for x86 for the first time.

*`--shared` refused every static, including ones with nothing to initialize.*
SL0380 exists because a library has no entry point to run initializers from. An
imported `extern "C"` variable has no initializer at all, so the rule never
applied to it -- but the check counted it, and twelve library and interop cases
failed on Linux the moment `Standard.Resources` declared two.

**Win32 APIs in the stdlib need `__stdcall`.** kernel32 is reached for the
resource directory, and on x86 the import library exports `_GetModuleHandleW@4`
while a cdecl declaration looks for `_GetModuleHandleW`. `bindings/win32` has
this wrong throughout and has never been linked for x86 -- worth knowing before
anyone tries.

**`user32` is deliberately not used.** `LoadStringW` would be the obvious way to
read a string table, and it would make every program that touches a resource
link a library it may want nothing else from. The block arithmetic it performs
is thirty lines, so it is written out and both platforms share it: strings are
filed sixteen to a block, so id 201 is the tenth entry of block 13.

**`rc` strips the `BITMAPFILEHEADER`.** Windows never wants it -- `LoadImageW`
takes the DIB header onwards -- and every other decoder does.
`Resources.BitmapFile` puts it back, verified byte-for-byte against the original
`.bmp`, which is what lets GTK decode a resource bitmap through a
`GdkPixbufLoader`. That closed the one asymmetry in the widget seam:
`Bitmap.FromResource` and `ImageList.AddResource` now work on both backends.


### What extern variables cost, which was less than expected

`extern "C" int errno;` is the data half of what `extern "C"` already did for
functions, and most of it was already built. **The syntax already parsed** --
the parser routes an extern declaration through `ParseFunctionOrField` and
`WithConvention` even has an error for "this declares a value", so a field came
out the other side with its linkage dropped on the floor. **The storage already
existed** too: a module-level `static` emits an LLVM global and
`EmitStaticAccess` already loads through `@name`. What was missing was the
wiring -- carry `Linkage` onto `FieldDeclSyntax`, give `StaticSymbol` a
`LinkName` and `IsImported`, declare rather than refuse, and emit `external
global` under the C name. About 210 lines including the documentation.

**One trap that is the compiler's fault and one that is not.**

`SortStatics` walks `_staticSyntax`, which is keyed by *initializer*. An
imported variable has none by definition, so the symbol bound, the load emitted,
and the global was never declared -- IR that names `@errno` and does not define
it. `_foreignVariables` is a second list for exactly that reason, and the
comment on it says so.

`errno` itself does not work and should not. Every C library defines it as a
macro over a function so each thread gets its own -- `_errno()` in the UCRT,
`__errno_location()` in glibc -- and there is no preprocessor here to see
through a macro. It fails as a link error naming the symbol, which is the good
kind; the alternative would have been a plausible wrong number.

**The width trap caught this session's own test.** `long probe_wide = -1;` in
the C half read back as `2093069526210969599`, because C's `long` is 32 bits on
Windows and a Stainless `long` is a fixed 64. On a function that is an argument
arriving wrong; on a variable it is a silent 8-byte load from a 4-byte global.
The compiler cannot check it -- it never sees the C declaration -- so it is
documented in §8 and the case's C file says why it uses `long long`.

**It removes a C shim from the resources-on-Linux work.** `llvm-objcopy -I
binary` leaves `_binary_<name>_start`/`_end`, whose *addresses* are the data;
reaching them needed a C file whose whole content was two getters, and now does
not. Verified on Linux: a Stainless program read an embedded 272-byte `.res`
with no C in the build at all.


### What implementing resources found

**clang links a `.res` directly, so there is no cvtres step.** This was the
whole question the feature turned on, and it was settled by trying it rather
than by reading: `clang main.c app.res -o app.exe` works, the driver passes the
`.res` through, and every linker that can produce a PE folds it in. The LLVM
install here has no `llvm-cvtres.exe` at all, so a design that needed one would
have been stuck. `llvm-rc` *is* there, beside the clang the build already
found — which is why `ResourceCompilerPath` looks next to `ClangPath` before it
looks at `PATH`. The copy beside the driver is the copy that matches.

**`llvm-rc` resolves relative paths against the script's directory, not the
working directory.** This is a deliberate difference from Microsoft's `rc.exe`
and it is the better rule — it is what lets a project keep `app.rc` beside its
bitmaps and still be built from anywhere. Worth knowing because it is the one
place a `.rc` that works here will behave differently under MSVC's toolchain.

**The warning had to move before the `EmitIrOnly` return.** SL0700 is reported
right after the target is known rather than beside the link, because
`assemble.txt` cases set `EmitIrOnly` and return long before any linker is
reached — so a warning raised at link time could not be pinned by a case at
all. It is also simply more correct: it is a fact about the target, not about
linking. `tests/cases/resources-no-section` is the case, and it only passes
because of that move.

**Three names collided on the way in.** `module` is a keyword, so
`FindResourceW(HMODULE module, ...)` does not parse — the file's own convention
is `HMODULE library`. `GetDlgItem` was already declared in `User32.sl` under
windows, so the dialog block re-declared it (SL0211). And the Win32 widget set's
`LoadBitmapResource` override initially called a free function of the same
name, which is infinite recursion; the existing `LoadBitmap`/`LoadBitmapFile`
split is the pattern, and the free function is now `LoadResourceBitmap`.

**The `.exe.manifest` side-car is gone.** `samples/forms/build.ps1` used to
write one beside every sample because there was no way to ask the linker for
anything but a library, which `forms/README.md` listed as a known limit. It is
now `samples/forms/forms.rc` with `1 24 "forms.manifest"`, verified with
`llvm-readobj --coff-resources`, and the README paragraph has been rewritten
rather than left standing.

**Incremental builds were already right, by accident of an earlier decision.**
A changed `.rc` rebuilds the package with nothing added, because
`Digest.OfDirectory` hashes *every* file under a package that is not in
`obj`/`bin`/`build`/`.git` rather than only the `.sl` ones. So the `.h` a
script includes and the `.bmp` it names are covered too. The "every input, or
rebuild" rule in `BuildStamp` paid for itself here.

**Two scripts with the same file name overwrote each other.** The first version
named the output after the script's stem alone, so `a/app.rc` and `b/app.rc`
both produced `obj/app.res` -- the second overwriting the first, the same path
added to the link line twice, and one script's resources silently absent from
the binary. A name already taken now gets eight hex digits of the full path's
digest appended, only on the collision, so the ordinary `obj/` still holds a
readable `app.res`. Verified by building both and reading a string out of each.

### The tree view had never held an item

`common`'s "a tree node reads back its text" had been failing at `42/43` on
Windows since before this work -- confirmed by stashing every change and
re-running -- and it turned out to be one wrong literal.

**`TVI_ROOT` is a negative number.** `commctrl.h` spells it
`((HTREEITEM)(ULONG_PTR)-0x10000)`, so on a 64-bit machine the sign extends
through the whole pointer: `0xFFFFFFFFFFFF0000`. `Win32.ComCtl32` had it as
`(nuint)0xFFFF0000u`, which zero-extends to `0x00000000FFFF0000` -- a different
value, naming no node and not the root. `TVM_INSERTITEMW` rejected every insert
under it and answered zero, and nothing checked the answer.

So the Win32 tree view had **never held a single item**. The other tree checks
passed because `TreeView` keeps a mirror list of its nodes in Stainless and
those assertions were reading the mirror, not the control. Only the one check
that asked the *control* for text ever noticed.

Finding it took ruling out everything else first: the struct offsets, the
message numbers, the mask bits and `sizeof` were all verified byte-for-byte
against a C program doing the same thing. The decisive step was dumping the 72
bytes of `TVINSERTSTRUCTW` from both and diffing them -- the first eight bytes
differed and nothing else did. Worth remembering as the technique, because
every individual constant read as correct.

**The same construction appears in `Win32.AdvApi32`**, where `HKEY_CLASSES_ROOT`
and its neighbours are `(LONG)0x80000000` sign-extended. Those were truncated
too and were spelled at full width while here -- but note that they were *not*
broken: `RegOpenKeyExW` opens the same key given either bit pattern, which was
measured with a C program rather than assumed. The registry tests were passing
honestly. They now match the header because a binding should be the value C
passes, not merely one the API tolerates.

Both samples now pass every check on Win32: `demo` 21/21, `common` 43/43.

### What running Linux x86 found

Both were failures at compile or link time rather than wrong answers, which is
the good kind, and neither was in the classifier the entry was about. `X86Abi`'s
i386 System V rule was right as written.

**The runtime's lock storage was counted in pointers.** `SlMutex` and
`SlCondition` are opaque storage sized for the largest platform primitive, and
they were `void *opaque[5]` and `[6]` -- forty and forty-eight bytes on a
64-bit machine, which is what glibc's `pthread_mutex_t` and `pthread_cond_t`
need. On i386 those are 24 and 48 and a pointer is four, so the storage came
out at twenty and twenty-four and `thread.c`'s own `_Static_assert` refused to
compile it. A pthread primitive is not a row of pointers and does not shrink
with one; they are counted in `long long` now.

**Decoration was being applied to ELF.** `Mangler` decorated `__stdcall` on
every x86 target, and the `@N` suffix is Microsoft's and reaches no further
than PE. clang gives an i386 ELF `__stdcall` the convention -- the callee still
removes the arguments -- and the plain name, which is what gcc has always done.
So `x86-conventions` asked the linker for `_add_stdcall@8` and there was no
such symbol. The rule is now the object format's rather than the
architecture's, and the same correction applies to `__vectorcall` on x86-64,
which was being decorated on Linux too.

**`geekom-a7` builds 32-bit binaries natively now, and the note that used to be
here had the reason wrong.** The claim was that the box lacked `gcc-multilib`
and `libc6-dev-i386`. It did not: both were installed, i386 was an enabled
foreign architecture, and `/usr/lib32` had `Scrt1.o` and `crti.o`. The 32-bit
cases failed anyway, with

```
/usr/include/stdint.h:26:10: fatal error: 'bits/libc-header-start.h' file not found
```

because what was missing was the **headers**, not the libraries.
`libc6-dev-i386` ships `/usr/lib32` plus a couple of `-32.h` stubs and leaves
the real headers shared, so `bits/libc-header-start.h` existed only under
`/usr/include/x86_64-linux-gnu/`. clang targeting `i386-linux-gnu` looks in
`/usr/include/i386-linux-gnu/`, which nothing had created.

The package that creates it is **`libc6-dev:i386`** -- the i386-architecture
build, and *not* the similarly named `libc6-dev-i386` that was already there.
That naming is the whole trap. It is installed now, and the four 32-bit cases
pass on the box directly:

```
dotnet run --project tests/Stainless.Tests -- x86
all 4 tests passed
```

**So the container is no longer needed for anything.**
[tests/linux-x86.Dockerfile](tests/linux-x86.Dockerfile) is kept because a
machine without those packages still wants it, but the whole Linux suite now
runs on the box itself -- 270 pass, 13 skipped, in 136s against the container's
249s.

**And the box is reachable without a password.** `ssh brandon@geekom-a7` works
with key auth and `BatchMode=yes`, so syncing and running the suite there needs
no interaction at all. An earlier note here said otherwise, and believing it
cost two runs.

### What ARM64 needed that the other three did not

**The registers can cover more of a value than exists.** A twelve-byte struct
travels in two eight-byte registers, so the load is sixteen bytes wide. Every
other classifier here sizes its pieces to what the value actually occupies, and
the emitter reads and writes them at the object's own address -- which on
AAPCS64 would read four bytes that are not part of it, and, worse, write four
that belong to whatever comes next. `ArgInfo.PaddedSize` says how far, and the
emitter makes the copy clang makes.

**`byval` is not a spelling of "indirect".** LLVM lowers `byval` to the value on
the *outgoing stack* on every target. That is what System V AMD64 wants; Win64
gets away with it; AAPCS64 wants a pointer in a general register, which is a
different place read by a different instruction. Nothing diagnoses the
difference -- the IR verifies, the program links, and the callee reads a
register the caller never wrote. It was caught by reading the asm for a
three-line `.ll` rather than by a test, because no test here can run one.

**Windows and Linux agree about ARM64, and it is worth knowing why the tables
looked different at first.** Compiling the same C for both triples gave
different answers for `struct { long a, b; }` -- until the obvious: `long` is
four bytes on Windows and eight on Linux, so the two files did not describe the
same struct. Stainless has no type whose width depends on the system, so one
classifier serves both, and `arm64-abi-windows` exists to keep that testable.

### What writing the second backend found

**A bare member read inside a lambda is captured by value.** It is the
documented rule (spec §2.15) and it is a trap the GTK backend fell into eight
times over: the guard that stops a program-driven change being reported back as
the user's was written `if (settingValue)` inside a handler, which tests what
the flag said when the handler was connected. False, for ever.

Written that way it compiles, it runs, and it guards nothing. A program that
ticked a checked menu item from its own click handler recursed until the stack
ran out, and the backtrace was thirty frames of GObject with nothing in it to
suggest a capture rule.

**The fix is to name the receiver**: `this.busy` captures `this` -- an object
reference, by the same by-value rule -- and reads the field through it. A
method that reads the field does the same thing. Only the bare name copies.

**The compiler warns about it now** (SL0610), and the warning is the reason
this entry is short: it fires on a captured member that something else
assigns, it points at the read, and it names `this.x` as the fix.
`tests/cases/warn-captured-member` is the case, and reinstating the bare read
in `Menus.sl` makes the compiler name the exact line that cost the stack.

**The spec was wrong about `this.Factor`** and now is not: it said a member
read through `this` copied like a bare one, and it does not -- `this` is
captured and the field is read through it. That is worth knowing, because it is
the difference between the rule having an escape hatch and not.

**A signal's arity has to match the connector's, and nothing checks.**
`Gtk.Events` connects handlers taking a sender, one pointer and user data.
`switch-page` carries a page *and* a page number; `row-activated` a path *and*
a column. Connect either through it and the user data arrives in a register the
handler is not reading, so the boxed closure is read out of a `guint`. Segfault
at the first tab added.

**`gtk_window_resize` is a request and `MoveWindow` is an instruction.** The
configure events already in flight describe the size *before* the request, so a
form that resized twice in quick succession laid itself out for the first. The
window peer drops echoes until one matches what was asked for, bounded at four
so that a window manager refusing a size cannot silence the window.

**Report the new size after writing it down, not before.** `OnPlatformResized`
lays the form out again and the layout asks the peer for `ClientBounds` --
which reads the field the report was about to update. Reporting first meant
every relayout used the size before the one being reported. That one took a
`Console.WriteLine` inside the backend to see, because every number involved
was plausible.

**A `GtkSpinButton` is not a `GtkRange`.** It has a value, a range and steps,
and `gtk_range_set_range` on one is a `GTK_IS_RANGE` assertion at run time and
nothing at all at compile time -- because every widget is a `GtkWidget*` to a
binding. The binding cannot reproduce GTK's checked casts, which is the cost of
the one-pointer-type decision and is worth remembering when a call does
nothing.

### From before

**A 32-bit build already linked and ran, and was silently wrong.** Before any
of the target work, `--target x86` did not exist but the path did: clang was
handed the IR, it compiled, it linked, and hello-world printed. What that
proved was the toolchain, and nothing else. A probe that allocated an object
reported `sizeof(nuint)` as 8 on a target where a pointer is 4, and an array's
length as 1953724755.

The cause is worth keeping because it explains which things break: the
runtime's headers are `size_t` and shrink on x86, and the compiler's were
constants that did not. Fields and elements read correctly, because the
compiler was self-consistent about those. The two that broke are exactly the
ones the *runtime* writes — the TypeInfo pointer and the length. A disagreement
about layout does not fail loudly; it fails where the two sides meet.

**The decoration was never the problem, which is what the TODO assumed.** LLVM
applies x86's leading underscore to every global on its own, so `@sl_alloc` in
IR is `_sl_alloc` in the object, matching the runtime. The link error that
looked like a mangling bug was the x86 UCRT keeping `printf` inline, which
`-llegacy_stdio_definitions` fixes — and which a C program for the same target
needs too.

**`inreg` is the mark that does not announce itself.** `__stdcall` worked
first time. `__fastcall` built, linked, ran, and printed nothing: LLVM
allocates registers from the `inreg` marks rather than deriving them from the
calling convention, so the arguments went to the stack while the C callee read
ECX and EDX. The marks have to be identical on the declaration and at every
call — a call that marks a different set is undefined rather than refused.

**Win64's classifier is correct for Windows x86, and it is worth saying why.**
"In a register" on a target with no argument registers degenerates to "on the
stack", which is x86's rule for every aggregate, and both systems return 1, 2,
4 and 8-byte structs in EAX or EDX:EAX. i386 System V is the one that differs:
it returns *every* struct through a hidden pointer, one byte included. All of
that was read off clang by compiling the same C for each triple, rather than
off a specification.

**`nuint - 1` stopped compiling, and the standard library is written in it.**
At eight bytes `nuint` was wider than `int` and won the usual arithmetic rule.
At four they are the same width and opposite signedness, which the rule widens
to `long` — and then refuses to assign back. The fix is narrow: in that one
pairing, an integer literal takes the other side's type when the value fits.
It is what C# does, and it keeps the same source meaning the same thing at both
widths, which `tests/cases/x86-runtime` is the check on: every line of its
output matches the x64 build except the two that report a pointer's width.

**Documentation found two bugs, and both were found by writing rather than by
reading.** `String.ByteAt` reads the buffer through the pointer, where every
other position on a `String` clamps -- so the class could not state the rule it
appeared to keep, and the method now says it is the exception. And the
`TcpClient.Close` note claimed a bare close resets the peer, which is true only
with `SO_LINGER` at zero or unread data waiting; the text now says what the
platform actually decides. Neither is reachable by probing, because both are
about what a caller may assume rather than what a program does.

**`///` blocks were not in the syntax tree, and TODO said they were.** The
lexer discarded them with every other line comment, so nothing downstream had
ever seen one. That is the kind of claim worth checking before planning around
it: the generator entry was written as "a writer over what already exists", and
the writer was the smaller half of the work.

Three rules fell out of putting them in, and each decides where a block may be
written. Four slashes are not three, or a rule drawn across the file becomes a
line of punctuation mid-description. An ordinary `//` comment between a block
and its declaration separates the two -- so an implementation note goes *above*
the block, which is the opposite of what `Utf16Encoding.Preamble` was doing. And
a blank line separates them too, so a block above nothing documents nothing.

**Generating the pages found a class of gap no audit over the source had.** An
interface's members carry no `public` keyword, because they are the contract --
so a sweep looking for `public` misses every one of them, and `IStream` had
seven members saying nothing. A variant's cases are neither a member nor a
modifier, so `Optional`'s `None` and `Some`, `Result`'s `Ok` and `Fail`, and all
six of `JsonValue`'s were silent too. **The generator is the audit**: a page
that prints *No documentation* for what is missing finds what a grep for a
keyword cannot.

**The documentation writer reads syntax, not the bound program.** A generic
emits nothing until it is instantiated, so `List<T>`, `Dictionary<K, V>` and
`Optional<T>` have no bound symbol at all unless some program happened to use
one. A reference covering only the instantiated half of the standard library
would be worse than none, because nothing on the page would say which half it
was. It still binds first and writes nothing if that failed, so a signature on a
page is one the compiler accepted.

**The comment pass was small, and the boundary is why.** Splitting `///` from
`//` turned "a large mechanical pass over everything" into about thirty
comments. What made it tractable is that the two are different things: a `///`
block is documentation and keeps the first entry's bar, and a `//` note above a
line is describing that line. What was left after that split -- free-standing
argument, history, comparison with an absent alternative -- was the whole of the
job.

And the finding inside it: **there are no free-standing argumentative `//`
blocks in the tree.** Every `//` block reaching for the vocabulary of an
argument sits directly above the code it is about. The prose that argues already
lives in `///`, which is where it belongs -- so the pass was mostly a
confirmation that the convention was already being followed.

**A hardening pass found nine bugs, and eight of them were silent.** The method
was the one the last audit established -- compile a probe rather than read the
code -- run over a battery of about 150 adversarial programs rather than over
the spec. What that catches is a different population from what reading
catches: every one of these is a program that compiled.

**Deeply nested source ended the process rather than being refused.** Four
hundred nested parentheses overflowed the stack, and a stack overflow is the
one answer .NET cannot catch: no diagnostic, no exit code worth reading,
nothing naming the file. Blocks, prefix operators and a member chain each found
it by a different route, and the member chain found it in the *binder* after
the parser had survived -- `FlattenName` recursed over a chain the parser had
built with a loop, so nothing upstream bounded it.

The fix is two things and neither is enough alone. `Recursion.MaxDepth` turns
the crash into SL0108, and it has to be a fixed number rather than a probe so
that the same file is refused on every machine. `Recursion.OnADeepStack` is
what keeps that number from having to be small: on a default stack a few
hundred levels are already fatal, which is low enough that generated source
could reach it honestly. Reserving 64 MB is free, since it is address space.

Two details worth keeping. The limit must report *once* and then stop parsing,
because the unwind that follows produces one `expected ')'` per level -- 1,625
of them for a 600-deep file, burying the one message that explains it. And
`Speculate` has to save and restore the "already said so" flag along with the
diagnostics it discards, or a limit tripped inside a speculative parse is
reported into a bag that is thrown away and never mentioned again. That one
cost an hour: the guard was firing and the message was nowhere.

**A literal too large for its type was cut to 32 bits and said nothing.**
`long l = 9223372036854775808;` compiled and held zero. Every integer literal
started out an `int`, so a value past that range assigned to something at least
as wide fell through to an ordinary widening -- `int` to `long` has nothing to
complain about -- and the emitter narrowed it on the way out. A *narrower*
target was always caught, but only because nothing widens an `int` to a `byte`:
the right answer for the wrong reason, which is why the hole was invisible.

Worse and more ordinary: `double d = 5000000000;` printed 705032704. Valid
code, quietly given a different number.

The fix is C#'s rule, which is worth having for its own sake: a literal is the
narrowest of `int`, `uint`, `long` and `ulong` that holds it. That makes
`0xFFFF0000` a `uint`, so `flags & 0xFFFF0000` on an `int` widens the operation
to `long` and the mask means what a C header means by it. **The bindings were
relying on the truncation** -- `Com.sl` masks an `HRESULT` that way -- and they
were getting the right bit pattern by accident. Four samples stopped binding
the moment the rule was right, which is the useful kind of breakage.

**`char16` and `char32` could not cross a library boundary.** The metadata
reader's list of primitives was a second copy of the type system's, and it was
those two short -- so a public struct with a `char16` field was described by
the library and refused by everything that referenced it. `Primitives_` is
derived from `PrimitiveTypeSymbol.All` now, and a unit test round-trips every
primitive there is, so a new one fails that test until it can cross.

A slice and a tuple failed the other way: both are named types interned under
`Standard`, so they were written as `Standard.int[:]` -- a type in no source
file, which nothing could read back. They are structural, so they are spelled
structurally now, and the reader is handed the binder's own `SliceOf` and
`TupleOf`, because a slice made separately would not compare equal to one the
consumer's own source resolves to. `tests/cases/library-type-names` proves that
by assigning one to the other.

The general lesson is the one the writer's ordered type switch already taught:
**a list kept in two places is a bug with a delay on it.**

**Four shapes reached clang as IR it refuses**, which is the worst kind of
compiler message -- it names generated text for a mistake in the source, or for
no mistake at all:

- `void` as a local, a field, a parameter or a type argument became
  `alloca void` and `type { void }`. It is the absence of a value, so the only
  place it can be written is what a function returns (SL0309). The three
  container messages survive because their element is resolved with
  `allowVoid` -- "there is no array of `void`" says more than the general rule,
  and two codes for one rule is what the retired list exists to prevent.
- A struct containing a *fixed array* of itself. The cycle check only recursed
  through a struct-typed field, so `S[4]` was never looked through; the size
  was read before it was computed, the struct came out zero bytes wide, and the
  emitter wrote an LLVM type that referred to itself.
- A non-ASCII identifier. `SymbolSafe` and `SanitizeIdentifier` both tested
  `char.IsLetterOrDigit`, which is Unicode-aware, and LLVM's grammar is not --
  so `café` passed straight through into the IR. Anything past ASCII is spelled
  as its code point now. Worth noting that a *function* name already worked,
  because the mangler encodes lengths: the bug was visible only in the three
  positions that do not.
- A 2,000-character identifier, which clang reports as a multiple definition of
  a name defined once. The readable part of an IR local is capped at 64 now;
  nothing is lost, since what tells two slots apart is the counter after it. A
  parameter has no counter, so it gets its index appended -- but *only* when the
  name was actually cut, because the ABI tests pin ordinary signatures and
  renaming every one of them to fix an absurd case is a bad trade.

**Three malformed literals were taken quietly.** `''` became a zero, an escape
of `\u` with two digits became U+0012, and `1lul` meant 1. All three are values
nobody wrote. A character literal is exactly one scalar, `\u` takes exactly four
digits and `\U` eight -- `\x` stays variable, since it is a byte and C says so
-- and a suffix is measured against the set C# actually has.

**A missing dictionary key stopped the program, and that was the wrong call.**
The question that found it was the user's: how do other languages handle this?
The survey is the argument, so it is worth keeping.

No language puts an *uncatchable* crash behind the natural spelling. The ones
that crash on a missing key -- Python, C#, C++ -- all let you catch it. The
ones whose crash cannot be caught -- Go, Swift, Zig -- made the natural
spelling return an optional instead. Rust panics uncatchably on `map[k]`, and
gets away with it because `map[k]` is rare there and `.get()` is what people
write. Stainless was in the one corner nobody occupies: uncatchable, and the
shortest thing to write was the one that killed the process.

`Find(key)` returns `Optional<V>` now, on `Dictionary` and `SortedList`. The
name was already the library's word for it -- `Functional.Find`,
`Collections.IndexOf`, `Process.Finished` all answer "might not be there" that
way -- so dictionary lookup was the one place that did not, which reads more
like an oversight than a decision. `Get` still asserts and still aborts, which
keeps it consistent with `Optional.Get`.

Two arguments for `Find` that are not about taste. It is **one probe** where
`ContainsKey` then `Get` is two, each running the hash walk from scratch. And
`GetOr(k, fallback)` cannot tell a missing key from one mapped to the fallback,
which is Java's null ambiguity wearing a different coat.

**The `Dictionary` indexer is back, and it answers `Optional<V>`.** It was
removed first, on the reasoning that an indexer could not be honest here --
getter and setter share one type (§7.5), so an `Optional<V>` one would make
every write `map[k] = Some(v)`. That reasoning was right about the mechanism
and wrong about the conclusion, because Swift solves it with one rule the
language did not have: **a value promotes to the optional holding it.**

With `T` → `Optional<T>` implicit, the shared type stops being a cost and
starts saying something. `map[k] = v` sets, and `map[k] = None` removes,
because `None` *is* the absence of a value. That is Swift's subscript exactly,
and it is better than what was there before removal.

The rule is recognised by shape, the way `try` already recognises `Result`:
a variant whose template is named `Optional` with a `None` carrying nothing
and a `Some` carrying one field. It desugars in `BindConversion` to the
construction `Some(x)` already produces, so the emitter learned nothing. It has
to be asked in **two** places, `BindConversion` and `IsImplicitlyConvertible`,
or overload resolution and the conversion itself would disagree about what is
possible.

Three properties worth keeping, each pinned by
`tests/cases/optional-promotion`: an exact match beats a promotion, so
`Which(int)` still wins over `Which(Optional<int>)`; something already of the
target type is not wrapped twice; and an `Optional<T>` assigned to an
`Optional<Optional<T>>` *is*, which is what that says.

`map[key] += 1` does not compile, and that is the design rather than a gap --
there is nothing to add to when the key is absent. `map[key] =
map[key].ValueOr(0) + 1` says what should happen, and Swift's `dict[key,
default: 0]` exists for the same reason.

`List<T>` keeps its plain indexer. The line between them is real rather than
convenient: **an index is a position the caller worked out; a key is data that
arrived.**

**An abort threw away everything the program had printed.** `sl_fail` writes
its line to stderr and calls `abort`, and `abort` does not flush -- so a
buffered stdout was discarded and the reader got the message saying why the
program stopped and none of the output that led up to it. Not even a line
printed immediately before. Redirected to a file, the file was empty.
`sl_cast_failed` flushed stderr and had the same hole for stdout.

Both flush everything now, before the message rather than after, so the
explanation lands below the output it explains. It is one line of C and it is
the difference between a failure you can read and one you can only be told
about.

Found by asking the question rather than by probing: *are these actually
unrecoverable?* They are -- `abort` is unconditional, and every abort path in
`stainless.h` now says `SL_NORETURN` so the header answers that without anyone
reading the body. The audit of all 55 call sites is worth keeping: they fall
into exactly two groups, a **mistake in the program** (18: bounds, division,
casts, `checked`, an empty queue, a missing key) and **the runtime running
out** (37: memory, a thread, a mutex, entropy). The first group is what §2.6
says should abort. The second has no channel at all -- the function that failed
returns the thing it could not make. Every library abort has a way to ask
first, and each now says so where it is declared; `SortedList.Get` and
`Random()` were the two that did not.

**The harness could not test any of it**, which is why none of this was
covered: a case whose program does not return 0 failed on the exit code.
`aborts.txt` says a case is expected to stop, and the output is still matched
exactly -- which is what makes it a test of what a program leaves behind.

**No double survived being written and read back, and that is the one this
run would have most regretted missing.** `Text.FromDouble` was `snprintf` with
a plain `%g`, which is six significant digits -- so pi printed as 3.14159, a
measurement written to a file came back as a different measurement, and a JSON
document of numbers was quietly damaged by being saved. Nothing failed; the
numbers were simply not the ones the program had.

The rule now is the shortest *text* that reads back as the same double, found
by trying each precision from one to seventeen and keeping the shortest that
round-trips. Two details cost a suite run each and are worth keeping:

- **Shortest text is not shortest precision.** `%.1g` of 60 is `6e+01`, which
  round-trips perfectly and is five characters where `60` is two. `%g` turns
  exponential once the precision drops below the decimal exponent, so stopping
  at the first precision that round-trips turns every round number into
  scientific notation -- which is how `$60` became `$6e+01` in a sample.
- **On a tie, plain beats exponential.** `7e+04` and `70000` are both five
  characters, and only one of them is what anybody means by seventy thousand.

And the inverse had the same shape of bug from the other side: `Convert.
ToDouble` read the digits by hand, ten times a running total and a tenth of a
running scale, which loses a bit per digit -- a tenth not being a binary
fraction. It validates the syntax as before and now asks the runtime for the
value, so what the library writes the library can read. Worth noting the
division of labour: which spellings are a number is the library's rule, and
what the digits are worth is arithmetic nobody should do twice.

**The runtime is clean under `-Wall -Wextra -Wconversion -Wshadow
-Wcast-qual`**, which is worth knowing because it means the warnings are not
where to look. The only ones left are a Windows CRT deprecation, a Win32 macro's
signedness, three deliberate partial initialisers, and the twenty-four
`-Wcast-qual` hits in `reflection.c` that are the one documented unsafe cast --
a stored function pointer to the prototype its kind implies.

What a warning cannot see is size arithmetic, and two allocations lacked the
guard `sl_array_alloc` already had: `sl_string_new` adds a header and a NUL to
a length, and the builder's reserve adds and then doubles. Both wrap rather
than fail, and the doubling wraps to zero and loops for ever. It takes an
unreachable amount of text to get there, which is exactly why nobody would
notice if it happened. Guarded now, on the same terms as the array.

**Editing `runtime/*.c` needs a `dotnet build` before any program sees it.**
The C sources are embedded resources written out to the object directory, the
same as `stdlib/*.sl`, so a fix tested without rebuilding the compiler is a fix
tested against the old runtime. That cost one wrong conclusion here.

**The containers had no indexers, and the language has had them all along.**
`list[i]` did not compile; `list.At(i)` and `list.Set(i, v)` were the whole
surface, and `map.Get(k)` likewise. The methods stay, because an interface has
no indexers and `IReadOnlyList<T>` declares them, but the brackets are what to
reach for where the type is known. Probing the way in found this, not reading:
the first line of the collections probe was `list[0]` because that is what
anyone would write.

Worth knowing that a **generic** indexer already worked -- on a class and on a
struct, with `+=` reading through the getter and writing through the setter --
and that nothing covered it. `tests/cases/indexers` does now.

**An argument that failed to bind was reported twice**, and the second message
came first: overload resolution saw an error-typed argument, found it matched
everything and nothing, and said "the call is ambiguous" above the real error.
The guard has to test the *node* rather than its type, which cost a suite run
to learn -- `out var x`, an array literal and `Ok(v)` are drafts that carry an
error type precisely while they wait to be told what they are, and refusing to
resolve is how they would never be told.

**The project file crashed on `null`.** JSON `null` lands in a property whatever
its type says and the deserializer does not count it as missing, so eight fields
answered a malformed file with a NullReferenceException and a stack trace. The
same pass made a value of the wrong shape name its own field rather than a .NET
type: `'kind' takes 'executable' or 'library'` instead of `The JSON value could
not be converted to Stainless.Driver.ProjectKind`.

**Two functions with the same signature are diagnosed now** (SL0211), which the
TODO had wanted for a while. The check is one line, because the mangled name
already *is* the signature: two functions in a module collide exactly when they
mangle alike. It catches a redeclared `extern` too, which is the same mistake
wearing a C hat.


**`base.P` on a property dispatched back to the override.** A method has always
been non-virtual through `base` -- the spec says so and `BindMemberOf` passed
the fact along for a call -- but a property accessor is a method too and did
not. So the obvious override,

    public override bool Flag { get => base.Flag; }

called itself for ever. Not a crash and not a diagnostic: the program hangs with
nothing to say, which is how it was found -- a GUI that came up and never
returned. `BoundCall.IsNonVirtual` already existed; the getter now sets it and
`BoundPropertyAssignment` gained the same flag for the setter, which travels by
a different route. `tests/cases/base-property` covers both halves and two levels
of inheritance.

**A generic instantiated over a struct declared later gave it a one-byte
layout.** `Forms.Platform` names `Result<Color, DialogOutcome>`; pass 4 reached
that before it reached `Forms.Drawing`, so laying the instantiation out walked
into a `Color` with no fields yet, settled on one byte, and set `LayoutComputed`
so nothing looked again. `Color.FromRgb` then compiled to `define i8` and every
colour in the program lost its green and blue -- a red window, and a `Bitmap`
whose only symptom was that.

The trap is the one `Binder.Generics` already documents for template-to-template
cycles; what was missing is that an *ordinary* struct can be reached the same
way. The fix is one condition: an instantiation made while pass 4 is still
running waits, and the deferred layouts settle when every source type has its
members. `tests/cases/generic-over-later-struct` is the regression, and it
prints `sizeof: 1` without it.

Worth knowing for its own sake: a wrong `Size` shows up as a *truncated return*,
because `Win64Abi.ClassifyReturn` coerces a register-sized struct to `i{Size*8}`.
If a struct ever comes back with only its first field set, look at its layout
before looking at the call.

**A GUI is the thing that finds the holes.** Five of the six bugs the Forms work
turned up were invisible until something was measured, and none of them made a
compiler or a test complain:

- the form never painted its background, so the client area was black *and*
  every region a moved control vacated kept its old pixels -- one swallowed
  `WM_ERASEBKGND`, two symptoms that looked unrelated;
- `WM_SIZE` reports the *client* extent and `Bounds` is the *window* rectangle,
  so every resize shrank each bordered control by its frame, compounding, while
  the borderless button beside it stayed exactly put;
- reporting a message is not consuming it: answering `WM_MOUSEMOVE` left
  clicking able to place the caret and dragging unable to select anything;
- `TCM_INSERTITEMW` is `TCM_FIRST + 62` *decimal*, and the ListView trio are
  `+75/76/77` -- write the ANSI numbers instead and nothing fails, the control
  reads a UTF-16 pointer as ANSI and stops at the first zero high byte, so a row
  count is right and the text is one letter;
- inserting a tab does not select it, so showing "whichever page is current"
  showed none of them.

The lesson that generalises: **a peer must not answer what the platform should
handle**, and a count is not evidence that text arrived. Both are now checked by
`tests/cases/forms-input` and `tests/cases/forms-menus`, which drive real
messages rather than calling the API.

**Interface-to-class narrowing cost 25 lines and emits nothing.** `IShape s; if
(s is Square sq)` was refused, and the machinery was already there: an interface
reference *is* the object pointer, `Downcast` emits `sl_is_instance` on that
pointer, and `EmitTypeTest` already had the class-target path -- which is why
the old error said the test could be asked but its answer could not be named.
One rule in `ClassifyConversion` was all that was missing. The refusal that
survives is a *sealed* class that does not implement the interface, since
nothing below it can supply what it lacks.

It is worth knowing how this bit: the seam grew an `OwnedByParent()` method on
`IMenuPeer` purely because the Win32 backend could not reach its own concrete
`MenuPeer` through the interface. A language gap became an API wart one level
up, and removing the gap removed the wart.

**Array type info was named after the element's simple name.** Two `Point`
structs in different modules gave their arrays one symbol between them and LLVM
rejected the second definition -- a message about generated IR, naming a symbol
that is in no source file, for two ordinary declarations that have every right
to coexist. `ArraySuffix` now qualifies, as the struct and destructor names
beside it always did.

**`event` was mostly encapsulation, not machinery.** A list of closures, added
to and removed from by value, was already writable by hand before any of this --
`closure` compares on both words, which the spec describes as what makes one
"removable from a list of them". What the word adds is that from outside the
declaring type, `+=` and `-=` are the *only* things that can be written. That is
the whole difference between an event and a public field of closure type.

**The array is replaced rather than mutated, and that is not a detail.** A raise
reads the field into a local first and walks that, so a handler may subscribe or
unsubscribe while the event is running. The obvious first choice -- a `List<T>`
mutated in place -- makes that case skip a handler or run off the end. C# gets
the same property for free because multicast delegates are immutable; here it
comes from copy-on-write. The cost is one allocation per subscription change,
which is what C# pays too.

**Two of C#'s warts were worth not copying**, and both were the user's call: an
empty event raises nothing rather than throwing, which removes `?.Invoke` from
every raise site; and a handler must return `void`, because with several
subscribers "what did it return" has no honest answer and C# silently keeps the
last one's.

**A closure crossed a library boundary as a struct, and a delegate as nothing.**
A closure *is* a struct of two compiler-owned fields, so it matched the struct
case in the metadata writer and was described by fields a consumer cannot name;
a delegate is not a struct, matched no case at all, and was silently absent.
Both now cross as signatures with the far side rebuilding the representation.
Worth remembering that the writer's type switch is ordered, and that a `case`
which matches nothing fails quietly.

**Deriving across a library boundary was mostly an export problem.** The TODO
called it emitter work and it was four smaller things, three of which were the
library refusing to hand over what it already had: the destroy hook was `define
internal`, protected methods were neither described nor exported, and the
dispatch table's slots were never written down. Once those crossed, the binder
needed no new logic at all -- `ResolveVirtuals` copies a base's table and
appends, and it does not care where the table came from.

**The one real obstacle was Windows, and it is about data, not dispatch.** A
derived class's TypeInfo names its base's, and on Windows an imported *datum*
has no address until the loader has filled in the import table -- so it cannot
appear in a constant initializer. The fix is a store at startup through the
existing `llvm.global_ctors` hook, which the emitter already had for binding
string literals. ELF needs none of it: a relocation into another shared object
is ordinary there, which is why the same code passed on Linux before the
Windows path existed.

**The vtable length is now part of a library's contract.** A derived class
appends after the base's last slot, so a later version of the base adding a
virtual method wants a slot something else is using. The decision taken is that
this is a breaking change by definition -- no reserved slots, no second
indirection -- and the ABI digest is what enforces it, which is why the digest
carries the table slot by slot rather than just its contents.

**A guard was written for a case that cannot happen.** The first version refused
to derive from a referenced com class. A com class never crosses in metadata at
all (`Crosses` excludes it, and SL0544 says so where the library is built), so
the check was dead code with a diagnostic attached. Worth checking what the
*writer* refuses before writing a rule about what the reader might see.

**The project file is for reading, not for building.** The command line already
said everything a build needs; what it could not do was answer a question. That
is the whole argument for `stainless.json` and the whole argument against a
Makefile — a Makefile builds the program perfectly well and the only way to find
out what it builds is to run it. Everything else about the design follows from
that one sentence, including JSON, which is not the nicest syntax and is the
only one both sides can already parse: `System.Text.Json` in the compiler and
[stdlib/Json.sl](stdlib/Json.sl) in the language itself. An IDE written in
Stainless can read its own project file with nothing new written.

**A source dependency is the right default, and that was not obvious.** Every
other package manager's dependency is a binary one, so `"link": "shared"` looked
like the main case and compiling the source in looked like a shortcut. It is the
other way round: this language binds a whole program at once with no headers, so
a source dependency is simply *more files in the same compilation* — which is
why generics, interfaces and variants cross one and cannot cross a `.slmod`.
Shared is the opt-in, and it is opting into a boundary with real costs.

**Two digests, and they answer different questions.** `sourceDigest` is over the
files that were read and is computed at resolution; `abiDigest` is over the
layouts that came out and can only be known after a build. Conflating them was
the first design and it was wrong in both directions — a source dependency has
no library to fingerprint, and a fixed commit whose files changed is a damaged
cache rather than a version mistake.

**The digest only earns its place if an addition is silent.** The first version
reported any change to a library's surface under an unchanged version. That fires
on every added function, which is harmless — nothing compiled against the smaller
surface can be invalidated by it — and a warning that is usually wrong is a
warning people learn to skip. Only what *changed or disappeared* is reported now.

**`--update` did not re-fetch a moved tag**, and the test that found it was the
obvious one: move the tag, build, check the lock held; then `--update`, and check
it moved. It had not, because the cached checkout was keyed by the pin and a
present checkout was never re-read. Worth remembering that the cache has two
independent questions in it — is it here, and is it current — and that a tag is
immutable by convention rather than by construction.

**`closure` is the piece the rest now rests on.** A `delegate` is one pointer,
which is what makes it a C function pointer and what stops it carrying
anything: a lambda that reads a name from around it cannot become one (SL0381).
A closure is that pointer *and* a receiver — Delphi's `of object` — so a
callback can know *which* counter to add to.

It cost far less than expected, and the reason is worth remembering:

- **A method already takes its receiver as argument zero**, so a bound method
  pointer is literally `{method address, object}` and calling one is a single
  indirect call. No thunk, no shuffling.
- **It is a two-field struct**, so layout, both ABI classifiers, and the
  reference walk that retains and releases what a value holds all apply to it
  without one line of any of them being written for closures. The receiver's
  static type is an internal marker class, because counting does not care which
  class an object is — `sl_release` finds that in the object's own header.
- **A lambda becomes one through the machinery that already existed**: the
  generated capture class *is* the receiver, and its method already takes it
  first. So a lambda and a bound method are the same two words.

**Events were built and then deleted, and that was the right sequence.** The
`event` keyword worked -- `+=`, `-=`, subscription order, safe unsubscription
mid-raise, ARC -- in about 700 lines of compiler. What killed it was the
question it forced: *what carries the handler?* Interfaces were the only answer
at the time, and interfaces were not wanted. Closures answered it better and
made the keyword's remaining value one thing only: **only the declaring type
may raise**, which cannot be expressed as a library type because anything that
can reach the handler list to add to it can also iterate it, and iterating is
raising. There is no `internal` or `friend`.

If events come back, they should be `event C Name;` over a closure type, and
the 700 lines are in `4fc1dde`'s parent commits to crib from.

**Monomorphization dropped every member that is not a method, and the three
that were dropped failed in two different ways.** This is the bug the last run
left open, and looking at it properly found two more beside it.

`Instantiate` queued the bodies of `type.Methods`, its constructors and its
destructor. An **operator** is deliberately not in `Methods` — no receiver, no
dispatch slot — and neither is the `static Name() { }` **setup block**, which is
reached from the static-initialization pass rather than by lookup. So both were
declared, both were called, both mangled, and neither was ever emitted. The
symptom is a link error naming one mangled symbol, which is why `Box<T>` with an
`operator+` failed with one instantiation or with several: the count was never
the variable.

**Statics failed one step further out, and that is the part worth remembering.**
Their initializers were bound and topologically sorted in pass 10, which had
already finished by the time pass 11 bound a body that asked for a *new*
instantiation — so that instantiation's storage was never allocated at all. A
generic reached only from inside another generic hit this and nothing else did,
which is why it had never been seen. The passes interleave now: bodies and
statics feed each other until neither has anything left, and only then is the
order the initializers run in settled. `_staticSyntax` also carries the
substitution in force where each static was declared, because an initializer
that names `T` is bound long after anything else remembers what T was.

The lesson generalizes past this fix: **a member kind that lives outside
`Methods` is a member kind monomorphization will forget.** The full inventory is
methods (property accessors included), operators, constructors, the destructor,
the static setup block, statics, and generic methods — which instantiate
themselves and are the one kind that was never at risk.

**Two more compiler bugs found by trying a user's design rather than by
testing.**

- `var d = SomeFunction;` bound cleanly and emitted `store ptr 0`, which clang
  rejected as a compiler bug. The lambda case beside it had been fixed and left
  a comment describing the identical symptom; this was its missing sibling.
  Fixed, SL0553.
- A closure call was not in the has-an-effect list, so calling one as a
  statement warned SL0222. Fixed.

**A hard keyword is a tax on every program.** `event` was made contextual after
the GTK bindings turned out to use `event` as a parameter name fifteen times —
code written hours earlier in the same session. `closure` is contextual for the
same reason. The test for whether a word can be taken is not "is it rare" but
"did we ourselves just use it".

**Reflection describes properties now, and that was a correctness fix rather
than a feature.** An automatic property's storage is a field *named after the
property*, so a walk over the field table found `Left`, wrote it, and went
straight past the setter that would have re-run the layout.
`Field.IsPropertyStorage()` is what tells the two apart; `sl_property_get_*`
and `_set_*` call the accessors. The unsafe cast from a stored function pointer
to the prototype its kind implies is written **once**, in the runtime, rather
than at each call site that would have to guess.

**`FindType` is the other half of a form file.** Types and properties can now
both be named by a document: `FindType("App.Button")`, `Make`, then set
properties through their setters. What is still missing is **methods**, so an
event handler named by a document has nothing to resolve against. That is the
one remaining piece before a designer.

**The GTK binding is verified against the libraries, not against
documentation.** Every declared symbol was checked with `nm -D` against both
`libgtk-3.so.0` and `libgtk-x11-2.0.so.0`. That caught nine calls filed as
shared that GTK 2 lacks, and `gtk_entry_set_editable`, which GTK 3 removed. Do
this after adding declarations: a misfiled call is a link error naming one
symbol at a time.

**`g_object_ref_sink` is right for widgets and wrong for a plain GObject.**
Every `GtkWidget` is a `GInitiallyUnowned`, so its reference is floating and
sinking claims it. A `GtkTextBuffer` is not, and sinking one *adds* a
reference — which showed up once as a 126 MB leak that was the test's and not
the binding's.

**Two representations behind one syntax is the thing to avoid.** `T?` on a
value type was turned down in favour of `Optional<T>`, a variant. `C?` is a
null pointer and costs nothing; a tagged pair is a different thing. The same
instinct is why `ClosureTypeSymbol` is not a flag on `DelegateTypeSymbol`:
sixteen bytes silently reaching a slot that expects a C function pointer is the
kind of mistake that shows up as a corrupt stack in someone else's code.

**An audit drove most of this run, and the audit's own method is the thing to
keep.** Every claim in it was checked by compiling a probe rather than by
reading, and that is what turned up the two findings nobody would have written
down otherwise: `delete` was a reserved word the parser never mentioned, and
the standard library was built on the five one-method interfaces the design had
already disowned. Neither is visible from the source; both are obvious the
moment something tries them.

**The repository keeps answering the keyword question.** `out` is a local in
`Convert.sl` and `Encoding.sl`; `checked` is a parameter name in
`tests/cases/static-methods`. Both are contextual now, as `closure` and `event`
already were. That is four for four: every time a word looked safe, the tree
already used it. Grep before taking one — and grep the *code*, not the comments,
which is a mistake made once this run and caught by the suite.

**A mechanical rewrite needs a test that fails.** A script turning `x = x + 1`
into `x++` also turned `value = value * 10 + digit` into `value *= 10 + digit`,
and exactly one test noticed. The compound-assignment pass was dropped: a script
that cannot see precedence has no business deciding which of those was meant.
`++` alone is unambiguous and is all that ran.

**Three bugs found by the Linux run that Windows could not have shown.**

- A small struct returned through a **closure or a delegate** was used as an
  address. The direct-call path has always landed a register-returned struct in
  a slot; the two indirect paths did not. Nothing hit it until
  `Optional<T>.FlatMap` began taking a closure rather than an interface, an
  interface call being a direct call through a vtable slot. SysV-only, that
  being the ABI that returns an `Optional<nuint>` in two registers.
- `default(T)` for a struct returned the constant `zeroinitializer`, and a
  struct travels as the *address* of its storage — so the store memcpy'd from
  address zero. Caught by a segfault in the first probe.
- The hidden local a tuple deconstruction holds its tuple in was not tracked as
  owned, so each element was one release short. Caught by a destructor that
  printed.

All three are the same shape: **a value that is really an address, or an
address that is really a value.** That is the seam to look at first when
something new touches structs.

**`?.` needed somewhere to put a temporary**, and expressions have nowhere to
put a statement. `BoundLet` — a value held for the duration of an expression —
is what came of it, and tuples wanted it too. It borrows: whatever produced the
value is already a temporary the statement will drop.

**Uniform call syntax rather than extension methods.** `x.F(y)` falls back to
`F(x, y)` when `x` has no member `F`, so the whole combinator surface became
chainable with no library change at all. C# needs `this` because everything must
live in a class; a module is a scope here, so there is nothing the modifier
would add. A member always wins, the fallback being reached only after member
lookup fails.

**Nesting is about where a name is reached from, and nothing else.** A type
declared inside another is lifted out and named `Outer.Inner` — no privileged
view, no hidden reference to an outer instance, no bearing on layout. The
parser's `hoisted` list, which already existed for anonymous members, is the
whole mechanism.

**A tuple is a struct**, so layout, both ABI classifiers and the reference walk
apply to it with nothing written for tuples. Its fields are `Item1` upwards on
purpose: named elements either take part in the type's identity, making
`(int a, int b)` and `(int x, int y)` different types, or they do not, leaving
two names for one field. The name is wanted at the use site, and
`var (low, high) = ...` is where it goes.

**The documentation was brought back in line, and `tests/cases/doc-examples`
is what keeps it there.** Every block this session added to README.md or the
spec is compiled and run by that case, so the next time the prose and the
compiler disagree something fails rather than nobody noticing. The three
entries at the top of TODO.md came out of the same pass: the standard library
is the part of this language most people will read, and it is the part with the
least written about it.

## Next, in the order I would do it

**For `forms/`, `forms/README.md` has the full roadmap** -- every LCL unit a
program would miss, grouped by how much work it is. The short version, now that
the GTK backend is done and the dialogs, `PaintBox` and `Timer` that this
paragraph used to recommend are all in: **DPI awareness** first, because both
backends turn points into pixels at a hard-coded 96 and every control is wrong
on a scaled display; then **owner drawing**, which half a dozen controls want
and none has; and `grids.pas`, which is 14,000 lines that neither platform has
a widget for.

0. **Pin the README's numbers.** Nothing is unpushed any more, but the counts
   in the README drift on every commit that adds a case and they were four
   audits stale when this one found them — a unit test asserting them against
   the two suites is two hours and stops it for good.
0.5 **A registry, or a decision not to have one.** Resolution unifies sources
   rather than searching versions, because a path and a git tag each pin exactly
   one version and nothing can offer an alternative. That is honest and it is
   also the reason two packages needing incompatible versions of a third is a
   hard error with no way out. The search belongs in `PackageResolver.Visit`
   when there is something to search.
1. **Method metadata in reflection**, with invoke-by-name. Now the last piece
   before a form file can wire a handler — `event` supplies the other half, and
   what is missing is finding the method by name — and the same work would let a
   deserializer fill a `List<T>` — the one shape `Standard.Json` cannot
   represent.
2. **The component layer.** `samples/gtk/control.sl` is what one control looks
   like by hand; the next step is a `Component`/`Control` base with ownership
   and bounds, and a narrow backend interface with GTK and Win32 behind it.
   Everything it needs exists.
3. **A reachability pass from `Main`.** Every program compiles the whole
   library. It is the most expensive missing thing and gets worse as the
   library grows.
4. **The +0/+1 dataflow pass.** Still the acknowledged performance item.
5. **`List<T>` has no `Remove(T)`.** Its `IndexOf` wants `IEquatable<T>`, which
   a closure is not. Less pressing than it was — `RemoveWhere` takes a predicate
   for exactly this reason, and a list of callbacks is now usually an `event` —
   but `Remove(T)` is still the obvious method that is not there.
6. **`Standard.Collections` does not use the operators it could.** `Money` in
   the samples still calls `Money.Add`; `Standard.Time` has had this pass.
7. Format specifiers in interpolation; the samples cover about half the
   language.

## Things to know before touching the build

- **Heredocs mangle backslashes here.** A `\n` inside `bash <<'EOF'` arrives as
  a literal newline, which has broken C#, C and Python source repeatedly — and
  did so twice more this run, in both cases silently reverting an edit whose
  assertion then failed. Use the Write or Edit tool for anything with escapes.
- **This file uses em dashes.** A patch script matching on `--` will fail its
  own assertion; check which is in the text before writing the pattern.
- `io.open(p, 'wb').write(io.open(p, 'rb').read())` truncates the file before
  reading it — Python evaluates the callee first.
- **There is no `rsync` on this Windows box.** What works is tar over ssh, and
  `git ls-files` keeps `bin/` and `obj/` out of it — a stale `obj/` from the
  other platform is what makes a synced tree fail in confusing ways:
  ```sh
  tar -czf /tmp/sync.tgz $(git ls-files -c -o --exclude-standard)
  cat /tmp/sync.tgz | ssh brandon@geekom-a7 "mkdir -p ~/stainless-fix && tar -xzf - -C ~/stainless-fix"
  ```
  `-c -o --exclude-standard` is tracked files *and* new ones that are not
  ignored, which is what a work-in-progress tree needs: `git ls-files` alone
  leaves out every case the run just wrote, and the suite then fails on cases
  that are not there.
- **Running the suite on that box, 32-bit cases included**, once the tree is
  synced:
  ```sh
  docker build -t stainless-x86 -f tests/linux-x86.Dockerfile tests
  docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -e DOTNET_CLI_HOME=/tmp       -v "$HOME/stainless-fix:/src" -w /src stainless-x86       bash -c 'dotnet build Stainless.slnx && dotnet run --project tests/Stainless.Tests --no-build'
  ```
  The container is only needed for `--target x86`; everything else builds
  against the box's own clang. It is there because the box has the i386
  runtime libraries and none of the development ones, and installing those
  wants a password.
- **Run that container as yourself.** Without `-u` the build is root's, and the
  `bin/` and `obj/` it leaves in the bind-mounted tree belong to root: the next
  sync cannot overwrite them and you cannot delete them without going back in
  as root to do it. `HOME` goes with `-u`, because dotnet writes to one and the
  container has no home directory for a borrowed uid.
- **The first `dotnet build` after a sync onto Linux sometimes dies with
  `Internal CLR error (0x80131506)`.** It is transient: run it again and it is
  clean. It happened twice in an earlier run and neither time was real.
- `-o /dev/null` does not work for a build on Windows; the linker wants a real
  path.
- **Windows reserves `COM1`–`COM9` even with an extension**, so a scratch file
  named `com2.sl` does not exist as far as any program is concerned.
- A documented `SL####` needs an `errors.txt` case pinning it, or
  `DiagnosticTests.EveryDocumentedCodeIsPinnedByACase` fails.
- **A new sample must be listed in `SampleTests`**, or
  `EverySampleOnDiskIsListed` fails. The GTK commit missed this and the failure
  only showed on Linux, because the sample is `UnixOnly` and skipped on
  Windows. **Run the unit tests, not just the end-to-end suite, before
  committing.**
- A test that looks up a function by name fragment will match the standard
  library once it grows something of that name — `AbiTests` matched
  `Standard.Xml.Cursor.Take` instead of its own. Qualify: `4Test4Take`.
- Adding a `stdlib/*.sl` file needs `dotnet build` before any program can
  import it; the library is an embedded resource picked up by a wildcard.
- **Two end-to-end runs at once corrupt each other.** The harness builds every
  case under one shared `%TEMP%/stainless-tests/`, so a second run overwrites
  the first's object files mid-compile. It shows up as a scattering of
  unrelated failures that all pass when the suite is run alone.

## Running a GUI with no screen

Both are set up on `geekom-a7` and both are in `bindings/gtk/README.md`:

```sh
broadwayd :5 &                       # GTK 3 only, no X at all
GDK_BACKEND=broadway BROADWAY_DISPLAY=:5 ./Program

Xvfb :9 -screen 0 1024x768x24 &      # either version
DISPLAY=:9 ./Program
```

`broadwayd :5` reports `broadway6.socket`, and `BROADWAY_DISPLAY=:5` is still
what connects to it. GTK 2 has no broadway — `libgdk-x11-2.0` contains not one
mention of it — so Xvfb is what tests that side.

**Watch stderr.** GTK reports a bad signal name or a failed cast there and
nowhere else, so a clean stderr is most of what a headless run is worth.
