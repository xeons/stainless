# Handoff

What the last runs built, what was learned that is not obvious from the code,
and what is worth doing next. Written to be read cold.

## State

```
dotnet build Stainless.slnx                     0 warnings
dotnet test tests/Stainless.UnitTests           563 pass
dotnet run --project tests/Stainless.Tests      226 cases, 1 skipped on Windows
```

Green on Windows and on Linux (`ssh brandon@geekom-a7`). That box now has GTK 2
and GTK 3, the development packages, Xvfb and `broadwayd`, so a GUI can be
built *and run* there headlessly — see `bindings/gtk/README.md`.

`master` is ahead of `origin/master`; the reflection and closure commits have
not been pushed.

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
| *(this run)* | generic types get their operators, statics and setup blocks |

## Findings worth keeping

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

## Next, in the order I would do it

1. **Method metadata in reflection**, with invoke-by-name. The last piece
   before a form file can wire a handler, and the same work would let a
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
   a closure is not, so a list of callbacks is removed from by hand.
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
