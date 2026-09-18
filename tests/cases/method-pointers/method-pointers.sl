// SPDX-License-Identifier: 0BSD
//
// `closure`: a function and the object it belongs to.
//
// A `delegate` is one pointer, which is what makes it a C function pointer and
// what stops it carrying anything -- a lambda that reads a name from around it
// cannot become one. A closure is that pointer *and* a receiver, which is what
// Delphi means by `of object` and what a callback has to be if it is to know
// anything.
//
// The representation costs nothing to support: a method already takes its
// receiver as argument zero, so a bound method pointer is literally {method,
// object} and calling one is a direct indirect call. Being two fields is also
// what gives it layout, both ABI classifiers, and the reference walking that
// retains and releases what it holds -- none of which was written for it.
module MethodPointers;

import Standard.Collections;
import Standard.Console;

extern "C" int printf(byte* format, ...);

public closure void Notify(int value);
public closure int Fold(int running, int value);

class Counter
{
    public String Name;
    public int Total;

    public Counter(String name)
    {
        Name = name;
        Total = 0;
    }
    ~Counter() { printf("~Counter(%s)\n", Name.ToPointer()); }

    public void Add(int value) => Total = Total + value;
    public void Subtract(int value) => Total = Total - value;

    public int Combine(int running, int value) => running + value + Total;
}

void Say(String label, String value)
{
    Console.WriteLine(label + " = " + value);
}

/// A closure passed like any other value.
void Repeat(Notify what, int times, int with)
{
    for (int i = 0; i < times; i = i + 1)
        what(with);
}

/// And returned, which is what proves the receiver outlives its scope.
Notify Escaping()
{
    var counter = new Counter("escaped");
    return counter.Add;
}

public int Main()
{
    var one = new Counter("one");
    var two = new Counter("two");

    // ------------------------------------------------- bound methods
    Notify first = one.Add;
    Notify second = two.Add;

    first(5);
    first(3);
    second(100);

    Say("one", Text.FromInteger((long)one.Total));
    Say("two", Text.FromInteger((long)two.Total));

    // The same object, a different method.
    Notify down = one.Subtract;
    down(1);
    Say("after-subtract", Text.FromInteger((long)one.Total));

    // ------------------------------------------------------ equality
    // Two words: the same method *and* the same object. This is what a value
    // buys over an object -- two mentions of `one.Add` are equal, where two
    // generated wrappers would not have been.
    Say("same", Text.FromBool(first == one.Add));
    Say("other-object", Text.FromBool(first == two.Add));
    Say("other-method", Text.FromBool(first == one.Subtract));
    Say("not-equal", Text.FromBool(first != two.Add));

    // ------------------------------------------------------- lambdas
    // A capturing lambda is the same type and the same two words: the object
    // is the class the compiler generated to hold what was captured.
    //
    // **Capture is by value**, taken when the closure is made, so a captured
    // `int` is a copy and writing it changes nothing outside. Capturing a
    // *reference* captures the reference, and what it points at is shared --
    // which is how a handler reaches the thing it is meant to change.
    var counted = new Counter("counted");
    Notify through = (v) => { counted.Add(v); };
    through(4);
    through(6);
    Say("through-capture", Text.FromInteger((long)counted.Total));

    // A copy, to show the other half of the same rule.
    int untouched = 0;
    Notify byValue = (v) => { untouched = untouched + v; };
    byValue(99);
    Say("by-value", Text.FromInteger((long)untouched));

    // A lambda and a bound method are interchangeable.
    Repeat(one.Add, 3, 10);
    Repeat((v) => { counted.Add(v); }, 2, 5);
    Say("repeated", Text.FromInteger((long)one.Total));
    Say("repeated-lambda", Text.FromInteger((long)counted.Total));

    // ------------------------------------------------- a result, and args
    Fold combine = one.Combine;
    Say("fold", Text.FromInteger((long)combine(1, 2)));

    // ------------------------------------------------------ collections
    // An ordinary list of them: what a multicast callback is, with no language
    // feature for it. Closures are values, so `Remove` finds one by comparing
    // both words.
    var handlers = new List<Notify>();
    handlers.Add(one.Add);
    handlers.Add(two.Add);
    handlers.Add(counted.Add);

    for (nuint i = 0u; i < handlers.Count; i = i + 1u)
        handlers[i](1);
    Say("after-all", Text.FromInteger((long)one.Total)
        + "/" + Text.FromInteger((long)two.Total)
        + "/" + Text.FromInteger((long)counted.Total));

    // Found by comparing both words, so the right one goes. `List<T>` has no
    // `Remove(T)` -- its `IndexOf` wants `IEquatable<T>`, which a closure is
    // not -- so this is the scan that would be behind one.
    for (nuint i = 0u; i < handlers.Count; i = i + 1u)
    {
        if (handlers[i] == two.Add)
        {
            handlers.RemoveAt(i);
            break;
        }
    }

    Say("left", Text.FromInteger((long)handlers.Count));

    // And the one removed is the one meant: two is untouched from here on.
    for (nuint i = 0u; i < handlers.Count; i = i + 1u)
        handlers[i](1);
    Say("after-removal", Text.FromInteger((long)one.Total)
        + "/" + Text.FromInteger((long)two.Total)
        + "/" + Text.FromInteger((long)counted.Total));

    // ----------------------------------------------------------- escape
    // The counter is made inside Escaping and nothing else refers to it, so
    // "returned" appearing before the destructor is what proves the closure is
    // holding it: without the retain it would have died on the way out.
    printf("escaping\n");
    {
        Notify held = Escaping();
        printf("returned\n");
        held(7);
    }
    printf("escaped\n");

    return 0;
}
