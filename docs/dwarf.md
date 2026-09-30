# What the debug information actually contains

Everything on this page was **measured**, on a binary built by the compiler in
this tree, and every claim names the command that produced it. That is the
point of the page: a debug engine is built on a dozen assumptions about what
LLVM emits for us, and a reading of LLVM's output is not a measurement of it.

The subject is `-g -O0`, which is what the IDE's Debug configuration passes and
the only thing a debugger is expected to cope with. Where `-O2` differs it is
said so. The fixture is a `Total(int[] values)` summing in a `for` loop, with a
local `here` inside the loop, called from `Main`.

> **`-g` alone is not a debug build.** The default optimisation level is `-O2`,
> so `stainless build -g` gives an optimised binary *with* debug information:
> small functions are inlined away and locals live in `.debug_loclists` rather
> than at a fixed frame offset. The frame pointer survives, because `-g` asks
> for it (section 3). Pass `-O0`.

## How to re-measure any of it

`llvm-dwarfdump` is not in the Windows LLVM install; it is on the Linux box at
`/usr/lib/llvm-21/bin/`, and it reads PE as happily as ELF, so a Windows binary
can be copied over and dumped there. `llvm-objdump` and `llvm-readobj` *are* on
Windows, which is enough for sections and unwind tables.

```
stainless build fixture.sl -g -O0 -o f0
llvm-dwarfdump --debug-info --verbose f0    # DIEs, with the form of every attribute
llvm-dwarfdump --debug-line f0              # the line table, rows and flags
llvm-dwarfdump --show-section-sizes f0
llvm-objdump -h f0                          # section names, which is question one
llvm-readobj --unwind f0                    # .pdata on a PE
readelf --debug-dump=frames f0              # .eh_frame on an ELF
```

## 1. The DWARF section names survive a PE link

This was the question that could have changed the format, because every DWARF
section name is longer than the eight bytes a COFF section header holds, and
`.debug_line` and `.debug_line_str` both truncate to `.debug_l`.

They survive. `lld-link` says so on the way past --

```
lld-link: warning: section name .debug_line_str is longer than 8 characters
                   and will use a non-standard string table
```

-- and `llvm-objdump -h` reads all nine back in full: `.debug_abbrev`,
`.debug_addr`, `.debug_info`, `.debug_line`, `.debug_line_str`,
`.debug_loclists`, `.debug_rnglists`, `.debug_str`, `.debug_str_offsets`.

**What a reader has to do.** The name field holds `/NNN`, a *decimal* byte
offset into the COFF string table, and the string table sits at
`PointerToSymbolTable + NumberOfSymbols * 18`. The trap is that lld writes
**`NumberOfSymbols` = 0** while leaving `PointerToSymbolTable` pointing at a
string table that exists and is 132 bytes long -- so a reader that treats "no
symbols" as "no string table" resolves nothing. A name of exactly eight
characters has no terminator, which is the other half of the same function.

Measured with `llvm-objdump -h` and again by parsing the headers by hand,
because the first tool resolves the indirection and therefore cannot prove it
is there.

## 2. `DW_AT_frame_base` is a register, not the CFA

The obvious reading of LLVM's x86-64 output is `DW_OP_call_frame_cfa`, which
would mean a local could not be read without a CFA and therefore without an
unwinder. **That is not what is emitted, for us or for clang.**

| built as | `DW_AT_frame_base` |
|---|---|
| ours, with `-g` | `DW_OP_reg6 RBP` |
| ours, with no frame pointer | `DW_OP_reg7 RSP` |
| clang's own C at `-O0` | `DW_OP_reg6 RBP` |
| the C runtime, as the toolchain builds it (`-O0 -g`) | `DW_OP_reg6 RBP` |

So a local is one register read and an addition. All 912 subprograms of an ELF
`-g -O0` build, the C runtime's included, name RBP. `DW_OP_call_frame_cfa` is
still worth a rule in a reader: it is what a C library built with optimisation
writes, and nothing guarantees what a system library was built with.

## 3. There is a frame pointer, because `-g` asks for one

LLVM omits the frame pointer at every optimisation level unless a function
says otherwise, `-O0` included. So under `-g` the emitter writes one attribute
group, `attributes #0 = { "frame-pointer"="all" }`, and puts it on every
definition; without `-g` it writes none. The prologue is then what an unwinder
wants:

```
00000000000011b0 <_SL7Fixture5TotalAiEi>:
    11b0:  pushq  %rbp
    11b1:  movq   %rsp, %rbp
    11b4:  subq   $0x40, %rsp
    11b8:  movq   %rdi, -0x8(%rbp)
```

and `values` is `DW_OP_fbreg -8`, which is `-0x8(%rbp)` in the disassembly.
Without the attribute the same function begins `sub $0x38,%rsp` and its locals
are `DW_OP_fbreg +48` and upwards against RSP: a correct description of a
frame that cannot be walked.

Unwinding is `PC(n+1) = [RBP(n)+8]`, `RBP(n+1) = [RBP(n)]`, and no CFI
interpreter is needed to show a call stack at `-O0`.

## 4. The unit is a range list, and most of it is at address zero

Our compile unit describes its code as `DW_AT_ranges [DW_FORM_rnglistx]` on
both ELF and PE, with `DW_AT_low_pc` zero beside it. Every function is compiled
into a section of its own and the linker drops the sections nothing reaches, so
the unit's code is not one stretch.

**A dropped function is still described.** Its subprogram and its range-list
entry stay, with the address the linker could not give it written as zero: on
a PE build of a small fixture, 551 of the unit's 554 ranges begin at
`0x0000000000000000`, and so do 551 of its subprograms' `DW_AT_low_pc`. A
reader that maps an address back to a function MUST skip them, or its table of
functions fills with hundreds of overlapping ranges that describe nothing.

A subprogram or a lexical block with contiguous code is `DW_AT_low_pc
[DW_FORM_addrx]` and `DW_AT_high_pc [DW_FORM_data4]`, so a reader still needs
both shapes.

All four DWARF 5 base attributes are emitted where they are needed:
`DW_AT_str_offsets_base`, `DW_AT_addr_base`, `DW_AT_loclists_base`, and
`DW_AT_rnglists_base` when range lists are used. Tools default these when they
are missing, so their presence has to be checked rather than inferred from a
dump that resolved.

## 5. `prologue_end` is emitted, and so is `epilogue_begin`

928 rows of one fixture's line table carry `prologue_end`. `Total` begins at
`0x11b0` and its `prologue_end` is at `0x11b8`, past the frame pointer's
setup, which is where a breakpoint on the function belongs.

```
0x11b0  line 11            is_stmt
0x11b8  line 11 col 1      is_stmt prologue_end
0x11bc  line 13 col 5      is_stmt
...
0x1232  line 19 col 5      epilogue_begin
0x1238  line 19 col 5      end_sequence
```

So a breakpoint on a function does not have to guess where the prologue ends by
counting instructions, which is the usual fallback and is wrong on any function
the register allocator treated unusually.

## 6. Unwind tables are there, and they cover Stainless functions

Not only the C runtime, which was the thing worth checking.

- **ELF**: `.eh_frame` and `.eh_frame_hdr`, with an FDE at
  `pc=0x11b0..0x1238` -- exactly `Total`'s symbol address and size.
- **PE**: `.pdata`, 458 `RUNTIME_FUNCTION` entries, starting at the first byte
  of `.text`.

The definitions are not `nounwind`, which is why. **If anyone ever adds
`nounwind` to definitions as an optimisation, `uwtable` has to go on in the
same commit**, or this disappears and every stack through optimised code goes
with it.

## 7. Every form and tag the emitter actually produces

A reader that meets a form it has no rule for cannot skip it, and loses its
place in the DIE stream for the rest of the unit. This is the complete list for
one `-g -O0` ELF binary, which is the list to write skip rules against:

```
data1   9497    ref4    5318    exprloc 3554    strx1   3296
strx2   2694    data2   1766    flag_present 1281
data4   1168    addrx   1168    udata    417    sec_offset 65
rnglistx  16    addr      16    sdata     10    loclistx   6
```

**Both `strx1` and `strx2` appear**, and the difference matters:
every program carries the standard library's functions, so its unit has more
strings than one byte indexes even when the program is twenty lines. A reader
that implements only `strx1` fails on every binary this compiler writes.

Tags, most common first: `formal_parameter` 1666, `variable` 1045,
`subprogram` 912, `member` 906, `pointer_type` 376, `enumerator` 362,
`typedef` 272, `lexical_block` 256, `structure_type` 212, `const_type` 151,
`base_type` 142, `subrange_type` 101, `array_type` 101, `subroutine_type` 54,
`enumeration_type` 19, `compile_unit` 16, `union_type` 10, `volatile_type` 2.
A program with a class hierarchy adds `inheritance`, and one with an interface
reference a structure with `DW_AT_declaration`. Every program carries an
`Optional` of a reference from the standard library, so every unit also has
`variant_part` and `variant`, with `DW_AT_discr` on the part and
`DW_AT_discr_value` on the variant for the empty case.

## Four things that will bite a reader

**A block's scope starts at its first instruction, not at a declaration.** A
`{ }` and a `for` are each a `DW_TAG_lexical_block` with its own address range,
and `Total`'s `here` sits in the loop body's block. A local declared halfway
down a block is in that block's scope from the block's first instruction, so a
debugger stopped above its declaration line shows it holding whatever the stack
slot happened to contain.

**A Windows DWARF build describes the Stainless module and nothing else.** The
C runtime objects are compiled for the MSVC target and carry CodeView, so a
forced-DWARF PE has exactly one compile unit, and `sl_retain` appears nowhere
in it. Stepping into the runtime is therefore not a thing that can be switched
on there -- it is a thing that does not exist unless the runtime is also built
`-gdwarf`.

**Paths mix separators once they are joined.** A file is a name and a directory,
stored apart, and on Windows the directory is written with backslashes:
`C:\...\scratchpad\abi\obj\stdlib\Text` and `Format.sl`. Whoever joins them
chooses the separator, so `llvm-dwarfdump` on Linux prints
`C:\...\scratchpad\abi/fixture.sl`. Matching a breakpoint's file against one of
these by string comparison will not work.

**`DW_AT_language` is `DW_LANG_C_plus_plus`.** We are not C++, and a consumer
that switches on the language -- for name demangling above all -- will do the
wrong thing with a `_SL`-mangled name.

## Where this leads

`--debug-format` picks the format, and without it the format follows the
**target** rather than the machine the compiler is running on --
[docs/cli.md](cli.md#which-debugger-reads-it) is the page. The C runtime is not
rebuilt with DWARF on Windows, so choosing DWARF there narrows what can be
stepped to the Stainless module, as measured above. And `DW_AT_language` is
`DW_LANG_C_plus_plus`, which is wrong.
