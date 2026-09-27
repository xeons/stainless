// SPDX-License-Identifier: 0BSD
module Bad;

abstract class Animal
{
    public abstract String Sound();
    public abstract int Legs { get; }
}

class Bird : Animal
{
    public override String Sound() => base.Sound() + ", quietly";   // nothing there to call
    public override int Legs => base.Legs;                            // nor here
}

int Main() => 0;
