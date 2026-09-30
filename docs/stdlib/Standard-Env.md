# Standard.Env

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

What the program was started with and what surrounds it.

The arguments are also reachable as `Main(String[] args)`, which is the
better way to read them -- a function that takes what it needs beats one
that goes looking. These are for the code that is nowhere near `Main`.

## Contents

**Functions** &nbsp; [ArgumentCount](#argumentcount-function) &middot; [CurrentDirectory](#currentdirectory-function) &middot; [GetArgument](#getargument-function) &middot; [GetArguments](#getarguments-function) &middot; [GetEnvironmentVariable](#getenvironmentvariable-function) &middot; [GetEnvironmentVariableNames](#getenvironmentvariablenames-function) &middot; [GetEnvironmentVariableOrDefault](#getenvironmentvariableordefault-function) &middot; [GetProcessPath](#getprocesspath-function) &middot; [HasEnvironmentVariable](#hasenvironmentvariable-function) &middot; [RemoveEnvironmentVariable](#removeenvironmentvariable-function) &middot; [SetCurrentDirectory](#setcurrentdirectory-function) &middot; [SetEnvironmentVariable](#setenvironmentvariable-function)

## Functions

### ArgumentCount *function*

```
nuint ArgumentCount()
```

How many arguments the program was given, not counting its own name.

<sub>[stdlib/Env.sl:87](../../stdlib/Env.sl#L87)</sub>

### CurrentDirectory *function*

```
String CurrentDirectory()
```

The directory relative paths are resolved against.

**See also** &nbsp; [Env.SetCurrentDirectory](#setcurrentdirectory-function)

<sub>[stdlib/Env.sl:292](../../stdlib/Env.sl#L292)</sub>

### GetArgument *function*

```
String GetArgument(nuint index)
```

One argument, counting from zero. Aborts past the end, as an array does.

<sub>[stdlib/Env.sl:90](../../stdlib/Env.sl#L90)</sub>

### GetArguments *function*

```
String[] GetArguments()
```

Every argument, as an array. The same thing `Main(String[] args)` receives.

<sub>[stdlib/Env.sl:98](../../stdlib/Env.sl#L98)</sub>

### GetEnvironmentVariable *function*

```
String? GetEnvironmentVariable(String name)
```

A variable's value, or null when it is not set.

Null rather than empty, because "not set" and "set to nothing" are
different states and both platforms can tell them apart.
`GetEnvironmentVariableOrDefault` is what
most callers want.

**See also** &nbsp; [Env.GetEnvironmentVariableOrDefault](#getenvironmentvariableordefault-function)

<sub>[stdlib/Env.sl:116](../../stdlib/Env.sl#L116)</sub>

### GetEnvironmentVariableNames *function*

```
String[] GetEnvironmentVariableNames()
```

The name of every variable, in whatever order the platform keeps them.

The block is one run of NUL-terminated wide strings ending in an empty one.
A name beginning with `=` is Windows' per-drive working directory (`=C:`),
which is not a variable anybody set.

<sub>[stdlib/Env.sl:214](../../stdlib/Env.sl#L214)</sub>

### GetEnvironmentVariableOrDefault *function*

```
String GetEnvironmentVariableOrDefault(String name, String fallback)
```

A variable's value, or `fallback` when it is not set.

**Parameters**

- `name` -- the variable to read
- `fallback` -- what to answer when there is no such variable

**See also** &nbsp; [Env.GetEnvironmentVariable](#getenvironmentvariable-function)

<sub>[stdlib/Env.sl:159](../../stdlib/Env.sl#L159)</sub>

### GetProcessPath *function*

```
String GetProcessPath()
```

The program's own path, as the operating system gave it. That is not
necessarily where the executable is: a shell may pass a bare name, and on
Linux nothing guarantees any relationship at all.

<sub>[stdlib/Env.sl:103](../../stdlib/Env.sl#L103)</sub>

### HasEnvironmentVariable *function*

```
bool HasEnvironmentVariable(String name)
```

Whether a variable is set, whatever it is set to.

<sub>[stdlib/Env.sl:168](../../stdlib/Env.sl#L168)</sub>

### RemoveEnvironmentVariable *function*

```
bool RemoveEnvironmentVariable(String name)
```

Removes a variable, reporting whether the platform accepted it. Removing
one that was never set is not a failure.

**See also** &nbsp; [Env.SetEnvironmentVariable](#setenvironmentvariable-function)

<sub>[stdlib/Env.sl:189](../../stdlib/Env.sl#L189)</sub>

### SetCurrentDirectory *function*

```
bool SetCurrentDirectory(String path)
```

Changes it, reporting whether the platform accepted it. It fails when the
path is not a directory, or is not reachable.

**See also** &nbsp; [Env.CurrentDirectory](#currentdirectory-function)

<sub>[stdlib/Env.sl:312](../../stdlib/Env.sl#L312)</sub>

### SetEnvironmentVariable *function*

```
bool SetEnvironmentVariable(String name, String value)
```

Sets a variable for this process and anything it starts afterwards.

It does not reach the shell that started this program: a process's
environment is its own, and a child gets a copy. Reports whether the
platform accepted it.

An empty value leaves the variable set and empty, on both platforms, and
`GetEnvironmentVariable` answers with the empty string rather than null.

**Parameters**

- `name` -- the variable to set
- `value` -- what to set it to

**See also** &nbsp; [Env.RemoveEnvironmentVariable](#removeenvironmentvariable-function)

<sub>[stdlib/Env.sl:182](../../stdlib/Env.sl#L182)</sub>

