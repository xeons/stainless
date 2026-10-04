// SPDX-License-Identifier: 0BSD
//
// int128 needs a 64-bit target: clang has no __int128 on a 32-bit one, and
// compiler-rt divides one for a 64-bit target alone.
module BadInt128;

int128 Twice(int128 value) => value * 2;

int Main() => 0;
