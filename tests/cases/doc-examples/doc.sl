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
    printf("done\n");
    return 0;
}
