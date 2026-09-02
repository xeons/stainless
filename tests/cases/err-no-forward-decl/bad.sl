// SPDX-License-Identifier: 0BSD
module Bad;

// There are no forward declarations, because order never matters.
int Later();

int Main() { return Later(); }
