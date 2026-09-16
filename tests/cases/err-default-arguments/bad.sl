// SPDX-License-Identifier: 0BSD
//
// What a default may not be, and where it may not be declared. Each refusal is
// the same rule seen from a different side: a default is a constant the caller
// writes into its own call, from one declaration that it can see.
module Bad;

int Twice(int n) => n * 2;

public interface IDraw
{
    void Draw(int width = 4);
}

public class Base
{
    public virtual void Show(int n = 1) { }
}

public class Derived : Base, IDraw
{
    // An override takes the default of what it replaces; a second one here
    // would depend on which reference the call was made through.
    public override void Show(int n = 2) { }

    // And so would a second one on the class beside the interface's.
    public void Draw(int width = 9) { }
}

// The ones that may be left out are the tail of the list, not a hole in it.
void Hole(int a = 1, int b) { }

// A default is written into the call, so running something there would run it
// at the caller and once per call site.
void Running(int n = Twice(2)) { }

// These pass the caller's storage rather than a value.
void Borrowed(ref int n = 3) { }
void Outward(out int n = 3) => n = 1;

void Two(int a, int b = 1) { }

int Main()
{
    Two();
    Two(1, 2, 3);
    return 0;
}
