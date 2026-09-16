// SPDX-License-Identifier: 0BSD
//
// A static outlives every thread, so whatever it holds is reachable from all
// of them at once. Nothing synchronizes a List, and the warning says so --
// then compiles it, because a program with one thread has no race to have.
module Bad;

import Standard.Collections;

extern "C" int printf(byte* format, ...);

static readonly List<int> Registry = new List<int>();

int Main()
{
    Registry.Add(7);
    printf("registry=%llu %d\n", Registry.Count(), Registry.At(0u));
    return 0;
}
