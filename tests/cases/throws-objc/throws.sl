// SPDX-License-Identifier: 0BSD
//
// `[Throws]` on a message and on a C function: an Objective-C exception the
// call throws comes back as a value, with its name and reason, and a call
// that throws nothing answers what it produced.
module ObjCThrows;

import Standard.Console;
import Standard.ObjC;
import Standard.Text;

#pragma comment(framework, "Foundation")

[ObjCRoot]
public extern objc class NSObject
{
    [Selector("alloc")]
    public static Self Alloc();
    [Selector("init")]
    public Self Init();
}

public extern objc class SLThrower : NSObject
{
    /// Throws for a negative count.
    [Throws]
    [Selector("countOf:")]
    public Result<long, ForeignException> CountOf(long count);

    /// Throws the second time.
    [Throws]
    [Selector("reset")]
    public ForeignException? Reset();

    [Throws]
    [Selector("made")]
    public static Result<NSObject, ForeignException> Made();
}

/// Throws for an odd number.
[Throws]
extern "C" Result<int, ForeignException> SLHalve(int number);

String Describe(ForeignException thrown) => thrown.Name + ": " + thrown.Reason;

int Main()
{
    var thrower = SLThrower.Alloc().Init();

    var counted = thrower.CountOf(3);
    Console.WriteLine("count 3: " + (counted.Ok ? FromInteger(counted.Value) : Describe(counted.Error)));
    counted = thrower.CountOf(-1);
    Console.WriteLine("count -1: " + (counted.Ok ? FromInteger(counted.Value) : Describe(counted.Error)));

    var reset = thrower.Reset();
    Console.WriteLine("reset: " + (reset == null ? "fine" : Describe((ForeignException)reset)));
    reset = thrower.Reset();
    Console.WriteLine("reset again: " + (reset == null ? "fine" : Describe((ForeignException)reset)));

    var made = SLThrower.Made();
    Console.WriteLine("made: " + (made.Ok ? "an object" : Describe(made.Error)));

    var half = SLHalve(8);
    Console.WriteLine("halve 8: " + (half.Ok ? FromInteger(half.Value) : Describe(half.Error)));
    half = SLHalve(7);
    Console.WriteLine("halve 7: " + (half.Ok ? FromInteger(half.Value) : Describe(half.Error)));
    Console.WriteLine("kind: " + (half.Ok ? "none" : half.Error.Kind == ForeignExceptionKind.ObjectiveC ? "Objective-C" : "other"));
    return 0;
}
