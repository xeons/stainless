// SPDX-License-Identifier: 0BSD
//
// What a module-level variable may and may not be.
//
// Storage that crosses to C is the one there is a reason for, because the name
// belongs to the C library rather than to this program. Everything else at
// module scope is still refused: a mutable global with no boundary to justify
// it is state every thread reaches and nothing declares.
module BadExternVariables;

// A declaration of storage defined elsewhere cannot also define it.
extern "C" int already_there = 5;

// A C++ variable's name is mangled by rules neither ABI shares with its
// functions, and none of that is written.
extern "C++" int cpp_global;

// And an ordinary module-level variable is refused as it always was.
int plain;

int Main() { return 0; }
