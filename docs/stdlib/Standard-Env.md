# Standard.Env

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

What the program was started with and what surrounds it.

The arguments are also reachable as `Main(String[] args)`, which is the
better way to read them -- a function that takes what it needs beats one
that goes looking. These are for the code that is nowhere near `Main`.

## Contents

**Functions** &nbsp; [ArgumentCount](#argumentcount-function) &middot; [CurrentDirectory](#currentdirectory-function) &middot; [GetArgument](#getargument-function) &middot; [GetArguments](#getarguments-function) &middot; [GetVariable](#getvariable-function) &middot; [GetVariableNames](#getvariablenames-function) &middot; [GetVariableOrDefault](#getvariableordefault-function) &middot; [HasVariable](#hasvariable-function) &middot; [ProgramPath](#programpath-function) &middot; [RemoveVariable](#removevariable-function) &middot; [SetCurrentDirectory](#setcurrentdirectory-function) &middot; [SetVariable](#setvariable-function)

## Functions

### ArgumentCount *function*

```
nuint ArgumentCount()
```

How many arguments the program was given, not counting its own name.

<sub>[stdlib/Env.sl:86](../../stdlib/Env.sl#L86)</sub>

### CurrentDirectory *function*

```
String CurrentDirectory()
```

The directory relative paths are resolved against.

<sub>[stdlib/Env.sl:282](../../stdlib/Env.sl#L282)</sub>

### GetArgument *function*

```
String GetArgument(nuint index)
```

One argument, counting from zero. Aborts past the end, as an array does.

<sub>[stdlib/Env.sl:89](../../stdlib/Env.sl#L89)</sub>

### GetArguments *function*

```
String[] GetArguments()
```

Every argument, as an array. The same thing `Main(String[] args)` receives.

<sub>[stdlib/Env.sl:97](../../stdlib/Env.sl#L97)</sub>

### GetVariable *function*

```
String? GetVariable(String name)
```

A variable's value, or null when it is not set.

Null rather than empty, because "not set" and "set to nothing" are
different states and both platforms can tell them apart. `GetVariableOrDefault` is what
most callers want.

<sub>[stdlib/Env.sl:119](../../stdlib/Env.sl#L119)</sub>

### GetVariableNames *function*

```
String[] GetVariableNames()
```

The name of every variable, in whatever order the platform keeps them.

The block is one run of NUL-terminated wide strings ending in an empty one.
A name beginning with `=` is Windows' per-drive working directory (`=C:`),
which is not a variable anybody set.

<sub>[stdlib/Env.sl:206](../../stdlib/Env.sl#L206)</sub>

### GetVariableOrDefault *function*

```
String GetVariableOrDefault(String name, String fallback)
```

A variable's value, or `fallback` when it is not set.

<sub>[stdlib/Env.sl:158](../../stdlib/Env.sl#L158)</sub>

### HasVariable *function*

```
bool HasVariable(String name)
```

Whether a variable is set, whatever it is set to.

<sub>[stdlib/Env.sl:167](../../stdlib/Env.sl#L167)</sub>

### ProgramPath *function*

```
String ProgramPath()
```

The program's own path, as the operating system gave it. That is not
necessarily where the executable is: a shell may pass a bare name, and on
Linux nothing guarantees any relationship at all.

<sub>[stdlib/Env.sl:109](../../stdlib/Env.sl#L109)</sub>

### RemoveVariable *function*

```
bool RemoveVariable(String name)
```

Removes a variable, reporting whether the platform accepted it. Removing
one that was never set is not a failure.

<sub>[stdlib/Env.sl:181](../../stdlib/Env.sl#L181)</sub>

### SetCurrentDirectory *function*

```
bool SetCurrentDirectory(String path)
```

Changes it, reporting whether the platform accepted it. It fails when the
path is not a directory, or is not reachable.

<sub>[stdlib/Env.sl:300](../../stdlib/Env.sl#L300)</sub>

### SetVariable *function*

```
bool SetVariable(String name, String value)
```

Sets a variable for this process and anything it starts afterwards.

It does not reach the shell that started this program: a process's
environment is its own, and a child gets a copy. Reports whether the
platform accepted it.

An empty value leaves the variable set and empty, on both platforms, and
`GetVariable` answers with the empty string rather than null.

<sub>[stdlib/Env.sl:177](../../stdlib/Env.sl#L177)</sub>

