// SPDX-License-Identifier: 0BSD
module Bad;

// An imported declaration has no body, whichever language it comes from.
extern "C++" int WithBody(int n) { return n; }

// "C" and "C++" are the conventions there are.
extern "Rust" int Elsewhere(int n);

int Main() { return 0; }
