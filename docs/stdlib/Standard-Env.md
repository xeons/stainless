# Standard.Env

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

What the program was started with and what surrounds it.

The arguments are also reachable as `Main(String[] args)`, which is the
better way to read them -- a function that takes what it needs beats one
that goes looking. These are for the code that is nowhere near `Main`.

## Contents

**Functions** &nbsp; [ArgumentAt](#argumentat-function) &middot; [ArgumentCount](#argumentcount-function) &middot; [Arguments](#arguments-function) &middot; [CurrentDirectory](#currentdirectory-function) &middot; [Get](#get-function) &middot; [GetOr](#getor-function) &middot; [Has](#has-function) &middot; [Names](#names-function) &middot; [Program](#program-function) &middot; [Remove](#remove-function) &middot; [Set](#set-function) &middot; [SetCurrentDirectory](#setcurrentdirectory-function)

## Functions

### ArgumentAt *function*

```
String ArgumentAt(nuint index)
```

One argument, counting from zero. Aborts past the end, as an array does.

<sub>[stdlib/Env.sl:89](../../stdlib/Env.sl#L89)</sub>

### ArgumentCount *function*

```
nuint ArgumentCount()
```

How many arguments the program was given, not counting its own name.

<sub>[stdlib/Env.sl:86](../../stdlib/Env.sl#L86)</sub>

### Arguments *function*

```
String[] Arguments()
```

Every argument, as an array. The same thing `Main(String[] args)` receives.

<sub>[stdlib/Env.sl:97](../../stdlib/Env.sl#L97)</sub>

### CurrentDirectory *function*

```
String CurrentDirectory()
```

The directory relative paths are resolved against.

<sub>[stdlib/Env.sl:282](../../stdlib/Env.sl#L282)</sub>

### Get *function*

```
String? Get(String name)
```

A variable's value, or null when it is not set.

Null rather than empty, because "not set" and "set to nothing" are
different states and both platforms can tell them apart. `GetOr` is what
most callers want.

<sub>[stdlib/Env.sl:119](../../stdlib/Env.sl#L119)</sub>

### GetOr *function*

```
String GetOr(String name, String fallback)
```

A variable's value, or `fallback` when it is not set.

<sub>[stdlib/Env.sl:158](../../stdlib/Env.sl#L158)</sub>

### Has *function*

```
bool Has(String name)
```

Whether a variable is set, whatever it is set to.

<sub>[stdlib/Env.sl:167](../../stdlib/Env.sl#L167)</sub>

### Names *function*

```
String[] Names()
```

The name of every variable, in whatever order the platform keeps them.

The block is one run of NUL-terminated wide strings ending in an empty one.
A name beginning with `=` is Windows' per-drive working directory (`=C:`),
which is not a variable anybody set.

<sub>[stdlib/Env.sl:206](../../stdlib/Env.sl#L206)</sub>

### Program *function*

```
String Program()
```

The program's own path, as the operating system gave it. That is not
necessarily where the executable is: a shell may pass a bare name, and on
Linux nothing guarantees any relationship at all.

<sub>[stdlib/Env.sl:109](../../stdlib/Env.sl#L109)</sub>

### Remove *function*

```
bool Remove(String name)
```

Removes a variable, reporting whether the platform accepted it. Removing
one that was never set is not a failure.

<sub>[stdlib/Env.sl:181](../../stdlib/Env.sl#L181)</sub>

### Set *function*

```
bool Set(String name, String value)
```

Sets a variable for this process and anything it starts afterwards.

It does not reach the shell that started this program: a process's
environment is its own, and a child gets a copy. Reports whether the
platform accepted it.

An empty value leaves the variable set and empty, on both platforms, and
`Get` answers with the empty string rather than null.

<sub>[stdlib/Env.sl:177](../../stdlib/Env.sl#L177)</sub>

### SetCurrentDirectory *function*

```
bool SetCurrentDirectory(String path)
```

Changes it, reporting whether the platform accepted it. It fails when the
path is not a directory, or is not reachable.

<sub>[stdlib/Env.sl:300](../../stdlib/Env.sl#L300)</sub>

