// SPDX-License-Identifier: 0BSD
//
// The other side of the boundary. These are ordinary C globals; what the case
// is about is that Stainless names them directly rather than through a getter.
#include <stddef.h>

int  probe_counter = 7;

/* `long long`, not `long`. A Stainless `long` is a fixed 64 bits on every
   target -- C's `long long` -- and C's own `long` is 32 bits on Windows. With
   a function the mismatch is an argument nobody reads; with a variable it is a
   silent 8-byte load from a 4-byte global, which reads whatever follows it. */
long long probe_wide = -1;
const char *probe_name = "defined in C";

/* Defined in Stainless, read here. */
extern int sl_depth;
extern int sl_flags;

void probe_bump(void)  { probe_counter += 1; }
int  probe_read(void)  { return probe_counter; }
int  sl_depth_from_c(void) { return sl_depth; }
int  sl_flags_from_c(void) { return sl_flags; }
void set_sl_flags(int value) { sl_flags = value; }
