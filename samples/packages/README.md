<!-- SPDX-License-Identifier: 0BSD -->
# A program and the package it depends on

Two directories, each with a `stainless.json`, and one of them depends on the
other:

```
stainless run                  # from samples/packages/app
```

That is the whole command. No paths, no `-o`, no list of the other package's
files — the project file says what this program is made of, and the build reads
it.

## What is here

[`shapes/`](shapes) is a library package. Its project file says three things:

```json
{ "name": "shapes", "version": "1.0.0", "kind": "library", "sources": ["src"] }
```

[`app/`](app) is a program that uses it:

```json
{
  "name": "app",
  "version": "0.1.0",
  "kind": "executable",
  "sources": ["src"],
  "dependencies": { "shapes": { "path": "../shapes", "version": "^1.0" } }
}
```

`^1.0` is a caret range: any 1.x from 1.0 up, but not 2.0. A bare `"1.0"` means
the same thing — the caret is what a version means unless something else is
said, and `"=1.0.0"` is how to pin one exactly.

[`app/stainless.lock`](app/stainless.lock) is what resolution decided, and it is
committed on purpose. The project file says what would do; the lock says what
was chosen, down to the digest of the files that were read. Two people with the
same lock build the same program.

## The two ways to depend on something

The dependency above has no `link`, so it is a **source** dependency:
`shapes`'s files join this program's compilation, exactly as though they had
been listed on the command line. That is the model this language already has —
one program, no headers, whole-program binding — and it is why generics,
interfaces and variants all work across it.

Adding `"link": "shared"` makes it a **binary** dependency instead:

```json
"shapes": { "path": "../shapes", "version": "^1.0", "link": "shared" }
```

Now `shapes` is built once as a real shared library, `app` binds against its
metadata, and `build/` ends up holding `shapes.dll`, its import library, its
`.slmod` and the shared runtime both sides link:

```
build/app.exe  build/shapes.dll  build/shapes.lib  build/shapes.slmod
build/stainless-rt.dll
```

Try it: the program prints the same thing either way. What differs is what was
built, and what a boundary costs — a `.slmod` describes layouts and signatures,
so generics and interfaces do not cross one. The compiler says so where the
library is built rather than leaving the consumer to find a public type missing.

## What the version is actually for

A version number is a promise a person makes, and people are wrong about them.
So the `.slmod` also carries a digest taken over the layouts themselves, and the
lock records it. Change a field in `Canvas` without changing `shapes`'s version,
build again, and the build says so by name:

```
note: 'shapes' 1.0.0 describes a different surface than the last build of 1.0.0
      did: Shapes.Canvas. A version number is a promise about exactly this ...
```

Adding a new function is not a broken promise and says nothing. Moving a field
that something already compiled against is, and the linker cannot tell, because
the symbols did not change. That is the case the digest exists for.
