// An optional protocol member is sent only to an object that answers it; one
// that does not stops the program rather than raising Objective-C's
// unrecognized-selector exception.
module ObjCOptional;

import Standard.Console;
import Standard.ObjC;

#pragma comment(framework, "Foundation")

public objc interface SLListener
{
    [Optional, Selector("heard:")]
    void Heard(long value);
}

[ObjCRoot]
public extern objc class NSObject
{
    [Selector("new")]
    public static Self New();
}

public extern objc class SLQuiet : NSObject, SLListener
{
}

int Main()
{
    SLListener listener = SLQuiet.New();
    Console.WriteLine("telling");
    listener.Heard(3);
    Console.WriteLine("not reached");
    return 0;
}
