// What a block may carry, and what may become one.
module BadObjCBlocks;

import Standard.ObjC;

[ObjCRoot]
public extern objc class NSObject
{
}

public class Plain
{
}

// An 'out', a String and a Stainless object cannot cross to Objective-C.
public objc closure void Writes(out long result);
public objc closure void Named(String name);
public objc closure Plain Made();

public objc closure void Done(long value);
public closure void Other(double value);

void Use(AnyObject thing, Other other)
{
    // A block cannot be asked what it takes.
    bool asked = thing is Done;

    // A closure of another signature does not become the block.
    Done done = other;
}

int Main() => 0;
