// Classes defined in Stainless and registered with the Objective-C runtime:
// an override sending to its superclass, a protocol whose member a class
// answers by name, a class derived from another defined here, a struct
// returned in memory, BOOL both ways, and a class method. probe.m calls each
// of them from Objective-C, which is the only way to know the runtime sees
// what the compiler meant it to.
module ObjCSubclass;

import Standard.Console;
import Standard.ObjC;

#pragma comment(framework, "Foundation")

[ObjCName("NSObject")]
public objc interface NSObjectProtocol
{
    [Selector("description")] NSString Description { get; }
}

[ObjCRoot]
public extern objc class NSObject : NSObjectProtocol
{
    [Selector("alloc")] public static Self Alloc();
    [Selector("init")] public Self Init();
    [Selector("description")] public NSString Description { get; }
}

public extern objc class NSString : NSObject
{
    [Selector("stringWithUTF8String:")] public static Self FromUtf8(byte* text);
    [Selector("stringByAppendingString:")] public NSString Append(NSString other);
    [Selector("hasPrefix:")] public bool HasPrefix(NSString prefix);
    [Selector("UTF8String")] public byte* Utf8 { get; }
    [Selector("length")] public nuint Length { get; }
}

public struct Wide
{
    public double A;
    public double B;
    public double C;
    public double D;
}

public objc interface Shape
{
    [Selector("area")] double Area();
    [Selector("sides")] long Sides { get; }
    [Optional, Selector("grow:")] void Grow(double by);
}

public objc class Square : NSObject, Shape
{
    // Shape's members, answered by name.
    public double Area() => 4.0;
    public long Sides => 4;

    [Selector("scaled:")] public long Scaled(long by) => by * 3;

    [Selector("spreadFlipped:")]
    public Wide Spread(bool flipped)
    {
        Wide wide;
        wide.A = flipped ? 4 : 1;
        wide.B = flipped ? 3 : 2;
        wide.C = flipped ? 2 : 3;
        wide.D = flipped ? 1 : 4;
        return wide;
    }

    [Selector("isLargerThan:")] public bool IsLargerThan(double other) => Area() > other;

    [Selector("named:")] public NSString Named(NSString name) => name.Append(NSString.FromUtf8(" square"));

    public override NSString Description => NSString.FromUtf8("a square, ").Append(base.Description);

    [Selector("square")] public static Square Make() => Square.Alloc().Init();

    // No selector: a Stainless helper, called directly.
    long Doubled(long value) => value * 2;
    public long DoubledSides() => Doubled(Sides);
}

public objc class Cube : Square
{
    public override double Area() => base.Area() * 6.0;
    public override long Sides => 6;
}

extern "C"
{
    double SLAreaOf(AnyObject shape);
    long SLSidesOf(AnyObject shape);
    long SLScale(AnyObject square, long by);
    bool SLConforms(AnyObject shape);
    bool SLAnswersGrow(AnyObject shape);
    bool SLIsLarger(AnyObject square, double other);
    double SLSpreadSum(AnyObject square, bool flipped);
    double SLSpreadFirst(AnyObject square, bool flipped);
    byte* SLDescribe(AnyObject anything);
    byte* SLNamed(AnyObject square, byte* name);
    long SLMadeByName(byte* name);
    byte* SLSuperclassOf(byte* name);
    nuint strlen(byte* text);
}

String Text(byte* text) => Standard.Text.FromBytes(text, strlen(text));

String Text(NSString text) => Standard.Text.FromBytes(text.Utf8, text.Length);

void FromStainless()
{
    var square = Square.Make();
    var cube = (Cube)Cube.Alloc().Init();
    Console.WriteLine($"stainless: area {square.Area()} {cube.Area()}");
    Console.WriteLine($"stainless: sides {square.Sides} {cube.Sides} {cube.DoubledSides()}");
    Console.WriteLine($"stainless: scaled {square.Scaled(5)}");
    Console.WriteLine($"stainless: a shape {square is Shape} {cube is Square}");

    Shape shape = cube;
    Console.WriteLine($"stainless: through the protocol {shape.Area()}");

    var description = cube.Description;
    Console.WriteLine($"stainless: described {description.HasPrefix(NSString.FromUtf8("a square, <ObjCSubclass.Cube: 0x"))}");
}

void FromObjectiveC()
{
    var square = Square.Make();
    var cube = (Cube)Cube.Alloc().Init();
    Console.WriteLine($"objc: area {SLAreaOf(square)} {SLAreaOf(cube)}");
    Console.WriteLine($"objc: sides {SLSidesOf(square)} {SLSidesOf(cube)}");
    Console.WriteLine($"objc: scaled {SLScale(cube, 7)}");
    Console.WriteLine($"objc: conforms {SLConforms(square)} answers grow {SLAnswersGrow(square)}");
    Console.WriteLine($"objc: larger {SLIsLarger(square, 3.5)} {SLIsLarger(square, 4.5)}");
    Console.WriteLine($"objc: spread {SLSpreadFirst(square, false)} {SLSpreadFirst(square, true)} {SLSpreadSum(cube, true)}");
    Console.WriteLine($"objc: named {Text(SLNamed(square, "big"))}");
    Console.WriteLine($"objc: by name {SLMadeByName("ObjCSubclass.Square")} {SLMadeByName("ObjCSubclass.Cube")}");
    Console.WriteLine($"objc: superclass {Text(SLSuperclassOf("ObjCSubclass.Cube"))} {Text(SLSuperclassOf("ObjCSubclass.Square"))}");
}

int Main()
{
    WithAutoreleasePool(() => FromStainless());
    WithAutoreleasePool(() => FromObjectiveC());
    return 0;
}
