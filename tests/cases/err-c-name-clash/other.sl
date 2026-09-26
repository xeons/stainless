// SPDX-License-Identifier: 0BSD
module Other;

// Another module is no escape: the linker has one namespace.
export "C" int Twin(long x) => 2;

// Nor is declaring it with a prototype the definition does not have.
extern "C" int Solo(double x);

export "C" int Solo(int x) => x;
