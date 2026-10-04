// Messages to Foundation and to a class probe.m defines: the ownership each
// selector's family implies, Self, BOOL both ways, a struct returned in
// memory, an out object written back, and asking an object what it is.
module ObjCFoundation;

import Standard.Console;
import Standard.ObjC;

#pragma comment(framework, "Foundation")

[ObjCName("NSObject")]
public objc interface NSObjectProtocol
{
    [Selector("isEqual:")] bool IsEqual(AnyObject? other);
}

public objc interface NSSecureCoding
{
    [Selector("supportsSecureCoding")] static abstract bool SupportsSecureCoding { get; }
}

[ObjCRoot]
public extern objc class NSObject : NSObjectProtocol
{
    [Selector("description")] public static NSString ClassDescription { get; }
    [Selector("alloc")] public static Self Alloc();
    [Selector("init")] public Self Init();
}

public extern objc class NSString : NSObject, NSSecureCoding
{
    [Selector("stringWithUTF8String:")] public static Self FromUtf8(byte* text);
    [Selector("UTF8String")] public byte* Utf8 { get; }
    [Selector("length")] public nuint Length { get; }
    [Selector("isEqualToString:")] public bool IsEqualToString(NSString other);
    [Selector("stringByAppendingString:")] public NSString Append(NSString other);
    [Selector("copy")] public NSString Copy();
    [Selector("stringWithFormat:")] public static NSString WithFormat(NSString format, ...);
}

public extern objc class NSMutableArray : NSObject
{
    [Selector("addObject:")] public void Add(AnyObject item);
    [Selector("count")] public nuint Count { get; }
    [Selector("objectAtIndex:")] public AnyObject ObjectAt(nuint index);
}

public extern objc class NSNumber : NSObject
{
    [Selector("numberWithBool:")] public static NSNumber FromBool(bool value);
    [Selector("numberWithLong:")] public static NSNumber FromLong(long value);
    [Selector("boolValue")] public bool BoolValue { get; }
    [Selector("longValue")] public long LongValue { get; }
}

public struct Wide
{
    public double A;
    public double B;
    public double C;
    public double D;
}

public extern objc class SLTracked : NSObject
{
    [Selector("alive")] public static int Alive { get; }
    [Selector("trackedWithValue:")] public static SLTracked WithValue(long value);
    [Selector("initWithValue:")] public SLTracked InitWithValue(long value);
    [Selector("value", "setValue:")] public long Value { get; set; }
    [Selector("spread")] public Wide Spread { get; }
    [Selector("isPositive")] public bool IsPositive { get; }
    [Selector("isGreaterThan:flag:")] public bool IsGreaterThan(long other, bool flag);
    [Selector("copyDoubled")] public SLTracked CopyDoubled();
    [Selector("makeTwin:")] public bool MakeTwin(out SLTracked? twin);
    [Selector("maybe:")] public SLTracked? Maybe(bool give);
    [Selector("initIfPositive:")] public Self? InitIfPositive(long value);
}

String Text(NSString text) => Standard.Text.FromBytes(text.Utf8, text.Length);

void Strings()
{
    var hello = NSString.FromUtf8("hello");
    var both = hello.Append(NSString.FromUtf8(", world"));
    Console.WriteLine($"{Text(both)} has {both.Length} characters");
    Console.WriteLine($"equal: {hello.IsEqualToString(NSString.FromUtf8("hello"))}");
    Console.WriteLine($"a copy: {Text(hello.Copy())}");

    // A variadic message: an int, an object, a float that widens and a C string.
    var formatted = NSString.WithFormat(NSString.FromUtf8("%d %@ %.2f %s"), 42, hello, 2.5f, "bytes");
    Console.WriteLine($"formatted: {Text(formatted)}");
}

void Collections()
{
    var list = NSMutableArray.Alloc().Init();
    list.Add(NSString.FromUtf8("first"));
    list.Add(NSNumber.FromLong(42));
    list.Add(NSNumber.FromBool(true));
    Console.WriteLine($"count {list.Count}");

    AnyObject first = list.ObjectAt(0u);
    if (first is NSString text)
        Console.WriteLine($"the first is a string of {text.Length}");
    Console.WriteLine($"the first is a number: {first is NSNumber}");

    if (list.ObjectAt(1u) is NSNumber number)
        Console.WriteLine($"the second is {number.LongValue}");

    var flag = (NSNumber)list.ObjectAt(2u);
    Console.WriteLine($"the third is {flag.BoolValue}");
}

void Tracked()
{
    var made = SLTracked.Alloc().InitWithValue(5);
    var cheap = SLTracked.WithValue(-3);
    var doubled = made.CopyDoubled();
    made.Value = 7;
    Console.WriteLine($"values {made.Value} {cheap.Value} {doubled.Value}");
    Console.WriteLine($"positive {made.IsPositive} {cheap.IsPositive}");
    Console.WriteLine($"greater {made.IsGreaterThan(6, true)} {made.IsGreaterThan(6, false)}");

    var spread = made.Spread;
    Console.WriteLine($"spread {spread.A} {spread.B} {spread.C} {spread.D}");

    if (made.MakeTwin(out var twin))
        Console.WriteLine($"twin {twin!.Value}");

    Console.WriteLine($"maybe {made.Maybe(true) is not null} {made.Maybe(false) is null}");

    // A class message goes to the class named, though a superclass declares it.
    Console.WriteLine($"class description: {Text(SLTracked.ClassDescription)}");
    Console.WriteLine($"a protocol's class member: {NSString.SupportsSecureCoding}");

    SLTracked? positive = SLTracked.Alloc().InitIfPositive(4);
    SLTracked? refused = SLTracked.Alloc().InitIfPositive(-4);
    Console.WriteLine($"an init that may fail: {positive?.Value ?? 0} {refused is null}");
}

// Each part runs inside a pool of its own, so that what it was handed at +0
// is gone when it returns and the count afterwards is the whole answer: an
// object freed too early crashes, and one freed never is still counted.
int Main()
{
    WithAutoreleasePool(() => Strings());
    WithAutoreleasePool(() => Collections());
    WithAutoreleasePool(() => Tracked());
    Console.WriteLine($"alive at the end: {SLTracked.Alive}");
    return 0;
}
