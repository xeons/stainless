// SPDX-License-Identifier: 0BSD
//
// Built for Linux from whatever host runs the suite. Microsoft would open a
// new storage unit at 'B', because the declared type's size changes; Itanium
// packs it into the same int. The target decides, not the machine compiling.
module Bits;

public struct Mixed { public int A : 3; public byte B : 2; }

public int MixedSize() => (int)sizeof(Mixed);
