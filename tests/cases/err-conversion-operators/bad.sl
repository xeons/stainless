// SPDX-License-Identifier: 0BSD
//
// What a conversion may not be. Every one of these is the same rule: a
// conversion is chosen by the two types at the point of use, so a reader has
// to be able to find it from those two types, and there has to be one of it.
module Bad;

public interface IThing { void Do(); }

public class Base { }

public class Alias : Base {
    // The language already carries a derived reference to its base.
    public static implicit operator Base(Alias a) { return a; }
}

public struct Coin {
    public long Cents;

    // Neither side is the type this is written in.
    public static implicit operator int(double d) { return (int)d; }

    // To an interface, which is a question about what an object is.
    public static implicit operator IThing(Coin c) { return new Doer(); }

    // Reachable only from its own module.
    static implicit operator Coin(short s) { Coin made; made.Cents = s; return made; }

    // Two of the same pair.
    public static implicit operator Coin(long cents) { Coin made; made.Cents = cents; return made; }
    public static explicit operator Coin(long other) { Coin made; made.Cents = other; return made; }
}

public class Doer : IThing {
    public void Do() { }
}

public struct Token {
    // Itself.
    public static implicit operator Token(Token t) { return t; }
}

// Each of these is legal where it is written -- a conversion may be declared by
// either of the two types it is between -- and together they leave a call site
// with two answers and nothing to choose between them.
public struct Yard {
    public double Length;

    public static implicit operator Foot(Yard y) { Foot made; made.Length = y.Length * 3.0; return made; }
}

public struct Foot {
    public double Length;

    public static implicit operator Foot(Yard y) { Foot made; made.Length = y.Length * 3.0; return made; }
}

double Measure(Foot f) { return f.Length; }

int Main() {
    Yard yard;
    yard.Length = 2.0;

    return (int)Measure(yard);
}
