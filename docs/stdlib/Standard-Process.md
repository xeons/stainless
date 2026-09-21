# Standard.Process

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

Running another program.

**There is no shell.** The program and its arguments are a list, so a `>`, a
`|` or a space in a filename is a character the child receives rather than
something a shell acts on. That is the whole of shell injection, designed
out rather than warned about -- and it is why there is no `Run(String
commandLine)` here to reach for by mistake.

    var done = try Run("git", ["rev-parse", "HEAD"]);
    if (done.Ok()) { Console.WriteLine(done.Output.Trim()); }

`Run` waits and captures; `Start` hands back a `Process` to wait on later.
Both read the child's streams while it runs, which is not optional: a pipe
holds about 64KB, so a parent that waits before reading waits forever on a
child that writes more than that.

## Contents

**Types** &nbsp; [Completed](#completed-struct) &middot; [Process](#process-class) &middot; [ProcessError](#processerror-enum) &middot; [Running](#running-class) &middot; [Signals](#signals-class)

**Functions** &nbsp; [Open](#open-function) &middot; [Open](#open-function) &middot; [Run](#run-function) &middot; [Run](#run-function)

## Types

### Completed *struct*

```
struct Completed
```

What a finished program left behind.

<sub>[stdlib/Process.sl:91](../../stdlib/Process.sl#L91)</sub>

#### ExitCode *field*

```
int ExitCode
```

Zero by convention means success; 128 + N means a signal killed it,
which is what a shell reports too.

<sub>[stdlib/Process.sl:95](../../stdlib/Process.sl#L95)</sub>

#### Output *field*

```
String Output
```

Everything it wrote to its output, as one String.

<sub>[stdlib/Process.sl:98](../../stdlib/Process.sl#L98)</sub>

#### Errors *field*

```
String Errors
```

And to its error stream, kept separate so that a program which prints
progress there does not corrupt what was being captured.

<sub>[stdlib/Process.sl:102](../../stdlib/Process.sl#L102)</sub>

#### Ok *method*

```
bool Ok()
```

The usual question, spelled once.

<sub>[stdlib/Process.sl:105](../../stdlib/Process.sl#L105)</sub>

### Process *class*

```
class Process
```

A program that was started and has not been waited for.

Its streams are this process's own, so what it prints goes where this
program's output goes. `Run` is the one that captures.

<sub>[stdlib/Process.sl:192](../../stdlib/Process.sl#L192)</sub>

#### Id *property*

```
long Id { get; }
```

What the operating system calls it.

<sub>[stdlib/Process.sl:206](../../stdlib/Process.sl#L206)</sub>

#### Wait *method*

```
Result<int, ProcessError> Wait()
```

Waits for it to finish, and answers with the code it left.

Asking twice is harmless and answers the same both times.

<sub>[stdlib/Process.sl:211](../../stdlib/Process.sl#L211)</sub>

#### Finished *property*

```
Optional<int> Finished { get; }
```

The code it left, if it has finished, without waiting for it.

    while (child.Finished.IsEmpty) { DoSomethingElse(); }

<sub>[stdlib/Process.sl:222](../../stdlib/Process.sl#L222)</sub>

#### Stop *method*

```
bool Stop()
```

Asks it to stop, the way Ctrl-C would. It may decline.

<sub>[stdlib/Process.sl:234](../../stdlib/Process.sl#L234)</sub>

#### Kill *method*

```
bool Kill()
```

Makes it stop. It cannot decline, and gets no chance to tidy up.

<sub>[stdlib/Process.sl:237](../../stdlib/Process.sl#L237)</sub>

#### Start *method*

```
static Result<Process, ProcessError> Start(String program, String[] arguments)
```

Starts a program without waiting for it.

<sub>[stdlib/Process.sl:240](../../stdlib/Process.sl#L240)</sub>

### ProcessError *enum*

```
enum ProcessError
```

Why a program could not be started.

Only about *starting* it. A program that ran and failed is a `Completed`
with a non-zero `ExitCode`, which is an outcome rather than an error --
`grep` answering 1 for "no match" is the ordinary case, not a fault.

<sub>[stdlib/Process.sl:72](../../stdlib/Process.sl#L72)</sub>

#### None *case*

```
None
```

It started.

<sub>[stdlib/Process.sl:75](../../stdlib/Process.sl#L75)</sub>

#### NotFound *case*

```
NotFound
```

No such program, on the PATH or at the path given.

<sub>[stdlib/Process.sl:78](../../stdlib/Process.sl#L78)</sub>

#### Denied *case*

```
Denied
```

It exists and this process may not run it.

<sub>[stdlib/Process.sl:81](../../stdlib/Process.sl#L81)</sub>

#### NoResource *case*

```
NoResource
```

Out of processes, descriptors or memory.

<sub>[stdlib/Process.sl:84](../../stdlib/Process.sl#L84)</sub>

#### Failed *case*

```
Failed
```

It did not start, for a reason none of the above names.

<sub>[stdlib/Process.sl:87](../../stdlib/Process.sl#L87)</sub>

### Running *class*

```
class Running
```

A program running with both its output streams captured, read as they fill.

**What `Run` cannot do.** `Run` does not answer until the child has exited,
so a build taking a minute says nothing for a minute and then says all of
it at once. This hands over what has arrived so far, as often as it is
asked -- which is what a window showing a build as it happens needs, and
the only difference between the two.

    var started = Open("stainless", ["build"]);
    if (started.Ok)
    {
        var child = started.Value;
        while (child.Read())
        {
            Show(child.TakeOutput());
            Complain(child.TakeErrors());
        }
        Console.WriteLine("exit " + Text.FromInteger(child.Wait().ValueOr(-1)));
    }

**`Read` waits**, and that is deliberate: it answers when there is
something to hand over or when the child has closed both streams, and never
immediately with nothing. So the loop above blocks rather than spinning,
and belongs on a thread of its own when there is a window to keep painting.

**Both streams are watched together**, which is not a detail a caller could
add afterwards. A pipe holds about 64KB, and a reader that drains one to
the end while the child fills the other is waiting for a child that is
waiting for the reader. That is why this hands back two strings rather than
being two objects with a `Read` each.

<sub>[stdlib/Process.sl:287](../../stdlib/Process.sl#L287)</sub>

#### Id *property*

```
long Id { get; }
```

What the operating system calls it.

<sub>[stdlib/Process.sl:308](../../stdlib/Process.sl#L308)</sub>

#### Read *method*

```
bool Read()
```

Takes in whatever the child has written since the last call, and
answers whether there may be more after this one.

False means both streams are closed and everything they held has
already been handed over, so the last `Take` before it is not missing
anything.

<sub>[stdlib/Process.sl:316](../../stdlib/Process.sl#L316)</sub>

#### TakeOutput *method*

```
String TakeOutput()
```

What the child wrote to its output since this was last asked, and
nothing at all the next time.

**Taken rather than read.** The buffer is emptied, because a caller
showing output as it arrives wants each line once; `Run` is the one
that answers with the whole of it at the end.

<sub>[stdlib/Process.sl:330](../../stdlib/Process.sl#L330)</sub>

#### TakeErrors *method*

```
String TakeErrors()
```

The same for what it wrote to its error stream.

<sub>[stdlib/Process.sl:333](../../stdlib/Process.sl#L333)</sub>

#### Wait *method*

```
Result<int, ProcessError> Wait()
```

Waits for it to finish, and answers with the code it left.

**After `Read` has answered false**, not before: waiting on a child
whose output pipe is full is the deadlock the pumping exists to avoid,
arriving from the other side. Asking twice is harmless and answers the
same both times.

<sub>[stdlib/Process.sl:341](../../stdlib/Process.sl#L341)</sub>

#### Stop *method*

```
bool Stop()
```

Asks it to stop, the way Ctrl-C would. It may decline.

<sub>[stdlib/Process.sl:350](../../stdlib/Process.sl#L350)</sub>

#### Kill *method*

```
bool Kill()
```

Makes it stop. It cannot decline, and gets no chance to tidy up.

<sub>[stdlib/Process.sl:353](../../stdlib/Process.sl#L353)</sub>

### Signals *class*

```
class Signals
```

Ctrl-C, asked for rather than delivered.

A signal handler runs between two instructions of whatever was executing,
so almost nothing is legal inside one: no allocation, no locks, and
therefore no Stainless at all. What is legal is a store to a flag, so that
is what the handler does, and this is where a program reads it -- at the
top of its own loop, where it can actually tidy up.

    Signals.Watch();
    while (!Signals.Interrupted) { DoAPieceOfWork(); }
    Console.WriteLine("stopping");

<sub>[stdlib/Process.sl:402](../../stdlib/Process.sl#L402)</sub>

#### Watch *method*

```
static bool Watch()
```

Starts noticing interrupts. Until this is called they end the program,
which is the right default for something that has nothing to tidy.

<sub>[stdlib/Process.sl:406](../../stdlib/Process.sl#L406)</sub>

#### Interrupted *property*

```
static bool Interrupted { get; }
```

Whether one has arrived since the last `Clear`.

<sub>[stdlib/Process.sl:409](../../stdlib/Process.sl#L409)</sub>

#### Clear *method*

```
static void Clear()
```

Forgets the one that arrived, for a program that means to carry on.

<sub>[stdlib/Process.sl:412](../../stdlib/Process.sl#L412)</sub>

## Functions

### Open *function*

```
Result<Running, ProcessError> Open(String program, String[] arguments)
```

Starts a program with its output captured, to be read as it arrives.

`arguments` does **not** include the program's own name; that is `program`,
and it is what a PATH lookup is done on when it has no separator in it --
the same bargain `Run` makes.

<sub>[stdlib/Process.sl:361](../../stdlib/Process.sl#L361)</sub>

### Open *function*

```
Result<Running, ProcessError> Open(String program, String[] arguments, String? input)
```

The same, with something written to the program's input first.

The pipe is closed once `input` has been written, which is what makes a
program reading to end-of-input stop rather than wait. It is written before
any reading starts, so this is for input small enough to fit in a pipe --
a child that will not read until it has answered, and an input larger than
the buffer, would deadlock here exactly as it does under `Run`.

<sub>[stdlib/Process.sl:373](../../stdlib/Process.sl#L373)</sub>

### Run *function*

```
Result<Completed, ProcessError> Run(String program, String[] arguments)
```

Runs a program to completion and answers with what it wrote and what it
returned.

    var done = try Run("git", ["status", "--short"]);

`arguments` does **not** include the program's own name; that is `program`,
and it is what a PATH lookup is done on when it has no separator in it.

<sub>[stdlib/Process.sl:154](../../stdlib/Process.sl#L154)</sub>

### Run *function*

```
Result<Completed, ProcessError> Run(String program, String[] arguments, String? input)
```

The same, with something written to the program's input first.

The pipe is closed once `input` has been written, which is what makes a
program reading to end-of-input stop rather than wait. A child that exits
without reading is not an error here: the write stops and the run goes on.

<sub>[stdlib/Process.sl:164](../../stdlib/Process.sl#L164)</sub>

