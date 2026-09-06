// SPDX-License-Identifier: 0BSD
//
// What `static` may not be written on, and what a static method may not reach.
//
// Every one of these is the same fact from a different side: a static member
// belongs to the type, so there is no object anywhere in it -- not to read a
// field through, not to dispatch on, and not to be called on.
module ErrStaticMethods;

public class Box {
    int value;

    public Box() { value = 1; }

    public int Read() { return value; }

    // SL0228: no receiver at all, so `this` names nothing.
    public static int ReadsThis() { return this.value; }

    // SL0576: the field is reached through an object, and there is none.
    public static int ReadsField() { return value; }

    // SL0576: so is the method.
    public static int CallsMethod() { return Read(); }

    // SL0575: dispatch chooses a body from the object a call arrives on.
    public static virtual int Dispatched() { return 1; }

    // SL0575: `protected` is about what a derived object reaches through
    // itself.
    protected static int Guarded() { return 1; }

}

public interface IThing {
    // SL0574: an interface promises what an object can do.
    static int Detached();
}

// SL0573: at module scope the word says nothing that was not already true.
public static int Free() { return 1; }

public int Main() {
    var box = new Box();

    // SL0576: reached on a value, when it belongs to the type.
    int a = box.ReadsThis();

    // SL0576: reached on the type, when it belongs to a value.
    int b = Box.Read();

    return a + b;
}
