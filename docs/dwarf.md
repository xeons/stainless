# What the debug information actually contains

Everything on this page was **measured**, on a binary built by the compiler in
this tree, and every claim names the command that produced it. That is the
point of the page: a debug engine is built on a dozen assumptions
about what LLVM emits for us, and three of the ones this started with were
wrong.

The subject is `-g -O0`, which is what the IDE's Debug configuration passes and
the only thing a debugger is expected to cope with. Where `-O2` differs it is
said so.

> **`-g` alone is not a debug build.** The default optimisation level is `-O2`,
> so `stainless build -g` gives an optimised binary *with* debug information:
> small functions are inlined away, locals live in `.debug_loclists` rather than
> at a fixed frame offset, and `DW_AT_frame_base` is the stack pointer because
> there is no frame pointer to point at. Measuring that by mistake is how the
> first draft of this page reached four wrong conclusions. Pass `-O0`.

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

-- and `llvm-objdump -h` reads all eight back in full: `.debug_abbrev`,
`.debug_addr`, `.debug_info`, `.debug_line`, `.debug_line_str`,
`.debug_loclists`, `.debug_str`, `.debug_str_offsets`.

**What a reader has to do.** The name field holds `/NNN`, a *decimal* byte
offset into the COFF string table, and the string table sits at
`PointerToSymbolTable + NumberOfSymbols * 18`. The trap is that lld writes
**`NumberOfSymbols` = 0** while leaving `PointerToSymbolTable` pointing at a
string table that exists and is 116 bytes long -- so a reader that treats "no
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
| ours, as the compiler emits today | `DW_OP_reg7 RSP` |
| ours, with `"frame-pointer"="all"` | `DW_OP_reg6 RBP` |
| clang's own C at `-O0` | `DW_OP_reg6 RBP` |
| the C runtime, as the toolchain builds it | `DW_OP_call_frame_cfa, DW_OP_consts -N, DW_OP_plus` |

So a local is one register read and an addition, and `DW_OP_call_frame_cfa`
appears only in the C runtime's own compilation units. A reader still needs the
third form to step into `arc.c`, but nothing about reading a Stainless local
depends on it.

## 3. There is no frame pointer, and one attribute is the whole fix

`grep -c "^attributes" ` over a real `-g -O0` module answers **zero**: the
emitter writes no function attributes at all, so LLVM omits the frame pointer
at every level. `Total` begins `sub $0x38,%rsp` and its locals are at
`0x30(%rsp)`, `0x2c(%rsp)`, `0x20(%rsp)` -- matching `DW_OP_fbreg +48`, `+44`,
`+32` exactly, so the description is correct; it is simply describing a frame
that cannot be walked.

Adding one attribute group and putting it on every definition changes the
prologue to what an unwinder wants:

```
00000000000435e0 <_SL7Fixture5TotalAiEi>:
   435e0:  55              push   %rbp
   435e1:  48 89 e5        mov    %rsp,%rbp
   435e4:  48 83 ec 40     sub    $0x40,%rsp
```

and `DW_AT_frame_base` becomes `DW_OP_reg6 RBP` on 1532 of the 1647
subprograms, with `values` moving from `DW_OP_fbreg +48` to `DW_OP_fbreg -8` --
which is `-0x8(%rbp)` in the disassembly. The 115 that keep RSP are the C
runtime objects, which were not rebuilt with it.

Unwinding is then `PC(n+1) = [RBP(n)+8]`, `RBP(n+1) = [RBP(n)]`, and no CFI
interpreter is needed to show a call stack at `-O0`.

## 4. Whether the unit uses ranges depends on the link, not the platform

Our compile unit describes its code two different ways in two binaries built
from the same source:

- **ELF**: `DW_AT_ranges [DW_FORM_rnglistx]`, and `.debug_rnglists` is present.
- **PE**: `DW_AT_low_pc [DW_FORM_addrx]` + `DW_AT_high_pc [DW_FORM_data4]`,
  covering `0x140001000..+0x54555`, and there is no `.debug_rnglists` at all.

The difference is not Windows against Linux. The ELF links sixteen C runtime
compilation units whose code is interleaved with ours, so our unit's code is no
longer contiguous and needs a range list; the PE carries one unit covering one
contiguous stretch. **A reader must handle both**, and must not conclude from
one binary that it will only ever see the other.

All four DWARF 5 base attributes are emitted where they are needed:
`DW_AT_str_offsets_base`, `DW_AT_addr_base`, `DW_AT_loclists_base`, and
`DW_AT_rnglists_base` when range lists are used. Tools default these when they
are missing, so their presence has to be checked rather than inferred from a
dump that resolved.

## 5. `prologue_end` is emitted, and so is `epilogue_begin`

1664 rows of one fixture's line table carry `prologue_end`. `Total` begins at
`0x1200` and its `prologue_end` is at `0x1204`, which is where a breakpoint on
the function belongs.

```
0x1200  line 35            is_stmt
0x1204  line 35 col 1      is_stmt prologue_end
0x1209  line 37 col 5      is_stmt
...
0x1293  line 43 col 5      epilogue_begin
0x1298  line 43 col 5      end_sequence
```

So a breakpoint on a function does not have to guess where the prologue ends by
counting instructions, which is the usual fallback and is wrong on any function
the register allocator treated unusually.

## 6. Unwind tables are there, and they cover Stainless functions

Not only the C runtime, which was the thing worth checking.

- **ELF**: `.eh_frame` and `.eh_frame_hdr`, with an FDE at
  `pc=0x1200..0x1298` -- exactly `Total`'s symbol address and size.
- **PE**: `.pdata`, 461 `RUNTIME_FUNCTION` entries, starting at the first byte
  of `.text`.

The definitions are not `nounwind`, which is why. **If anyone ever adds
`nounwind` to definitions as an optimisation, `uwtable` has to go on in the
same commit**, or this disappears and every stack through optimised code goes
with it.

## 7. Every form and tag the emitter actually produces

A reader that meets a form it has no rule for cannot skip it, and loses its
place in the DIE stream for the rest of the unit. This is the complete list for
one `-g -O0` binary, which is the list to write skip rules against:

```
data1  13641    ref4    8266    strx2   6908    exprloc 6344
data2   4735    strx1   3233    flag_present 2006
data4   1707    addrx   1707    udata    577    sdata    110
sec_offset 69   rnglistx  17    addr      17    loclistx   5
```

**Both `strx1` and `strx2` appear**, and the difference matters:
a unit with ~18,000 metadata nodes has more strings than one byte indexes, so a
reader that implements only `strx1` works on a small program and fails on a
real one.

Tags, most common first: `formal_parameter` 2993, `variable` 1828,
`subprogram` 1647, `member` 1223, `enumerator` 452, `pointer_type` 405,
`structure_type` 368, `typedef` 265, `base_type` 152, `const_type` 128,
`subrange_type` 80, `array_type` 80, `subroutine_type` 60, `lexical_block` 60,
`enumeration_type` 30, `compile_unit` 17, `inheritance` 11, `union_type` 8,
`volatile_type` 1.

## Four things that will bite a reader

**There are no lexical blocks in our units.** The 60 above belong to the C
runtime's clang-built units. `Total` declares `int here` inside a loop body and
its DIE sits flat under the subprogram beside `values`, `sum` and `i` --
so a debugger stopped before that line will show a variable that is not in
scope yet, holding whatever the stack slot happened to contain. Filtering by
`DW_AT_decl_line` in the engine would be guessing at something the compiler
knows and could say.

**A Windows DWARF build describes the Stainless module and nothing else.** The
C runtime objects are compiled for the MSVC target and carry CodeView, so a
forced-DWARF PE has exactly one compile unit, and `sl_retain` appears nowhere
in it. Stepping into the runtime is therefore not a thing that can be switched
on there -- it is a thing that does not exist unless the runtime is also built
`-gdwarf`.

**Paths mix separators within one string.** A `DW_AT_decl_file` on Windows
reads `C:\...\scratchpad\dwarf\obj\stdlib/Text.sl` -- backslashes from the
directory and a forward slash from the part the compiler joined on. Matching a
breakpoint's file against one of these by string comparison will not work.

**`DW_AT_language` is `DW_LANG_C_plus_plus`.** We are not C++, and a consumer
that switches on the language -- for name demangling above all -- will do the
wrong thing with a `_SL`-mangled name.

## Where this leads

The compiler-side changes a debugger needs are unchanged by this, except that
the frame pointer is now measured rather than assumed and is the one that
unblocks call stacks. Two more are worth adding to them: emit
`DW_AT_language` as something that is not C++, and decide whether the
`--debug-format` switch also rebuilds the C runtime with DWARF on Windows,
because today choosing DWARF there silently narrows what can be stepped.
