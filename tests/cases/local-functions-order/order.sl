// SPDX-License-Identifier: 0BSD
//
// Local functions called before they are declared, from each other, from a
// lambda and from inside another local function; a generic one; and the ones
// in a static method and on a struct.
module LocalFunctionsOrder;

import Standard.Collections;
import Standard.Console;
import Standard.Text;

public closure int Transform(int value);
public closure void Action();

class Registry
{
    static int s_made = 0;
    static int Next() => ++s_made;

    public static int Make()
    {
        int Twice() => Next() * 2;
        return Twice();
    }
}

public struct Cell
{
    public int Value;

    public void Grow()
    {
        void Add(int by) => Value += by;
        Add(3);
        Add(4);
    }
}

int Main()
{
    int a = 1;
    int b = 2;

    // Both called before either is declared, each reading something else.
    Console.WriteLine(Text.FromInteger(Ping(3)));
    int Ping(int n) => n <= 0 ? a : Pong(n - 1) + a;
    int Pong(int n) => n <= 0 ? b : Ping(n - 1) + b;

    // A lambda before a declaration, inside a function that is itself nested.
    int Outer()
    {
        Transform early = v => Deep(v);
        return early(10);

        int Deep(int v) => v + a + b;
    }
    Console.WriteLine(Text.FromInteger(Outer()));

    // A generic one used before it is declared, reading a variable.
    Console.WriteLine(Text.FromInteger((long)Wrap(5).Count) + " " + Wrap("s")[1]);
    List<T> Wrap<T>(T item)
    {
        var made = new List<T>();
        for (int i = 0; i < b; i++)
            made.Add(item);
        return made;
    }

    // Loop variables, and closures that outlive the iteration.
    var actions = new List<Action>();
    int[] tens = [10, 20, 30];
    foreach (int n in tens)
    {
        void Say() => Console.WriteLine("n=" + Text.FromInteger(n));
        actions.Add(Say);
    }
    foreach (var action in actions)
        action();

    Console.WriteLine(Text.FromInteger(Registry.Make()) + " " + Text.FromInteger(Registry.Make()));

    Cell cell;
    cell.Value = 1;
    cell.Grow();
    Console.WriteLine(Text.FromInteger(cell.Value));
    return 0;
}
