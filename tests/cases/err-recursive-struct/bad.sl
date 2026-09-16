// SPDX-License-Identifier: 0BSD
module Bad;

// A fixed array holds its elements where it is written, so a struct with one
// of itself has no finite size -- exactly as a plain field of itself does.
// Looking only at a struct-typed field missed this: the size was read before
// it was computed, the type came out zero bytes wide, and the emitter wrote an
// LLVM type that referred to itself, which clang reports against generated IR.

struct Direct
{
    public Direct[4] Kids;
}

struct Nested
{
    public Nested[2] Grid;
}

struct First
{
    public Second[2] Seconds;
}

struct Second
{
    public First[2] Firsts;
}

int Main() => 0;
