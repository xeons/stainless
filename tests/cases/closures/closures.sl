// SPDX-License-Identifier: 0BSD
module Closures;

import Standard.Collections;
import Standard.Console;

extern "C" int printf(byte* format, ...);

public interface ITransform { int Apply(int value); }
public interface IAction { void Run(); }

// A functional interface may be generic like any other.
public interface IFunc<T> { T Produce(); }

public delegate int Plain(int value);

class Tag {
    String name;
    public Tag(String n) { name = n; }
    public String Name() { return name; }
    ~Tag() { printf("~Tag(%s)\n", name.ToPointer()); }
}

// A closure outlives the scope that built it, because it captured by value.
ITransform MakeAdder(int amount) {
    return value => value + amount;
}

int ApplyAll(IReadOnlyList<ITransform> steps, int start) {
    int result = start;
    for (nuint i = 0; i < steps.Count(); i = i + 1) {
        result = steps.At(i).Apply(result);
    }
    return result;
}

int Main() {
    int factor = 3;

    // Explicit parameter type, inferred parameter type, and a block body.
    ITransform scale = (int value) => value * factor;
    ITransform shift = value => value + factor;
    ITransform back = (int value) => { return value - factor; };

    printf("scale=%d shift=%d back=%d\n", scale.Apply(7), shift.Apply(10), back.Apply(10));

    // The captured value is a copy taken when the closure was made, so changing
    // the local afterwards does not change what the closure sees.
    factor = 100;
    printf("unchanged=%d\n", scale.Apply(7));

    // Returned from a function, long after its frame is gone.
    var addTen = MakeAdder(10);
    printf("adder=%d\n", addTen.Apply(5));

    // Closures are objects, so they go in collections like anything else.
    var steps = new List<ITransform>();
    steps.Add(MakeAdder(1));
    steps.Add(MakeAdder(2));
    steps.Add(MakeAdder(3));
    printf("chained=%d\n", ApplyAll(steps, 0));

    // A lambda that captures nothing becomes a plain function pointer, which is
    // what a delegate is; one that captures could not.
    Plain doubled = (int value) => value * 2;
    printf("plain=%d\n", doubled(21));

    // Nested: the inner lambda captures through the outer one.
    int outer = 5;
    IFunc<ITransform> factory = () => value => value * outer;
    printf("nested=%d\n", factory.Produce().Apply(6));

    // A void interface, and a captured reference: the closure retains the Tag
    // and releases it when the closure itself dies.
    printf("before\n");
    {
        var tag = new Tag("held");
        IAction announce = () => Console.WriteLine(tag.Name());
        announce.Run();
        printf("leaving\n");
    }
    printf("after\n");

    printf("done\n");
    return 0;
}
