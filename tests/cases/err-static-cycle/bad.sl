// SPDX-License-Identifier: 0BSD
module Bad;

// No order gives either one a value before the other reads it.
static readonly int First = Second + 1;
static readonly int Second = First + 1;

int Main() { return First; }
