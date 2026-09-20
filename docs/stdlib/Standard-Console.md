# Standard.Console

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

Standard input and output, as text.

Bytes cross unchanged in both directions. A `String` is already UTF-8, so
nothing is transcoded on the way out, and input is read as bytes and taken
to be UTF-8 -- which is what a program piped a UTF-8 file needs, and is
wrong for a Windows console typed into by hand, where the active code page
arrives instead. Reading typed non-ASCII there wants `ReadConsoleW`.

This module is not imported automatically. Printing is a choice, and a
program that never prints has no reason to carry `Write` in scope.

## Contents

**Functions** &nbsp; [AtEnd](#atend-function) &middot; [Flush](#flush-function) &middot; [ReadLine](#readline-function) &middot; [ReadToEnd](#readtoend-function) &middot; [Write](#write-function) &middot; [WriteError](#writeerror-function) &middot; [WriteLine](#writeline-function)

## Functions

### AtEnd *function*

```
bool AtEnd()
```

Whether stdin has reached its end.

It reads a byte to find out and pushes it back, so it answers only when
the stream has something to say: on one that is open and idle it waits.

<sub>[stdlib/Console.sl:88](../../stdlib/Console.sl#L88)</sub>

### Flush *function*

```
void Flush()
```

Pushes what is buffered out to the operating system.

stdout is line buffered at a terminal and block buffered into a pipe, so a
program whose output another program is reading may so far have written
nothing the reader can see. A process killed rather than returned from
loses whatever is still held.

<sub>[stdlib/Console.sl:70](../../stdlib/Console.sl#L70)</sub>

### ReadLine *function*

```
String? ReadLine()
```

One line without its terminator, or null at the end of input.

Null rather than empty, because a blank line and no line at all are
different answers and a loop reading until there is nothing left has to
tell them apart.

<sub>[stdlib/Console.sl:79](../../stdlib/Console.sl#L79)</sub>

### ReadToEnd *function*

```
String ReadToEnd()
```

Everything left on stdin, as one string.

<sub>[stdlib/Console.sl:82](../../stdlib/Console.sl#L82)</sub>

### Write *function*

```
void Write(String text)
```

Text, with nothing after it.

<sub>[stdlib/Console.sl:52](../../stdlib/Console.sl#L52)</sub>

### WriteError *function*

```
void WriteError(String text)
```

Text and a newline, on stderr.

The newline is not optional here as it is for stdout. A diagnostic is a
whole line by the time anything reads it, and stderr is unbuffered, so a
partial one would interleave with whatever wrote next.

<sub>[stdlib/Console.sl:62](../../stdlib/Console.sl#L62)</sub>

### WriteLine *function*

```
void WriteLine(String text)
```

Text and a newline.

<sub>[stdlib/Console.sl:55](../../stdlib/Console.sl#L55)</sub>

