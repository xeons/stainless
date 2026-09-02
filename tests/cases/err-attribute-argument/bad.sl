module Bad;

import Standard.Reflection;

public attribute Label { String Name; }

int Answer() { return 1; }

[Reflect]
public class Thing {
    // Attribute arguments are written into the binary, so they must be constants.
    [Label(Answer())] public int Value;
}

int Main() { return 0; }
