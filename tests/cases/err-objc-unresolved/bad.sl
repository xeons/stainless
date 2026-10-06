// A name that does not resolve is reported once, where it is written, and
// nothing that mentions what it would have been says anything more.
module BadObjCUnresolved;

import Standard.ObjC;

[ObjCRoot]
public extern objc class NSObject
{
    [Selector("description")]
    Missing Description { get; }
}

public objc class Square : NSObject
{
    override NSObject Description => this;
}

[ReturnsRetained]
extern "C" Absent MakeRetained(long value);

public objc closure void Seen(Unknown item, bool flag);

void Call(Seen seen)
{
    seen(null, true, true);
}

int Main()
{
    return 0;
}
