// SPDX-License-Identifier: 0BSD
module Bad;

class Owner { int value; }
struct Holder { Owner owner; }

// A struct holding a reference cannot cross a language boundary, in either
// direction: the other side would copy its bytes and leave the count behind.
extern "C++" void Consume(Holder h);
export "C++" Holder Produce() { Holder h; return h; }

int Main() { return 0; }
