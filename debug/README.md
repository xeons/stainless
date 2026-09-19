# The debug engine

A debugger for Stainless, written in Stainless, with a console front end so
that it can be tested without a window.

```
stainless build --project debug
.\debug\build\sldb --selftest
.\debug\build\sldb sections <binary>
```

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
| `src/Target/Select.sl` | the one `#if` in the engine |
| `src/Engine.sl` | breakpoints, the slide, run control and stepping |
| `src/Stack.sl` | the frame-pointer walk |
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

## Still to come

Values -- locals, the type graph, `String` and arrays, and the runtime type out
of an object header -- and then `ptrace`, which the seam exists to make a
transcription job. The IDE
surface is last and is meant to be thin: everything in it comes from snapshot
types this console tool has already exercised.

**The Linux target is a stub that says so.** `MakeTarget` answers a `Result`,
and on a platform without one it fails with a sentence rather than silently
doing nothing -- the reading half of this engine is complete on both platforms
and every command but `run` works there.
