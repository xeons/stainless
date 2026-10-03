// An Objective-C exception that unwinds through a method a Stainless class
// answers stops the program there: the Stainless frames it passed through
// released nothing they held, so nothing after it could be trusted.
module ObjCException;

import Standard.Console;
import Standard.ObjC;

#pragma comment(framework, "Foundation")

[ObjCRoot]
public extern objc class NSObject
{
    [Selector("alloc")] public static Self Alloc();
    [Selector("init")] public Self Init();
}

extern "C"
{
    void SLThrow();
    void SLRun(AnyObject runner);
}

public objc class Runner : NSObject
{
    [Selector("run")]
    public void Run()
    {
        Console.WriteLine("throwing");
        SLThrow();
        Console.WriteLine("not reached");
    }
}

int Main()
{
    Console.WriteLine("running");
    SLRun(new Runner());
    Console.WriteLine("not reached");
    return 0;
}
