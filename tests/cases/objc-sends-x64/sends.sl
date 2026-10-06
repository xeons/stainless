// One message of each shape, sent to a class nothing here defines. The case
// stops at an object file, so it runs on every host; ir.txt holds each send
// against what clang writes for the same calls in Objective-C, at -O0 and
// without selector stubs.
module ObjCSends;

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
    [Selector("alloc")]
    public static Self Alloc();
}

public extern objc class SLShapes : NSObject
{
    [Selector("shapesWithValue:")]
    public static SLShapes WithValue(long value);
    [Selector("initWithValue:")]
    public SLShapes InitWithValue(long value);
    [Selector("spread")]
    public Wide Spread { get; }
    [Selector("isGreaterThan:flag:")]
    public bool IsGreaterThan(long other, bool flag);
    [Selector("copyDoubled")]
    public SLShapes CopyDoubled();
    [Selector("makeTwin:")]
    public bool MakeTwin(out SLShapes? twin);
}

long Use()
{
    var made = SLShapes.Alloc().InitWithValue(5);
    var cheap = SLShapes.WithValue(3);
    var doubled = made.CopyDoubled();
    var wide = made.Spread;
    bool greater = made.IsGreaterThan(6, true);
    made.MakeTwin(out var twin);
    return (long)wide.A + (greater ? 1 : 0) + (twin is null ? 0 : 1) + (long)cheap.CopyDoubled().Spread.B
        + (long)doubled.Spread.C;
}

int Main() => (int)Use();
