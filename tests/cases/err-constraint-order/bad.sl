// SPDX-License-Identifier: 0BSD
//
// How a `where` clause is written, rather than what it demands. The order
// carries no meaning, but a fixed one means every clause reads the same way --
// which is C#'s reason for the same rule.
module Bad;

public interface INamed { String Name(); }

// `class` and `struct` say what kind of type this is, so they come first.
T First<T>(T v) where T : INamed, class { return v; }
T Also<T>(T v) where T : INamed, struct { return v; }

// And a type parameter is one kind or the other, not both.
T Both<T>(T v) where T : class, struct { return v; }

// `new()` is the last thing asked of a parameter.
T Early<T>(T v) where T : new(), INamed { return v; }

// A value type is always made with no arguments, so this adds nothing.
T Redundant<T>(T v) where T : struct, new() { return v; }

// And there is nothing to put in the parentheses: a body that wanted
// arguments would have to know their types.
T Args<T>(T v) where T : new(int) { return v; }

int Main() => 0;
