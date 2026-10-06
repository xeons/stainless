// An Objective-C object handed back by a C function, at +0 by ARC's rule or
// at +1 when declared so, and one a C variable holds, which is read.
module ObjCCFunctions;

import Standard.Console;
import Standard.ObjC;

#pragma comment(framework, "Foundation")

[ObjCRoot]
public extern objc class NSObject { }

public extern objc class NSString : NSObject
{
    [Selector("length")]
    public nuint Length { get; }
}

public extern objc class SLCounted : NSObject
{
    [Selector("value")]
    public long Value { get; }
}

extern "C" int SLAlive();
extern "C" SLCounted SLMakeAutoreleased(long value);
[ReturnsRetained]
extern "C" SLCounted SLMakeRetained(long value);
extern "C" SLCounted? SLMaybe(bool give);
extern "C" SLCounted SLShared;
extern "C" NSString NSDefaultRunLoopMode;

int Main()
{
    int before = SLAlive();
    for (int i = 0; i < 1000; i++)
    {
        WithAutoreleasePool(() =>
        {
            var plain = SLMakeAutoreleased(i);
            var owned = SLMakeRetained(i);
            if (plain.Value + owned.Value != 2 * i) Console.WriteLine("wrong value");
        });
    }
    Console.WriteLine($"alive after: {SLAlive() - before}");

    Console.WriteLine($"maybe: {SLMaybe(true)?.Value ?? -1}, {SLMaybe(false)?.Value ?? -1}");

    // Each read retains and each is released: a store would over-release it.
    long total = 0;
    for (int i = 0; i < 1000; i++)
    {
        var read = SLShared;
        total += read.Value;
    }
    Console.WriteLine($"read a thousand times: {total}");

    var shared = SLShared;
    Console.WriteLine($"shared: {shared.Value}, again: {SLShared.Value}");
    Console.WriteLine($"run loop mode: {NSDefaultRunLoopMode.Length} characters");
    return 0;
}
