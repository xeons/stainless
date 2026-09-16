// SPDX-License-Identifier: 0BSD
module Bad;

// Two functions in one module collide exactly when their parameter types do.
// Without the check both were emitted under one symbol and LLVM reported the
// redefinition, in a message about generated IR.
public int F(int a) => a + 1;
public int F(int a) => a + 2;

// A return type alone does not distinguish two functions.
bool G(String s) => true;
int G(String s) => 1;

// The mode is part of a signature, but the type is what is compared.
void H(ref int x) => x = 1;
void H(int x) { }

// An extern redeclared is the same mistake: one C symbol, two prototypes.
extern "C" int puts(byte* text);
extern "C" int puts(byte* text);

// Overloads that differ are fine.
int K(int a) => a;
int K(long a) => 0;

int Main() => 0;
