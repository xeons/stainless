// A message declared to return an object that answers nil stops the program
// there, naming the message, rather than handing a nil to code that trusts it.
module ObjCNil;

import Standard.Console;
import Standard.ObjC;

#pragma comment(framework, "Foundation")

[ObjCRoot]
public extern objc class NSObject
{
}

public extern objc class SLNothing : NSObject
{
    [Selector("nothing")] public static SLNothing Nothing();
}

int Main()
{
    Console.WriteLine("asking");
    var made = SLNothing.Nothing();
    Console.WriteLine("not reached");
    return 0;
}
