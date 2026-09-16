// SPDX-License-Identifier: 0BSD
module GenericMethods;

import Standard.Collections;
import Standard.Console;

extern "C" int printf(byte* format, ...);

public interface INamed { String Describe(); }

public class Money : IComparable<Money>, INamed
{
    int _cents;
    public Money(int c) => _cents = c;
    public int Cents() => _cents;
    public int CompareTo(Money other) => _cents - other.Cents();
    public String Describe() => "money";
}

// A generic method on an ordinary class. Each instantiation is a separate
// function, exactly as a generic free function is. Type arguments are always
// inferred from the values passed; they cannot be written at the call.
public class Util
{
    public T Choose<T>(T a, T b, bool first) => first ? a : b;

    public nuint CountOf<T>(T[] values) => values.Length;

    // Constrained, and checked where it is called.
    public T Bigger<T>(T a, T b) where T : IComparable<T>
    {
        return a.CompareTo(b) > 0 ? a : b;
    }

    // Calling one generic method from another, with no receiver written.
    public T Middle<T>(T a, T b) => Choose(a, b, false);
}

// A generic method inside a generic class: two sets of type parameters, one
// fixed by the class and one inferred at the call.
public class Pair<A>
{
    A _left;
    public Pair(A value) => _left = value;
    public A Left() => _left;

    public A KeepLeft<B>(B other) => _left;
    public B TakeOther<B>(B other) => other;
}

int Main()
{
    var util = new Util();

    printf("int=%d\n", util.Choose(10, 20, true));
    printf("intB=%d\n", util.Choose(10, 20, false));

    Console.WriteLine(util.Choose("yes", "no", true));

    var numbers = new int[3];
    printf("count=%d\n", (int)util.CountOf(numbers));

    var words = new String[5];
    printf("wordCount=%d\n", (int)util.CountOf(words));

    var rich = util.Bigger(new Money(500), new Money(250));
    printf("bigger=%d\n", rich.Cents());

    printf("middle=%d\n", util.Middle(1, 2));

    var pair = new Pair<String>("outer");
    Console.WriteLine(pair.KeepLeft(7));
    printf("taken=%d\n", pair.TakeOther(7));

    printf("done\n");
    return 0;
}
