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
T Twice<T>(T v) where T : class where T : INamed => v;           // SL0788

// One constraint written twice.
T Repeated<T>(T v) where T : INamed, INamed => v;                // SL0789

// Two base classes.
T TwoBases<T>(T v) where T : Animal, Dog => v;                   // SL0790

// Each parameter required to be the other.
T Circle<T, U>(T a, U b) where T : U where U : T => a;           // SL0791

// 'default' with nothing inherited to undo.
T Plain<T>(T v) where T : default => v;                          // SL0792

// A struct cannot constrain anything.
public struct Point { public int X; }
T ByPoint<T>(T v) where T : Point => v;                          // SL0329

// And the new words demand what they say.
nuint Size<T>(T v) where T : unmanaged => 0;
T Keep<T>(T v) where T : notnull => v;

int Main()
{
    var n = Size("text");                                        // SL0328
    Dog? missing = null;
    var k = Keep(missing);                                       // SL0328
    return 0;
}
