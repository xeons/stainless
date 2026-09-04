// What deriving does not grant, from outside the base's own module.
module Outside;

import Zoo;

public class Quieter : Quiet {
    Quieter() { base(); }

    // The base closed this one.
    public override String Speak() { return "shhh"; }     // SL0501

    // Protected reaches a derived class, so this is fine, and is here to show
    // what the refusals below are being contrasted with.
    public int Fine() { return Legs(); }

    // Private is the module's, and deriving is not being in the module.
    public int Wrong() { return Tag(); }                  // SL0257
}

/// Not derived from anything, so protected means nothing to it.
public class Bystander {
    public int Peek(Animal animal) {
        return animal.Legs();                             // SL0257
    }

    public int Poke(Animal animal) {
        return animal.legs;                               // SL0249
    }
}

int Main() { return 0; }
