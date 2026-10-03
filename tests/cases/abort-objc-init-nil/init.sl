// A constructor's `this` is the object alloc made, so a superclass init
// that answers nil -- or another object -- stops the program rather than
// leave the constructor holding what init gave up.
module ObjCInitNil;

import Standard.Console;
import Standard.ObjC;

#pragma comment(framework, "Foundation")

[ObjCRoot]
public extern objc class NSObject
{
    [Selector("alloc")] public static Self Alloc();
    [Selector("init")] public Self Init();
}

// Written in refuse.m: its init answers nil.
public extern objc class SLRefuser : NSObject
{
}

public objc class Child : SLRefuser
{
    public Child()
    {
        Console.WriteLine("not reached");
    }
}

int Main()
{
    Console.WriteLine("making one");
    var child = new Child();
    Console.WriteLine("not reached");
    return 0;
}
