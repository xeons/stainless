// SPDX-License-Identifier: 0BSD
module Bad;

// There is no mutable global: nothing would synchronize it.
static int Counter = 0;

int Main() { return Counter; }
