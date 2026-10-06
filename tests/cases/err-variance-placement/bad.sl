// SPDX-License-Identifier: 0BSD
module Bad;

// Only an interface's or a delegate's parameters may be written with a
// variance: it says when one instantiation may stand for another.
public class Box<out T> { }                      // SLG0022

public struct Pair<in T> { }                     // SLG0022

T Pick<out T>(T value) => value;                 // SLG0022

int Main() => 0;
