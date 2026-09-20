# The debug engine

A debugger for Stainless, written in Stainless, with a console front end so
that it can be tested without a window.

```
stainless build --project debug
.\debug\build\sldb --selftest
.\debug\build\sldb sections <binary>
```

**A binary to debug MUST carry DWARF.** On Windows an ordinary `-g` build
writes CodeView into a `.pdb`, which this reads none of, so build with
`--debug-format dwarf -O0`. Without it `sldb` says so rather than quietly
reporting addresses that have no lines.

## What is here

| | |
|---|---|
| `src/Bytes.sl` | a bounds-checked cursor, for DWARF's variable-length encodings |
| `src/Image.sl` | an executable reduced to its sections, and the sniff that picks a reader |
| `src/Image/Pe.sl` | the COFF header structures |
| `src/Image/Elf.sl` | the ELF header structures, section and program both |
| `src/Dwarf/Constants.sl` | the tags, attributes and forms, and names for printing them |
| `src/Dwarf/Abbrev.sl` | `.debug_abbrev`, and a skip rule for every form |
| `src/Dwarf/Info.sl` | `.debug_info` as units and entries, indirections resolved |
| `src/Dwarf/Lines.sl` | `.debug_line`, which is a bytecode and so an interpreter |
| `src/Target.sl` | the seam: `ITarget`, and a `DebugEvent` variant |
| `src/Target/Win32.sl` | the `DEBUG_EVENT` loop |
| `src/Target/Linux.sl` | the `ptrace` loop |
| `src/Target/Select.sl` | the one `#if` in the engine |
| `src/Engine.sl` | breakpoints, the slide, run control and stepping |
| `src/Paths.sl` | whether two spellings name one source file |
| `src/Session.sl` | a stop, read into a `Snapshot` a window can hold |
| `src/Stack.sl` | the frame-pointer walk |
| `src/Values.sl` | a location and a type, read out of the process |
| `src/Watch.sl` | a watch expression, parsed and then walked |
| `tests/sldb.sl` | the console debugger |

## Four decisions worth knowing before reading the code

**It is a separate tree from `ide/`, and it must never import `Forms`.** A
debug engine that can only be driven by a GUI cannot be tested headless, and
this repository's most expensive lesson is that a GUI self test proves the
model and nothing about the screen. `sldb` is what a scripted test drives; the
IDE is the second consumer, and it gets no capability the console tool lacks.

It cannot live in `stdlib/` either: reading a process needs `DEBUG_EVENT` and
`ptrace`, and the standard library declares its own `extern "C"` and never
imports `bindings/`.

**The DWARF is read from the file on disk, never out of the target's memory.**
That is what `fpdebug` does, and it is what lets every reader here be exercised
on a machine that could not launch the binary if it tried. The only thing a
live process is needed for is the *slide* -- where the loader actually put the
image, against where it was linked to go.

**A header is a struct, not a sequence of reads.** This language has C's
layout, so a COFF or ELF header is declared once and a pointer is cast at the
bytes -- which is shorter, matches the format specification line for line, and
cannot drift the way a run of `Skip(4)` calls with explanatory comments can.
The byte cursor is for DWARF, which is the part with no shape to declare:
LEB128 is variable-length by construction, a DIE's attribute widths are decided
at run time by a table in another section, and the line-number program is a
bytecode interpreter.

What a cast still owes its caller is a bounds check, since the input is a file
somebody else wrote -- one per header rather than one per field. And a check
that the declarations are right: `HeaderSizeProblem` compares all ten
structures against the sizes their formats fix, which costs nothing, needs no
binary, and is the only cover the 32-bit layouts have until something here
builds a 32-bit binary. It was verified by breaking a struct on purpose and
watching it fail.

**A reader survives a bad file rather than aborting on one.** Every read is
bounds-checked and a read past the end answers zero and sets a sticky
`Overran`. The input is a file some other program wrote, and half the point of
a reader like this is to cope with one that is truncated, corrupt, or simply
not the format it was taken for. A debugger that aborts on a bad binary is
worse than one that says the binary is bad.

## What the containers do not agree about

[docs/dwarf.md](../docs/dwarf.md) is the measured account of what the compiler
emits. Two things from it shape the code here:

**A PE section name is eight bytes and every DWARF name is longer.**
`.debug_line` and `.debug_line_str` would both truncate to `.debug_l`, so
lld-link writes the long ones into a string table and leaves `/NNN` -- a
decimal offset -- in the header. The trap is that it writes `NumberOfSymbols`
as *zero* while still pointing `PointerToSymbolTable` at a string table that is
really there; a reader that takes "no symbols" for "no string table" silently
finds no DWARF at all.

**`SizeOfRawData` is rounded up to the file alignment and `VirtualSize` is the
truth.** For `.text` the difference is padding nobody executes. For a DWARF
section it is a run of trailing zeros that the reader above takes seriously --
zero is a valid entry in `.debug_addr` and `.debug_str_offsets`, and a unit
header of zeros is a unit. Both were caught by comparing against
`llvm-objdump -h`, which is the check to repeat whenever this changes.

## How the DWARF reader is checked

`sldb dies` prints the entry tree in the shape `llvm-dwarfdump --debug-info`
prints it, so the two can be diffed rather than compared by eye. On the
fixture in `docs/dwarf.md`:

```
                ELF          PE
entries        9808         6226
line rows     21964        15507
differing         0            0
```

-- every entry offset and tag, and every line row's address, line, column, file
and flags, across seventeen compilation units and every form the compiler
emits. That is the check to repeat after any change here, and it is worth more
than any number of assertions about individual fields.

Three things it does not cover, and which the self test does instead.

That every form this engine can *name* it can also *skip*, and that one it has
never heard of is refused rather than skipped by zero bytes -- both the same
failure, losing position in a stream whose entries carry no length and then
producing entries that still look plausible.

And **the two searches over the line rows**, which a diff of the rows says
nothing about. The subtle one is that a sequence's last row covers nothing: its
address is one past the last instruction, so treating it as a row reaching the
next sequence reports the previous function for every address in the gap.

## What it can answer

The two questions the reading half exists for, neither of which needs a
process:

```
$ sldb line f0 fixture.sl:38
0x1211  /home/brandon/spike/fixture.sl:38

$ sldb line f0 fixture.sl:34
0x1200  /home/brandon/spike/fixture.sl:35
      (line 34 has no code; moved to 35)

$ sldb addr f0 0x122a
/home/brandon/spike/fixture.sl:40  (0x122a, a statement)
      in Total at +42
```

**A breakpoint that moves says so.** A line with no code binds to the next one
that has some, which every debugger does; one that leaves the marker where it
was asked for is the one that wastes an afternoon.

## Running one

```
$ sldb run f0-dwarf.exe fixture.sl:41
breakpoint at 0x140045b8d  fixture.sl:41
stopped at ...ixture.sl:41
      in Total
stopped at ...ixture.sl:41
      in Total
stopped at ...ixture.sl:41
      in Total
stopped at ...ixture.sl:41
      in Total
exited with 0
```

Four stops because the array has four elements, and the program's own output is
still right -- which is the check that matters, because it says the trap byte
went back correctly every time.

**The slide is the one thing the reading half could not know.** Everything in
the DWARF is an address the linker chose; the loader may put the image
elsewhere, and `CREATE_PROCESS_DEBUG_EVENT` is where the difference is learned.
Forgetting it works perfectly on Windows, where the preferred base is usually
honoured, and misses every breakpoint on a Linux position-independent
executable, which never lands at zero.

**Standing on a breakpoint is the case everyone gets wrong once.** Continuing
from one means executing the instruction the trap replaced, so the trap cannot
be there -- and putting it back means knowing when "afterwards" is. The answer
is: rewind the program counter on to the instruction (the trap has already
executed, so the counter is one byte past it), restore the byte, single-step
exactly one instruction, re-plant, carry on. Get any part of it wrong and the
first hit looks perfect while the second crashes.

**The loader's breakpoint is not yours.** Every Windows process raises one when
the loader finishes. Reporting it starts every session at an address in `ntdll`
that no source line covers; handing it back to the program with
`DBG_EXCEPTION_NOT_HANDLED` kills the program. It is swallowed exactly once.

## Stepping and the stack

```
$ sldb stack fp-dwarf.exe fixture.sl:41
stopped at .../fixture.sl:41
  #0  Total                   .../fixture.sl:41
  #1  Main                    .../fixture.sl:61

$ sldb step fp-dwarf.exe fixture.sl:61 4      # into the call
  -> .../fixture.sl:35   Total
  -> .../fixture.sl:37   Total
  -> .../fixture.sl:38   Total
  -> .../fixture.sl:40   Total

$ sldb next fp-dwarf.exe fixture.sl:61 3      # over it
  -> .../fixture.sl:62   Main
  -> .../fixture.sl:63   Main
  -> .../fixture.sl:65   Main
```

**The stack walk is two loads per frame, and only because the compiler emits a
frame pointer.** It does that under `-g` and nowhere else -- one attribute
group, `"frame-pointer"="all"`, added because LLVM omits the frame pointer at
every optimisation level unless asked, `-O0` included. Without it
`DW_AT_frame_base` describes RSP, which is correct and describes a frame
nothing can unwind. It is not an unwinder: at `-O2`, or through the C runtime,
the real answer is `.eh_frame` and `.pdata`, both of which every binary already
carries.

**Every frame above the first is a return address**, so the line table is asked
about the byte *before* it. Asked about the return address directly it answers
the line the call comes back to, which is usually the same line and
occasionally the next one -- `#1 Main` above lands on line 61, the call itself,
because of that one subtraction.

**A call is recognised by leaving the function's address range, not by the
stack pointer going down.** The obvious test is the stack pointer, and it is
wrong: a function's own prologue pushes the frame pointer, so the first
instruction of every function looks like a call was taken. Stepping into
`Total` then "arrived" at `Total` again and stopped on its opening line for
ever, and stepping over it read a saved `rbp` where a return address should be.

**Three failures here shared one shape**, which is worth naming because the
fourth will too: a target that has stopped is waiting for a `Resume` that
answers the event it reported, and every path that forgets one looks like a
hang or like a step that ran to the end of the program. Getting off a
breakpoint is itself a step, so a flag has to say whether the single step now
in flight is housekeeping or the thing somebody asked for.

**Stepping in stops at the callee's first instruction, not at its
`prologue_end`.** Running to the marker means a temporary breakpoint, and a
temporary breakpoint at an address taken from the line table without first
proving it is inside this function is `0xCC` written into somebody else's code
-- which is exactly what happened, and what the wild addresses in the output
were. Worth doing, worth doing carefully, and not done here.

## Values

```
$ sldb locals fp-dwarf.exe fixture.sl:65
  numbers     int[]                   4 elements at 0x17ede8fe2a0
  sum         int                     10
  s           Fixture.Shape           Fixture.Shape (Fixture.Circle) at 0x...
  label       Standard.Text.String    "circle"
```

**`Fixture.Shape (Fixture.Circle)` needs no reflection metadata.** Every object
carries a 24-byte header whether or not it carries field tables, and `type` at
+16 is an `SlTypeInfo*` whose `name` is at +16 of that -- so two pointer reads
turn a variable declared as a base class into one that shows what it actually
is. `strong` at +0 being zero means the object is dead, which turns the stale
weak reference `docs/abi.md` warns about from a lie into `(dead)`.

**An array and a `String` are described as far as their length and no
further**, because DWARF can only express an array whose bound it knows
statically. `length` is at offset 24 and the elements at **32** -- the length
is a word of its own, and a reader that puts them at 24 gets the length as its
first element.

**Every local of the function is listed, including ones not reached yet**,
because the compiler emits no lexical blocks. A variable declared inside a loop
belongs to the function's scope as far as DWARF is concerned, so it is in the
list from the first line holding whatever its slot contained. Filtering by
`DW_AT_decl_line` would be the debugger guessing at something the compiler
knows and could emit.

**A compiler bug came out of this, and it is the kind that hides.** A class
reference is described as a pointer to the class body -- except that building
the body registered *itself* under the class's own entry in the type map,
overwriting the pointer its caller had just put there. So the first reference
to any class got the pointer and every one after it got the 40-byte structure,
sitting in a slot holding an 8-byte reference. It verified, it ran, and only a
debugger reading a local ever noticed. `DebugInfoTests` now follows the node
number from a variable to what it points at, with two locals of one type
because one would have passed.

## Watch expressions

```
$ sldb watch fixture.exe fixture.sl:52 numbers[i] head.Next.Label names[2]
stopped at .../fixture.sl:52
  numbers[i]          int                     33
  head.Next.Label     Standard.Text.String    "tail"
  names[2]                                    -- index 2 is past the end of
                                                 String[], which has 2 elements
```

`a`, `a.b.c`, `a[3]`, `a[i]`, `*p` and a number, decimal or hexadecimal. No
arithmetic, no casts, no parentheses, and **never a call into the debuggee**:
calling into an ARC'd runtime from a process stopped inside the allocator's
lock deadlocks the thing being inspected, and it is where `fpdebug`'s hardest
bugs live. `fppascalparser.pas` is 263 KB because Lazarus promises that a watch
is a whole Pascal expression. The promise here is much smaller and is kept.

**Parsing and evaluating are separate passes**, which is what makes the grammar
testable: a malformed expression is a question with no process, no binary and
no frame in it, so `sldb --selftest` covers every refusal and the IDE can turn
one down in the box it was typed into rather than at the next stop.

**Every refusal names what was wrong.** `a.b` on something with no `b` says so
and says what it did have; an index past the end says how many there are; a
stray byte is quoted back. A watch is typed by a person, and "invalid
expression" tells them nothing about which half.

**`.` goes through a reference by itself**, so `head.Next.Label` reads the way
it is written. Postfix binds tighter than `*`, as in C, so `*p.next` follows
`p.next` and the other grouping cannot be written -- that is what parentheses
would be for.

**An array is indexed from the DWARF rather than from a table of offsets
here.** The compiler describes an array object's elements as a flexible array
member -- the element type, claiming no bound, because the bound is the `length`
word in front of it -- and `String` and `Utf16String` carry the same shape under
the names `runtime/stainless.h` gives them. So the element type, the stride and
the length all come out of the file, and `bytes`, `units` and `elements` are one
case rather than three.

Two things are refused rather than guessed. A bit field is a run of bits inside
a word it shares, and reading it from its byte would answer whatever its
neighbours hold. And an index that is negative is refused rather than widened:
an `int` holding -1 read as an unsigned index is four billion elements along,
which passes every bounds check that compares the wrong way.

Half the watches in a session are out of scope at any moment, so a watch that
cannot be read is a line saying why rather than a missing row -- a pane that
drops what it could not evaluate lies about how many watches there are.

## Linux

Everything above works identically under `ptrace`:

```
$ sldb run /home/brandon/spike/fp fixture.sl:41
breakpoint at 0x1262  fixture.sl:41
image slid by 0x5bc2ec101000
stopped at /home/brandon/spike/fixture.sl:41
      in Total                                  (four times, then exit 0)
```

**It was mostly a transcription, which is what the seam was for.** Four
differences were real:

- **Windows reports events; ptrace reports signals.** A planted trap and a
  finished single step are both `SIGTRAP`, told apart only by what the tracer
  asked for -- so the target remembers, and the engine never had to learn.
- **The stop address is read, not reported.** Windows hands over the faulting
  address; here the program counter is fetched, and for a breakpoint it is one
  past the trap exactly as on Windows.
- **Memory is a file.** `/proc/<pid>/mem` with positional reads, which beats
  `PEEKDATA` a word at a time and is simpler -- the rare case of both. And no
  instruction cache to flush: x86 keeps its own coherent with stores.
- **There is no loader breakpoint to swallow.** The first stop is the `SIGTRAP`
  the kernel raises when `execv` completes under a tracer, and that one *is*
  the start of the session.

**The seam had one real hole, and only the second platform could find it: it
never said who consumes the first stop.** `Engine.Start` called `Continue`,
which resumes before waiting -- harmless on Windows, where nothing has been
reported and the resume finds no event outstanding. On Linux the launch has
already reaped the exec's `SIGTRAP`, so the same call let the program run
before its image base had been read, and a slide nobody learned is every
breakpoint unplanted. Nothing resumes before the first event is read now.

**A stdlib bug came with it.** `Standard.File.ReadAllBytes` trusted the size a
file reports, and `/proc` reports zero and then hands over kilobytes -- so
`/proc/<pid>/maps` came back empty and the loader base with it. It reads to the
end now, which is what "all bytes" has to mean on Linux;
`tests/cases/proc-files` pins it and fails without it.

**`Attach` is not implemented and would ship untested if it were.** Under
Linux's default `ptrace_scope` a process may trace its own child and nothing
else, so every test here launches. That is said where it matters rather than
left to be discovered.

## What the window gets

A `Snapshot`: where the program stopped, its call stack, and every local in
scope, read on the session's thread while the program was stopped and numbers
and text afterwards. `src/Session.sl` builds it and `sldb snapshot` prints it.

```
$ sldb snapshot demo.exe fixture.sl:41
state    stopped
stop     breakpoint
where    ...\demo/fixture.sl:41
function Total
frames
  #0  Total                   ...\demo/fixture.sl:41
  #1  Main                    ...\demo/fixture.sl:61
locals
  values      int[]                   4 elements at 0x2d0b4451e60   (parameter)
  sum         int                     0
  i           nuint                   0
  here        int                     1
watches
  (none)
```

**A pane MUST NOT show more than a snapshot holds.** Anything the IDE needs is
a field added here first, so that `sldb snapshot` covers it headlessly. The
window never calls into the engine at all: every call into a debuggee must come
from the one thread that launched it, and by the time a pane paints that thread
is busy.

The two exceptions are `Engine.RequestBreak` and `ITarget.RequestBreak`, which
another thread MAY call. Neither touches the tracing relationship: Windows
creates a thread inside the target that executes an `int3`, Linux sends
`SIGSTOP`, and each arrives at the session's thread as an ordinary event. Only
the engine can tell the result from a fault, because only the engine knows it
asked -- which is what `StopKind.Paused` is.

## Still to come

**The six comparisons**, which is what a conditional breakpoint needs and the
only part of the watch grammar deliberately left out of it.

**Real unwind info**, for `-O2` and for frames through the C runtime. The
frame-pointer walk is right at `-O0` and answers one frame where there is no
frame pointer. `.eh_frame` on ELF and `.pdata` on PE are already in every
binary this compiler produces.

Named rather than done, in the value reader: a `struct` prints as its address
and size rather than member by member; a `double` prints its bits, because
reinterpreting eight bytes as a float needs a cast this does not have yet; and
a variant prints nothing useful, because the cases are numbered in declaration
order while DWARF gets a member only for the ones carrying a payload -- the
k-th member is not tag k, and twelve lines of compiler would fix it properly.

Step-in stops at the callee's first instruction rather than at `prologue_end`,
so the first step into a function lands before its locals have slots.
