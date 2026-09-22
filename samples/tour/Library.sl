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

void ShowMembers()
{
    PrintHeading("7. properties, indexers, operators and statics");

    // §7.3: a property is a pair of functions wearing the spelling of a field,
    // so writing one runs the setter -- which is what the counter shows.
    var control = new Control("panel");
    control.Left = 5;
    control.Left = 8;
    PrintValue("property", (long)control.Left);
    PrintValue("setter ran", (long)control.Layouts);
    PrintValue("computed", (long)control.Right);
    PrintValue("automatic", control.Name);

    // §7.5: an indexer is a property that takes an argument, and overloads on
    // the index type.
    PrintValue("indexer get", (long)control[2u]);
    control[3u] = 20;
    PrintValue("indexer set", (long)control.Left);
    PrintValue("other indexer", control["panel"]);

    // §7.4: operators, declared inside the type with every operand written
    // out. `3 * money` is why there is no implicit receiver.
    var price = CreateMoney(1250);
    var tax = CreateMoney(100);
    PrintValue("plus", (price + tax).Cents);
    PrintValue("minus", (price - tax).Cents);
    PrintValue("negate", (-price).Cents);
    PrintValue("times", (price * 3).Cents);
    PrintValue("times, other way", (3 * price).Cents);
    PrintValue("divide", (price / 5).Cents);
    PrintValue("remainder", (price % 7).Cents);
    PrintValue("equal", price == CreateMoney(1250));
    PrintValue("less", price < tax);
    PrintValue("compound", (price += tax).Cents);

    var bits = CreateMask(12u);
    var other = CreateMask(10u);
    PrintValue("or / and / xor",
        $"{(bits | other).Bits} {(bits & other).Bits} {(bits ^ other).Bits}");
    PrintValue("complement", (long)(~bits).Bits);
    PrintValue("shifts", $"{(bits << 2).Bits} {(bits >> 2).Bits}");
    PrintValue("not", !CreateMask(0u));

    // §7.6: storage that belongs to the type. The static constructor ran
    // before `Main`, in the same pass the field initializers did.
    var one = new Registry("one");
    var two = new Registry("two");
    PrintValue("static field", Registry.Kind);
    PrintValue("static readonly", Registry.Version);
    PrintValue("static method", Registry.HasMade(2));
    PrintValue("static property", (long)Registry.Doubled);
    PrintValue("instances", one.Name + " " + two.Name);
    PrintValue("static class", $"{Defaults.Retries} {Defaults.Note}");

    // A type declared inside another, named for where it was written.
    var widget = new Widget;
    widget.Mood = Widget.State.Busy;    // the long name, from outside
    Widget.Span span;
    span.From = 2;
    span.To = 9;
    widget.Extent = span;
    PrintValue("nested enum", (long)widget.Mood);
    PrintValue("nested struct", (long)widget.Width);
}

// ==================================================================== §7.1

/// Overloads are told apart by their parameters, and a free function is
/// reached without a prefix from inside the module that declares it.
String RenderValue(int value) => $"int {value}";
String RenderValue(double value) => $"double {value}";
String RenderValue(String value) => $"text {value}";

// ==================================================================== §7.2

/// `ref` is one storage location under two names: the callee writes what the
/// caller can see.
void DoubleInPlace(ref int value) => value *= 2;

/// `in` is the same address without the permission to write through it, which
/// is how a large struct is passed without a copy.
double SumCoordinates(in Point point) => point.X + point.Y;

/// `out` is a second answer rather than a second call. It must be written
/// before the function returns, and the caller need not have initialized it.
bool TryHalve(int n, out int half)
{
    if (n % 2 != 0)
    {
        half = 0;
        return false;
    }
    half = n / 2;
    return true;
}

/// Passing one straight on, which is what makes `out` compose.
bool ForwardTryHalve(int n, out int half) => TryHalve(n, out half);

/// Four parameters, three of which read as nothing at a call site without
/// names for them.
String DecorateText(String text, int width, bool center, char fill)
{
    var pad = new StringBuilder();
    for (int i = 0; i < width; i++)
        pad.Append(Text.FromChar((char32)fill));
    return (center ? "[" : "<") + text + pad.ToText() + (center ? "]" : ">");
}

void ShowCalls()
{
    PrintHeading("7.1 and 7.2 how a function is called");

    // Overloads, resolved on the arguments.
    PrintValue("overload int", RenderValue(3));
    PrintValue("overload double", RenderValue(3.5));
    PrintValue("overload String", RenderValue("three"));

    // `ref`: the caller's own storage, and the word is written at both ends so
    // that a call that can change its argument says so where it is read.
    int counter = 21;
    DoubleInPlace(ref counter);
    PrintValue("ref", (long)counter);

    // `in`: the address, and no way to write through it. It is not written at
    // the call, because a promise not to change anything needs no warning --
    // where `ref` is, so that a line that may come back changed says so.
    Point point;
    point.X = 3.0;
    point.Y = 4.0;
    PrintValue("in", SumCoordinates(point));

    // `out`: the answer beside the answer.
    int half = 0;
    PrintValue("out, taken", TryHalve(84, out half) ? $"yes {half}" : "no");
    PrintValue("out, refused", TryHalve(7, out half) ? $"yes {half}" : $"no {half}");
    ForwardTryHalve(100, out half);
    PrintValue("out, passed on", (long)half);

    // Named arguments, which may be given in any order once the positional
    // ones are done -- and are matched to parameters by name rather than by
    // where they sit.
    PrintValue("positional", DecorateText("x", 3, true, '.'));
    PrintValue("named", DecorateText(text: "x", width: 3, center: true, fill: '.'));
    PrintValue("reordered", DecorateText("x", center: false, fill: '-', width: 5));
}

// ==================================================================== §4

void ShowGenerics()
{
    PrintHeading("4. generics");

    // Monomorphization: `T` is substituted and the body compiled again, so
    // there is no boxing, no type erasure and no shared code.
    // §4.4: type arguments are inferred and never written at a call, `<` in
    // expression position being ambiguous with less-than.
    PrintValue("over int", (long)ChooseLarger(3, 9));
    PrintValue("over String", ChooseLarger("alpha", "beta"));
    PrintValue("over long", (long)ChooseLarger(2L, 7L));

    // A generic type, whose operators are instantiated with it.
    var a = CreateBox(3);
    var b = CreateBox(4);
    PrintValue("generic operator", (long)(a + b).Value);
    PrintValue("generic equality", a == CreateBox(3));
    PrintValue("generic method", a.PairWith("text"));

    // Two type parameters bound at different times, and an instantiation held
    // inside another.
    var cell = new Cell<Box<int>>(a);
    PrintValue("nested instantiation", (long)cell.Held.Value);

    // A constraint is what lets the body call something. Two at once is the
    // shape `Dictionary` needs of a key.
    int[] numbers = [3, 1, 4, 1, 5];
    PrintValue("constrained", (long)ComputeDigest(numbers));

    // §2.14 again, now generic: a closure over a type parameter is what the
    // standard library's whole combinator surface is built on.
    Keeps<int> odd = n => n % 2 != 0;
    Turns<int, String> show = n => $"<{n}>";
    PrintValue("generic closure", odd(3));
    PrintValue("generic transform", show(9));
}

// ==================================================================== §5

void ShowLibrary()
{
    PrintHeading("5. the standard library");

    // ------------------------------------------------------------ containers
    var list = new List<String>();
    list.Add("gamma");
    list.Add("alpha");
    list.Add("beta");
    PrintValue("List", $"{list.Count} items, first {list[0u]}");

    var map = new Dictionary<String, int>();
    map.Set("one", 1);
    map.Set("two", 2);
    PrintValue("Dictionary", (long)map.GetOr("two", -1));
    PrintValue("missing", (long)map.GetOr("three", -1));

    var set = new HashSet<int>();
    set.Add(1);
    set.Add(1);
    set.Add(2);
    PrintValue("HashSet", (long)set.Count);

    var queue = new Queue<int>();
    queue.Enqueue(1);
    queue.Enqueue(2);
    PrintValue("Queue", (long)queue.Dequeue());

    var stack = new Stack<int>();
    stack.Push(1);
    stack.Push(2);
    PrintValue("Stack", (long)stack.Pop());

    var chain = new LinkedList<String>();
    chain.AddLast("tail");
    chain.AddFirst("head");
    PrintValue("LinkedList", (long)chain.Count);

    var sorted = new SortedList<int, String>();
    sorted.Set(2, "two");
    sorted.Set(1, "one");
    PrintValue("SortedList", sorted.ValueAt(0u));

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
    foreach (var n in picked)
        line.Append($"{n} ");
    PrintValue("chained", line.ToText().Trim());

    PrintValue("map / reduce", (long)values.Select(n => n * 2).Aggregate(0, (t, n) => t + n));
    PrintValue("any / all", $"{values.Any(n => n > 8)} {values.All(n => n > 0)}");
    PrintValue("count where", (long)values.CountWhere(n => n == 3));
    PrintValue("find", (long)values.Find(n => n > 4).ValueOr(-1));
    PrintValue("index where", (long)values.IndexWhere(n => n == 9).ValueOr(0u));

    Sort(values);
    PrintValue("sorted", (long)values[0u]);

    // ------------------------------------------------------------ numbers
    PrintValue("Math", $"{Sqrt(16.0)} {Floor(2.7)} {Abs(-3.0)} {Pow(2.0, 10.0)}");
    PrintValue("Pi", Round(Pi * 100.0) / 100.0);

    // Seeded, so the tour prints the same numbers every time it runs.
    var dice = new Random(20260906);
    PrintValue("Random", (long)(dice.NextBelow(6u) + 1u));
    PrintValue("again", (long)(dice.NextBelow(6u) + 1u));

    // ------------------------------------------------------------ the clock
    //
    // A monotonic clock only goes forward, which is the one thing about it a
    // test may assert without printing a time that changes every run.
    var clock = new Clock();
    long spun = 0;
    for (int i = 0; i < 100000; i++)
        spun += i;
    var taken = clock.Elapsed();
    PrintValue("monotonic", taken.Nanoseconds >= 0);
    PrintValue("a duration", Duration.FromSeconds(90).TotalMinutes);

    // ------------------------------------------------------------ the world
    PrintValue("has PATH", Env.Has("PATH") || Env.Has("Path"));
    PrintValue("set and read",
        Env.Set("STAINLESS_TOUR", "yes") ? Env.GetOr("STAINLESS_TOUR", "-") : "-");

    // ------------------------------------------------------------ files
    //
    // Written and read back in a directory this program makes, so what is
    // printed comes from the tour rather than from the machine it ran on.
    var folder = Path.Join(Env.CurrentDirectory(), "tour-scratch");
    var file = Path.Join(folder, "notes.txt");

    PrintValue("made a directory", IO.Describe(Directory.CreateAll(folder)));
    String lines = "one" + GetNewline() + "two" + GetNewline();
    PrintValue("wrote", IO.Describe(File.WriteAllText(file, lines)));

    var read = File.ReadAllLines(file);
    PrintValue("read back", read.Ok ? (long)read.Value.Count : -1);
    PrintValue("size", File.Size(file));
    PrintValue("extension", Path.Extension(file));
    PrintValue("file name", Path.FileName(file));
    PrintValue("without it", Path.WithoutExtension(Path.FileName(file)));
    PrintValue("rooted", Path.IsRooted(file));

    File.Delete(file);
    Directory.Delete(folder);
    PrintValue("cleaned up", !File.Exists(file) && !Directory.Exists(folder));

    // ------------------------------------------------------------ documents
    var document = Json.Parse("{\"name\":\"tour\",\"count\":3,\"on\":true}");
    if (document.Ok)
    {
        var members = MembersOf(document.Value);
        PrintValue("JSON", TextOr(members.Find("name"), "-"));
        PrintValue("JSON number", IntegerOr(members.Find("count"), -1));
        PrintValue("JSON round trip", Json.Write(document.Value));
    }

    var parsed = Xml.Parse("<tour kind=\"sample\"><part>one</part></tour>");
    if (parsed.Ok)
    {
        PrintValue("XML", parsed.Value.Name);
        PrintValue("XML attribute", parsed.Value.Attributes.Find("kind", "-"));
    }

    // ------------------------------------------------------------ text, again
    PrintValue("base64", Convert.ToBase64Text("stainless"));
    PrintValue("hex of 48879", Convert.FromLong(48879, 16u));
}

// ==================================================================== §6

/// One serializer, written once, for any reflected type. `T` is concrete by the
/// time this is compiled, so `typeof(T)` is a constant and every call below is
/// a load from a table in the binary's read-only data.
String DescribeValue<T>(T value)
{
    var type = typeof(T);
    var text = new StringBuilder();

    text.Append("{");
    var first = true;

    for (nuint i = 0u; i < type.FieldCount; i++)
    {
        var field = type.FieldAt(i);
        if (field.Has("Hidden"))
            continue;

        if (!first)
            text.Append(",");
        first = false;

        var name = field.Name;
        if (field.Has("Column"))
            name = field.Get("Column").AsText(0u);

        text.Append(name);
        text.Append("=");

        var raw = (byte*)value;
        if (field.Kind == KindString)
        {
            text.Append(ReadText(raw, field));
        }
        else if (field.Kind == KindBool)
        {
            text.Append(Text.FromBool(ReadBool(raw, field)));
        }
        else if (field.IsFloating)
        {
            text.AppendDouble(ReadDouble(raw, field));
        }
        else if (field.IsInteger)
        {
            text.AppendInteger(ReadInteger(raw, field));
        }
        else
        {
            text.Append("?");
        }
    }

    text.Append("}");
    return text.ToText();
}

void ShowReflection()
{
    PrintHeading("6. attributes and reflection");

    var person = new Person("Ada", 36);
    var type = typeof(Person);

    PrintValue("type name", type.Name);
    PrintValue("fields", (long)type.FieldCount);
    PrintValue("serialized", DescribeValue(person));

    // A field is an offset, so writing one stores bytes.
    var years = type.FindField("Years");
    WriteInteger((byte*)person, years, 37);
    PrintValue("field written", (long)person.Years);

    // A property is a pair of functions, so writing one runs the setter --
    // which is the difference the two tables exist to keep.
    PrintValue("properties", (long)type.PropertyCount);
    var city = type.FindProperty("City");
    PrintValue("can write", city.CanWrite);
    SetText((byte*)person, city, "Lovelace");
    PrintValue("property written", person.City);

    // The annotation travels with the storage.
    PrintValue("attribute", type.FindField("Name").Get("Column").AsText(0u));
    PrintValue("ignored", type.FindField("Internal").Has("Hidden"));

    // And a type may be found by its name, which is what a loader needs.
    PrintValue("by name", FindType("Tour.Types.Person").Exists);
}

// ==================================================================== §8

void ShowInterop()
{
    PrintHeading("8. interoperability");

    // A variadic `extern` -- the only kind there is, a Stainless function
    // never being variadic.
    printf("  %-22s%s %d\n", "printf".ToPointer(), "called with".ToPointer(), 3);

    // A delegate is one function pointer with the C convention, so C both
    // receives one and calls back through it.
    Adjust twice = value => value + 1;
    PrintValue("C called back", (long)c_apply_twice(twice, 10));

    // A struct of plain data crosses by value, laid out as C lays it out.
    PlainPair pair;
    pair.A = 4;
    pair.B = 5;
    PrintValue("struct by value", (long)c_sum_pair(pair));   // C calls tour_triple

    // And the other direction: `export "C"` put this in the export table under
    // exactly that name, which is what the C file called.
    PrintValue("export", (long)tour_triple(7));

    // §8.1: C++, reached by mangling the signature the way the target's own
    // compiler does. Nothing here is `extern "C"`, and there is no shim.
    PrintValue("C++ namespace", area(3.0, 4.0));
    PrintValue("C++ round trip", (long)cpp_round_trip(20));
}

// ==================================================================== §9.2

/// `threadsafe` asserts what no declaration can prove: every operation here
/// goes through an atomic, so sharing one really is sound. Without the word the
/// `spawn` below still compiles, and warns.
threadsafe class Tally
{
    AtomicLong _total;

    public Tally(AtomicLong cell) => _total = cell;

    public void Add(long amount) => _total.Add(amount);
}

int SquareValue(int value) => value * value;

long SumRange(int[] values, int from, int upto)
{
    long total = 0;
    for (int i = from; i < upto; i++)
        total += values[i];
    return total;
}

void ShowConcurrency()
{
    PrintHeading("9.2 parallel, spawn, and what may be shared");

    var values = new int[100];
    for (int i = 0; i < 100; i++)
        values[i] = i;

    // Two halves, each writing into a local the parent still owns. The join at
    // the closing brace is what makes that sound.
    long left = 0;
    long right = 0;

    parallel
    {
        left = spawn SumRange(values, 0, 50);
        right = spawn SumRange(values, 50, 100);
    }

    PrintValue("parallel", left + right);

    // One job per iteration: sharing one argument block would give every job
    // the last iteration's values.
    var squares = new int[8];
    parallel
    {
        for (int i = 0; i < 8; i++)
        {
            squares[i] = spawn SquareValue(values[i]);
        }
    }
    PrintValue("spawn in a loop", (long)(squares[3] + squares[7]));

    // `for parallel` is the same thing said once: the body runs for every
    // index, and nothing it writes may be read by another iteration.
    var doubled = new int[16];
    for parallel (int i = 0; i < 16; i++)
    {
        doubled[i] = values[i] * 2;
    }
    PrintValue("for parallel", (long)doubled[15]);

    // A mutex owns what it guards, so there is no way to read the value
    // without holding the lock.
    var guarded = new Mutex<long>(0);
    var counter = new AtomicLong(0);
    var tally = new Tally(counter);

    parallel
    {
        spawn ContributeToBoth(tally, guarded, 10);
        spawn ContributeToBoth(tally, guarded, 32);
    }

    PrintValue("atomic", counter.Load());
    PrintValue("mutex", guarded.Lock().Value);

    // A queue that several threads may hold at once.
    var pending = new ConcurrentQueue<long>();
    parallel
    {
        spawn pending.Enqueue(1);
        spawn pending.Enqueue(2);
    }
    PrintValue("concurrent queue", (long)pending.Count);

    // A thread of its own, for work no closing brace brackets. It takes a
    // closure, and a closure captures by value -- so there is no frame here
    // for it to outlive.
    var ticks = new AtomicLong(0);
    var worker = new Thread(() => ticks.Add(7));
    worker.Join();
    PrintValue("thread", ticks.Load());

    // A future is the same idea with a result. `Get` blocks, which is what
    // having real threads buys: no `async`, no state machine, and nothing in
    // any signature changes colour.
    var later = new Future<long>(() => SumRange(values, 0, 100));
    PrintValue("future", later.Get());
}

/// A newline, written as an escape rather than embedded, so the file the tour
/// writes is the same on both platforms.
String GetNewline() => Text.FromChar((char32)10);

void ContributeToBoth(Tally tally, Mutex<long> guarded, long amount)
{
    tally.Add(amount);
    var guard = guarded.Lock();
    guard.Set(guard.Value + amount);
}
