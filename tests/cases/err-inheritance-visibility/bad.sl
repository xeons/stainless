// What deriving does not grant, from outside the base's own module.
module Outside;

import Zoo;

public class Quieter : Quiet
{
    Quieter() => base();

    // The base closed this one.
    public override String Speak() => "shhh"; // SLC0041

    // Protected reaches a derived class, so this is fine, and is here to show
    // what the refusals below are being contrasted with.
    public int Fine() => Legs();

    // Private is the module's, and deriving is not being in the module.
    public int Wrong() => Tag(); // SLN0014
}

/// Not derived from anything, so protected means nothing to it.
public class Bystander
{
    public int Peek(Animal animal)
    {
        return animal.Legs();                             // SLN0014
    }

    public int Poke(Animal animal)
    {
        return animal.legs;                               // SLN0014
    }
}

int Main() => 0;
