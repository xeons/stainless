// SPDX-License-Identifier: 0BSD
module Bad;

// A property belongs to a type; a module has no instance to read from.
public int Count { get; set; }

int Main() { return 0; }
