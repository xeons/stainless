// SPDX-License-Identifier: 0BSD
module Bad;

// Not a power of two.
[Align(3)]
public struct Odd { public int A; }

// More than the allocator guarantees.
[Align(64)]
public struct TooWide { public double X; }

// Neither applies to a class.
[Packed]
public class Object { public int A; public Object() { A = 0; } }

[Align(8)]
public class Aligned { public int A; public Aligned() { A = 0; } }

// Nor to a variant, whose payload area is not a field the source arranged.
[Packed]
public variant Choice { One(int N); Two; }

int Main() { return 0; }
