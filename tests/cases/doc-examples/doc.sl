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

    var pixels = new int[16];
    parallel for (int i = 0; i < 16; i = i + 1) { pixels[i] = i * i; }
    printf("pixels=%d\n", pixels[15]);

    foreach (int p in pixels) { }
    printf("done\n");
    return 0;
}
