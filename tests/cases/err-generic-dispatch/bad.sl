// SPDX-License-Identifier: 0BSD
module Bad;

import Standard.Collections;

public interface IStore
{
    T Keep<T>(T value);
}

// Nothing of that shape.
public class Forgetful : IStore { }                          // SLC0013

// The right shape, and not the right types once instantiated.
public class Wrong : IStore
{
    public int Keep<T>(T value) => 0;                        // SLC0015
}

// A requirement of the type is met by its own member, which a generic one
// could only be one instantiation at a time.
public interface IMake
{
    static abstract T Make<T>();                             // SLG0002
}

public abstract class Shape
{
    public abstract R Measure<R>(R unit);
    public virtual String Name<T>(T tag) => "shape";
    public String Fixed<T>(T tag) => "fixed";
}

// An abstract generic method left unanswered.
public class Blank : Shape { }                               // SLC0044

public class Square : Shape
{
    public override R Measure<R>(R unit) => unit;

    // Nothing of that shape is inherited.
    public override String Name<T, U>(T a, U b) => "";       // SLC0039

    // The same shape as a non-virtual one.
    public String Fixed<T>(T tag) => "mine";                 // SLC0043
}

public class Circle : Shape
{
    public override R Measure<R>(R unit) => unit;

    // Overrides, and returns something else once instantiated.
    public override int Name<T>(T tag) => 0;                 // SLC0042
}

// Each instantiation asks for a larger one of itself, through dispatch as
// much as through a direct call; there is no last one to compile.
public class Nesting : IStore
{
    public IStore Inner;

    public Nesting(IStore inner) => Inner = inner;

    public T Keep<T>(T value)
    {
        var list = Inner.Keep(new List<T>());                // SLG0021
        return value;
    }
}

int Main()
{
    IStore store = new Nesting(new Wrong());
    var kept = store.Keep(1);

    Shape shape = new Circle();
    var named = shape.Name(1);
    return 0;
}
