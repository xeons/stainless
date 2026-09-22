// SPDX-License-Identifier: 0BSD
//
//   stainless run samples/tour
//
// A program that uses every feature of the language, in the order the
// specification introduces them. Each section prints what it did, so running it
// is a check that the tour is still true rather than only that it still builds.
//
// Sections 1, 2, 3 and 9 are here: modules, types, text, and the statements and
// expressions that drive them. Sections 4 to 8 -- generics, the standard
// library, reflection, the call forms and interoperability -- are in Library.sl,
// which declares this same module.
//
// What is deliberately not here, and why:
//
//   - COM (§8.5) and the platform bindings, which need Windows and a registered
//     object; `tests/cases/win32-com` is where those live.
//   - Building a shared library (§8.2), which is a different command rather
//     than a different program.
//   - The error cases. Every rule this file relies on has an `err-` case in
//     `tests/cases`, because a program that does not compile prints nothing.
#define TOUR_BUILD

module Tour;

import Standard.Collections;
import Standard.Console;
import Standard.Convert;
import Standard.Encoding;
import Tour.Platform;
import Tour.Types;

// ==================================================================== §9.3

/// A `const` is a value, folded where it is used. It may be an integer, a
/// bool, a char, a double or an enum.
const int Width = 11;
const double Half = 0.5;

/// A `static` is storage, initialized before `Main` in dependency order rather
/// than in the order written -- so `Total` may name `Doubled` above it.
static readonly int Total = Doubled + 1;
static readonly int Doubled = Width * 2;

/// And a mutable one, which is what a counter needs.
static int Steps = 0;

// ------------------------------------------------------------------ helpers

void PrintHeading(String name)
{
    Console.WriteLine("");
    Console.WriteLine("== " + name + " " + "=".Repeat(60u - name.ByteLength()));
}

void PrintValue(String label, String value)
{
    Console.WriteLine("  " + label.PadRight(22u) + value);
}

void PrintValue(String label, long value) => PrintValue(label, Text.FromInteger(value));
void PrintValue(String label, bool value) => PrintValue(label, Text.FromBool(value));
void PrintValue(String label, double value) => PrintValue(label, Text.FromDouble(value));

// ==================================================================== §1

void ShowModules()
{
    PrintHeading("1. modules");

    // A module is reached by the last segment of its name, so `Tour.Platform`
    // is `Platform` at a use site -- and an imported name needs no prefix at
    // all when it is unambiguous.
    PrintValue("platform", GetPlatformFamily());
    PrintValue("qualified", Tour.Platform.GetPlatformFamily());
    PrintValue("not compiled", GetMood());

    // §1.5: two aliases over two undeclared types are two types, and passing
    // one where the other belongs is caught at compile time for nothing at
    // run time.
    Slot slot = MakeSlot(7u);
    Cursor cursor = MakeCursor(3u);
    PrintValue("slot", (long)GetSlotNumber(slot));
    PrintValue("check", (long)CheckHandles(slot, cursor));
    PrintValue("check(null)", (long)CheckHandles(null, cursor));

    // A weak alias converts nothing, because there is nothing to convert: a
    // `Status` is an `int` and an `int` is a `Status`.
    Status status = Fine;
    int plain = status;
    PrintValue("weak alias", (long)plain);

    // §10: a symbol this file defined for itself.
#if TOUR_BUILD
    PrintValue("#define", "TOUR_BUILD is on");
#endif
}

// ==================================================================== §2.1

void ShowPrimitives()
{
    PrintHeading("2.1 primitives");

    bool yes  = true;
    byte b    = 200;              // a literal converts to what can hold it
    sbyte sb   = (sbyte)-100;    // a *negative* literal is an expression
    short s    = (short)-30000;  // rather than a literal, so it needs a cast
    ushort us   = 60000;
    int i    = -2000000000;
    uint ui   = 4000000000u;
    long l    = -9000000000000000000;
    ulong ul   = 18000000000000000000u;
    nint ni   = -42;              // pointer-wide
    nuint nu   = 42u;
    float f    = (float)1.5;     // there is no float literal suffix
    double d    = 2.25;

    PrintValue("bool", yes);
    PrintValue("byte / sbyte", $"{b} {sb}");
    PrintValue("short / ushort", $"{s} {us}");
    PrintValue("int / uint", $"{i} {ui}");
    PrintValue("long / ulong", $"{l} {ul}");
    PrintValue("nint / nuint", $"{ni} {nu}");
    PrintValue("float / double", $"{(double)f} {d}");

    // §2.1: three code-unit types, one scalar literal. Which type a character
    // literal becomes is decided by what holds it in a single unit.
    char ascii    = 'A';          // U+0041, one UTF-8 byte
    char16 accented = 'é';     // one UTF-16 unit, two UTF-8 bytes
    char32 emoji    = '\U0001F600'; // one of anything, and only that
    char tab      = '\t';

    PrintValue("char", (long)ascii);
    PrintValue("char16", (long)accented);
    PrintValue("char32", (long)emoji);
    PrintValue("escape", (long)tab);

    // Widening is implicit, narrowing needs a cast, and there is no implicit
    // conversion to bool at all.
    long widened = i;
    byte narrowed = (byte)us;
    PrintValue("widened", widened);
    PrintValue("narrowed", (long)narrowed);
}

// ==================================================================== §2.2

void ShowValues()
{
    PrintHeading("2.2 structs, and what may be asked about one");

    // A struct is a value. There is no constructor: every field starts zeroed.
    Point a;
    a.X = 3.0;
    a.Y = 4.0;

    Point copy = a;                 // a copy, not a second name
    copy.X = 30.0;

    PrintValue("a", $"({a.X}, {a.Y})");
    PrintValue("copy", $"({copy.X}, {copy.Y})");
    Point origin;
    PrintValue("method", a.MeasureDistanceSquaredTo(origin));

    // §2.2: a struct may hold a reference, and then copying retains and
    // dropping releases -- which is what lets a value type own something.
    Labelled held;
    held.Name = "owned by a value";
    held.Weight = 3;
    Labelled second = held;
    PrintValue("struct holding", $"{second.Name} {second.Weight}");

    // §8: the three questions a binding has to be able to ask about itself.
    PrintValue("sizeof(Point)", (long)sizeof(Point));
    PrintValue("alignof(Point)", (long)alignof(Point));
    PrintValue("offsetof(Point.Y)", (long)offsetof(Point, Y));
    PrintValue("sizeof(Squeezed)", (long)sizeof(Squeezed));   // [Packed]: 9, not 16
    PrintValue("sizeof(Wide)", (long)sizeof(Wide));           // [Align(16)]
    PrintValue("sizeof(Matrix)", (long)sizeof(Matrix));       // an inline double[4]

    // An inline array is storage rather than a reference, so it is written
    // through the struct that holds it.
    Matrix m;
    for (nuint k = 0u; k < m.Cell.Length; k++)
        m.Cell[k] = (double)k * Half;
    PrintValue("matrix", $"{m.Cell[0u]} {m.Cell[1u]} {m.Cell[2u]} {m.Cell[3u]}");

    // Bit-fields lay out as the target's C ABI lays them out -- which differs
    // between Windows and Linux, so this reads and writes rather than printing
    // a size.
    Packet packet;
    packet.Kind = 5u;
    packet.Level = 17u;
    packet.Rest = 1000000u;
    packet.Level--;
    PrintValue("bit-fields", $"{packet.Kind} {packet.Level} {packet.Rest}");

    // §2.7: every member at offset zero, and a nameless struct inside a union.
    Word word;
    word.Signed = -1;
    PrintValue("union", $"{word.Signed} {word.Unsigned}");

    LargeInteger big;
    big.Quad = 0;
    big.Low = 4294967295u;
    big.High = 1;
    PrintValue("anonymous member", big.Quad);
}

// ==================================================================== §2.5

void ShowPointers()
{
    PrintHeading("2.5 pointers, and the absence of a value");

    int number = 5;
    int* at = &number;
    *at = 6;
    PrintValue("through a pointer", (long)number);

    Point p;
    p.X = 1.0;
    p.Y = 2.0;
    Point* q = &p;
    q->X = 10.0;                    // C's arrow, for a pointer to a struct
    PrintValue("arrow", $"({p.X}, {p.Y})");

    void* anything = (void*)at;
    PrintValue("void*", (long)(nuint)anything != 0 ? "not null" : "null");

    // A class reference is not null unless its type says so, and a `T?` is
    // narrowed by the test rather than by an assertion.
    Loud? maybe = null;
    PrintValue("null", maybe == null);

    maybe = new Loud("optional");
    if (maybe != null)
    {
        PrintValue("narrowed", maybe.Label);   // a `Loud` here, not a `Loud?`
    }

    // §9.5.1: `?.` reaches through, `??` says what to do instead, and `??=`
    // fills a slot only if it is empty. The receiver is read once.
    // `Label` is a `String`, which has no null of its own to stand for "there
    // was no receiver" -- so the `??` is not optional here, and that is
    // SL0605 rather than a silently nullable answer.
    Loud? nothing = null;
    PrintValue("?.", nothing?.Label ?? "there was nobody");
    PrintValue("?. present", maybe?.Label ?? "-");

    String? filled = null;
    filled ??= "filled in";
    filled ??= "not this one";
    PrintValue("??=", filled ?? "-");
}

// ==================================================================== §2.6

String FormatArea(Shape shape)
{
    // A `switch` over a variant is exhaustive: leaving a case out is an error
    // rather than a fall-through to nothing.
    switch (shape)
    {
        case Circle c: return Text.FromDouble(3.0 * c.Radius * c.Radius);
        case Rect r:   return Text.FromDouble(r.Width * r.Height);
        case Empty:    return "0";
    }
}

int CountLeaves(Tree<int> tree)
{
    switch (tree)
    {
        case Leaf:    return 1;
        case Node n:  return CountLeaves(n.Pair.Left) + CountLeaves(n.Pair.Right);
        case Nothing: return 0;
    }
}

void ShowVariants()
{
    PrintHeading("2.6 variants");

    PrintValue("circle", FormatArea(Shape.Circle(2.0)));
    PrintValue("rect", FormatArea(Shape.Rect(3.0, 4.0)));
    PrintValue("empty", FormatArea(Shape.Empty));

    // §2.6: `is` with a name takes the value once and names what came out,
    // which is what a field or a call result needs.
    Shape shape = Shape.Rect(2.0, 5.0);
    if (shape is Rect r)
        PrintValue("is binding", $"{r.Width}x{r.Height}");
    if (shape is Circle)
        PrintValue("is", "unreachable");

    // A generic variant, holding itself. A case is named without its type
    // arguments, because the type it is being built for is already known --
    // §4.4: type arguments are inferred and never written at a call.
    Tree<int> one = Leaf(1);
    Tree<int> two = Leaf(2);
    Tree<int> three = Leaf(3);
    Tree<int> pair = Node(new Branch<int>(one, two));
    Tree<int> tree = Node(new Branch<int>(pair, three));
    PrintValue("leaves", (long)CountLeaves(tree));

    // `Optional<T>` is a variant in the standard library, and is what a null
    // pointer cannot say: "a value, which may itself be null".
    Optional<String> found = Some("here");
    Optional<String> missing = None;
    PrintValue("optional", found.ValueOr("-") + " / " + missing.ValueOr("-"));
    if (found is Some got)
        PrintValue("optional is", got.Value);
}

// ==================================================================== §2.8

/// A function that can fail says so in its type. `Ok` and `Fail` are decided by
/// the return type rather than by a name in scope.
Result<int, ConvertError> ParseHalf(String text)
{
    // `try` is the early return: on failure it returns `Fail` with the same
    // error, and on success the expression is the value.
    long n = try Convert.ToLong(text);
    if (n % 2 != 0)
        return Fail(ConvertError.Malformed);
    return Ok((int)(n / 2));
}

void ShowResults()
{
    PrintHeading("2.8 Result, and try");

    var good = ParseHalf("84");
    var odd = ParseHalf("7");
    var bad = ParseHalf("nonsense");

    // The two halves are readable only where the compiler has seen which one
    // is there.
    if (good.Ok)
        PrintValue("ok", (long)good.Value);
    if (!odd.Ok)
        PrintValue("odd", (long)odd.Error);
    if (!bad.Ok)
        PrintValue("not a number", (long)bad.Error);

    // A default needs no proof, because it supplies one.
    PrintValue("valueOr", (long)bad.ValueOr(-1));

    // `&&` carries the proof into what it guards.
    var left = ParseHalf("10");
    var right = ParseHalf("20");
    if (left.Ok && right.Ok)
        PrintValue("sum", (long)(left.Value + right.Value));
}

// ==================================================================== §2.10

void ShowContracts()
{
    PrintHeading("2.10 interfaces");

    // A class may implement several, and an interface may extend another.
    IDrawable square = new Square(3.0);
    PrintValue("dispatch", square.DrawAsText());
    PrintValue("inherited", square.Name);        // from INamed, through IDrawable

    Figure figure = new Square(2.0);
    PrintValue("virtual", figure.DrawAsText());          // Polygon's, which calls base's
    PrintValue("area", figure.Area);
    PrintValue("not virtual", (long)figure.Sides);
    PrintValue("property", figure.Tag);

    // `is` and a cast both work on a class, and a failed cast is a refusal
    // rather than a wrong answer.
    PrintValue("is Polygon", figure is Polygon);
    if (figure is Square sq)
        PrintValue("corners", (long)sq.Corners);

    // The delegating constructor, which ran `this(1.0)`.
    var unit = new Square();
    PrintValue("this(...)", unit.Area);
}

// ==================================================================== §2.11

void ShowArrays()
{
    PrintHeading("2.11 arrays, and 2.12 slices");

    // `new T[n]` is a counted heap object, zeroed.
    var numbers = new int[6];
    for (nuint i = 0u; i < numbers.Length; i++)
        numbers[i] = (int)i + 1;
    PrintValue("length", (long)numbers.Length);

    // An array may also be written out, and its element type inferred.
    var few = [10, 20, 30];
    String[] names = ["alpha", "beta", "gamma"];
    PrintValue("literal", $"{few[0u]} {few[1u]} {few[2u]}");
    PrintValue("of Strings", names.Length == 3u ? names[1u] : "?");

    // A fixed array is storage rather than a reference.
    int[3] inline = [7, 8, 9];
    PrintValue("inline", (long)(inline[0u] + inline[1u] + inline[2u]));

    // A slice is a view: it borrows the array, keeps it alive, and writing
    // through one writes the array it came from. Either end may be left out.
    PrintValue("whole", SumValues(numbers));
    PrintValue("[1:4]", SumValues(numbers[1u:4u]));
    PrintValue("[3:]", SumValues(numbers[3u:]));
    PrintValue("[:2]", SumValues(numbers[:2u]));

    FillValues(numbers[4u:], 0);
    PrintValue("written through", SumValues(numbers));

    // §9.4: `foreach` over an array, a slice, and anything with a
    // `GetEnumerator` -- which is a shape rather than an interface.
    long total = 0;
    foreach (var n in numbers)
        total += n;
    foreach (var n in numbers[1u:3u])
        total += n;
    PrintValue("foreach", total);

    long counted = 0;
    foreach (var n in new Countdown(4))
        counted = counted * 10 + n;
    PrintValue("own enumerator", counted);
}

// ==================================================================== tuples

/// Two answers that belong together, and no struct declared for the sake of
/// one function. A tuple *is* a struct, so layout, both ABI classifiers and
/// the walk that retains and releases what a value holds all apply to it with
/// nothing written for tuples.
(int, int) MinMax(int[:] numbers)
{
    int low = numbers[0u];
    int high = numbers[0u];

    foreach (var n in numbers)
    {
        if (n < low)
            low = n;
        if (n > high)
            high = n;
    }

    return (low, high);
}

void ShowTuples()
{
    PrintHeading("2.15 tuples");

    int[] numbers = [5, 3, 9, 1, 8];

    // Deconstruction, which is where a name is wanted: the fields themselves
    // are `Item1` upwards, because a named element would either take part in
    // the type's identity or leave two names for one field.
    var (low, high) = MinMax(numbers);
    PrintValue("deconstructed", $"{low}..{high}");

    // The type written out, and the fields under their own names.
    (int, String) labelled = (7, "seven");
    PrintValue("by field", $"{labelled.Item1} is {labelled.Item2}");

    // It is structural: `(int, String)` written in two modules is one type,
    // interned by its element types the way a slice is by its element.
    (int, String) same = labelled;
    PrintValue("copied", same.Item2);

    // And it may carry a reference, which is then owned by the tuple.
    (String, String) split = ("front", "back");
    PrintValue("holding references", split.Item1 + "/" + split.Item2);
}

long SumValues(int[:] values)
{
    long total = 0;
    for (nuint i = 0u; i < values.Length; i++)
        total += values[i];
    return total;
}

void FillValues(int[:] values, int with)
{
    for (nuint i = 0u; i < values.Length; i++)
        values[i] = with;
}

// ==================================================================== §2.13

String DescribeAccess(Access mode)
{
    var text = new StringBuilder();
    if (mode.HasFlag(Access.Read))
        text.Append("r");
    if (mode.HasFlag(Access.Write))
        text.Append("w");
    if (mode.HasFlag(Access.Execute))
        text.Append("x");
    if (mode == Access.None)
        text.Append("-");
    return text.ToText();
}

void ShowEnumerations()
{
    PrintHeading("2.13 enums");

    // A distinct type over an integer: it does not convert on its own, and
    // arithmetic on one is refused.
    Level level = Level.Warning;
    PrintValue("value", (long)level);
    PrintValue("one past", (long)Level.Severe);
    PrintValue("named base", (long)sizeof(Level));

    switch (level)
    {
        case Level.Low: PrintValue("switch", "low"); break;
        case Level.Warning: PrintValue("switch", "warning"); break;
        default: PrintValue("switch", "something else"); break;
    }

    // `[Flags]` is what makes the bitwise operators and `HasFlag` legal.
    var mode = Access.Read | Access.Write;
    PrintValue("flags", DescribeAccess(mode));
    PrintValue("with execute", DescribeAccess(mode | Access.Execute));
    PrintValue("without write", DescribeAccess(mode & ~Access.Write));
    PrintValue("none", DescribeAccess(Access.None));
}

// ==================================================================== §2.14

int AddIntegers(int a, int b) => a + b;
int MultiplyIntegers(int a, int b) => a * b;

void ShowFunctions()
{
    PrintHeading("2.14 delegates, closures and lambdas");

    // A delegate is one function pointer: it holds a function, not an object.
    Combine how = AddIntegers;
    PrintValue("delegate", (long)how(3, 4));
    how = MultiplyIntegers;
    PrintValue("reassigned", (long)how(3, 4));

    // A lambda that captures nothing is still one, so it may be a delegate.
    Combine written = (a, b) => a - b;
    PrintValue("lambda", (long)written(10, 4));

    // A closure is a method and the object it belongs to. A lambda that
    // captures becomes one, and so does a method named on an instance.
    //
    // **Capture is by value, taken when the closure is made** -- C++'s `[=]`
    // and Rust's `move`, not C#'s capture by reference. It costs a copy and
    // buys the thing that matters: a closure may outlive the scope that built
    // it with no lifetime question to answer.
    int factor = 3;
    Turns<int, int> scale = value => value * factor;
    factor = 100;
    PrintValue("captured by value", (long)scale(7));   // still 21, not 700

    // What was copied may itself be a reference, and then the one object is
    // shared -- which is the same rule, not an exception to it.
    var control = new Control("bound");
    Notify move = control.MoveBy;      // a method, and the object it is on
    move(4);
    move(6);
    PrintValue("bound method", (long)control.Left);

    // So a closure outlives the scope that made it, holding what it captured.
    var later = CreateAdder(100);
    PrintValue("escaped", (long)later(5));

    // A lambda written in a method reaches its object: a field, a property,
    // `this`, and a method called with no receiver all resolve.
    var scaler = new Scaler(6);
    PrintValue("over a field", (long)scaler.CreateFieldScaler()(7));
    PrintValue("over a method", (long)scaler.CreateMethodScaler()(7));

    ShowEvents();
}

// ================================================================== §2.14.2

/// Counts what an event told it, so subscribing can be seen to have worked.
class Watcher
{
    public int Seen;
    public int Last;

    public Watcher()
    {
        Seen = 0;
        Last = 0;
    }

    public void OnMoved(int at)
    {
        Seen = Seen + 1;
        Last = at;
    }
}

void ShowEvents()
{
    PrintHeading("2.14.2 events");

    var control = new Control("watched");
    var first = new Watcher();
    var second = new Watcher();

    // Nobody has subscribed, so raising it inside MoveBy does nothing. There is
    // no null to trip over: a declared event always has a list, sometimes empty.
    control.MoveBy(1);
    PrintValue("no subscribers", (long)first.Seen);

    control.Moved += first.OnMoved;
    control.Moved += second.OnMoved;
    control.MoveBy(1);
    PrintValue("both ran", (long)(first.Seen + second.Seen));
    PrintValue("in order, same value", first.Last == second.Last);

    // Removal is by closure equality -- the same method *and* the same object --
    // so this takes the first one off and leaves the second.
    control.Moved -= first.OnMoved;
    control.MoveBy(1);
    PrintValue("one left", (long)second.Seen);
    PrintValue("the other stopped", (long)first.Seen);

    // A lambda is a closure, so it subscribes like anything else.
    control.Moved += (at) => { PrintValue("a lambda subscribed", (long)at); };
    control.MoveBy(1);

    // Unsubscribing something that was never subscribed does nothing, which is
    // what lets a tidy-up run twice.
    control.Moved -= first.OnMoved;
    PrintValue("absent removal", true);
}

/// A lambda written inside a class, which is where `this` can be reached.
class Scaler
{
    public int Factor;

    public Scaler(int factor) => Factor = factor;

    int TripleValue(int n) => n * 3;

    /// A member read is captured as a value, so this copies what `Factor` said
    /// when the closure was made.
    public Turns<int, int> CreateFieldScaler() => value => value * Factor;

    /// A call captures the object, because the call needs one -- and that is
    /// what makes an object holding its own closure a cycle to break.
    public Turns<int, int> CreateMethodScaler() => value => TripleValue(value);
}

/// Returns a closure over its own parameter, which is what makes the capture
/// a heap object rather than a stack slot.
Turns<int, int> CreateAdder(int by)
{
    return value => value + by;
}

// ==================================================================== §2.4

void ShowReferences()
{
    PrintHeading("2.4 classes, and what owns what");

    // ARC: the count is the scope. Both of these are released at the closing
    // brace, in reverse order.
    {
        var first = new Loud("first");
        var second = new Loud("second");
        PrintValue("made", first.Label + " and " + second.Label);
    }
    PrintValue("scope left", "both gone");

    // A cycle needs one weak end, or neither is ever released.
    {
        var parent = new Parent(1);
        var child = new Child(2);
        parent.Kid = child;         // strong down
        child.Owner = parent;       // weak back up

        // A field may be a different value by the time it is read, and a weak
        // one may have died between the check and the use -- so both are read
        // into a local first, and the local is what the check is about.
        Child? kid = parent.Kid;
        Parent? owner = child.Owner;
        if (kid != null && owner != null)
            PrintValue("linked", (long)(kid.Id + owner.Id));
    }

    // A weak reference reads back as null once what it named is gone, rather
    // than as a pointer into freed memory.
    var orphan = new Child(3);
    {
        var owner = new Parent(4);
        orphan.Owner = owner;
        Parent? alive = orphan.Owner;
        PrintValue("while alive", alive != null);
    }
    Parent? gone = orphan.Owner;
    PrintValue("after", gone != null);
}

// ==================================================================== §3

void ShowText()
{
    PrintHeading("3. text");

    // A String is UTF-8, counted, and immutable. A literal is one interned
    // object however often it is written.
    String greeting = "hello";
    PrintValue("length in bytes", (long)greeting.ByteLength());
    PrintValue("byte at", (long)greeting.ByteAt(1u));
    PrintValue("substring", greeting.Substring(1u, 3u));
    PrintValue("upper", greeting.ToUpperAscii());
    PrintValue("padded", "[" + greeting.PadLeft(8u) + "]");
    PrintValue("replaced", greeting.Replace("l", "L"));
    PrintValue("compare", (long)greeting.CompareTo("hellp"));
    PrintValue("contains", greeting.Contains("ell"));
    PrintValue("index of", greeting.IndexOf("l"));

    // Escapes, and the two that are not one character.
    PrintValue("escapes", "tab[\t] quote[\"] backslash[\\] newline is next");

    // Splitting and joining.
    var parts = "a,b,c".Split(",");
    PrintValue("split", $"{parts.Length} parts, second is {parts[1u]}");
    PrintValue("joined", "-".Join(parts));

    // §3.5: one allocation that grows, for text built a piece at a time.
    var builder = new StringBuilder();
    for (int i = 0; i < 4; i++)
    {
        builder.Append(Text.FromInteger((long)i));
        builder.Append(";");
    }
    PrintValue("builder", builder.ToText());

    // §3.8: interpolation. The whole thing is joined in one allocation, where
    // the chain of `+` it replaces allocated once per operator.
    int clicks = 7;
    double ratio = 0.25;
    bool on = true;
    PrintValue("interpolated", $"{greeting}: {clicks} at {ratio}, on={on}");
    PrintValue("braces", $"{{literal}} and {clicks}");
    PrintValue("empty", $"[{""}]");

    // §3.7: the conversions the interpolation is sugar over.
    PrintValue("from integer", Text.FromInteger(-42));
    PrintValue("from double", Text.FromDouble(1.5));
    PrintValue("from bool", Text.FromBool(false));
    PrintValue("from char", Text.FromChar('A'));
    PrintValue("to hex", Convert.FromLong(255, 16u));
    PrintValue("parsed", (long)Convert.ToLong("123").ValueOr(-1));

    // §3.4: UTF-16, for the platform APIs that want it. A `Utf16String` is a
    // second representation rather than a second string type: it converts on
    // the way out and on the way back.
    var wide = "hello".ToUtf16();
    PrintValue("utf-16 units", (long)wide.UnitCount());
    PrintValue("back again", wide.ToText());
    PrintValue("from a buffer", Text.FromUtf16(wide.ToPointer(), wide.UnitCount()));

    // §3.6: other encodings, behind an interface, so what a file was written
    // in is a value rather than a branch.
    var latin = Encoding.Latin1();
    var bytes = latin.GetBytes("café");
    PrintValue("latin-1 bytes", (long)bytes.Length);
    PrintValue("decoded", latin.GetString(bytes));

    // §3.3: reaching C. `ToPointer` is a null-terminated view of the same
    // bytes rather than a copy.
    printf("  %-22s%s\n", "to a C pointer".ToPointer(), greeting.ToPointer());
    PrintValue("strlen agrees", (long)strlen(greeting.ToPointer()));
}

// ==================================================================== §9

void ShowStatements()
{
    PrintHeading("9. statements and expressions");

    // `if`, and a condition that must be `bool`.
    int n = 7;
    if (n > 5)
    {
        PrintValue("if", "greater");
    }
    else
    {
        PrintValue("if", "not greater");
    }

    // The conditional, which evaluates only the arm it selects.
    PrintValue("ternary", n > 5 ? "yes" : "no");
    PrintValue("chained", n < 0 ? "negative" : n == 0 ? "zero" : "positive");

    // `for`, with `break` and `continue`.
    int total = 0;
    for (int i = 0; i < 10; i++)
    {
        if (i == 3)
            continue;
        if (i == 8)
            break;
        total += i;
    }
    PrintValue("for", (long)total);

    // `while`, and §9.7 `do`, which runs its body before it asks.
    int j = 0;
    while (j < 5)
        j += 2;
    PrintValue("while", (long)j);

    int tries = 0;
    do { tries++; } while (tries < 3);
    PrintValue("do while", (long)tries);

    int never = 0;
    do { never++; } while (false);
    PrintValue("do at least once", (long)never);

    // §9.6: every assignment operator, and stepping by one either way.
    int value = 10;
    value += 5;  value -= 3;  value *= 2;  value /= 4;  value %= 5;
    value <<= 3; value >>= 1; value |= 1;  value &= 14; value ^= 3;
    PrintValue("compound", (long)value);

    int step = 0;
    step++;
    ++step;
    PrintValue("postfix then prefix", (long)(step++ + ++step));
    step--;
    --step;
    PrintValue("and back", (long)step);

    // §9.1: `switch` over an integer, with stacked labels and a `default`.
    // There is no fall-through: every arm ends.
    String said = "";
    switch (n)
    {
        case 1:
        case 2: said = "small"; break;
        case 7: said = "seven"; break;
        default: said = "other"; break;
    }
    PrintValue("switch", said);

    // Over a String, which C# allows and C does not.
    switch (said)
    {
        case "seven": PrintValue("switch on text", "matched"); break;
        default: PrintValue("switch on text", "missed"); break;
    }

    // §9.8: `goto`, and a label, which may only sit at the top level of a
    // function so that what a jump releases is one answer.
    int found = -1;
    for (int a = 1; a < 10; a++)
    {
        for (int b = 1; b < 10; b++)
        {
            if (a * b == 42)
            {
                found = a * 10 + b;
                goto done;
            }
        }
    }

done:
    PrintValue("goto", (long)found);

    // §9.9: `nameof`, which is the name as written, checked to exist.
    PrintValue("nameof local", nameof(value));
    PrintValue("nameof function", nameof(ShowStatements));
    PrintValue("nameof type", nameof(Money));

    // §9.10: `checked`, which asks `+`, `-` and `*` to notice rather than
    // wrap. `unchecked` is the default and says so where it matters.
    int room = checked(2000000 + 2000000);
    PrintValue("checked", (long)room);

    checked
    {
        PrintValue("checked block", (long)(1000 * 1000));
    }

    unchecked
    {
        int wrapped = 2147483647;
        wrapped = wrapped + 1;      // defined: it wraps, as C# does
        PrintValue("wrapped", (long)wrapped);
    }

    // §9.6.1: the value a type's storage holds before anything is put in it.
    PrintValue("default(int)", (long)default(int));
    PrintValue("default(bool)", default(bool));
    Point origin = default(Point);
    PrintValue("default(Point)", $"({origin.X}, {origin.Y})");

    // §9.3: a const is folded, a static is storage, and both were settled
    // before this line ran.
    Steps++;
    PrintValue("const / static", $"{Width} {Doubled} {Total} {Steps}");

    // A block is a scope, and an inner name may shadow nothing: a redeclared
    // local is an error, so this one is genuinely new.
    {
        int inner = 3;
        PrintValue("block", (long)inner);
    }

    // The right operand of `&&` and `||` does not run when the left already
    // decides the answer -- which is the only reason `d != 0 && 100 / d > 1`
    // is safe to write.
    int d = 0;
    PrintValue("short circuit", d != 0 && 100 / d > 1);
    PrintValue("or", d == 0 || 100 / d > 1);
}

// ==================================================================== main

int Main(String[] args)
{
    Console.WriteLine("A tour of Stainless, in " + GetPlatformFamily() + " form.");
    PrintValue("arguments", (long)args.Length);

    ShowModules();
    ShowPrimitives();
    ShowValues();
    ShowPointers();
    ShowVariants();
    ShowResults();
    ShowContracts();
    ShowArrays();
    ShowEnumerations();
    ShowTuples();
    ShowFunctions();
    ShowReferences();
    ShowText();
    ShowStatements();

    // The rest of the tour, in Library.sl.
    ShowMembers();
    ShowCalls();
    ShowGenerics();
    ShowLibrary();
    ShowReflection();
    ShowInterop();
    ShowConcurrency();

    Console.WriteLine("");
    Console.WriteLine("Done.");
    return 0;
}
