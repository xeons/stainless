// SPDX-License-Identifier: 0BSD
module Bad;

class Owner { int value; }

// A struct is raw bytes, so it cannot own a reference count.
struct Holder { Owner owner; }

int Main() { return 0; }
