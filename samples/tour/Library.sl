// SPDX-License-Identifier: 0BSD
//
// The second half of the tour, and the second file of `module Tour` -- which is
// §1.2 demonstrated by being it: the two halves see each other's private names,
// and neither imports the other.
//
// Members (§7), generics (§4), the standard library (§5), reflection (§6),
// interoperability (§8) and concurrency (§9.2).
module Tour;

import Standard.Collections;
import Standard.Concurrent;
import Standard.Console;
import Standard.Convert;
import Standard.Directory;
import Standard.Env;
import Standard.File;
import Standard.IO;
import Standard.Json;
import Standard.Math;
import Standard.Path;
import Standard.Random;
import Standard.Reflection;
import Standard.Threading;
import Standard.Time;
import Standard.Xml;
import Tour.Platform;
import Tour.Types;

// ==================================================================== §7

void Members() {
    Heading("7. properties, indexers, operators and statics");

    // §7.3: a property is a pair of functions wearing the spelling of a field,
    // so writing one runs the setter -- which is what the counter shows.
    var control = new Control("panel");
    control.Left = 5;
    control.Left = 8;
    Say("property", (long)control.Left);
    Say("setter ran", (long)control.Layouts);
    Say("computed", (long)control.Right);
    Say("automatic", control.Name);

    // §7.5: an indexer is a property that takes an argument, and overloads on
    // the index type.
    Say("indexer get", (long)control[2u]);
    control[3u] = 20;
    Say("indexer set", (long)control.Left);
    Say("other indexer", control["panel"]);

    // §7.4: operators, declared inside the type with every operand written
    // out. `3 * money` is why there is no implicit receiver.
    var price = Cents(1250);
    var tax = Cents(100);
    Say("plus", (price + tax).Cents);
    Say("minus", (price - tax).Cents);
    Say("negate", (-price).Cents);
    Say("times", (price * 3).Cents);
    Say("times, other way", (3 * price).Cents);
    Say("divide", (price / 5).Cents);
    Say("remainder", (price % 7).Cents);
    Say("equal", price == Cents(1250));
    Say("less", price < tax);
    Say("compound", (price += tax).Cents);

    var bits = Of(12u);
    var other = Of(10u);
    Say("or / and / xor", $"{(bits | other).Bits} {(bits & other).Bits} {(bits ^ other).Bits}");
    Say("complement", (long)(~bits).Bits);
    Say("shifts", $"{(bits << 2).Bits} {(bits >> 2).Bits}");
    Say("not", !Of(0u));

    // §7.6: storage that belongs to the type. The static constructor ran
    // before `Main`, in the same pass the field initializers did.
    var one = new Registry("one");
    var two = new Registry("two");
    Say("static field", Registry.Kind);
    Say("static readonly", Registry.Version);
    Say("static method", (long)Registry.Made());
    Say("static property", (long)Registry.Doubled);
    Say("instances", one.Name() + " " + two.Name());
    Say("static class", $"{Defaults.Retries} {Defaults.Note()}");

    // A type declared inside another, named for where it was written.
    var widget = new Widget();
    widget.Mood = Widget.State.Busy;    // the long name, from outside
    Widget.Span span;
    span.From = 2;
    span.To = 9;
    widget.Extent = span;
    Say("nested enum", (long)widget.Mood);
    Say("nested struct", (long)widget.Width());
}

// ==================================================================== §7.1

/// Overloads are told apart by their parameters, and a free function is
/// reached without a prefix from inside the module that declares it.
String Render(int value) { return $"int {value}"; }
String Render(double value) { return $"double {value}"; }
String Render(String value) { return $"text {value}"; }

// ==================================================================== §7.2

/// `ref` is one storage location under two names: the callee writes what the
/// caller can see.
void Twice(ref int value) { value *= 2; }

/// `in` is the same address without the permission to write through it, which
/// is how a large struct is passed without a copy.
double Length(in Point point) { return point.X + point.Y; }

/// `out` is a second answer rather than a second call. It must be written
/// before the function returns, and the caller need not have initialized it.
bool TryHalve(int n, out int half) {
    if (n % 2 != 0) { half = 0; return false; }
    half = n / 2;
    return true;
}

/// Passing one straight on, which is what makes `out` compose.
bool Forward(int n, out int half) { return TryHalve(n, out half); }

/// Four parameters, three of which read as nothing at a call site without
/// names for them.
String Draw(String text, int width, bool center, char fill) {
    var pad = new StringBuilder();
    for (int i = 0; i < width; i++) { pad.Append(Text.FromChar((char32)fill)); }
    return (center ? "[" : "<") + text + pad.ToText() + (center ? "]" : ">");
}

void Calls() {
    Heading("7.1 and 7.2 how a function is called");

    // Overloads, resolved on the arguments.
    Say("overload int", Render(3));
    Say("overload double", Render(3.5));
    Say("overload String", Render("three"));

    // `ref`: the caller's own storage, and the word is written at both ends so
    // that a call that can change its argument says so where it is read.
    int counter = 21;
    Twice(ref counter);
    Say("ref", (long)counter);

    // `in`: the address, and no way to write through it. It is not written at
    // the call, because a promise not to change anything needs no warning --
    // where `ref` is, so that a line that may come back changed says so.
    Point point;
    point.X = 3.0;
    point.Y = 4.0;
    Say("in", Length(point));

    // `out`: the answer beside the answer.
    int half = 0;
    Say("out, taken", TryHalve(84, out half) ? $"yes {half}" : "no");
    Say("out, refused", TryHalve(7, out half) ? $"yes {half}" : $"no {half}");
    Forward(100, out half);
    Say("out, passed on", (long)half);

    // Named arguments, which may be given in any order once the positional
    // ones are done -- and are matched to parameters by name rather than by
    // where they sit.
    Say("positional", Draw("x", 3, true, '.'));
    Say("named", Draw(text: "x", width: 3, center: true, fill: '.'));
    Say("reordered", Draw("x", center: false, fill: '-', width: 5));
}

// ==================================================================== §4

void Generics() {
    Heading("4. generics");

    // Monomorphization: `T` is substituted and the body compiled again, so
    // there is no boxing, no type erasure and no shared code.
    // §4.4: type arguments are inferred and never written at a call, `<` in
    // expression position being ambiguous with less-than.
    Say("over int", (long)Larger(3, 9));
    Say("over String", Larger("alpha", "beta"));
    Say("over long", (long)Larger(2L, 7L));

    // A generic type, whose operators are instantiated with it.
    var a = Boxed(3);
    var b = Boxed(4);
    Say("generic operator", (long)(a + b).Value);
    Say("generic equality", a == Boxed(3));
    Say("generic method", a.Pair("text"));

    // Two type parameters bound at different times, and an instantiation held
    // inside another.
    var cell = new Cell<Box<int>>(a);
    Say("nested instantiation", (long)cell.Held.Value);

    // A constraint is what lets the body call something. Two at once is the
    // shape `Dictionary` needs of a key.
    int[] numbers = [3, 1, 4, 1, 5];
    Say("constrained", (long)Digest(numbers));

    // §2.14 again, now generic: a closure over a type parameter is what the
    // standard library's whole combinator surface is built on.
    Keeps<int> odd = n => n % 2 != 0;
    Turns<int, String> show = n => $"<{n}>";
    Say("generic closure", odd(3));
    Say("generic transform", show(9));
}

// ==================================================================== §5

void Library() {
    Heading("5. the standard library");

    // ------------------------------------------------------------ containers
    var list = new List<String>();
    list.Add("gamma");
    list.Add("alpha");
    list.Add("beta");
    Say("List", $"{list.Count()} items, first {list.At(0u)}");

    var map = new Dictionary<String, int>();
    map.Set("one", 1);
    map.Set("two", 2);
    Say("Dictionary", (long)map.GetOr("two", -1));
    Say("missing", (long)map.GetOr("three", -1));

    var set = new HashSet<int>();
    set.Add(1);
    set.Add(1);
    set.Add(2);
    Say("HashSet", (long)set.Count());

    var queue = new Queue<int>();
    queue.Enqueue(1);
    queue.Enqueue(2);
    Say("Queue", (long)queue.Dequeue());

    var stack = new Stack<int>();
    stack.Push(1);
    stack.Push(2);
    Say("Stack", (long)stack.Pop());

    var chain = new LinkedList<String>();
    chain.AddLast("tail");
    chain.AddFirst("head");
    Say("LinkedList", (long)chain.Count());

    var sorted = new SortedList<int, String>();
    sorted.Set(2, "two");
    sorted.Set(1, "one");
    Say("SortedList", sorted.ValueAt(0u));

    // ------------------------------------------------------------ sequences
    //
    // §7.1: `x.F(y)` means `F(x, y)` when `x` has no member `F`, so the whole
    // combinator surface chains without an extension-method modifier. A member
    // always wins; the fallback is reached only after member lookup fails.
    int[] values = [5, 3, 9, 3, 1, 8];

    var picked = values
        .Where(n => n > 2)
        .Distinct()
        .OrderBy((x, y) => x - y)
        .ToArray();

    var line = new StringBuilder();
    foreach (var n in picked) { line.Append($"{n} "); }
    Say("chained", line.ToText().Trim());

    Say("map / reduce", (long)values.Select(n => n * 2).Aggregate(0, (t, n) => t + n));
    Say("any / all", $"{values.Any(n => n > 8)} {values.All(n => n > 0)}");
    Say("count where", (long)values.CountWhere(n => n == 3));
    Say("find", (long)values.Find(n => n > 4).ValueOr(-1));
    Say("index where", (long)values.IndexWhere(n => n == 9).ValueOr(0u));

    Sort(values);
    Say("sorted", (long)values[0u]);

    // ------------------------------------------------------------ numbers
    Say("Math", $"{Sqrt(16.0)} {Floor(2.7)} {Abs(-3.0)} {Pow(2.0, 10.0)}");
    Say("Pi", Round(Pi * 100.0) / 100.0);

    // Seeded, so the tour prints the same numbers every time it runs.
    var dice = new Random(20260906);
    Say("Random", (long)(dice.NextBelow(6u) + 1u));
    Say("again", (long)(dice.NextBelow(6u) + 1u));

    // ------------------------------------------------------------ the clock
    //
    // A monotonic clock only goes forward, which is the one thing about it a
    // test may assert without printing a time that changes every run.
    var clock = new Clock();
    long spun = 0;
    for (int i = 0; i < 100000; i++) { spun += i; }
    var taken = clock.Elapsed();
    Say("monotonic", taken.Nanoseconds >= 0);
    Say("a duration", Duration.FromSeconds(90).TotalMinutes());

    // ------------------------------------------------------------ the world
    Say("has PATH", Env.Has("PATH") || Env.Has("Path"));
    Say("set and read", Env.Set("STAINLESS_TOUR", "yes") ? Env.GetOr("STAINLESS_TOUR", "-") : "-");

    // ------------------------------------------------------------ files
    //
    // Written and read back in a directory this program makes, so what is
    // printed comes from the tour rather than from the machine it ran on.
    var folder = Path.Join(Env.CurrentDirectory(), "tour-scratch");
    var file = Path.Join(folder, "notes.txt");

    Say("made a directory", IO.Describe(Directory.CreateAll(folder)));
    Say("wrote", IO.Describe(File.WriteAllText(file, "one" + Newline() + "two" + Newline())));

    var read = File.ReadAllLines(file);
    Say("read back", read.Ok ? (long)read.Value.Count() : -1);
    Say("size", File.Size(file));
    Say("extension", Path.Extension(file));
    Say("file name", Path.FileName(file));
    Say("without it", Path.WithoutExtension(Path.FileName(file)));
    Say("rooted", Path.IsRooted(file));

    File.Delete(file);
    Directory.Delete(folder);
    Say("cleaned up", !File.Exists(file) && !Directory.Exists(folder));

    // ------------------------------------------------------------ documents
    var document = Json.Parse("{\"name\":\"tour\",\"count\":3,\"on\":true}");
    if (document.Ok) {
        var members = MembersOf(document.Value);
        Say("JSON", TextOr(members.Find("name"), "-"));
        Say("JSON number", IntegerOr(members.Find("count"), -1));
        Say("JSON round trip", Json.Write(document.Value));
    }

    var parsed = Xml.Parse("<tour kind=\"sample\"><part>one</part></tour>");
    if (parsed.Ok) {
        Say("XML", parsed.Value.Name);
        Say("XML attribute", parsed.Value.Attributes.Find("kind", "-"));
    }

    // ------------------------------------------------------------ text, again
    Say("base64", Convert.ToBase64Text("stainless"));
    Say("hex of 48879", Convert.FromLong(48879, 16u));
}

// ==================================================================== §6

/// One serializer, written once, for any reflected type. `T` is concrete by the
/// time this is compiled, so `typeof(T)` is a constant and every call below is
/// a load from a table in the binary's read-only data.
String Describe<T>(T value) {
    var type = typeof(T);
    var text = new StringBuilder();

    text.Append("{");
    var first = true;

    for (nuint i = 0u; i < type.FieldCount(); i++) {
        var field = type.FieldAt(i);
        if (field.Has("Hidden")) { continue; }

        if (!first) { text.Append(","); }
        first = false;

        var name = field.Name();
        if (field.Has("Column")) { name = field.Get("Column").AsText(0u); }

        text.Append(name);
        text.Append("=");

        var raw = (byte*)value;
        if (field.Kind() == KindString) { text.Append(ReadText(raw, field)); }
        else if (field.Kind() == KindBool) { text.Append(Text.FromBool(ReadBool(raw, field))); }
        else if (field.IsFloating()) { text.AppendDouble(ReadDouble(raw, field)); }
        else if (field.IsInteger()) { text.AppendInteger(ReadInteger(raw, field)); }
        else { text.Append("?"); }
    }

    text.Append("}");
    return text.ToText();
}

void Reflected() {
    Heading("6. attributes and reflection");

    var person = new Person("Ada", 36);
    var type = typeof(Person);

    Say("type name", type.Name());
    Say("fields", (long)type.FieldCount());
    Say("serialized", Describe(person));

    // A field is an offset, so writing one stores bytes.
    var years = type.FindField("Years");
    WriteInteger((byte*)person, years, 37);
    Say("field written", (long)person.Years);

    // A property is a pair of functions, so writing one runs the setter --
    // which is the difference the two tables exist to keep.
    Say("properties", (long)type.PropertyCount());
    var city = type.FindProperty("City");
    Say("can write", city.CanWrite());
    SetText((byte*)person, city, "Lovelace");
    Say("property written", person.City);

    // The annotation travels with the storage.
    Say("attribute", type.FindField("Name").Get("Column").AsText(0u));
    Say("ignored", type.FindField("Internal").Has("Hidden"));

    // And a type may be found by its name, which is what a loader needs.
    Say("by name", FindType("Tour.Types.Person").Exists());
}

// ==================================================================== §8

void Interop() {
    Heading("8. interoperability");

    // A variadic `extern` -- the only kind there is, a Stainless function
    // never being variadic.
    printf("  %-22s%s %d\n", "printf".ToPointer(), "called with".ToPointer(), 3);

    // A delegate is one function pointer with the C convention, so C both
    // receives one and calls back through it.
    Adjust twice = value => value + 1;
    Say("C called back", (long)c_apply_twice(twice, 10));

    // A struct of plain data crosses by value, laid out as C lays it out.
    PlainPair pair;
    pair.A = 4;
    pair.B = 5;
    Say("struct by value", (long)c_sum_pair(pair));   // C calls tour_triple

    // And the other direction: `export "C"` put this in the export table under
    // exactly that name, which is what the C file called.
    Say("export", (long)tour_triple(7));

    // §8.1: C++, reached by mangling the signature the way the target's own
    // compiler does. Nothing here is `extern "C"`, and there is no shim.
    Say("C++ namespace", area(3.0, 4.0));
    Say("C++ round trip", (long)cpp_round_trip(20));
}

// ==================================================================== §9.2

/// `threadsafe` asserts what no declaration can prove: every operation here
/// goes through an atomic, so sharing one really is sound. Without the word the
/// `spawn` below still compiles, and warns.
threadsafe class Tally {
    AtomicLong total;

    public Tally(AtomicLong cell) { total = cell; }

    public void Contribute(long amount) { total.Add(amount); }
}

int Squared(int value) { return value * value; }

long SumOf(int[] values, int from, int upto) {
    long total = 0;
    for (int i = from; i < upto; i++) { total += values[i]; }
    return total;
}

void Concurrency() {
    Heading("9.2 parallel, spawn, and what may be shared");

    var values = new int[100];
    for (int i = 0; i < 100; i++) { values[i] = i; }

    // Two halves, each writing into a local the parent still owns. The join at
    // the closing brace is what makes that sound.
    long left = 0;
    long right = 0;

    parallel {
        spawn left = SumOf(values, 0, 50);
        spawn right = SumOf(values, 50, 100);
    }

    Say("parallel", left + right);

    // One job per iteration: sharing one argument block would give every job
    // the last iteration's values.
    var squares = new int[8];
    parallel {
        for (int i = 0; i < 8; i++) {
            spawn squares[i] = Squared(values[i]);
        }
    }
    Say("spawn in a loop", (long)(squares[3] + squares[7]));

    // `parallel for` is the same thing said once: the body runs for every
    // index, and nothing it writes may be read by another iteration.
    var doubled = new int[16];
    parallel for (int i = 0; i < 16; i += 1) {
        doubled[i] = values[i] * 2;
    }
    Say("parallel for", (long)doubled[15]);

    // A mutex owns what it guards, so there is no way to read the value
    // without holding the lock.
    var guarded = new Mutex<long>(0);
    var counter = new AtomicLong(0);
    var tally = new Tally(counter);

    parallel {
        spawn Contribute(tally, guarded, 10);
        spawn Contribute(tally, guarded, 32);
    }

    Say("atomic", counter.Load());
    Say("mutex", guarded.Lock().Value());

    // A queue that several threads may hold at once.
    var pending = new ConcurrentQueue<long>();
    parallel {
        spawn pending.Enqueue(1);
        spawn pending.Enqueue(2);
    }
    Say("concurrent queue", (long)pending.Count());
}

/// A newline, written as an escape rather than embedded, so the file the tour
/// writes is the same on both platforms.
String Newline() { return Text.FromChar((char32)10); }

void Contribute(Tally tally, Mutex<long> guarded, long amount) {
    tally.Contribute(amount);
    var guard = guarded.Lock();
    guard.Set(guard.Value() + amount);
}
