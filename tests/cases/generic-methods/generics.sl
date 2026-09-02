// SPDX-License-Identifier: 0BSD
module GenericMethods;

import Standard.Collections;
import Standard.Console;

extern "C" int printf(byte* format, ...);

public interface INamed { String Describe(); }

public class Money : IComparable<Money>, INamed {
    int cents;
    public Money(int c) { cents = c; }
    public int Cents() { return cents; }
    public int CompareTo(Money other) { return cents - other.Cents(); }
    public String Describe() { return "money"; }
}

// A generic method on an ordinary class. Each instantiation is a separate
// function, exactly as a generic free function is. Type arguments are always
// inferred from the values passed; they cannot be written at the call.
public class Util {
    public T Choose<T>(T a, T b, bool first) { return first ? a : b; }

    public nuint CountOf<T>(T[] values) { return values.Length; }

    // Constrained, and checked where it is called.
    public T Bigger<T>(T a, T b) where T : IComparable<T> {
        return a.CompareTo(b) > 0 ? a : b;
    }

    // Calling one generic method from another, with no receiver written.
    public T Middle<T>(T a, T b) { return Choose(a, b, false); }
}

// A generic method inside a generic class: two sets of type parameters, one
// fixed by the class and one inferred at the call.
public class Pair<A> {
    A left;
    public Pair(A value) { left = value; }
    public A Left() { return left; }

    public A KeepLeft<B>(B other) { return left; }
    public B TakeOther<B>(B other) { return other; }
}

int Main() {
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
