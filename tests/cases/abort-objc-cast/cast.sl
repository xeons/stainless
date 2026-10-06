// A cast to an Objective-C class asks the object, and one that is not that
// class stops the program, naming what it really was.
module ObjCCast;

import Standard.Console;
import Standard.ObjC;

#pragma comment(framework, "Foundation")

[ObjCRoot]
public extern objc class NSObject
{
    [Selector("new")]
    public static Self New();
}

public extern objc class SLOne : NSObject
{
}

public extern objc class SLTwo : NSObject
{
}

int Main()
{
    AnyObject held = SLOne.New();
    var one = (SLOne)held;
    Console.WriteLine("an SLOne is an SLOne");
    var two = (SLTwo)held;
    Console.WriteLine("not reached");
    return 0;
}
