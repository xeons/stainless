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
differing         0            0
```

-- every offset and every tag, across seventeen compilation units and every
form the compiler emits. That is the check to repeat after any change here, and
it is worth more than any number of assertions about individual fields.

Two things it does not cover, and which the self test does instead: that every
form this engine can *name* it can also *skip*, and that one it has never heard
of is refused rather than skipped by zero bytes. Both are the same failure --
losing position in a stream whose entries carry no length, and then producing
entries that still look plausible.

## Still to come

The line-number program, so that a file and a line can be turned into an
address and back; then process control (`ITarget`, the `DEBUG_EVENT` loop,
`ptrace`), stack walking, values, and the IDE surface.
