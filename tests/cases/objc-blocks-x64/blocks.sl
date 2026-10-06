// A lambda made a block, a call through one, and a block an IMP is handed.
// The case stops at an object file, so it runs on every host; ir.txt holds
// the literal and the descriptor against what clang writes for the same
// blocks in Objective-C.
module ObjCBlockIr;

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

public objc closure void Seen(AnyObject item, bool flag);
public objc closure Wide Spread(long value);

public extern objc class SLTaker : NSObject
{
    [Selector("take:")]
    public static void Take(Seen seen);
    [Selector("takeWide:")]
    public static void TakeWide(Spread spread);
}

public objc class Holder : NSObject
{
    Seen? _held;

    [Selector("hold:")]
    public void Hold(Seen seen) => _held = seen;
}

public class Counter
{
    public long Count;
}

int Main()
{
    var counter = new Counter();
    SLTaker.Take((AnyObject item, bool flag) => counter.Count++);
    SLTaker.TakeWide((long value) =>
    {
        Wide wide;
        wide.A = (double)value;
        return wide;
    });

    Seen seen = (AnyObject item, bool flag) => counter.Count += 2;
    seen(NSObject.Alloc(), true);
    return (int)counter.Count;
}
