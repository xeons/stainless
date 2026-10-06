// SPDX-License-Identifier: 0BSD
module Bad;

public interface INamed
{
    String Name();
}

public class Animal { }
public class Dog : Animal { }

// None of these is ever instantiated; each is refused where it is written.

// Two clauses for one parameter.
T Twice<T>(T v) where T : class where T : INamed => v;           // SLG0015

// One constraint written twice.
T Repeated<T>(T v) where T : INamed, INamed => v;                // SLG0016

// Two base classes.
T TwoBases<T>(T v) where T : Animal, Dog => v;                   // SLG0017

// Each parameter required to be the other.
T Circle<T, U>(T a, U b) where T : U where U : T => a;           // SLG0018

// 'default' with nothing inherited to undo.
T Plain<T>(T v) where T : default => v;                          // SLG0019

// A struct cannot constrain anything.
public struct Point { public int X; }
T ByPoint<T>(T v) where T : Point => v;                          // SLG0007

// And the new words demand what they say.
nuint Size<T>(T v) where T : unmanaged => 0;
T Keep<T>(T v) where T : notnull => v;

int Main()
{
    var n = Size("text");                                        // SLG0006
    Dog? missing = null;
    var k = Keep(missing);                                       // SLG0006
    return 0;
}
