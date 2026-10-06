// Blocks both ways: a Stainless lambda Foundation calls, one probe.m keeps
// and calls later, a block Objective-C made that Stainless calls, and a
// class defined here that keeps a block Objective-C built on its stack.
// What each closure captured is freed once the block holding it is.
module ObjCBlocks;

import Standard.Collections;
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

public extern objc class NSString : NSObject
{
    [Selector("stringWithUTF8String:")]
    public static Self FromUtf8(byte* text);
    [Selector("length")]
    public nuint Length { get; }
    [Selector("UTF8String")]
    public byte* Utf8 { get; }
}

public objc closure void EachObject(AnyObject item, nuint index, bool* stop);

public extern objc class NSMutableArray : NSObject
{
    [Selector("addObject:")]
    public void Add(AnyObject item);
    [Selector("enumerateObjectsUsingBlock:")]
    public void EnumerateObjects(EachObject each);
}

public struct Wide
{
    public double A;
    public double B;
    public double C;
    public double D;
}

public objc closure long Transform(long value);
public objc closure bool Test(NSString text);
public objc closure NSString Name(long value);
public objc closure Wide Spread(double value);

// Written in probe.m.
public extern objc class SLBlocks : NSObject
{
    [Selector("keep:")]
    public static void Keep(Transform transform);
    [Selector("fire:")]
    public static long Fire(long value);
    [Selector("drop")]
    public static void Drop();
    [Selector("adderFor:")]
    public static Transform AdderFor(long amount);
    [Selector("ask:about:")]
    public static bool Ask(Test test, NSString text);
    [Selector("name:with:")]
    public static NSString CallName(Name name, long value);
    [Selector("spread:with:")]
    public static double CallSpread(Spread spread, double value);
    [Selector("handTo:")]
    public static long HandTo(AnyObject keeper);
}

public class Tally
{
    public long Total;
    public static int Alive = 0;
    public Tally() { Alive++; }
    ~Tally() { Alive--; }
}

public objc class Keeper : NSObject
{
    Transform? _kept;

    [Selector("keepFor:")]
    public void KeepFor(Transform transform)
    {
        _kept = transform;
    }

    [Selector("callKept:")]
    public long CallKept(long value) => _kept is Transform kept ? kept(value) : -1;
}

void Enumerate()
{
    var tally = new Tally();
    var array = NSMutableArray.Alloc().Init();
    array.Add(NSString.FromUtf8("one"));
    array.Add(NSString.FromUtf8("three"));
    array.Add(NSString.FromUtf8("seven"));
    array.EnumerateObjects((AnyObject item, nuint index, bool* stop) =>
    {
        if (item is NSString text) tally.Total += (long)text.Length * 10 + (long)index;
    });
    Console.WriteLine($"enumerated: {tally.Total}");
}

void Kept()
{
    var tally = new Tally();
    tally.Total = 100;
    SLBlocks.Keep((long value) => tally.Total + value);
    Console.WriteLine($"kept, fired later: {SLBlocks.Fire(5)} {SLBlocks.Fire(7)}");
    SLBlocks.Drop();
}

void Made()
{
    var add = SLBlocks.AdderFor(40);
    Console.WriteLine($"a block Objective-C made: {add(2)}");
}

void Results()
{
    Console.WriteLine($"BOOL: {SLBlocks.Ask((NSString text) => text.Length > 3u, NSString.FromUtf8("long"))} " +
                      $"{SLBlocks.Ask((NSString text) => text.Length > 3u, NSString.FromUtf8("no"))}");
    Console.WriteLine($"object: {SLBlocks.CallName((long value) => NSString.FromUtf8("named"), 3).Length}");
    Console.WriteLine($"struct: {SLBlocks.CallSpread((double value) => MakeWide(value), 1.5)}");
}

Wide MakeWide(double value)
{
    Wide wide;
    wide.A = value;
    wide.B = value * 2;
    wide.C = value * 3;
    wide.D = value * 4;
    return wide;
}

void Handed()
{
    var keeper = new Keeper();
    Console.WriteLine($"a stack block kept: {SLBlocks.HandTo(keeper)} {keeper.CallKept(1)}");
}

int Main()
{
    WithAutoreleasePool(() => Enumerate());
    WithAutoreleasePool(() => Kept());
    WithAutoreleasePool(() => Made());
    WithAutoreleasePool(() => Results());
    WithAutoreleasePool(() => Handed());
    Console.WriteLine($"tallies alive: {Tally.Alive}");
    return 0;
}
