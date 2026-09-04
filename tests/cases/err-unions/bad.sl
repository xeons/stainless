// SPDX-License-Identifier: 0BSD
module Bad;

import Standard.Collections;

public interface IShape { double Area(); }

// A union does not record which member is live, so it cannot count anything.
public union Held {
    public int N;
    public String Text;
}

public union Indirect {
    public int N;
    public List<int> Items;
}

// A struct holding a reference is the same problem one level down.
public struct Boxed { public String Text; }

public union Nested {
    public int N;
    public Boxed B;
}

// The choice between nothing at all.
public union Empty {
}

// A union is a value, so it dispatches through nothing.
public union Shaped : IShape {
    public int N;
}

int Main() { return 0; }
