<sub>[Stainless](../../README.md) &rsaquo; [Language specification](index.md)</sub>

# 1. Modules

Modules work like C# namespaces, with one addition: an unmarked declaration is
private to its module, so a module is also the unit of encapsulation.

## 1.1 Every file names its module

```csharp
module Shop.Catalog;
```

This is required — a file that does not say which module it belongs to is an
error. The name is never inferred from the file's path:

```
error[SL0332]: this file does not say which module it belongs to; start it with
a declaration such as 'module App.Thing;'
```

The compiler never looks at where a file sits. Folders are a convention for
people, so moving a file cannot change what its code means, and the same
sources compile identically however the build is invoked.

> Dots do not nest. `Shop.Catalog` and `Shop` are unrelated names that happen to
> share a prefix; importing `Shop` would not reach `Shop.Catalog`, and there is
> no such thing as a parent module.

## 1.2 A module may span files

Several files may name the same module and merge into it:

```csharp
// Catalog/Books.sl
module Shop.Catalog;

public class Book { ... }
String Decorate(String text) { ... }        // not public

// Catalog/Subscriptions.sl
module Shop.Catalog;

public class Subscription
{
    public String Label() { return Decorate(name); }   // sees it; same module
}
```

Nothing is imported between them, and order does not matter: they are one
module that happens to be written in two places.

This does not compromise the no-header property, which comes from resolving
every name in the program before checking any body — not from any one-file
rule.

### 1.2.1 And so may a type

A type may be declared more than once inside its own module, and the
declarations are one type:

```csharp
public class Shape
{
    public int Sides;                       // the shape
}

public class Shape
{
    public int Corners() { return Sides; }  // and the behaviour
}
```

The rule is narrower than C#'s `partial`, and the difference is the point. The
**first declaration settles what the type is** — its kind, its fields, and what
it derives from. A later one may add methods and properties and nothing else:

| In a later declaration | |
|---|---|
| a method or a property | added |
| a field | SL0552 — the layout belongs to the declaration that has the fields |
| a base or interface list | SL0551 — the dispatch tables are built from the first |
| a different kind | SL0550 — every declaration must agree about what it is |

No `partial` keyword marks either one. There is nothing for it to prevent: a
second declaration of a name in the same module used to be an error and is now
this, and a name from *another* module was never reachable to redeclare.

What this exists for is `String`. It is intrinsic — the runtime owns its layout
and its allocation, and the compiler creates the symbol before any source is
read — and until this rule existed, every method it had was a C function
declared in the compiler. Now `Standard.Text` declares `String` a second time
and writes the rest in Stainless ([§3.2](03-text.md#32-members)). The same door is open to any module for
its own types, which is why the rule is stated in general terms rather than as a
concession to the standard library.

## 1.3 The module is the unit of visibility

| Declaration | Visible to |
|---|---|
| `public class Book` | its module, and anything that can name the module |
| `class Book` | its module only, across all of the module's files |
| `protected int pages` | its class, and anything deriving from it, wherever that is |

The second row is C#'s `internal`, with the module playing the part of the
assembly. There is nothing else — no friend declarations, no export lists, and
no file-level privacy (C# only gained `file` in version 11).

Members follow the same rule: a field or method needs `public` for another
module to touch it. `protected` ([§2.4.3](02-types.md#243-inheritance)) is the one addition, and
the only visibility that crosses a module boundary without being public: a base
class handing something to its derived classes and to nobody else is the whole
of what the word is for. It adds to module privacy rather than replacing it, so
a `protected` member is still reachable inside its own module, and a private one
is not reachable from a derived class in another module however far down.

## 1.4 `import` adds names; it never grants access

```csharp
import Shop.Pricing;
```

After that line, every **public** member of `Shop.Pricing` can be named three
ways:

| Form | Example |
|---|---|
| bare | `Money`, `Cents(500)` |
| by last segment | `Pricing.Money`, `Pricing.Cents(500)` |
| fully qualified | `Shop.Pricing.Money`, `Shop.Pricing.Cents(500)` |

**The fully qualified form needs no import at all.** Qualification names the
module directly, so this is legal in a file that imports nothing:

```csharp
var boxed = new Shop.Bundles.Bundle("Starter set", 2);
```

An import is therefore a convenience for shortening names, not a permission
check. What you may touch is decided entirely by `public`.

**Imports are per file, not per module**, exactly as `using` is in C#. Two files
of one module may import different things, and adding an import to one of them
cannot quietly change how the other resolves a name.

## 1.5 Aliases

```csharp
import Shop.Pricing as Money;

Money.Format(total)
```

An alias *adds* a way to name the module. It does not remove the others, so
bare names and the full name still work after aliasing — unlike C#, where
`using X = A.B;` replaces unqualified access rather than adding to it.

**A type gets one with `using`**, which is free here because `import` took the
job C# gives that word:

```csharp
public using Handle = void*;
public using Count  = nuint;
public using Size   = Count;        // an alias may name another
```

An alias **is** the type it names. There is no wrapper, no conversion and
nothing at run time: a `Count` is a `nuint` and a `nuint` is a `Count`, and a
diagnostic names the underlying type because that is the type there is. What it
buys is a signature that says what it is for.

It is a module-level declaration, like a type, and `public` makes it visible to
importers the same way. An alias inside a type is refused (SL0525): a module is
what this language has instead of a namespace, and that is where a name lives.

A ring of aliases names no type, and is refused whether or not anything uses it:

```
error[SL0522]: 'Ring' is defined in terms of itself, so it names no type
```

**Distinctness comes from the type, not the alias** — see [§2.2.2](02-types.md#222-struct-hwnd__--a-type-declared-and-not-laid-out).

## 1.6 Ambiguity

If two imported modules both export a type called `Buffer`, using it bare is an
error rather than a silent pick:

```
error[SL0273]: 'Buffer' is ambiguous between 'Net.Buffer' and 'Disk.Buffer';
qualify it with its module name
```

Qualify it, or alias one of the modules.

## 1.7 What is automatic

Two modules are imported into every file without being asked for.

`Standard.Text`, because a string literal produces a `String` whether the
program mentioned one or not.

`Standard`, because what lives there is the language's own vocabulary rather
than a library: `Result<T, TError>` ([§2.8](02-types.md#28-resultt-terror--how-a-function-fails)) and the markers `[Flags]`, `[Packed]` and
`[Align]`, each of which is a rule about a declaration rather than a dependency
on one. Requiring an import for them would make a rule look like a library.

Everything else is requested. `Standard.Console` is not automatic — printing is
a choice — and neither is `Standard.Reflection`, so `[Reflect]` needs an import
like any other name.

## 1.8 `///` documentation blocks

A run of `///` lines documents the declaration under it. The marker and one
following space are removed, the lines are joined, and what is left is the
block. A blank line or an ordinary `//` comment between the run and the
declaration ends the run, and the block then documents nothing.

**A block is Markdown.** It is written as Markdown and `stainless doc` emits
Markdown, so there is no third syntax in the middle: a backtick is code, `**`
is bold, an indented or fenced block is a sample, and a list is a list.

**Everything before the first tag is the summary**, so a block with no tags is
a summary and nothing else.

### 1.8.1 `@tags`

A line whose first character is `@`, followed by letters, opens a tag. It runs
until the next tag or the end of the block, so a description wraps like any
other prose. **An indented `@` is text**, which is what keeps a code sample —
and an address, or a decorated symbol such as `_LoadLibraryA@4` — from being
read as markup.

| Tag | What it says | .NET's |
|---|---|---|
| `@param name` | what one parameter is | `<param>` |
| `@typeparam T` | what one type parameter stands for | `<typeparam>` |
| `@returns` | what the call answers | `<returns>` |
| `@value` | what a property or field holds | `<value>` |
| `@remarks` | an aside, after the summary | `<remarks>` |
| `@example` | a sample, kept exactly as written | `<example>` |
| `@failure Error.Case` | one failure a `Result` can carry | `<exception>` |
| `@see Name` | a pointer, rendered as a link | `<see>` |
| `@seealso Name` | the same, at the end | `<seealso>` |
| `@inheritdoc [Name]` | the block from what this overrides | `<inheritdoc>` |

```csharp
/// The whole file as text.
///
/// @param path  where to read from, absolute or relative to the working
///              directory
/// @returns the contents, decoded as UTF-8
/// @failure IOError.NotFound  there is no file at that path
/// @failure IOError.NoSpace   the disk filled up while reading
/// @see File.WriteAllText
public Result<String, IOError> ReadAllText(String path)
```

**`@failure` is what this language has in place of `<exception>`.** Nothing is
thrown here, so there is no exception to document; a call that can fail says so
in its return type, and `@failure` names the cases it can answer with. Both
shapes count: an operation that produces something returns
`Result<T, TError>` ([§2.8](02-types.md#28-resultt-terror--how-a-function-fails))
and the cases are `TError`'s, and one that produces nothing returns the error
itself with `None` for success, as most of `Standard.File` does. The error
type's own name may be written in front of the case or left off.

**A `@failure` that names no case of that type is SL0744**, and a tag on a
declaration that reports no failure at all is the same code. What is *not*
checked is whether the case can actually occur: the compiler knows the name
exists and no more, so the claim is still the author's.

**One spelling of each.** A word that is nearly a tag — `@summary`, `@return`,
`@throws` — is an unknown tag (SL0739) rather than a second way to write one,
and the diagnostic says what to write instead.

### 1.8.2 A tag is checked

Every tag makes a claim the compiler has already resolved for itself, so every
tag is checked against the declaration under it. Each is a warning: a mistake
in a block is a mistake in prose, never a reason to refuse the program.

```
warning[SL0740]: 'ReadAllText' has no parameter named 'pth'; it has 'path'
warning[SL0741]: 'Add' documents some of its parameters and not 'b'; document
all of them or none
warning[SL0742]: 'Add' has no type parameter named 'T'; it takes none
warning[SL0743]: '@value' says nothing about 'ReadAllText'; it belongs on a
property or a field
warning[SL0744]: 'IOError' has no case named 'Vanished'; it has 'None',
'NotFound' and 'NoSpace'
warning[SL0745]: 'Standard.NoSuchModule' is not a type, a member or a module
this file can see
```

SL0741 is C#'s CS1573 and exists for its reason: a parameter left out of a
documented set reads as an oversight, and nothing else says whether it is.

**A `cref` is a name, resolved the way a name in code is.** `@see Substring`,
`@see String.Substring` and `@see Standard.Text.String.Substring` reach the
same member; the shortest one that is clear where it stands is the one to
write. It is not an overload: `@see Text.FromInteger` names all three of them,
which is what a reader following it wants.

## 1.9 Order never matters

Not within a file, and not across them. The compiler resolves every name in the
program before checking any body, so these are all fine:

```csharp
int Main()
{
    return Later();          // declared below
}

int Later() => 0;
```

A module may be compiled before the module it depends on, and files may be
given to the compiler in any order.

---

<sub>[&larr; Contents](index.md) &nbsp;&middot;&nbsp; [Types &rarr;](02-types.md)</sub>
