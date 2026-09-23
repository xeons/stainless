<sub>[Stainless](../README.md) &rsaquo; Coding style</sub>

# Coding style

What code in this repository looks like, and why. It covers both languages
here: the C# the compiler is written in, and the Stainless that everything
above the compiler is written in. Where they differ, the difference is named
and a reason is given for it.

The baseline is Microsoft's two pages —
[identifier names](https://learn.microsoft.com/en-us/dotnet/csharp/fundamentals/coding-style/identifier-names)
and [coding conventions](https://learn.microsoft.com/en-us/dotnet/csharp/fundamentals/coding-style/coding-conventions).
Stainless is a C#-shaped language, so a reader who knows C# should be able to
read this codebase without learning a second set of habits. Everything below
either restates one of those pages for emphasis, or departs from it for a
reason written down beside the rule.

**This document is normative for new code.** The existing tree is being brought
to it in passes, so a file that disagrees with something here is debt, not a
counter-example.

---

## 1. Naming

### 1.1 Casing

| Thing | Case | Example |
|---|---|---|
| Module, namespace | `PascalCase`, dotted | `Standard.Collections` |
| Class, struct, enum, variant, union, delegate | `PascalCase` | `WindowedControl`, `ImageFormat` |
| Interface | `I` + `PascalCase` | `IEnumerable`, `IControlNotify` |
| Method, property, event, indexer | `PascalCase` | `FindForm`, `Bounds`, `Click` |
| Public or protected field | `PascalCase` | `public byte R;` |
| Constant | `PascalCase` | `const double Pi` |
| Enum member | `PascalCase` | `DockStyle.None` |
| Local, parameter | `camelCase` | `newParent`, `index` |
| Private or internal instance field | `_camelCase` | `_owner`, `_backgroundSet` |
| Private or internal static field | `s_camelCase` | `s_loaded`, `s_started` |
| Thread-static field | `t_camelCase` | `t_current` |
| Generic type parameter | `T`, or `T` + `PascalCase` | `T`, `TKey`, `TValue` |

**Constants are `PascalCase`, not `SCREAMING_CASE`.** This is C#'s rule and not
C's, and the tree already follows it — `Math.Pi`, `Math.Epsilon`,
`Path.Separator`. A `const` is part of the surface a caller reads, and there is
no reason for it to shout.

**A `const` that mirrors a foreign one keeps the foreign spelling.** In
`bindings/`, `GTK_RESPONSE_CANCEL` and `PixelFormat32bppArgb` are named as the
platform names them, because the value of a binding is that a reader can search
the vendor's documentation for the identifier in front of them. This is the one
place `SCREAMING_CASE` is correct, and it stops at the binding's edge: what
`forms/` exposes on top is named the way everything else here is.

### 1.2 The underscore on fields

A field that is private or internal is written with a leading underscore.

```csharp
public abstract class Control : IControlNotify
{
    WindowedControl? _owner;
    Rectangle _area;
    bool _backgroundSet;

    static List<Form> s_open = new List<Form>();
    static bool s_started = false;
}
```

**It is there to answer one question at the point of use.** Reading `_area`
inside a long method, you know without scrolling that it is state belonging to
this instance and that nothing outside the class can have written it. Reading
`area`, you do not — it could equally be a local, a parameter, or something the
uniform call syntax pulled in from another module. That ambiguity is worse here
than it is in C#, because [§7.1.1](spec/07-functions-members.md#711-xfy-is-fx-y)
means a bare name has more places it can come from.

**It also removes the need for `this.`** as a disambiguator. A constructor
parameter and the field it fills can both have the obvious name, and neither
has to be spelled awkwardly to avoid the other:

```csharp
Control(Rectangle area)
{
    _area = area;
}
```

**`s_` and `t_` mark storage that outlives the instance.** A static field is
shared by every caller on every thread, and a thread-static is the thing that
looks shared and is not; both are worth seeing at the point of use rather than
at the declaration. This is the Microsoft naming page's rule, kept for the
reason it exists.

**Public and protected fields take no underscore.** They are part of the type's
surface and are cased like any other member — `public byte R;` on `Rgba` stays
as it is. The underscore is a statement about visibility, so it appears exactly
where the visibility is private or internal.

### 1.3 Words, not abbreviations

**Spell it out.** `index` rather than `idx`, `parent` rather than `prnt`,
`count` rather than `cnt`. The exceptions are the ones that have stopped being
abbreviations — `Id`, `Ok`, `Rgba`, `Utf8`, `Xml`, `Io` — and the loop counter
`i`, which is a convention and not a name.

**An acronym of two letters is upper-cased; longer than two is `PascalCase`.**
`IOError`, but `XmlCursor` and `HtmlWriter`. This is C#'s rule and the tree
already follows it.

**No Hungarian notation**, no type in the name. `String text`, not
`String strText`. The declaration says what the type is and the compiler
enforces it.

**Avoid a name that differs from another only by case.** Stainless resolves the
whole program before it checks any body, so two names a reader can confuse are
two names a *reviewer* can confuse, and the compiler will not help.

### 1.4 What a name promises

**A method is a verb or a verb phrase.** It does something: `FindForm`,
`Invalidate`, `WriteLine`, `Adopt`. A method named for a noun is usually a
property that has not been written as one — see [§2.1](#21-a-property-or-a-method).

**A property is a noun, a noun phrase, or an adjective.** `Bounds`, `Parent`,
`Capacity`. It names the thing it gives back, because reading it is supposed to
feel like reading a field.

**A boolean is a question.** `Is`, `Has`, `Can`, `Should`, `Was` — `IsEmpty`,
`HasFocus`, `CanRead`, `IsInvisible`. A boolean named `Visible` is acceptable
where the adjective already reads as a state; a boolean named `Check` is not,
because it does not say which answer means what.

**An event is a verb in the tense it happened in.** `Click`, `Closing`,
`Closed`, `TextChanged`. The raiser is `On` + the event name, and is
`protected virtual void` — that pairing is described in
[forms/src/Control.sl](../forms/src/Control.sl) and is the shape every event in
this tree has.

**A method says what it acts on.** Microsoft's guidelines are the rule here:
a method is a verb phrase whose object is named — `BuildMenuBar`,
`ReleasePlatformItems`, `MeasureMenuItem`, `FindForm` — so that a call site
reads without the declaration beside it. `Build`, `Forget`, `Measure`, `Place`
and `Fire` name nothing a caller can predict.

**A single word is allowed only where .NET uses that word for the same
operation on the same kind of type.** It is .NET's vocabulary, not a
judgement about which words are clear enough:

| Kind of type | The single words that stay |
|---|---|
| a collection | `Add`, `Insert`, `Remove`, `RemoveAt`, `Clear`, `Contains`, `IndexOf`, `Sort`, `Reverse`, `Find` |
| a sequence, as LINQ | `Select`, `Where`, `Aggregate`, `Any`, `All`, `First`, `Last`, `Take`, `Skip`, `Count`, `Sum`, `Min`, `Max`, `Distinct`, `Concat`, `Zip` |
| a stream, file or socket | `Read`, `Write`, `Flush`, `Seek`, `Close`, `Open`, `Connect`, `Send`, `Receive`, `Accept`, `Listen`, `Bind` |
| a window or control | `Show`, `Hide`, `Close`, `Focus`, `Invalidate`, `Update`, `Refresh`, `Activate` |
| a lock, thread, timer or task | `Start`, `Stop`, `Wait`, `Join`, `Signal`, `Set`, `Reset`, `Release`, `Enter`, `Exit`, `Dispose` |
| any value | `Equals`, `CompareTo`, `Parse`, `TryParse` |

A word from the table is still wrong on a type it does not belong to: `Close`
on a stream is .NET's, `Close` on a tree node is not.

**A method is never past tense, an adjective or a noun.** `Clicked`, `Chosen`
and `Notified` are an `OnXxx` raiser or handler, or a real verb. `Font()`,
`Backend()` and `Separator()` are a property, a `CreateXxx` factory or a
constructor; `Size.Of` and `Point.At` are constructors or `FromXxx`.

**A field is named for the property it backs**: `_text` behind `Text`,
`_checked` behind `Checked`, never `_caption` or `_ticked`.

### 1.4a A name at module level carries no context, so it must supply its own

A member of a class is read with the class in front of it: `Cursor.Take`,
`Image.Find`, `Die.Range`. The type is half the name, and the short half is
allowed to be short because of it.

**A function at module level has no such half.** It is visible everywhere in
the module, it is a candidate wherever member lookup fails, and it will be read
at a call site with nothing beside it. So it has to say what it is on its own:

```
Fits(data, at, 40u)                      // fits what, inside what?
BytesRemainAt(data, at, 40u)             // says it

Hexadecimal(value)                       // of what, in what shape?
FormatHexadecimal(value)                 // says it

Load(path)                               // loads what, and answers what?
LoadDwarfOrComplain(path)                // says it
```

The rule: **at module level, a name is a verb phrase with its object in it**,
and a bare verb or a bare adjective is not enough. Inside a type the same name
may well be right -- `Find`, `Take`, `Range` are fine as members, because the
receiver supplies the noun.

This is not only taste. [§1.5](#15-two-collisions-the-standard-library-sets-up)
is the same problem with teeth: short module-level names are exactly the ones
that collide with the standard library's free verbs, and the collision is
silent. A module-level `Take` in a file that also imports
`Standard.Collections` is a question the reader has to answer and the binder
answers differently inside a lambda.

### 1.5 Two collisions the standard library sets up

`import Standard.Collections` brings roughly twenty short verbs into scope at
module level — `Take`, `Skip`, `Select`, `Where`, `Find`, `Any`, `All`,
`ForEach`. Because a free function is a candidate wherever member lookup fails,
two mistakes are easy and neither is loud:

- **A method of your own named after one of them** binds to the free function
  inside a lambda body, and to your method everywhere else. Write `this.` to
  settle it, or pick a different name.
- **`Fail` and `Ok` are `Result`'s case constructors** and are in scope
  everywhere. A method named `Fail` is never called, and the only sign is
  SL0222, *this expression has no effect*.

**Do not name a member after a case constructor or a collection verb.** The
compiler will not warn, and the failure looks like a logic bug.

---

## 2. Members

### 2.1 A property or a method

**If it takes no arguments, gives a value back, and has no side effect, it is a
property.**

```csharp
public nuint Count => _count;              // yes
public bool IsEmpty => _count == 0u;       // yes
public nuint Count() { return _count; }    // no
```

A property says *this is a fact about the object*; a method says *this does
something*. Writing a fact as a method costs the caller a pair of parentheses
that carry no information, and it costs the reader the question of whether the
call is cheap.

**It stays a method when any of those is untrue:**

- **It does work.** A call that walks a list, touches the filesystem or asks the
  platform is a method, however simple it looks from outside. `FindForm()`
  walks up the parent chain, so it is a method; `Parent` is a field read, so it
  is a property.
- **It can fail.** Anything returning `Result<T, TError>` is a method. A property
  that hands back a failure reads like a field and is not one.
- **It gives back something different each call.** `Random.NextULong()` is a
  method.
- **It has a side effect.** `Read()`, `MoveNext()`, `Clear()` are methods even
  where they return a value, because the object is not the same afterwards.

**`Count` is the property; `Count(predicate)` is the method.** Where both are
wanted, the no-argument form is the property and the overload that takes work to
do stays a method. They can coexist.

**Two exceptions, both of which are the language's rather than a judgement.**

- **A module-level function stays a function.** A property is a pair of
  accessors reached through an instance and a module has none, so
  `Env.ArgumentCount()`, `Threading.ProcessorCount()` and `Env.CurrentDirectory()` keep
  their parentheses however much they read like facts. Writing one as a
  property is SL0400.
- **`IsEmpty` is a property**, including on `String` and `StringBuilder`. It
  was the one exception here for a while, because those two get theirs from
  `Builtins.cs` and a builtin could only be a `FunctionSymbol`. Builtins can
  carry a `PropertySymbol` now, so the exception is gone and every `IsEmpty` in
  the tree agrees.

Everything has been converted: 328 declarations and the calls that reach them,
across the standard library, `forms/`, the IDE, the samples, the bindings and
the test cases.

### 2.2 Ordering inside a type

Constants, then fields, then constructors, then properties, then methods, then
nested types. Within each, public before protected before private, and static
before instance.

**A rule that is worth breaking for cohesion.** A property and the two methods
only it uses are easier to read together than correctly sorted apart. Where the
order is broken, the section comment says so — the `// ---- bounds` banners in
[forms/src/Control.sl](../forms/src/Control.sl) are that, and they are more use
than a strict sort would have been.

### 2.3 Visibility is written down

**Write the modifier even where it is the default.** `private` on a private
field, `internal` on an internal one. A reader should not have to remember what
a missing word means, and the existing tree's `WindowedControl? _owner;`, with
the underscore and no modifier, still leaves that question to the reader.

The exception is the `partial` halves of the compiler's `Binder`, where the
established file-local style is already consistent and uniform.

---

## 3. Layout

### 3.1 Braces on their own line

**Allman, in both languages.**

```csharp
public Form? FindForm()
{
    Control? walk = this;
    while (walk != null)
    {
        var here = (Control)walk;
        if (here is Form form)
        {
            return form;
        }

        walk = here.Parent;
    }

    return null;
}
```

This is the Microsoft convention, and the compiler's C# has always been written
this way. Stainless was not, and the two halves of one repository disagreeing
about something this visible is the kind of thing that makes the whole tree feel
unconsidered. One rule, both languages.

### 3.2 A body of one statement

A single statement under `if`, `else`, `for`, `foreach`, `while` or `do` is
written **without braces, on the next line, indented**:

```csharp
if (owner == null)
    return;

for (nuint i = 0u; i < arguments.Length; i++)
    total += arguments[i];
```

**Never on one line.** `if (owner == null) { return; }` packs a branch and its
consequence into a single line where a reader's eye expects one thing, and it
is the form this tree had most of. Both of these are wrong:

```csharp
if (owner == null) { return; }      // no
if (owner == null) return;          // no
```

**Braces come back as soon as anything else is true**: two statements, a body
that wraps over a line, or an `if` that has an `else` at all.

**An `if` with an `else` braces every arm**, however short they are. The
alternative is a rule about which single-statement arms may go bare, and the
dangling `else` is exactly the thing such a rule gets wrong — bracing the whole
chain costs two lines and settles it.

```csharp
if (found)
{
    _cache.Add(key, value);
    return value;
}
else
{
    return null;
}
```

**A `case` in a `switch` is not affected** — it is a label, and the statements
under it are indented without braces unless one declares a variable.

### 3.3 One-line members

The same idea on a member: a body of one expression is written with `=>`, not
as braces packed onto the declaration.

```csharp
public nuint Count => _count;                            // a property
public int Area() => _side * _side;                      // a method
public void Grow() => _side++;                           // void, equally
void Adopt(WindowedControl parent) => _owner = parent;

public nuint Count() { return _count; }                  // no
```

`=>` works on a method exactly as it does on a property
([§7.1](spec/07-functions-members.md#71-functions)): one that returns a value
returns the expression, and a `void` one evaluates it.

Where the body is more than one expression, or is a statement that is not one —
an `if`, a loop — the braces go on their own lines as anywhere else.

### 3.3a A run of equality tests on one value is a `switch`

**If three or more branches compare the same expression against constants, use
a `switch`.** Not a chain of `if`s, and not a chain of `else if`s.

```
// No.
if (form == FormData1) { reader.Skip(1u); return true; }
if (form == FormData2) { reader.Skip(2u); return true; }
if (form == FormData4 || form == FormRef4 || form == FormStrx4) { ... }

// Yes.
switch (form)
{
    case FormData1: reader.Skip(1u); return true;
    case FormData2: reader.Skip(2u); return true;

    case FormData4:
    case FormRef4:
    case FormStrx4:
        reader.Skip(4u);
        return true;
}
```

Three reasons, in the order they matter:

**It reads as the table it is.** A set of constants mapped to behaviour is a
table, and a `switch` is how this language writes one. Labels that share a body
stack above it, so the grouping is visible instead of living inside an `||`
chain the reader has to parse. A missing case is then a gap in a table rather
than a line that simply is not present.

**It is a jump and not a walk.** A chain is O(n) comparisons at run time and the
last case pays for all of them. That is invisible until the function is hot:
`ReadAttribute` in [debug/src/Dwarf/Info.sl](../debug/src/Dwarf/Info.sl) runs
once per attribute -- tens of thousands of times for one binary -- and its block
forms had been sitting at the bottom of forty comparisons.

**The compiler can see the set.** An `if` chain over constants is opaque; a
`switch` is a shape the binder knows, which is what makes exhaustiveness
checking possible at all -- see the variant switches in
[§2 of the spec](spec/02-types.md), where leaving a case out is SL0436.

The exception is a chain whose tests are not all the same question: ranges,
different operands, or conditions with side conditions attached. A `switch` that
has to be contorted into is worse than the chain it replaced.

### 3.4 Stepping by one

**`i++`, never `i += 1` and never `i = i + 1`.**

```csharp
for (nuint i = 0u; i < arguments.Length; i++)      // yes
for (nuint i = 0u; i < arguments.Length; i += 1u)  // no
```

`++` works on every writable place and every numeric type the language has,
`nuint` and pointers included — [§9.6](spec/09-statements-expressions.md#96-stepping-by-one)
is the whole rule. `i += 1u` additionally drags the literal's suffix into a line
that did not need it, and `i += 1` on a `nuint` is a conversion a reader has to
stop and check.

**`+=` is right when the step is not one.** `i += 2`, `offset += stride`.

**`for parallel` is no exception.** Its step is read as a stride before the
loop is split into ranges, and `i++` is a stride of one:

```csharp
for parallel (nuint i = 0u; i < pixels.Length; i++)
```

### 3.5 Whitespace

- **Four spaces**, never tabs.
- **One statement per line**, one declaration per line.
- **A blank line between members**, and between logical groups inside a long
  method. Not two.
- **No trailing whitespace**, and a single newline at end of file.
- **A space after a keyword and around a binary operator**; none between a
  method name and its `(`, and none inside brackets.

**Do not align declarations into columns.**

```csharp
WindowedControl? _owner;        // yes
Rectangle _area;
DockStyle _docking;

WindowedControl? _owner;        // no
Rectangle        _area;
DockStyle        _docking;
```

It looks tidy in the editor and costs a reflowed block every time a type is
renamed, which puts unrelated lines in a diff and unrelated names in
`git blame`. The tree had a good deal of this, and the layout pass removed it.

### 3.6 Line length

**Stop at 100 columns** for code; the tree's 99th percentile is 86 today, so
this is headroom rather than a target. **Wrap prose in comments at 80**, which
is what every `///` block here already does.

A call that does not fit breaks after the opening `(` with its arguments
indented once, or breaks between chained calls with each `.` at the same
indent:

```csharp
names.Where((n) => n.ByteLength() > 3u)
     .Select(Upper)
     .ToArray()
```

### 3.7 `var`

**Use `var` when the right-hand side already says the type** — a `new`, a cast,
a literal. Write the type out when the expression does not say it, which is most
calls:

```csharp
var here = (Control)walk;                  // the cast says it
var open = new List<Form>();               // the new says it
Result<Image, ImageError> loaded = Image.FromFile(path);   // nothing else would
```

This is the Microsoft convention's position and it is worth keeping, because
there is no IDE in the loop for most of this tree — the `///` reference is
generated from the source and a reviewer reads it as text.

---

## 4. Comments

### 4.1 Write one only where the code needs clarification

**A comment MUST earn its place.** Write one where the code cannot say the
thing itself: a constraint imposed from outside, a unit, an ordering that
matters, a reason the obvious alternative is wrong.

**Do not narrate.** A comment restating the line under it MUST NOT be written.
It is one more thing to keep true, and it goes stale first.

```csharp
counted++;                      // increment counted          -- no
inset = height / 5;             // clears the line above      -- yes
```

**Do not write history.** A comment MUST NOT describe a bug that was fixed, an
earlier version of the code, or what someone once got wrong. The reader needs
the code as it is. History belongs in `git log`, where it is attached to the
change that made it and does not have to be maintained.

```csharp
// This used to read the size and trust it, which broke /proc.    -- no
// The reported size is a hint; /proc reports zero and then gives
// kilobytes, so read to the end.                                 -- yes
```

### 4.2 Short sentences

**A comment SHOULD be one short sentence per point.** Two short sentences beat
one long one. A paragraph of reasoning in a `//` block is nearly always three
sentences that should have been one.

Bold lead-ins, rhetorical questions and asides are narration. Drop them.

### 4.3 RFC 2119 keywords for obligations

**Where a comment states an obligation, it MUST use the
[RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) keyword** — MUST, MUST NOT,
SHOULD, SHOULD NOT, MAY — in capitals. That is what separates a rule a caller
has to follow from a remark about the code.

```csharp
/// Every call MUST come from the thread that launched the target.
/// Callers MAY pass null, which means the host's own.
/// A derived class SHOULD call base first.
```

Use them for obligations and nothing else. A comment that explains rather than
requires is written in plain words.

### 4.4 `///` is the reference

**A `///` block states what a caller has to know before using the
declaration** — what it does, what it costs, how it fails, what it does *not*
do, and what the caller MUST do. It is the standard-library reference,
generated by `stainless doc`, so it is read far more often than the code under
it. The same rules apply: short sentences, no narration, no history.

**A block is Markdown**, and its first paragraph is the summary. Backticks for
an identifier, `**Bold claim.**` to open a paragraph, four spaces for a sample:
that is the house style and it needs no markup to say so.

**`@tags` are for what Markdown cannot say** — which parameter a sentence is
about, what a call answers, which failures it can report. They are optional,
and a block that uses none is a summary and nothing else:

```csharp
/// The whole file as text.
///
/// **Reads to the end rather than to the size**, because a file under `/proc`
/// reports zero and then hands over kilobytes.
///
/// @param path  where to read from, absolute or relative to the working
///              directory
/// @returns the contents, decoded as UTF-8
/// @failure IOError.NotFound  there is no file at that path
/// @see File.WriteAllText
public Result<String, IOError> ReadAllText(String path)
```

The tags are `@param`, `@typeparam`, `@returns`, `@value`, `@remarks`,
`@example`, `@failure`, `@see`, `@seealso` and `@inheritdoc` — .NET's set,
with `@failure` in place of `<exception>` because nothing is thrown here.
[§1.7 of the specification](spec/01-modules.md#17--documentation-blocks) is the
whole of it.

**A tag is checked.** A `@param` naming no parameter, a `@failure` naming a
case the error type does not have, a `cref` that resolves to nothing: each is a
warning where it was written. **Document all of a declaration's parameters or
none** — half of them is SL0741, for the same reason C# reports CS1573.

### 4.5 Layout

**A banner comment divides a long file into sections.** The existing
`// ====== the colour` and `// ------ bounds` forms are both in use; keep
whichever the file already uses rather than mixing them.

**Prose uses em dashes, not `--`.** A patch script that matches on `--` will
fail against text that uses `—`; check which is there before writing the
pattern.

### 4.6 Commit messages

**The subject is imperative and names the change**: *Read a file to its end
rather than to its length*, not *Fixed reading files* and not *The reader was
trusting the size*. Under 72 characters.

**The body carries only what the diff cannot show** — a measurement, a
platform constraint, a rejected alternative and why, the reason a test is
shaped as it is. If the body restates the diff, leave it out. Most commits
need no body.

---

## 5. Files

- **One module per file**, named for what it holds. `stdlib/Collections.sl`
  declares `module Standard.Collections`.
- **Every source file carries its licence header** — the GPL-with-runtime-
  exception block for `stdlib/`, `runtime/` and `forms/`, the
  `// SPDX-License-Identifier: 0BSD` line for `samples/`. Copy the header from a
  neighbour rather than writing a new one.
- **`module` first, then `import`s, then the code.** Imports are not sorted
  mechanically: `Standard.*` first, then the platform bindings, then the
  program's own.
- **A new file under `stdlib/` needs `dotnet build` before anything can import
  it**, because the standard library is an embedded resource picked up by a
  wildcard. The same is true of a change to `runtime/*.c`.

---

## 6. Stainless-specific

### 6.1 Failure

**A function that can fail returns `Result<T, TError>`**, and the error is an `enum`
of that module's own — `ImageError`, `IOError`, `ConvertError`. There are no
exceptions in the language and nothing is signalled by a sentinel return.

**`Optional<T>` is for absence, `Result<T, TError>` is for failure.** A lookup that
found nothing is an `Optional`; a lookup that could not be performed is a
`Result`.

### 6.2 `where` is not a parameter name

It is read as the start of a generic constraint, and the error lands a long way
from the cause. The same care is worth taking with any contextual keyword.

### 6.3 Nullability is written down

`WindowedControl?` means it can be null and the compiler will hold you to it.
A reference that is not marked is one a reader may assume is there — do not mark
a type nullable to silence a diagnostic you have not understood.

---

## 7. What is enforced

[.editorconfig](../.editorconfig) holds the C# half — brace placement, the
`_camelCase` and `s_camelCase` field rules, `var` usage, spacing — and
[Directory.Build.props](../Directory.Build.props) sets
`EnforceCodeStyleInBuild`, so the build checks some of them rather than leaving
all of it to whichever IDE someone happens to have open. The compiler's C#
already satisfies every rule there, which is what made turning it on free.

**Not all of that file reaches the build.** The naming rules, the ban on
`this.` and the predefined-type rules are at `warning` and are reported by
`dotnet build`, as warnings rather than errors. Brace placement and spacing are
formatting options with no `IDE0055` severity set, and the `var` and
expression-body preferences are at `suggestion`, so those three are applied by
an editor and not checked by the build.

**The Stainless half is not machine-enforced yet.** There is no formatter for
`.sl` and writing one is its own piece of work; until then this document is the
rule and review is what applies it. A `stainless format` subcommand is the
obvious home for it, and [TODO.md](../TODO.md) carries the note.

---

## 8. Bringing the tree to this

The tree has been brought to this, in passes, each its own commit so that a
reformat never travelled with a change of behaviour:

1. **Layout** — Allman, one-line bodies, `i++`, column alignment removed.
2. **Fields** — the `_`, `s_` and `t_` prefixes.
3. **Members** — the zero-argument methods that were facts, and `TKey`,
   `TValue` and `TError` in place of `K`, `V` and `E`. This one changed the
   public surface, so it moved the specification, the generated reference, the
   samples and the test cases with it.

**What is left is the part a script cannot do**, and there are two of them.

§1.4 — whether a name promises what the thing does — is unfinished: `Update`,
`Process`, `Handle`, `Get` and `Build` are still on members whose names do not
say what they update or build.

§4 is newer than most of the tree, so narration, history and plain-words
obligations are everywhere. Deciding whether a comment earns its place is
exactly what a script cannot do. Both want reading, one module at a time.

**Both suites run before each commit.** They ask different questions, and the
unit tests hold rules the end-to-end suite cannot see — a new sample has to be
listed in `SampleTests`, and a documented `SL####` has to be pinned by a case.
