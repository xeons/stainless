# Handoff

What the last runs built, what was learned that is not obvious from the code,
and what is worth doing next. Written to be read cold.

## State

```
dotnet build Stainless.slnx                     0 warnings
dotnet test tests/Stainless.UnitTests           659 pass
dotnet run --project tests/Stainless.Tests      255 cases, 2 skipped on Windows
samples/forms/build.ps1 -Test                   67 checks against real widgets
```

Green on Windows and on Linux (`ssh brandon@geekom-a7`). That box now has GTK 2
and GTK 3, the development packages, Xvfb and `broadwayd`, so a GUI can be
built *and run* there headlessly — see `bindings/gtk/README.md`.

`master` is eighteen commits ahead of `origin/master`. Nothing has been pushed
since the closure work.

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
| *this one* | the composites, and `base` on a property stops dispatching |

## Findings worth keeping

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

## Next, in the order I would do it

**For `forms/`, `forms/README.md` has the full roadmap** -- every LCL unit a
program would miss, grouped by how much work it is. The short version: common
dialogs are nearly free because `bindings/win32/Dialogs.sl` already has them;
`PaintBox` and `Timer` are small and unblock a lot; the GTK backend matters more
than any control, because a seam with one implementation has quietly stopped
being a seam; and `grids.pas` is 14,000 lines that Windows has no widget for.

0. **Push.** Fifteen commits are unpushed, and the last audit's numbers in the
   README drift on every commit that adds a case — a unit test pinning them is
   two hours and stops it for good.
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
  tar -czf /tmp/sync.tgz $(git ls-files) <any-untracked-files>
  cat /tmp/sync.tgz | ssh brandon@geekom-a7 "mkdir -p ~/stainless-fix && tar -xzf - -C ~/stainless-fix"
  ```
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
