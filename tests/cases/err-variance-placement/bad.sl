// SPDX-License-Identifier: 0BSD
module Bad;

// Only an interface's or a delegate's parameters may be written with a
// variance: it says when one instantiation may stand for another.
public class Box<out T> { }                      // SL0800

public struct Pair<in T> { }                     // SL0800

T Pick<out T>(T value) => value;                 // SL0800

int Main() => 0;
