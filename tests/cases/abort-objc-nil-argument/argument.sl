// An object parameter declared non-optional, sent nil from Objective-C,
// stops the program as the message arrives, naming the message and the
// parameter, rather than handing a nil to a body that trusts it.
module ObjCNilArgument;

import Standard.Console;
import Standard.ObjC;

#pragma comment(framework, "Foundation")

[ObjCRoot]
public extern objc class NSObject
{
    [Selector("alloc")]
    public static Self Alloc();
    [Selector("init")]
    public Self Init();
}

public objc class Greeter : NSObject
{
    [Selector("greet:")]
    public long Greet(NSObject other) => 1;
}

extern "C" long SLGreetNil(AnyObject greeter);

int Main()
{
    Console.WriteLine("sending nil");
    SLGreetNil(new Greeter());
    Console.WriteLine("not reached");
    return 0;
}
