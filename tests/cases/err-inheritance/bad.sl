// What the words about overriding refuse.
module ErrInheritance;

public abstract class Base
{
    public virtual int Value() => 1;

    public virtual int Twice(int n) => n * 2;

    public int Fixed() => 0;

    public abstract int Required();

    // A dispatched member has to be nameable by a derived class, so a private
    // one is a slot nothing could ever fill.
    virtual int Hidden() => 0; // SL0506

    // 'sealed' closes an inherited chain, so it goes with 'override'.
    public sealed int Closed() => 0; // SL0507

    // An abstract member with a body is two answers to one question.
    public abstract int Bodied() => 0; // SL0498
}

public class Derived : Base
{
    // The one word that does not belong on storage.
    public virtual int Count;                        // SL0497

    public override int Required() => 1;
    public override int Bodied() => 1;

    // Nothing of that name and those parameters is inherited.
    public override int Missing() => 0; // SL0499

    // Inherited, and not virtual.
    public override int Fixed() => 1; // SL0500

    // Same name and parameters as an inherited method, with no 'override'.
    public int Value() => 2; // SL0503

    // Overriding, but not with the same signature.
    public override long Twice(int n) => 4; // SL0502

    // An overload rather than an override: different parameters, so this is
    // fine and is here to prove the rule is about signatures.
    public int Twice(int n, int m) => n * m;
}

/// A concrete class that leaves an abstract method unanswered.
public class Incomplete : Base // SL0504
{
    public override int Bodied() => 0;
}

/// An abstract member in a class that is not abstract.
public class NotAbstract
{
    public abstract int Wanted();                    // SL0505
}

public sealed class Final : Base
{
    public override int Required() => 1;
    public override int Bodied() => 1;
    public sealed override int Value() => 3;
}

int Main() => 0;
