// SPDX-License-Identifier: 0BSD
//
// Operators, static constructors and statics on a generic type.
//
// All three used to be dropped by monomorphization, and the first two were
// dropped in the same way: `Instantiate` queued the bodies of `type.Methods`
// and nothing else. An operator is deliberately not a method -- it has no
// receiver and no dispatch slot -- so `a + b` bound, mangled, and named a
// function that was never emitted. The only sign of it was a link error.
//
// Statics failed one step later. Their initializers are bound and ordered in a
// pass of their own, which had already finished by the time a body bound during
// monomorphization asked for a new instantiation -- so that instantiation's
// storage was never allocated. The passes are interleaved now: bodies and
// statics feed each other until neither has anything left, and only then is the
// order the initializers run in settled.
module GenericOperators;

import Standard.Console;

// ------------------------------------------------------------------ a struct

public struct Box<T>
{
    public T Value;

    public static Box<T> operator +(Box<T> a, Box<T> b) { return BoxOf(a.Value + b.Value); }
    public static Box<T> operator -(Box<T> a, Box<T> b) { return BoxOf(a.Value - b.Value); }
    public static Box<T> operator -(Box<T> a) { return BoxOf(0 - a.Value); }

    public static bool operator ==(Box<T> a, Box<T> b) { return a.Value == b.Value; }
    public static bool operator !=(Box<T> a, Box<T> b) { return a.Value != b.Value; }

    public T Get() => Value;
}

/// A module-level function rather than a static one, because `Box<int>.Of(2)`
/// is not something the parser reads today -- a type argument list is only
/// written where a type is expected.
public Box<T> BoxOf<T>(T value)
{
    Box<T> made;
    made.Value = value;
    return made;
}

// ------------------------------------------------------------------- a class

public class Pair<T>
{
    public T First { get; set; }
    public T Second { get; set; }

    public Pair(T first, T second)
    {
        First = first;
        Second = second;
    }

    public static Pair<T> operator +(Pair<T> a, Pair<T> b)
    {
        return new Pair<T>(a.First + b.First, a.Second + b.Second);
    }

    public T this[int index] { get { return index == 0 ? First : Second; } }
}

// ------------------------------------- a static, and a block that sets it up

public struct Counted<T>
{
    // One per instantiation rather than one per template: `Counted<int>` and
    // `Counted<long>` count separately, which the output below shows.
    public static int Made = 0;

    static Counted() => Made = 100;

    public T Value;

    public static Counted<T> operator +(Counted<T> a, Counted<T> b)
    {
        Made = Made + 1;

        Counted<T> made;
        made.Value = a.Value + b.Value;
        return made;
    }

    public int Count() => Made;
}

// ----------------------------------- reached only from inside another generic

/// `Counted<T>` at `uint` is asked for while this body is being bound, which
/// happens after the pass that binds statics would have run. That is the case
/// the interleaving exists for: the operator, the static and the static
/// constructor all arrive late and still have to be emitted.
public int Late<T>(T left, T right)
{
    Counted<T> a;
    a.Value = left;

    Counted<T> b;
    b.Value = right;

    return (a + b).Count();
}

public int Main()
{
    var a = BoxOf(2);
    var b = BoxOf(3);

    Console.WriteLine("int      = " + Text.FromInteger((long)(a + b).Get()));
    Console.WriteLine("minus    = " + Text.FromInteger((long)(a - b).Get()));
    Console.WriteLine("unary    = " + Text.FromInteger((long)(-a).Get()));
    Console.WriteLine("equal    = " + Text.FromBool(a == b));
    Console.WriteLine("notEqual = " + Text.FromBool(a != b));

    // A second instantiation of the same template, which needs its own body.
    var c = BoxOf(40L);
    var d = BoxOf(2L);
    Console.WriteLine("long     = " + Text.FromInteger((c + d).Get()));

    var e = BoxOf(0.5);
    var f = BoxOf(0.25);
    Console.WriteLine("double   = " + Text.FromDouble((e + f).Get()));

    // A class, whose operator allocates.
    var p = new Pair<int>(1, 2) + new Pair<int>(10, 20);
    Console.WriteLine("pair     = " + Text.FromInteger((long)p[0])
        + " " + Text.FromInteger((long)p[1]));

    // 100 from the static constructor, then one per operator call.
    Counted<int> g;
    g.Value = 7;

    var once = g + g;
    var twice = once + g;
    Console.WriteLine("counted  = " + Text.FromInteger((long)twice.Count())
        + " " + Text.FromInteger((long)twice.Value));

    // Its own count, because the static belongs to the instantiation.
    Counted<long> h;
    h.Value = 1L;
    Console.WriteLine("separate = " + Text.FromInteger((long)(h + h).Count()));

    uint one = 1u;
    uint two = 2u;
    Console.WriteLine("late     = " + Text.FromInteger((long)Late(one, two)));
    return 0;
}
