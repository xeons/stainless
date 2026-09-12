// SPDX-License-Identifier: 0BSD
//
// The second half of the catalogue, and the demonstration of §1.2 by being it:
// this file declares the same module as Types.sl, so the two halves see each
// other's private names and neither imports the other.
//
// Members (§7), generics (§4), functions as values (§2.14) and attributes (§6).
module Tour.Types;

import Standard.Collections;
import Standard.Console;
import Standard.Reflection;

#region members

// ==================================================================== §7.3

public class Control {
    int left;

    /// A hand-written property: two functions wearing the spelling of a field.
    public int Left {
        get { return left; }
        set { left = value; Layouts++; }
    }

    /// An automatic one. Its storage *is* a field named after it.
    public String Name { get; set; }

    /// Get-only, so nothing outside may write it.
    public int Right { get { return left + 10; } }

    /// A private setter: written inside the class, read everywhere.
    public int Layouts { get; private set; }

    public Control(String called) {
        left = 0;
        Name = called;
        Layouts = 0;
    }

    // ================================================================ §7.5

    /// An indexer, which is a property that takes an argument.
    public int this[nuint at] {
        get { return left + (int)at; }
        set { left = value - (int)at; }
    }

    /// Indexers overload on the index type, as methods do on parameters.
    public bool this[String wanted] { get { return Name == wanted; } }

    /// An ordinary method, so that something exists to name on an instance
    /// and store in a closure.
    public void Bump(int by) { Left = Left + by; Moved(Left); }

    // ================================================================ §2.14.2

    /// Several subscribers behind one name. From outside this class the only
    /// things that can be written are `+=` and `-=`: it cannot be read,
    /// assigned or raised, which is the whole difference between an event and
    /// a public field of closure type.
    ///
    /// Raised above, by name, which only this class may do. With nobody
    /// subscribed that does nothing at all.
    public event Notify Moved;
}

// ==================================================================== §7.4

/// Operators are declared inside the type, `static`, with every operand
/// written out -- because `3 * money` has nothing to hang a `this` off.
public struct Money {
    public long Cents;

    public static Money operator +(Money a, Money b) { return Cents(a.Cents + b.Cents); }
    public static Money operator -(Money a, Money b) { return Cents(a.Cents - b.Cents); }
    public static Money operator -(Money a)          { return Cents(0 - a.Cents); }

    // Both ways round, so it reads either way it is written.
    public static Money operator *(Money a, long by) { return Cents(a.Cents * by); }
    public static Money operator *(long by, Money a) { return Cents(a.Cents * by); }
    public static Money operator /(Money a, long by) { return Cents(a.Cents / by); }
    public static Money operator %(Money a, long by) { return Cents(a.Cents % by); }

    // Comparison operators come in pairs.
    public static bool operator ==(Money a, Money b) { return a.Cents == b.Cents; }
    public static bool operator !=(Money a, Money b) { return a.Cents != b.Cents; }
    public static bool operator < (Money a, Money b) { return a.Cents <  b.Cents; }
    public static bool operator > (Money a, Money b) { return a.Cents >  b.Cents; }
    public static bool operator <=(Money a, Money b) { return a.Cents <= b.Cents; }
    public static bool operator >=(Money a, Money b) { return a.Cents >= b.Cents; }
}

public Money Cents(long value) {
    Money made;
    made.Cents = value;
    return made;
}

/// The bitwise ones, the unary complement, `!` and the shifts.
public struct Mask {
    public uint Bits;

    public static Mask operator |(Mask a, Mask b)  { return Of(a.Bits | b.Bits); }
    public static Mask operator &(Mask a, Mask b)  { return Of(a.Bits & b.Bits); }
    public static Mask operator ^(Mask a, Mask b)  { return Of(a.Bits ^ b.Bits); }
    public static Mask operator ~(Mask a)          { return Of(~a.Bits); }
    public static Mask operator <<(Mask a, int by) { return Of(a.Bits << (uint)by); }
    public static Mask operator >>(Mask a, int by) { return Of(a.Bits >> (uint)by); }
    public static bool operator !(Mask a)          { return a.Bits == 0u; }

    public static bool operator ==(Mask a, Mask b) { return a.Bits == b.Bits; }
    public static bool operator !=(Mask a, Mask b) { return a.Bits != b.Bits; }
}

public Mask Of(uint bits) {
    Mask made;
    made.Bits = bits;
    return made;
}

// ==================================================================== §7.6

/// Storage and members that belong to the type rather than to an instance.
public class Registry {
    static int made = 0;

    public static String Kind = "registry";

    /// Written once by its initializer, and immortal: no retain or release
    /// ever touches it again.
    public static readonly String Version = "1";

    /// A static constructor, which runs in the same pass the field
    /// initializers do -- before `Main`, rather than lazily behind a guard.
    static Registry() { Kind = "registry"; }

    String name;

    public Registry(String called) {
        name = called;
        made++;
    }

    public String Name() { return name; }

    public static int Made() { return made; }

    /// A static property, which is two static functions.
    public static int Doubled { get { return made * 2; } }
}

/// A class with no instances. A module is usually the better answer -- it is a
/// scope, so its members need no prefix -- but this is a name that can sit
/// inside a module.
public static class Defaults {
    public static int Retries = 3;
    public static String Note() { return "defaults"; }
}

// ============================================================ nested types

/// A type declared inside another is lifted out and named `Outer.Inner`. The
/// short name works inside, the long one everywhere else; there is no hidden
/// reference to an outer instance, and no bearing on layout.
public class Widget {
    public enum State { Idle, Busy, Gone }

    public struct Span { public int From; public int To; }

    public State Mood;
    public Span Extent;

    public Widget() {
        Mood = State.Idle;          // the short name, from inside
        Extent.From = 0;
        Extent.To = 10;
    }

    public int Width() { return Extent.To - Extent.From; }
}

#endregion
#region generics

// ==================================================================== §4

/// A generic function. `T` is substituted at each call and the body compiled
/// again, so there is no boxing and no type erasure.
public T Larger<T>(T a, T b) where T : IComparable<T> {
    return a.CompareTo(b) >= 0 ? a : b;
}

/// A generic type, with operators of its own -- which are instantiated with
/// it, and were not until recently.
public struct Box<T> {
    public T Value;

    public static Box<T> operator +(Box<T> a, Box<T> b) { return Boxed(a.Value + b.Value); }
    public static bool operator ==(Box<T> a, Box<T> b)  { return a.Value == b.Value; }
    public static bool operator !=(Box<T> a, Box<T> b)  { return a.Value != b.Value; }

    /// A generic *method* on a generic type: two parameters, bound at
    /// different times.
    public String Pair<U>(U other) { return $"{Value}/{other}"; }
}

public Box<T> Boxed<T>(T value) {
    Box<T> made;
    made.Value = value;
    return made;
}

/// Two constraints at once, both interfaces the standard library defines.
public nuint Digest<T>(T[:] items) where T : IHashable, IEquatable<T> {
    nuint total = 0u;
    foreach (var item in items) { total = total + item.HashCode(); }
    return total;
}

/// A generic type held inside another instantiation, which is what makes
/// monomorphization recursive.
public class Cell<T> {
    public T Held { get; set; }
    public Cell(T held) { Held = held; }
}

#endregion
#region functions as values

// ==================================================================== §2.14

/// One bare function pointer with the C calling convention, so C can hold one
/// and call back through it. It cannot capture, which is what makes it one.
public delegate int Combine(int left, int right);

/// A method and the object it belongs to: two pointers, and what a lambda that
/// captures becomes.
public closure void Notify(int value);

/// Both may be generic.
public closure bool Keeps<T>(T value);
public closure R    Turns<T, R>(T value);
public delegate int Orders<T>(T left, T right);

#endregion
#region attributes

// ==================================================================== §6.1

/// An attribute is an ordinary declaration. Its arguments must be constants,
/// because the values are written into the binary beside the field tables.
public attribute Column { String Name; }
public attribute Hidden { }

/// `[Reflect]` is what makes a type carry field metadata. Without it nothing is
/// emitted and `typeof` is an error, so reflection costs nothing unless asked.
[Reflect]
public class Person {
    [Column("full_name")] public String Name;
    [Column("age")]       public int    Years;
                          public bool   Active;
                          public double Rating;
    [Hidden]              public int    Internal;

    /// A property's storage is an ordinary field, so a reflected type sees it
    /// under the property's own name and carries the annotation with it.
    [Column("city")]      public String City { get; set; }

    public Person(String name, int years) {
        Name = name;
        Years = years;
        Active = true;
        Rating = 4.5;
        Internal = 99;
        City = "London";
    }
}

#endregion
