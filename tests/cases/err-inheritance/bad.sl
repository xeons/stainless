// What the words about overriding refuse.
module ErrInheritance;

public abstract class Base {
    public virtual int Value() { return 1; }

    public virtual int Twice(int n) { return n * 2; }

    public int Fixed() { return 0; }

    public abstract int Required();

    // A dispatched member has to be nameable by a derived class, so a private
    // one is a slot nothing could ever fill.
    virtual int Hidden() { return 0; }               // SL0506

    // 'sealed' closes an inherited chain, so it goes with 'override'.
    public sealed int Closed() { return 0; }         // SL0507

    // An abstract member with a body is two answers to one question.
    public abstract int Bodied() { return 0; }       // SL0498
}

public class Derived : Base {
    // The one word that does not belong on storage.
    public virtual int Count;                        // SL0497

    public override int Required() { return 1; }
    public override int Bodied() { return 1; }

    // Nothing of that name and those parameters is inherited.
    public override int Missing() { return 0; }      // SL0499

    // Inherited, and not virtual.
    public override int Fixed() { return 1; }        // SL0500

    // Same name and parameters as an inherited method, with no 'override'.
    public int Value() { return 2; }                 // SL0503

    // Overriding, but not with the same signature.
    public override long Twice(int n) { return 4; }  // SL0502

    // An overload rather than an override: different parameters, so this is
    // fine and is here to prove the rule is about signatures.
    public int Twice(int n, int m) { return n * m; }
}

/// A concrete class that leaves an abstract method unanswered.
public class Incomplete : Base {                     // SL0504
    public override int Bodied() { return 0; }
}

/// An abstract member in a class that is not abstract.
public class NotAbstract {
    public abstract int Wanted();                    // SL0505
}

public sealed class Final : Base {
    public override int Required() { return 1; }
    public override int Bodied() { return 1; }
    public sealed override int Value() { return 3; }
}

int Main() { return 0; }
