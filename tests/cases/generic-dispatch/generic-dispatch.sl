// SPDX-License-Identifier: 0BSD
module GenericDispatch;

import Standard.Console;
import Standard.Collections;

// ---------------------------------------------------------------- visitors

public abstract class Node
{
    public abstract R Accept<R>(IVisitor<R> visitor);
}

public class Number : Node
{
    public int Value;

    public Number(int value) => Value = value;
    ~Number() { Console.WriteLine("~Number " + Text.FromInteger(Value)); }

    public override R Accept<R>(IVisitor<R> visitor) => visitor.VisitNumber(this);
}

public class Sum : Node
{
    public Node Left;
    public Node Right;

    public Sum(Node left, Node right)
    {
        Left = left;
        Right = right;
    }

    public override R Accept<R>(IVisitor<R> visitor) => visitor.VisitSum(this);
}

public interface IVisitor<R>
{
    R VisitNumber(Number number);
    R VisitSum(Sum sum);
}

public class Evaluate : IVisitor<int>
{
    public int VisitNumber(Number number) => number.Value;
    public int VisitSum(Sum sum) => sum.Left.Accept(this) + sum.Right.Accept(this);
}

public class Show : IVisitor<String>
{
    public String VisitNumber(Number number) => Text.FromInteger(number.Value);
    public String VisitSum(Sum sum) =>
        "(" + sum.Left.Accept(this) + " + " + sum.Right.Accept(this) + ")";
}

// ------------------------------------------------------ an interface's own

public interface IStore
{
    // Every instantiation a caller names is a slot of its own.
    T Keep<T>(T value);

    // A generic default, which a class may leave alone.
    String Describe<T>(T value) => "stored";
}

public class Log : IStore
{
    public int Count;

    public T Keep<T>(T value)
    {
        Count++;
        return value;
    }
}

public class Loud : IStore
{
    public T Keep<T>(T value) => value;
    public String Describe<T>(T value) => "loud";
}

// Instantiating one class's template can ask for another instantiation, which
// every class then needs too.
public class Wrapping : IStore
{
    public IStore Inner;
    public String Last = "";

    public Wrapping(IStore inner) => Inner = inner;

    public T Keep<T>(T value)
    {
        var list = new List<T>();
        list.Add(value);
        Last = Inner.Describe(list);
        return Inner.Keep(value);
    }
}

// A generic class implementing it is only a class once something makes one.
public class Tagged<TTag> : IStore
{
    public T Keep<T>(T value) => value;
    public String Describe<T>(T value) => "tagged";
}

// --------------------------------------------------- a class's own virtuals

public class Formatter
{
    public virtual String Format<T>(T value) => "base";
    public String Twice<T>(T value) => Format(value) + "/" + Format(value);
}

public class Bracketed : Formatter
{
    public override String Format<T>(T value) => "[" + base.Format(value) + "]";
}

public class Plainer : Bracketed { }

public class Quoted : Plainer
{
    public override String Format<T>(T value) => "'q'";
}

int Main()
{
    Node tree = new Sum(new Number(1), new Sum(new Number(2), new Number(3)));
    Console.WriteLine(Text.FromInteger(tree.Accept(new Evaluate())));
    Console.WriteLine(tree.Accept(new Show()));

    var log = new Log();
    IStore store = log;
    Console.WriteLine(Text.FromInteger(store.Keep(4)) + store.Keep("text") + store.Describe(1.5));
    Console.WriteLine(Text.FromInteger(log.Count));

    IStore loud = new Loud();
    Console.WriteLine(loud.Describe('c'));

    var wrapping = new Wrapping(new Loud());
    IStore wrapped = wrapping;
    Console.WriteLine(wrapped.Keep("inner") + " " + wrapping.Last);

    IStore tagged = new Tagged<long>();
    Console.WriteLine(tagged.Describe(tagged.Keep(8)));

    Formatter formatter = new Bracketed();
    Console.WriteLine(formatter.Format(1) + formatter.Twice("x"));
    formatter = new Plainer();
    Console.WriteLine(formatter.Format(2.0));
    formatter = new Quoted();
    Console.WriteLine(formatter.Twice(3));
    return 0;
}
