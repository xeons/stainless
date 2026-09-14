// SPDX-License-Identifier: 0BSD
//
// `implicit` and `explicit operator`, which are C#'s shape: inside one of the
// two types, static, taking the value and returning what it becomes. The word
// decides whether a cast has to be written, and that is the whole difference
// between them -- one says "this never loses anything", the other says "say
// that you meant it".
module ConversionOperators;

import Standard.Console;
import Standard.Text;

public struct Money {
    public long Cents;

    public static Money Of(long cents) {
        Money made;
        made.Cents = cents;
        return made;
    }

    /// Nothing is lost, so nothing has to be written at the call.
    public static implicit operator Money(long cents) { return Of(cents); }

    /// The currency is, so this one is asked for.
    public static explicit operator long(Money value) { return value.Cents; }

    public static Money operator +(Money a, Money b) { return Of(a.Cents + b.Cents); }
}

public class Meters {
    public double Value;

    public Meters(double value) { Value = value; }

    public static implicit operator Meters(double value) { return new Meters(value); }
    public static explicit operator double(Meters m) { return m.Value; }
}

String Show(Money m) { return Text.FromInteger(m.Cents) + "c"; }
String Show(String text) { return text; }

int Main() {
    Money made = Money.Of(250);
    Money implied = 125L;
    Money literal = 5;              // the literal adopts 'long', then converts

    Console.WriteLine(Show(made));
    Console.WriteLine(Show(implied));
    Console.WriteLine(Show(literal));

    // In an argument, where overload resolution has to know it is possible
    // before it knows which overload was meant.
    Console.WriteLine(Show(40L));
    Console.WriteLine(Show("text, not money"));

    // As an operand, where the operator's parameter is what converts it.
    Console.WriteLine(Show(made + 50L));

    // Explicit is the direction that has to be written out.
    long cents = (long)made;
    Console.WriteLine(Text.FromInteger(cents));

    // A class works the same way, and the conversion is what allocates.
    Meters wide = 2.5;
    Console.WriteLine(Text.FromDouble(wide.Value));
    Console.WriteLine(Text.FromDouble((double)wide));

    // Through a return type, which is a conversion like any other.
    Console.WriteLine(Show(Fee()));
    return 0;
}

Money Fee() { return 99L; }
