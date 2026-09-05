// SPDX-License-Identifier: 0BSD
//
// The examples the documentation shows, compiled and run.
//
// Prose drifts away from a compiler quietly. This is here so that when it does,
// something fails rather than nobody noticing: every block below is lifted from
// README.md, docs/language-spec.md or docs/concurrency.md.
module Doc;

import Standard.Collections;
import Standard.Threading;
import Standard.Console;
import Standard.IO;
import Standard.File;
import Standard.Path;

extern "C" int printf(byte* format, ...);

// --- spec 5.2 / concurrency 4.2 -------------------------------------------
static readonly Mutex<List<String>> Registry =
    new Mutex<List<String>>(new List<String>());

void Record(String name) {
    var guard = Registry.Lock();
    guard.Value().Add(name);
}

// --- spec 2.8 delegates ---------------------------------------------------
public delegate int Transform(int value);
int Double(int value) { return value * 2; }

// --- spec 2.9 closures ----------------------------------------------------
public interface ITransform { int Apply(int value); }

ITransform MakeAdder(int amount) {
    return value => value + amount;
}

// --- spec 2.7 enums -------------------------------------------------------
public enum Color { Red, Green, Blue }
public enum Level : byte { Low = 1, Warning = 10, Severe, Fatal = 200 }

// --- concurrency 9.1 cancellation ----------------------------------------
int Search(int[] data, int from, int upto, AtomicBool stop) {
    for (int i = from; i < upto; i = i + 1) {
        if (stop.Load()) { return -1; }
        if (data[i] == 42) { stop.Store(true); return i; }
    }
    return -1;
}

// --- spec 5.7 IO ----------------------------------------------------------
String Roundtrip() {
    var buffer = new MemoryStream();
    buffer.WriteText("via a stream");

    var read = File.ReadAllText("no-such-file-anywhere.txt");
    var reason = read.Ok ? read.Value : IO.Describe(read.Error);

    return buffer.ToText() + " / " + reason + " / " + Path.FileName("x/y/notes.txt");
}

// --- spec 2.6 / 7.1 overloading, and one class implementing two interfaces -
interface IEq<T> { bool Same(T other); }

class Both : IEq<int>, IEq<String> {
    public bool Same(int other)    { return other == 7; }
    public bool Same(String other) { return other == "seven"; }
}

class Printer {
    public String Show(int n)    { return "int"; }
    public String Show(String s) { return "text"; }
    public String Show(double d) { return "double"; }
}

String Overloads() {
    var both = new Both();
    IEq<int> asNumber = both;
    IEq<String> asText = both;

    var printer = new Printer();
    return printer.Show(1) + " " + printer.Show("x") + " " + printer.Show(2.5)
        + " " + (asNumber.Same(7) && asText.Same("seven") ? "both" : "neither");
}

// --- spec 2.10 a lambda reaching its object -------------------------------
class Scaler {
    public int Factor;
    public Scaler(int factor) { Factor = factor; }

    int Triple(int n) { return n * 3; }

    public ITransform ByField()  { return value => value * Factor; }
    public ITransform ByThis()   { return value => value * this.Factor; }
    public ITransform ByMethod() { return value => Triple(value); }
}

// --- spec 2.4 weak breaks a cycle -----------------------------------------
class Kid {
    public weak Guardian? Owner;
}

class Guardian {
    public Kid? Child;
}

String Cycles() {
    var guardian = new Guardian();
    var kid = new Kid();
    guardian.Child = kid;
    kid.Owner = guardian;

    Guardian? back = kid.Owner;
    return back == null ? "lost" : "linked";
}

// --- spec 9 arithmetic C leaves undefined ---------------------------------
int Forty() { return 40; }

String Defined() {
    return Text.FromInteger(1 << Forty())          // 1 << (40 & 31)
        + ":" + Text.FromInteger(1 << 30);
}

// --- spec 2.5 Result ------------------------------------------------------
enum Why { None = 0, TooSmall = 1, TooBig = 2 }

Result<int, Why> Doubled(int n) {
    if (n < 0) { return Fail(Why.TooSmall); }
    return Ok(n * 2);
}

// The early return, and the proof it leaves behind.
Result<String, Why> Described(int n) {
    var doubled = Doubled(n);
    if (!doubled.Ok) { return Fail(doubled.Error); }
    return Ok("got " + Text.FromInteger(doubled.Value));
}

String Results() {
    var good = Described(21);
    var bad = Described(-1);

    // A declared local is a target the same way a return type is.
    Result<int, Why> held = Ok(4);

    return (good.Ok ? good.Value : "none")
        + " / " + Text.FromInteger(bad.Ok ? 0 : (int)bad.Error)
        + " / " + Text.FromInteger(Doubled(-9).ValueOr(8080))
        + " / " + Text.FromInteger(held.ValueOr(0));
}

// --- spec 2.2 a struct that holds a reference -----------------------------
struct Holder {
    public String Text;
    public int Tag;
}

String Held() {
    Holder one;
    one.Text = "owned";
    one.Tag = 3;

    var two = one;                 // the copy retains what it holds
    return two.Text + Text.FromInteger(two.Tag);
}

// --- spec 5.4 collections -------------------------------------------------
String Roster() {
    var ages = new Dictionary<String, int>();
    ages.Set("ada", 36);

    var numbers = new List<int>();
    numbers.Add(9); numbers.Add(2); numbers.Add(5);
    Sort(numbers);

    var line = new LinkedList<String>();
    var first = line.AddLast("a");
    line.AddLast("c");
    line.InsertAfter(first, "b");

    var text = new StringBuilder();
    text.AppendInteger(ages.Get("ada"));
    text.Append(":");
    for (nuint i = 0; i < numbers.Count(); i = i + 1) { text.AppendInteger(numbers.At(i)); }
    text.Append(":");
    for (nint at = line.First(); at >= 0; at = line.After(at)) { text.Append(line.ValueAt(at)); }
    return text.ToText();
}

// --- spec 2.7 flags enums -------------------------------------------------
[Flags]
public enum Access : byte {
    None = 0, Read = 1, Write = 2, Execute = 4, All = 7,
}

// --- spec 9.1 switch ------------------------------------------------------
String Name(Level level) {
    switch (level) {
        case Level.Low:     return "low";
        case Level.Warning: return "warning";
        case Level.Severe:  return "severe";
        default:            return "fatal";
    }
}

int SkipAndStop(int[] values) {
    int total = 0;
    for (nuint i = 0; i < values.Length; i = i + 1) {
        switch (values[i]) {
            case -1: continue;
            case 0:  break;
            default: total = total + values[i]; break;
        }
        total = total + 100;
    }
    return total;
}

// --- spec 7.2 properties --------------------------------------------------
public interface INamed {
    String Name { get; }
    int Rank { get; set; }
}

public class Person : INamed {
    public String Name { get; set; }         // automatic: the compiler owns the storage
    public int Visits { get; private set; }  // read anywhere, write in this module
    public int Id { get; }                   // set by a constructor, then fixed
    public int Rank { get; set; }

    public String Label => Name + "#" + Text.FromInteger(Id);   // computed

    public Person(String name, int id) { Name = name; Id = id; Visits = 0; Rank = 0; }
}

public class Thermostat {
    int celsius;

    public Thermostat(int c) { celsius = c; }

    public int Fahrenheit {
        get { return celsius * 9 / 5 + 32; }
        set { celsius = (value - 32) * 5 / 9; }
    }

    public int Kelvin {
        get => celsius + 273;
        set => celsius = value - 273;
    }
}

// --- spec 9.2 statics, out of order --------------------------------------
static readonly int Total   = Doubled + 1;
static readonly int Doubled = Base * 2;
static readonly int Base    = 20;


// --- README "Inheritance" / spec 2.4.1 and 2.4.2 --------------------------
public abstract class DocShape {
    protected int sides;

    DocShape(int howMany) { sides = howMany; }

    public abstract double Area();
    public virtual String Name() { return "shape"; }
}

public class DocPolygon : DocShape {
    double width;

    DocPolygon(int howMany, double w) {
        base(howMany);
        width = w;
    }

    public override double Area() { return width * width; }
    public override String Name() { return "polygon"; }
}

public sealed class DocSquare : DocPolygon {
    DocSquare(double side) { base(4, side); }

    public sealed override String Name() { return "square"; }
}

String Inherits() {
    DocShape shape = new DocSquare(3.0);

    String answer = shape.Name() + ":" + Text.FromDouble(shape.Area());

    if (shape is DocSquare) {
        DocSquare square = (DocSquare)shape;
        answer = answer + ":" + Text.FromDouble(square.Area());
    }

    return answer + ":" + Text.FromBool(shape is DocPolygon);
}

// --- README "Variants" / spec 2.5 -----------------------------------------
public variant Shape {
    Circle(double Radius);
    Rect(double Width, double Height);
    Empty;
}

double Area(Shape shape) {
    switch (shape) {
        case Circle c: return 3.14159 * c.Radius * c.Radius;
        case Rect r:   return r.Width * r.Height;
        case Empty:    return 0.0;
    }
}

double Radius(Shape shape) {
    if (shape.Circle) { return shape.Radius; }
    return 0.0;
}

String Shapes() {
    Shape a = Shape.Circle(2.0);
    Shape b = Circle(2.0);
    return Text.FromDouble(Area(a)) + ":" + Text.FromDouble(Area(b)) +
           ":" + Text.FromDouble(Area(Rect(3.0, 4.0))) +
           ":" + Text.FromDouble(Radius(Shape.Empty)) +
           ":" + Text.FromInteger((int)sizeof(Shape));
}


// --- README "Passing by reference" / spec 7.2 -----------------------------
public struct Origin { public double X; public double Y; }

void Bump(ref int n) { n = n + 1; }
double LengthSquared(in Origin p) { return p.X * p.X + p.Y * p.Y; }

extern "C" double modf(double value, ref double integral);

String ByReference() {
    int count = 1;
    Bump(ref count);

    Origin origin;
    origin.X = 3.0;
    origin.Y = 4.0;

    double whole = 0.0;
    double fraction = modf(3.75, ref whole);

    return Text.FromInteger(count) + ":" + Text.FromDouble(LengthSquared(origin)) +
           ":" + Text.FromDouble(whole) + ":" + Text.FromDouble(fraction);
}


// --- README "Slices" / spec 2.9 -------------------------------------------
String Slicing() {
    var numbers = new int[6];
    for (nuint i = 0; i < numbers.Length; i = i + 1) { numbers[i] = (int)i + 1; }

    int[:] all    = numbers;
    int[:] middle = numbers[1:4];
    int[:] tail   = numbers[3:];

    Sort(numbers[2:5]);

    // A view, not a copy: writing through one writes the array.
    middle[0] = 100;

    String text = "";
    foreach (int v in all) { text = text + Text.FromInteger(v) + " "; }

    return Text.FromInteger((int)middle.Length) + ":" +
           Text.FromInteger((int)tail.Length) + ":" + text;
}


// --- README "Conditional compilation" / spec 10 ---------------------------
#if WINDOWS
String Where() { return "a platform"; }
#elif UNIX
String Where() { return "a platform"; }
#else
#error this platform is not one of the ones this file knows
#endif


// --- README "Layout control" / spec 2.3 -----------------------------------
[Packed]
public struct Wire { public byte Tag; public int Value; public byte Trailer; }

[Align(16)]
public struct Wide { public double X; public double Y; }

String Layouts() {
    return Text.FromInteger((int)sizeof(Wire)) + ":" +
           Text.FromInteger((int)sizeof(Wide));
}


// --- README "Unions" / spec 2.7 -------------------------------------------
public union Word {
    public int Signed;
    public uint Unsigned;
    public float Real;
}

String Reinterpret() {
    Word word;
    word.Signed = -1;
    return Text.FromInteger((int)sizeof(Word)) + ":" +
           Text.FromInteger((int)(word.Unsigned / 1000000));
}


// --- README "Bit-fields" / spec 2.2 ---------------------------------------
public struct PacketHeader {
    public uint Version : 4;
    public uint Kind    : 4;
    public uint Length  : 24;
}

String Bits() {
    PacketHeader header;
    header.Version = 3;
    header.Kind = 9;
    header.Length = 1000000;
    header.Kind = header.Kind + (uint)1;

    return Text.FromInteger((int)header.Version) + ":" +
           Text.FromInteger((int)header.Kind) + ":" +
           Text.FromInteger((int)header.Length) + ":" +
           Text.FromInteger((int)sizeof(PacketHeader));
}

// --- spec 2.10.1 array literals -------------------------------------------
int SumSlice(int[:] slice) {
    int total = 0;
    for (nuint i = 0u; i < slice.Length; i = i + 1u) { total = total + slice[i]; }
    return total;
}

String Literals() {
    var numbers = [1, 2, 3, 4];
    String[] names = ["alpha", "beta"];
    int[3] fixed = [7, 8, 9];
    var mixed = [1, 2L, 3];

    return Text.FromInteger((long)numbers.Length) + " " + names[1] + " " +
           Text.FromInteger((long)fixed[2]) + " " +
           Text.FromInteger(mixed[1]) + " " +
           Text.FromInteger((long)SumSlice([10, 20, 30]));
}

int Main() {
    Record("first");
    { var g = Registry.Lock(); printf("recorded=%d\n", (int)g.Value().Count()); }

    Transform t = Double;
    printf("delegate=%d\n", t(21));

    int factor = 3;
    ITransform scale = value => value * factor;
    factor = 100;
    printf("closure=%d\n", scale.Apply(7));
    printf("adder=%d\n", MakeAdder(10).Apply(5));

    Level at = Level.Severe;
    printf("enum=%d\n", at >= Level.Warning ? 1 : 0);
    printf("severe=%d\n", (int)Level.Severe);

    var data = new int[100];
    for (int i = 0; i < 100; i = i + 1) { data[i] = i; }
    var stop = new AtomicBool(false);
    int half = 50;
    int hitLeft = 0;
    int hitRight = 0;
    parallel {
        spawn hitLeft  = Search(data, 0, half, stop);
        spawn hitRight = Search(data, half, 100, stop);
    }
    printf("found=%d\n", hitLeft + hitRight + 1);

    printf("statics=%d %d %d\n", Base, Doubled, Total);

    var person = new Person("Ada", 7);
    person.Rank += 3;
    INamed named = person;
    printf("property=%s %d\n", person.Label.ToPointer(), named.Rank);

    var thermostat = new Thermostat(0);
    thermostat.Fahrenheit = 212;
    printf("thermostat=%d %d\n", thermostat.Fahrenheit, thermostat.Kelvin);

    var mode = Access.Read | Access.Write;
    var readOnly = mode & ~Access.Write;
    mode ^= Access.Execute;
    printf("flags=%d %d %d\n",
        mode.HasFlag(Access.Read) ? 1 : 0, (int)readOnly, (int)mode);

    printf("switch=%s %s\n", Name(Level.Severe).ToPointer(), Name(Level.Fatal).ToPointer());
    printf("roster=%s\n", Roster().ToPointer());
    printf("io=%s\n", Roundtrip().ToPointer());
    printf("result=%s\n", Results().ToPointer());
    printf("held=%s\n", Held().ToPointer());

    var scaler = new Scaler(3);
    printf("capture=%d %d %d\n",
        scaler.ByField().Apply(7), scaler.ByThis().Apply(7), scaler.ByMethod().Apply(7));
    printf("cycle=%s\n", Cycles().ToPointer());
    printf("defined=%s\n", Defined().ToPointer());
    printf("overloads=%s\n", Overloads().ToPointer());
    printf("intrinsic=%d %d\n", 3.CompareTo(5), "apple".CompareTo("banana"));

    var counted = new int[4];
    counted[0] = 5;
    counted[1] = -1;
    counted[2] = 0;
    counted[3] = 7;
    printf("sections=%d\n", SkipAndStop(counted));

    var pixels = new int[16];
    parallel for (int i = 0; i < 16; i = i + 1) { pixels[i] = i * i; }
    printf("pixels=%d\n", pixels[15]);

    foreach (int p in pixels) { }
    printf("bits=%s\n", Bits().ToPointer());
    printf("union=%s\n", Reinterpret().ToPointer());
    printf("layout=%s\n", Layouts().ToPointer());
    printf("where=%s\n", Where().ToPointer());
    printf("slices=%s\n", Slicing().ToPointer());
    printf("byref=%s\n", ByReference().ToPointer());
    printf("shapes=%s\n", Shapes().ToPointer());
    printf("inherits=%s\n", Inherits().ToPointer());
    printf("literals=%s\n", Literals().ToPointer());
    printf("done\n");
    return 0;
}
