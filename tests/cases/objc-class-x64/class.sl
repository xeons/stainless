// A class defined for Objective-C, with a field, a BOOL, a struct returned in
// memory on Intel, a super send, a destructor and a protocol. The case stops
// at an object file, so it runs on every host; ir.txt holds the metadata
// against what clang writes for the same class in Objective-C.
module ObjCClass;

import Standard.ObjC;

public struct Wide
{
    public double A;
    public double B;
    public double C;
    public double D;
}

[ObjCRoot]
public extern objc class NSObject
{
    [Selector("alloc")] public static Self Alloc();
    [Selector("init")] public Self Init();
    [Selector("hash")] public nuint Hash { get; }
}

public objc interface Shape
{
    [Selector("area")] double Area();
    [Optional, Selector("grow:")] void Grow(double by);
}

public objc class Canvas : NSObject, Shape
{
    long _count = 3;
    NSObject? _held;

    [Selector("initWithCount:")]
    public Canvas(long count)
    {
        _count = count;
    }

    public double Area() => (double)_count;

    [Selector("isAbove:")] public bool IsAbove(bool flag) => flag && _count > 0;

    [Selector("spread")]
    public Wide Spread()
    {
        Wide wide;
        wide.A = (double)_count;
        return wide;
    }

    public override nuint Hash => base.Hash + 1u;

    [Selector("make")] public static Canvas Make() => new Canvas(1);

    ~Canvas()
    {
        _count = 0;
    }
}

int Main() => (int)Canvas.Make().Area();
