// SPDX-License-Identifier: 0BSD
module Bad;

class Owner { int value; }

// A struct may hold a reference; copying it then maintains the count.
struct Holder { Owner owner; }

// What it may not do is cross a C boundary, in either direction: C would
// copy the bytes and leave the count behind.
extern "C" void consume(Holder h);

export "C" Holder produce() { Holder h; return h; }

int Main() { return 0; }
