// SPDX-License-Identifier: 0BSD
//
// What `static` may not be written on, and what a static method may not reach.
//
// Every one of these is the same fact from a different side: a static member
// belongs to the type, so there is no object anywhere in it -- not to read a
// field through, not to dispatch on, and not to be called on.
module ErrStaticMethods;

public class Box
{
    int _value;

    public Box() => _value = 1;

    public int Read() => _value;

    // SLN0010: no receiver at all, so `this` names nothing.
    public static int ReadsThis() => this._value;

    // SLN0022: the field is reached through an object, and there is none.
    public static int ReadsField() => _value;

    // SLN0022: so is the method.
    public static int CallsMethod() => Read();

    // SLC0047: dispatch chooses a body from the object a call arrives on.
    public static virtual int Dispatched() => 1;

    // SLC0047: `protected` is about what a derived object reaches through
    // itself.
    protected static int Guarded() => 1;

}

public interface IThing
{
    // SLC0070: with no body, a static interface member is a requirement, and
    // says so with 'abstract'.
    static int Detached();
}

// SLC0123: at module scope the word says nothing that was not already true.
public static int Free() => 1;

public int Main()
{
    var box = new Box();

    // SLN0022: reached on a value, when it belongs to the type.
    int a = box.ReadsThis();

    // SLN0022: reached on the type, when it belongs to a value.
    int b = Box.Read();

    return a + b;
}
