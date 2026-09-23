# Standard.Process

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

Running another program.

**There is no shell.** The program and its arguments are a list, so a `>`, a
`|` or a space in a filename is a character the child receives rather than
something a shell acts on. That is the whole of shell injection, designed
out rather than warned about -- and it is why there is no `RunProcess(String
commandLine)` here to reach for by mistake.

    var done = try RunProcess("git", ["rev-parse", "HEAD"]);
    if (done.Succeeded) { Console.WriteLine(done.StandardOutput.Trim()); }

`RunProcess` waits and captures; `Start` hands back a `Process` to wait on later.
Both read the child's streams while it runs, which is not optional: a pipe
holds about 64KB, so a parent that waits before reading waits forever on a
child that writes more than that.

## Contents

**Types** &nbsp; [Process](#process-class) &middot; [ProcessError](#processerror-enum) &middot; [ProcessResult](#processresult-struct) &middot; [RunningProcess](#runningprocess-class) &middot; [Signals](#signals-class)

**Functions** &nbsp; [OpenProcess](#openprocess-function) &middot; [OpenProcess](#openprocess-function) &middot; [RunProcess](#runprocess-function) &middot; [RunProcess](#runprocess-function)

## Types

### Process *class*

```
class Process
```

A program that was started and has not been waited for.

Its streams are this process's own, so what it prints goes where this
program's output goes. `RunProcess` is the one that captures.

<sub>[stdlib/Process/Process.sl:172](../../stdlib/Process/Process.sl#L172)</sub>

#### Id *property*

```
long Id { get; }
```

What the operating system calls it.

<sub>[stdlib/Process/Process.sl:186](../../stdlib/Process/Process.sl#L186)</sub>

#### WaitForExit *method*

```
Result<int, ProcessError> WaitForExit()
```

Waits for it to finish, and answers with the code it left.

Asking twice is harmless and answers the same both times.

**Fails with**

- [ProcessError.Failed](#failed-case) — the wait itself failed, so there is no code to report

<sub>[stdlib/Process/Process.sl:194](../../stdlib/Process/Process.sl#L194)</sub>

#### TryGetExitCode *method*

```
Optional<int> TryGetExitCode()
```

The code it left, if it has finished, without waiting for it.

A method rather than a property because asking reaps a child that has
exited, which is not what a property may do.

    while (child.TryGetExitCode().IsEmpty) { DoSomethingElse(); }

<sub>[stdlib/Process/Process.sl:208](../../stdlib/Process/Process.sl#L208)</sub>

#### Stop *method*

```
bool Stop()
```

Asks it to stop, the way Ctrl-C would. It may decline.

<sub>[stdlib/Process/Process.sl:217](../../stdlib/Process/Process.sl#L217)</sub>

#### Kill *method*

```
bool Kill()
```

Makes it stop. It cannot decline, and gets no chance to tidy up.

<sub>[stdlib/Process/Process.sl:220](../../stdlib/Process/Process.sl#L220)</sub>

#### Start *method*

```
static Result<Process, ProcessError> Start(String program, String[] arguments)
```

Starts a program without waiting for it.

**Parameters**

- `program` — what to run, looked up on the PATH when it has no separator in it
- `arguments` — what to hand it, without the program's own name in front

**Fails with**

- [ProcessError.NotFound](#notfound-case) — no such program, on the PATH or at the path given
- [ProcessError.Denied](#denied-case) — it is there and may not be run
- [ProcessError.NoResource](#noresource-case) — out of processes, descriptors or memory
- [ProcessError.Failed](#failed-case) — it did not start, for a reason none of the others names

**See also** &nbsp; [RunProcess](#runprocess-function)

<sub>[stdlib/Process/Process.sl:236](../../stdlib/Process/Process.sl#L236)</sub>

### ProcessError *enum*

```
enum ProcessError
```

Why a program could not be started.

Only about *starting* it. A program that ran and failed is a `ProcessResult`
with a non-zero `ExitCode`, which is an outcome rather than an error --
`grep` answering 1 for "no match" is the ordinary case, not a fault.

<sub>[stdlib/Process/ProcessError.sl:31](../../stdlib/Process/ProcessError.sl#L31)</sub>

#### None *case*

```
None
```

It started.

<sub>[stdlib/Process/ProcessError.sl:34](../../stdlib/Process/ProcessError.sl#L34)</sub>

#### NotFound *case*

```
NotFound
```

No such program, on the PATH or at the path given.

<sub>[stdlib/Process/ProcessError.sl:37](../../stdlib/Process/ProcessError.sl#L37)</sub>

#### Denied *case*

```
Denied
```

It exists and this process may not run it.

<sub>[stdlib/Process/ProcessError.sl:40](../../stdlib/Process/ProcessError.sl#L40)</sub>

#### NoResource *case*

```
NoResource
```

Out of processes, descriptors or memory.

<sub>[stdlib/Process/ProcessError.sl:43](../../stdlib/Process/ProcessError.sl#L43)</sub>

#### Failed *case*

```
Failed
```

It did not start, for a reason none of the above names.

<sub>[stdlib/Process/ProcessError.sl:46](../../stdlib/Process/ProcessError.sl#L46)</sub>

### ProcessResult *struct*

```
struct ProcessResult
```

What a finished program left behind.

<sub>[stdlib/Process/ProcessResult.sl:27](../../stdlib/Process/ProcessResult.sl#L27)</sub>

#### ExitCode *field*

```
int ExitCode
```

Zero by convention means success; 128 + N means a signal killed it,
which is what a shell reports too.

<sub>[stdlib/Process/ProcessResult.sl:31](../../stdlib/Process/ProcessResult.sl#L31)</sub>

#### StandardOutput *field*

```
String StandardOutput
```

Everything it wrote to its output, as one String.

<sub>[stdlib/Process/ProcessResult.sl:34](../../stdlib/Process/ProcessResult.sl#L34)</sub>

#### StandardError *field*

```
String StandardError
```

And to its error stream, kept separate so that a program which prints
progress there does not corrupt what was being captured.

<sub>[stdlib/Process/ProcessResult.sl:38](../../stdlib/Process/ProcessResult.sl#L38)</sub>

#### Succeeded *property*

```
bool Succeeded { get; }
```

The usual question, spelled once.

<sub>[stdlib/Process/ProcessResult.sl:41](../../stdlib/Process/ProcessResult.sl#L41)</sub>

### RunningProcess *class*

```
class RunningProcess
```

A program running with both its output streams captured, read as they fill.

**What `RunProcess` cannot do.** `RunProcess` does not answer until the child has exited,
so a build taking a minute says nothing for a minute and then says all of
it at once. This hands over what has arrived so far, as often as it is
asked -- which is what a window showing a build as it happens needs, and
the only difference between the two.

    var started = OpenProcess("stainless", ["build"]);
    if (started.Ok)
    {
        var child = started.Value;
        while (child.ReadAvailableOutput())
        {
            Show(child.TakeOutput());
            Complain(child.TakeErrors());
        }
        Console.WriteLine(
            "exit " + Text.FromInteger(child.WaitForExit().GetValueOrDefault(-1)));
    }

**`ReadAvailableOutput` waits**, and that is deliberate: it answers when there is
something to hand over or when the child has closed both streams, and never
immediately with nothing. So the loop above blocks rather than spinning,
and belongs on a thread of its own when there is a window to keep painting.

**Both streams are watched together**, which is not a detail a caller could
add afterwards. A pipe holds about 64KB, and a reader that drains one to
the end while the child fills the other is waiting for a child that is
waiting for the reader. That is why this hands back two strings rather than
being two objects with a `ReadAvailableOutput` each.

<sub>[stdlib/Process/RunningProcess.sl:59](../../stdlib/Process/RunningProcess.sl#L59)</sub>

#### Id *property*

```
long Id { get; }
```

What the operating system calls it.

<sub>[stdlib/Process/RunningProcess.sl:81](../../stdlib/Process/RunningProcess.sl#L81)</sub>

#### ReadAvailableOutput *method*

```
bool ReadAvailableOutput()
```

Takes in whatever the child has written since the last call, and
answers whether there may be more after this one.

False means both streams are closed and everything they held has
already been handed over, so the last `Take` before it is not missing
anything.

<sub>[stdlib/Process/RunningProcess.sl:89](../../stdlib/Process/RunningProcess.sl#L89)</sub>

#### TakeOutput *method*

```
String TakeOutput()
```

What the child wrote to its output since this was last asked, and
nothing at all the next time.

**Taken rather than read.** The buffer is emptied, because a caller
showing output as it arrives wants each line once; `RunProcess` is the one
that answers with the whole of it at the end.

<sub>[stdlib/Process/RunningProcess.sl:103](../../stdlib/Process/RunningProcess.sl#L103)</sub>

#### TakeErrors *method*

```
String TakeErrors()
```

The same for what it wrote to its error stream.

<sub>[stdlib/Process/RunningProcess.sl:106](../../stdlib/Process/RunningProcess.sl#L106)</sub>

#### WaitForExit *method*

```
Result<int, ProcessError> WaitForExit()
```

Waits for it to finish, and answers with the code it left.

**After `ReadAvailableOutput` has answered false**, not before: waiting on a child
whose output pipe is full is the deadlock the pumping exists to avoid,
arriving from the other side. Asking twice is harmless and answers the
same both times.

**Fails with**

- [ProcessError.Failed](#failed-case) — the wait itself failed, so there is no code to report

**See also** &nbsp; [RunningProcess.ReadAvailableOutput](#readavailableoutput-method)

<sub>[stdlib/Process/RunningProcess.sl:118](../../stdlib/Process/RunningProcess.sl#L118)</sub>

#### Stop *method*

```
bool Stop()
```

Asks it to stop, the way Ctrl-C would. It may decline.

<sub>[stdlib/Process/RunningProcess.sl:127](../../stdlib/Process/RunningProcess.sl#L127)</sub>

#### Kill *method*

```
bool Kill()
```

Makes it stop. It cannot decline, and gets no chance to tidy up.

<sub>[stdlib/Process/RunningProcess.sl:130](../../stdlib/Process/RunningProcess.sl#L130)</sub>

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

    Signals.StartWatching();
    while (!Signals.Interrupted) { DoAPieceOfWork(); }
    Console.WriteLine("stopping");

<sub>[stdlib/Process/Signals.sl:39](../../stdlib/Process/Signals.sl#L39)</sub>

#### StartWatching *method*

```
static bool StartWatching()
```

Starts noticing interrupts. Until this is called they end the program,
which is the right default for something that has nothing to tidy.

<sub>[stdlib/Process/Signals.sl:43](../../stdlib/Process/Signals.sl#L43)</sub>

#### Interrupted *property*

```
static bool Interrupted { get; }
```

Whether one has arrived since the last `ClearInterrupt`.

<sub>[stdlib/Process/Signals.sl:46](../../stdlib/Process/Signals.sl#L46)</sub>

#### ClearInterrupt *method*

```
static void ClearInterrupt()
```

Forgets the one that arrived, for a program that means to carry on.

<sub>[stdlib/Process/Signals.sl:49](../../stdlib/Process/Signals.sl#L49)</sub>

## Functions

### OpenProcess *function*

```
Result<RunningProcess, ProcessError> OpenProcess(String program, String[] arguments)
```

Starts a program with its output captured, to be read as it arrives.

`arguments` does **not** include the program's own name; that is `program`,
and it is what a PATH lookup is done on when it has no separator in it --
the same bargain `RunProcess` makes.

**Fails with**

- [ProcessError.NotFound](#notfound-case) — no such program, on the PATH or at the path given
- [ProcessError.Denied](#denied-case) — it is there and may not be run
- [ProcessError.NoResource](#noresource-case) — out of processes, descriptors, pipes or memory
- [ProcessError.Failed](#failed-case) — it did not start, for a reason none of the others names

**See also** &nbsp; [RunProcess](#runprocess-function)

<sub>[stdlib/Process/Process.sl:265](../../stdlib/Process/Process.sl#L265)</sub>

### OpenProcess *function*

```
Result<RunningProcess, ProcessError> OpenProcess(String program, String[] arguments, String? input)
```

The same, with `input` written to the program's input.

What fits in the pipe is written before this returns, and the rest no
later than `ReadAvailableOutput` waits for output, so input of any size is safe to give a
filter that answers as it reads. The pipe is closed once all of it is written, which
is what makes a program reading to end-of-input stop rather than wait.

Without `input` the program reads end of input at once, rather than this
program's own.

**Fails with**

- [ProcessError.NotFound](#notfound-case) — no such program, on the PATH or at the path given
- [ProcessError.Denied](#denied-case) — it is there and may not be run
- [ProcessError.NoResource](#noresource-case) — out of processes, descriptors, pipes or memory
- [ProcessError.Failed](#failed-case) — it did not start, for a reason none of the others names

<sub>[stdlib/Process/Process.sl:287](../../stdlib/Process/Process.sl#L287)</sub>

### RunProcess *function*

```
Result<ProcessResult, ProcessError> RunProcess(String program, String[] arguments)
```

Runs a program to completion and answers with what it wrote and what it
returned.

    var done = try RunProcess("git", ["status", "--short"]);

`arguments` does **not** include the program's own name; that is `program`,
and it is what a PATH lookup is done on when it has no separator in it.

**Fails with**

- [ProcessError.NotFound](#notfound-case) — no such program, on the PATH or at the path given
- [ProcessError.Denied](#denied-case) — it is there and may not be run
- [ProcessError.NoResource](#noresource-case) — out of processes, descriptors or memory
- [ProcessError.Failed](#failed-case) — it did not start, for a reason none of the others names

**See also** &nbsp; [OpenProcess](#openprocess-function) &middot; [Process.Start](#start-method)

<sub>[stdlib/Process/Process.sl:122](../../stdlib/Process/Process.sl#L122)</sub>

### RunProcess *function*

```
Result<ProcessResult, ProcessError> RunProcess(String program, String[] arguments, String? input)
```

The same, with `input` written to the program's input.

It is written while the output is read, so a filter that answers as it
reads takes an input of any size. The pipe is closed once all of it is
written, which is what makes a program reading to end-of-input stop rather
than wait. A child that exits without reading is not an error here: the
rest is dropped and the run goes on.

Without `input` the program reads end of input at once, rather than this
program's own.

**Fails with**

- [ProcessError.NotFound](#notfound-case) — no such program, on the PATH or at the path given
- [ProcessError.Denied](#denied-case) — it is there and may not be run
- [ProcessError.NoResource](#noresource-case) — out of processes, descriptors or memory
- [ProcessError.Failed](#failed-case) — it did not start, for a reason none of the others names

<sub>[stdlib/Process/Process.sl:144](../../stdlib/Process/Process.sl#L144)</sub>

