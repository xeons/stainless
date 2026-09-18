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

**Types** &nbsp; [Completed](#completed-struct) &middot; [Process](#process-class) &middot; [ProcessError](#processerror-enum) &middot; [Signals](#signals-class)

**Functions** &nbsp; [Run](#run-function) &middot; [Run](#run-function)

## Types

### Completed *struct*

```
struct Completed
```

What a finished program left behind.

<sub>[stdlib/Process.sl:86](../../stdlib/Process.sl#L86)</sub>

#### ExitCode *field*

```
int ExitCode
```

Zero by convention means success; 128 + N means a signal killed it,
which is what a shell reports too.

<sub>[stdlib/Process.sl:90](../../stdlib/Process.sl#L90)</sub>

#### Output *field*

```
String Output
```

Everything it wrote to its output, as one String.

<sub>[stdlib/Process.sl:93](../../stdlib/Process.sl#L93)</sub>

#### Errors *field*

```
String Errors
```

And to its error stream, kept separate so that a program which prints
progress there does not corrupt what was being captured.

<sub>[stdlib/Process.sl:97](../../stdlib/Process.sl#L97)</sub>

#### Ok *method*

```
bool Ok()
```

The usual question, spelled once.

<sub>[stdlib/Process.sl:100](../../stdlib/Process.sl#L100)</sub>

### Process *class*

```
class Process
```

A program that was started and has not been waited for.

Its streams are this process's own, so what it prints goes where this
program's output goes. `Run` is the one that captures.

<sub>[stdlib/Process.sl:189](../../stdlib/Process.sl#L189)</sub>

#### Id *property*

```
long Id { get; }
```

What the operating system calls it.

<sub>[stdlib/Process.sl:203](../../stdlib/Process.sl#L203)</sub>

#### Wait *method*

```
Result<int, ProcessError> Wait()
```

Waits for it to finish, and answers with the code it left.

Asking twice is harmless and answers the same both times.

<sub>[stdlib/Process.sl:208](../../stdlib/Process.sl#L208)</sub>

#### Finished *property*

```
Optional<int> Finished { get; }
```

The code it left, if it has finished, without waiting for it.

    while (child.Finished.IsEmpty) { DoSomethingElse(); }

<sub>[stdlib/Process.sl:219](../../stdlib/Process.sl#L219)</sub>

#### Stop *method*

```
bool Stop()
```

Asks it to stop, the way Ctrl-C would. It may decline.

<sub>[stdlib/Process.sl:231](../../stdlib/Process.sl#L231)</sub>

#### Kill *method*

```
bool Kill()
```

Makes it stop. It cannot decline, and gets no chance to tidy up.

<sub>[stdlib/Process.sl:234](../../stdlib/Process.sl#L234)</sub>

#### Start *method*

```
static Result<Process, ProcessError> Start(String program, String[] arguments)
```

Starts a program without waiting for it.

<sub>[stdlib/Process.sl:237](../../stdlib/Process.sl#L237)</sub>

### ProcessError *enum*

```
enum ProcessError
```

Why a program could not be started.

Only about *starting* it. A program that ran and failed is a `Completed`
with a non-zero `ExitCode`, which is an outcome rather than an error --
`grep` answering 1 for "no match" is the ordinary case, not a fault.

<sub>[stdlib/Process.sl:67](../../stdlib/Process.sl#L67)</sub>

#### None *case*

```
None
```

It started.

<sub>[stdlib/Process.sl:70](../../stdlib/Process.sl#L70)</sub>

#### NotFound *case*

```
NotFound
```

No such program, on the PATH or at the path given.

<sub>[stdlib/Process.sl:73](../../stdlib/Process.sl#L73)</sub>

#### Denied *case*

```
Denied
```

It exists and this process may not run it.

<sub>[stdlib/Process.sl:76](../../stdlib/Process.sl#L76)</sub>

#### NoResource *case*

```
NoResource
```

Out of processes, descriptors or memory.

<sub>[stdlib/Process.sl:79](../../stdlib/Process.sl#L79)</sub>

#### Failed *case*

```
Failed
```

It did not start, for a reason none of the above names.

<sub>[stdlib/Process.sl:82](../../stdlib/Process.sl#L82)</sub>

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

<sub>[stdlib/Process.sl:265](../../stdlib/Process.sl#L265)</sub>

#### Watch *method*

```
static bool Watch()
```

Starts noticing interrupts. Until this is called they end the program,
which is the right default for something that has nothing to tidy.

<sub>[stdlib/Process.sl:269](../../stdlib/Process.sl#L269)</sub>

#### Interrupted *property*

```
static bool Interrupted { get; }
```

Whether one has arrived since the last `Clear`.

<sub>[stdlib/Process.sl:272](../../stdlib/Process.sl#L272)</sub>

#### Clear *method*

```
static void Clear()
```

Forgets the one that arrived, for a program that means to carry on.

<sub>[stdlib/Process.sl:275](../../stdlib/Process.sl#L275)</sub>

## Functions

### Run *function*

```
Result<Completed, ProcessError> Run(String program, String[] arguments)
```

Runs a program to completion and answers with what it wrote and what it
returned.

    var done = try Run("git", ["status", "--short"]);

`arguments` does **not** include the program's own name; that is `program`,
and it is what a PATH lookup is done on when it has no separator in it.

<sub>[stdlib/Process.sl:149](../../stdlib/Process.sl#L149)</sub>

### Run *function*

```
Result<Completed, ProcessError> Run(String program, String[] arguments, String? input)
```

The same, with something written to the program's input first.

The pipe is closed once `input` has been written, which is what makes a
program reading to end-of-input stop rather than wait. A child that exits
without reading is not an error here: the write stops and the run goes on.

<sub>[stdlib/Process.sl:159](../../stdlib/Process.sl#L159)</sub>

