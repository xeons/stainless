// The base half of a hierarchy that crosses a module boundary.
module Zoo;

import Standard.Text;

public abstract class Animal
{
    protected String name;
    protected int legs;

    Animal(String called, int howMany)
    {
        name = called;
        legs = howMany;
    }

    public abstract String Sound();

    public virtual String Speak() => name + " says " + Sound();

    /// Protected: reachable by anything deriving from this, wherever it lives.
    protected String Legs() => Text.FromInteger(legs);

    /// Private to this module, which deriving does not change.
    int Tag() => 7;

    public int OwnTag() => Tag();
}

/// A concrete class in the same module as its base, so the derived class in the
/// other module is two levels down rather than one.
public class Quadruped : Animal
{
    Quadruped(String called)
    {
        base(called, 4);
    }

    public override String Sound() => "...";
}
