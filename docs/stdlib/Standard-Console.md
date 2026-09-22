# Standard.Console

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

Standard input and output, as text.

Bytes cross unchanged in both directions. A `String` is already UTF-8, so
nothing is transcoded on the way out, and input is read as bytes and taken
to be UTF-8 -- which is what a program piped a UTF-8 file needs, and is
wrong for a Windows console typed into by hand, where the active code page
arrives instead. Reading typed non-ASCII there wants `ReadConsoleW`.

A Windows console also keeps the C runtime's text mode, where Ctrl-Z ends
typed input and LF is shown as CR LF. A pipe or a file does not.

This module is not imported automatically. Printing is a choice, and a
program that never prints has no reason to carry `Write` in scope.

## Contents

**Functions** &nbsp; [Flush](#flush-function) &middot; [IsInputAtEnd](#isinputatend-function) &middot; [ReadLine](#readline-function) &middot; [ReadToEnd](#readtoend-function) &middot; [Write](#write-function) &middot; [WriteError](#writeerror-function) &middot; [WriteLine](#writeline-function)

## Functions

### Flush *function*

```
void Flush()
```

Pushes what is buffered out to the operating system.

stdout is line buffered at a terminal and block buffered into a pipe, so a
program whose output another program is reading may so far have written
nothing the reader can see. A process killed rather than returned from
loses whatever is still held.

<sub>[stdlib/Console.sl:73](../../stdlib/Console.sl#L73)</sub>

### IsInputAtEnd *function*

```
bool IsInputAtEnd()
```

Whether stdin has reached its end.

It reads a byte to find out and pushes it back, so it answers only when
the stream has something to say: on one that is open and idle it waits.

<sub>[stdlib/Console.sl:91](../../stdlib/Console.sl#L91)</sub>

### ReadLine *function*

```
String? ReadLine()
```

One line without its terminator, or null at the end of input.

Null rather than empty, because a blank line and no line at all are
different answers and a loop reading until there is nothing left has to
tell them apart.

<sub>[stdlib/Console.sl:82](../../stdlib/Console.sl#L82)</sub>

### ReadToEnd *function*

```
String ReadToEnd()
```

Everything left on stdin, as one string.

<sub>[stdlib/Console.sl:85](../../stdlib/Console.sl#L85)</sub>

### Write *function*

```
void Write(String text)
```

Text, with nothing after it.

<sub>[stdlib/Console.sl:55](../../stdlib/Console.sl#L55)</sub>

### WriteError *function*

```
void WriteError(String text)
```

Text and a newline, on stderr.

The newline is not optional here as it is for stdout. A diagnostic is a
whole line by the time anything reads it, and stderr is unbuffered, so a
partial one would interleave with whatever wrote next.

<sub>[stdlib/Console.sl:65](../../stdlib/Console.sl#L65)</sub>

### WriteLine *function*

```
void WriteLine(String text)
```

Text and a newline.

<sub>[stdlib/Console.sl:58](../../stdlib/Console.sl#L58)</sub>

