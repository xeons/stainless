// SPDX-License-Identifier: 0BSD
//
// A 'late' field whose type does not resolve is reported once, for the type.
// Found by the fuzzer, as an internal compiler error asking whether '<error>'
// could be late.
module ErrLateUnresolved;

class Holder
{
    late Missing Entry;     // SLN0017, and nothing about 'late'
}

int Main() => 0;