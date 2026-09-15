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

void Heading(String name)
{
    Console.WriteLine("");
    Console.WriteLine("== " + name + " " + "=".Repeat(60u - name.ByteLength()));
}

void Say(String label, String value)
{
    Console.WriteLine("  " + label.PadRight(22u) + value);
}

void Say(String label, long value) => Say(label, Text.FromInteger(value));
void Say(String label, bool value) => Say(label, Text.FromBool(value));
void Say(String label, double value) => Say(label, Text.FromDouble(value));

// ==================================================================== §1

void Modules()
{
    Heading("1. modules");

    // A module is reached by the last segment of its name, so `Tour.Platform`
    // is `Platform` at a use site -- and an imported name needs no prefix at
    // all when it is unambiguous.
    Say("platform", Family());
    Say("qualified", Tour.Platform.Family());
    Say("not compiled", Mood());

    // §1.5: two aliases over two undeclared types are two types, and passing
    // one where the other belongs is caught at compile time for nothing at
    // run time.
    Slot slot = SlotAt(7u);
    Cursor cursor = CursorAt(3u);
    Say("slot", (long)NumberOf(slot));
    Say("check", (long)Check(slot, cursor));
    Say("check(null)", (long)Check(null, cursor));

    // A weak alias converts nothing, because there is nothing to convert: a
    // `Status` is an `int` and an `int` is a `Status`.
    Status status = Fine;
    int plain = status;
    Say("weak alias", (long)plain);

    // §10: a symbol this file defined for itself.
#if TOUR_BUILD
    Say("#define", "TOUR_BUILD is on");
#endif
}

// ==================================================================== §2.1

void Primitives()
{
    Heading("2.1 primitives");

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

    Say("bool", yes);
    Say("byte / sbyte", $"{b} {sb}");
    Say("short / ushort", $"{s} {us}");
    Say("int / uint", $"{i} {ui}");
    Say("long / ulong", $"{l} {ul}");
    Say("nint / nuint", $"{ni} {nu}");
    Say("float / double", $"{(double)f} {d}");

    // §2.1: three code-unit types, one scalar literal. Which type a character
    // literal becomes is decided by what holds it in a single unit.
    char ascii    = 'A';          // U+0041, one UTF-8 byte
    char16 accented = 'é';     // one UTF-16 unit, two UTF-8 bytes
    char32 emoji    = '\U0001F600'; // one of anything, and only that
    char tab      = '\t';

    Say("char", (long)ascii);
    Say("char16", (long)accented);
    Say("char32", (long)emoji);
    Say("escape", (long)tab);

    // Widening is implicit, narrowing needs a cast, and there is no implicit
    // conversion to bool at all.
    long widened = i;
    byte narrowed = (byte)us;
    Say("widened", widened);
    Say("narrowed", (long)narrowed);
}

// ==================================================================== §2.2

void Values()
{
    Heading("2.2 structs, and what may be asked about one");

    // A struct is a value. There is no constructor: every field starts zeroed.
    Point a;
    a.X = 3.0;
    a.Y = 4.0;

    Point copy = a;                 // a copy, not a second name
    copy.X = 30.0;

    Say("a", $"({a.X}, {a.Y})");
    Say("copy", $"({copy.X}, {copy.Y})");
    Say("method", a.LengthSquared());

    // §2.2: a struct may hold a reference, and then copying retains and
    // dropping releases -- which is what lets a value type own something.
    Labelled held;
    held.Name = "owned by a value";
    held.Weight = 3;
    Labelled second = held;
    Say("struct holding", $"{second.Name} {second.Weight}");

    // §8: the three questions a binding has to be able to ask about itself.
    Say("sizeof(Point)", (long)sizeof(Point));
    Say("alignof(Point)", (long)alignof(Point));
    Say("offsetof(Point.Y)", (long)offsetof(Point, Y));
    Say("sizeof(Squeezed)", (long)sizeof(Squeezed));   // [Packed]: 9, not 16
    Say("sizeof(Wide)", (long)sizeof(Wide));           // [Align(16)]
    Say("sizeof(Matrix)", (long)sizeof(Matrix));       // an inline double[4]

    // An inline array is storage rather than a reference, so it is written
    // through the struct that holds it.
    Matrix m;
    for (nuint k = 0u; k < m.Cell.Length; k++)
        m.Cell[k] = (double)k * Half;
    Say("matrix", $"{m.Cell[0u]} {m.Cell[1u]} {m.Cell[2u]} {m.Cell[3u]}");

    // Bit-fields lay out as the target's C ABI lays them out -- which differs
    // between Windows and Linux, so this reads and writes rather than printing
    // a size.
    Packet packet;
    packet.Kind = 5u;
    packet.Level = 17u;
    packet.Rest = 1000000u;
    packet.Level--;
    Say("bit-fields", $"{packet.Kind} {packet.Level} {packet.Rest}");

    // §2.7: every member at offset zero, and a nameless struct inside a union.
    Word word;
    word.Signed = -1;
    Say("union", $"{word.Signed} {word.Unsigned}");

    LargeInteger big;
    big.Quad = 0;
    big.Low = 4294967295u;
    big.High = 1;
    Say("anonymous member", big.Quad);
}

// ==================================================================== §2.5

void Pointers()
{
    Heading("2.5 pointers, and the absence of a value");

    int number = 5;
    int* at = &number;
    *at = 6;
    Say("through a pointer", (long)number);

    Point p;
    p.X = 1.0;
    p.Y = 2.0;
    Point* q = &p;
    q->X = 10.0;                    // C's arrow, for a pointer to a struct
    Say("arrow", $"({p.X}, {p.Y})");

    void* anything = (void*)at;
    Say("void*", (long)(nuint)anything != 0 ? "not null" : "null");

    // A class reference is not null unless its type says so, and a `T?` is
    // narrowed by the test rather than by an assertion.
    Loud? maybe = null;
    Say("null", maybe == null);

    maybe = new Loud("optional");
    if (maybe != null)
    {
        Say("narrowed", maybe.Label);   // a `Loud` here, not a `Loud?`
    }

    // §9.5.1: `?.` reaches through, `??` says what to do instead, and `??=`
    // fills a slot only if it is empty. The receiver is read once.
    // `Label` is a `String`, which has no null of its own to stand for "there
    // was no receiver" -- so the `??` is not optional here, and that is
    // SL0605 rather than a silently nullable answer.
    Loud? nothing = null;
    Say("?.", nothing?.Label ?? "there was nobody");
    Say("?. present", maybe?.Label ?? "-");

    String? filled = null;
    filled ??= "filled in";
    filled ??= "not this one";
    Say("??=", filled ?? "-");
}

// ==================================================================== §2.6

String Area(Shape shape)
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

int Leaves(Tree<int> tree)
{
    switch (tree)
    {
        case Leaf:    return 1;
        case Node n:  return Leaves(n.Pair.Left) + Leaves(n.Pair.Right);
        case Nothing: return 0;
    }
}

void Variants()
{
    Heading("2.6 variants");

    Say("circle", Area(Shape.Circle(2.0)));
    Say("rect", Area(Shape.Rect(3.0, 4.0)));
    Say("empty", Area(Shape.Empty));

    // §2.6: `is` with a name takes the value once and names what came out,
    // which is what a field or a call result needs.
    Shape shape = Shape.Rect(2.0, 5.0);
    if (shape is Rect r)
        Say("is binding", $"{r.Width}x{r.Height}");
    if (shape is Circle)
        Say("is", "unreachable");

    // A generic variant, holding itself. A case is named without its type
    // arguments, because the type it is being built for is already known --
    // §4.4: type arguments are inferred and never written at a call.
    Tree<int> one = Leaf(1);
    Tree<int> two = Leaf(2);
    Tree<int> three = Leaf(3);
    Tree<int> pair = Node(new Branch<int>(one, two));
    Tree<int> tree = Node(new Branch<int>(pair, three));
    Say("leaves", (long)Leaves(tree));

    // `Optional<T>` is a variant in the standard library, and is what a null
    // pointer cannot say: "a value, which may itself be null".
    Optional<String> found = Some("here");
    Optional<String> missing = None;
    Say("optional", found.ValueOr("-") + " / " + missing.ValueOr("-"));
    if (found is Some got)
        Say("optional is", got.Value);
}

// ==================================================================== §2.8

/// A function that can fail says so in its type. `Ok` and `Fail` are decided by
/// the return type rather than by a name in scope.
Result<int, ConvertError> Halved(String text)
{
    // `try` is the early return: on failure it returns `Fail` with the same
    // error, and on success the expression is the value.
    long n = try Convert.ToLong(text);
    if (n % 2 != 0)
        return Fail(ConvertError.Malformed);
    return Ok((int)(n / 2));
}

void Results()
{
    Heading("2.8 Result, and try");

    var good = Halved("84");
    var odd = Halved("7");
    var bad = Halved("nonsense");

    // The two halves are readable only where the compiler has seen which one
    // is there.
    if (good.Ok)
        Say("ok", (long)good.Value);
    if (!odd.Ok)
        Say("odd", (long)odd.Error);
    if (!bad.Ok)
        Say("not a number", (long)bad.Error);

    // A default needs no proof, because it supplies one.
    Say("valueOr", (long)bad.ValueOr(-1));

    // `&&` carries the proof into what it guards.
    var left = Halved("10");
    var right = Halved("20");
    if (left.Ok && right.Ok)
        Say("sum", (long)(left.Value + right.Value));
}

// ==================================================================== §2.10

void Contracts()
{
    Heading("2.10 interfaces");

    // A class may implement several, and an interface may extend another.
    IDrawable square = new Square(3.0);
    Say("dispatch", square.Draw());
    Say("inherited", square.Name());        // from INamed, through IDrawable

    Figure figure = new Square(2.0);
    Say("virtual", figure.Draw());          // Polygon's, which calls base's
    Say("area", figure.Area());
    Say("not virtual", (long)figure.Sides());
    Say("property", figure.Tag);

    // `is` and a cast both work on a class, and a failed cast is a refusal
    // rather than a wrong answer.
    Say("is Polygon", figure is Polygon);
    if (figure is Square sq)
        Say("corners", (long)sq.Corners);

    // The delegating constructor, which ran `this(1.0)`.
    var unit = new Square();
    Say("this(...)", unit.Area());
}

// ==================================================================== §2.11

void Arrays()
{
    Heading("2.11 arrays, and 2.12 slices");

    // `new T[n]` is a counted heap object, zeroed.
    var numbers = new int[6];
    for (nuint i = 0u; i < numbers.Length; i++)
        numbers[i] = (int)i + 1;
    Say("length", (long)numbers.Length);

    // An array may also be written out, and its element type inferred.
    var few = [10, 20, 30];
    String[] names = ["alpha", "beta", "gamma"];
    Say("literal", $"{few[0u]} {few[1u]} {few[2u]}");
    Say("of Strings", names.Length == 3u ? names[1u] : "?");

    // A fixed array is storage rather than a reference.
    int[3] inline = [7, 8, 9];
    Say("inline", (long)(inline[0u] + inline[1u] + inline[2u]));

    // A slice is a view: it borrows the array, keeps it alive, and writing
    // through one writes the array it came from. Either end may be left out.
    Say("whole", Sum(numbers));
    Say("[1:4]", Sum(numbers[1u:4u]));
    Say("[3:]", Sum(numbers[3u:]));
    Say("[:2]", Sum(numbers[:2u]));

    Fill(numbers[4u:], 0);
    Say("written through", Sum(numbers));

    // §9.4: `foreach` over an array, a slice, and anything with a
    // `GetEnumerator` -- which is a shape rather than an interface.
    long total = 0;
    foreach (var n in numbers)
        total += n;
    foreach (var n in numbers[1u:3u])
        total += n;
    Say("foreach", total);

    long counted = 0;
    foreach (var n in new Countdown(4))
        counted = counted * 10 + n;
    Say("own enumerator", counted);
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

void Tuples()
{
    Heading("2.15 tuples");

    int[] numbers = [5, 3, 9, 1, 8];

    // Deconstruction, which is where a name is wanted: the fields themselves
    // are `Item1` upwards, because a named element would either take part in
    // the type's identity or leave two names for one field.
    var (low, high) = MinMax(numbers);
    Say("deconstructed", $"{low}..{high}");

    // The type written out, and the fields under their own names.
    (int, String) labelled = (7, "seven");
    Say("by field", $"{labelled.Item1} is {labelled.Item2}");

    // It is structural: `(int, String)` written in two modules is one type,
    // interned by its element types the way a slice is by its element.
    (int, String) same = labelled;
    Say("copied", same.Item2);

    // And it may carry a reference, which is then owned by the tuple.
    (String, String) split = ("front", "back");
    Say("holding references", split.Item1 + "/" + split.Item2);
}

long Sum(int[:] values)
{
    long total = 0;
    for (nuint i = 0u; i < values.Length; i++)
        total += values[i];
    return total;
}

void Fill(int[:] values, int with)
{
    for (nuint i = 0u; i < values.Length; i++)
        values[i] = with;
}

// ==================================================================== §2.13

String Describe(Access mode)
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

void Enumerations()
{
    Heading("2.13 enums");

    // A distinct type over an integer: it does not convert on its own, and
    // arithmetic on one is refused.
    Level level = Level.Warning;
    Say("value", (long)level);
    Say("one past", (long)Level.Severe);
    Say("named base", (long)sizeof(Level));

    switch (level)
    {
        case Level.Low: Say("switch", "low"); break;
        case Level.Warning: Say("switch", "warning"); break;
        default: Say("switch", "something else"); break;
    }

    // `[Flags]` is what makes the bitwise operators and `HasFlag` legal.
    var mode = Access.Read | Access.Write;
    Say("flags", Describe(mode));
    Say("with execute", Describe(mode | Access.Execute));
    Say("without write", Describe(mode & ~Access.Write));
    Say("none", Describe(Access.None));
}

// ==================================================================== §2.14

int Add(int a, int b) => a + b;
int Multiply(int a, int b) => a * b;

void Functions()
{
    Heading("2.14 delegates, closures and lambdas");

    // A delegate is one function pointer: it holds a function, not an object.
    Combine how = Add;
    Say("delegate", (long)how(3, 4));
    how = Multiply;
    Say("reassigned", (long)how(3, 4));

    // A lambda that captures nothing is still one, so it may be a delegate.
    Combine written = (a, b) => a - b;
    Say("lambda", (long)written(10, 4));

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
    Say("captured by value", (long)scale(7));   // still 21, not 700

    // What was copied may itself be a reference, and then the one object is
    // shared -- which is the same rule, not an exception to it.
    var control = new Control("bound");
    Notify move = control.Bump;      // a method, and the object it is on
    move(4);
    move(6);
    Say("bound method", (long)control.Left);

    // So a closure outlives the scope that made it, holding what it captured.
    var later = Adder(100);
    Say("escaped", (long)later(5));

    // A lambda written in a method reaches its object: a field, a property,
    // `this`, and a method called with no receiver all resolve.
    var scaler = new Scaler(6);
    Say("over a field", (long)scaler.ByField()(7));
    Say("over a method", (long)scaler.ByMethod()(7));

    Events();
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

void Events()
{
    Heading("2.14.2 events");

    var control = new Control("watched");
    var first = new Watcher();
    var second = new Watcher();

    // Nobody has subscribed, so raising it inside Bump does nothing. There is
    // no null to trip over: a declared event always has a list, sometimes empty.
    control.Bump(1);
    Say("no subscribers", (long)first.Seen);

    control.Moved += first.OnMoved;
    control.Moved += second.OnMoved;
    control.Bump(1);
    Say("both ran", (long)(first.Seen + second.Seen));
    Say("in order, same value", first.Last == second.Last);

    // Removal is by closure equality -- the same method *and* the same object --
    // so this takes the first one off and leaves the second.
    control.Moved -= first.OnMoved;
    control.Bump(1);
    Say("one left", (long)second.Seen);
    Say("the other stopped", (long)first.Seen);

    // A lambda is a closure, so it subscribes like anything else.
    control.Moved += (at) => { Say("a lambda subscribed", (long)at); };
    control.Bump(1);

    // Unsubscribing something that was never subscribed does nothing, which is
    // what lets a tidy-up run twice.
    control.Moved -= first.OnMoved;
    Say("absent removal", true);
}

/// A lambda written inside a class, which is where `this` can be reached.
class Scaler
{
    public int Factor;

    public Scaler(int factor) => Factor = factor;

    int Triple(int n) => n * 3;

    /// A member read is captured as a value, so this copies what `Factor` said
    /// when the closure was made.
    public Turns<int, int> ByField() => value => value * Factor;

    /// A call captures the object, because the call needs one -- and that is
    /// what makes an object holding its own closure a cycle to break.
    public Turns<int, int> ByMethod() => value => Triple(value);
}

/// Returns a closure over its own parameter, which is what makes the capture
/// a heap object rather than a stack slot.
Turns<int, int> Adder(int by)
{
    return value => value + by;
}

// ==================================================================== §2.4

void References()
{
    Heading("2.4 classes, and what owns what");

    // ARC: the count is the scope. Both of these are released at the closing
    // brace, in reverse order.
    {
        var first = new Loud("first");
        var second = new Loud("second");
        Say("made", first.Label + " and " + second.Label);
    }
    Say("scope left", "both gone");

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
            Say("linked", (long)(kid.Id + owner.Id));
    }

    // A weak reference reads back as null once what it named is gone, rather
    // than as a pointer into freed memory.
    var orphan = new Child(3);
    {
        var owner = new Parent(4);
        orphan.Owner = owner;
        Parent? alive = orphan.Owner;
        Say("while alive", alive != null);
    }
    Parent? gone = orphan.Owner;
    Say("after", gone != null);
}

// ==================================================================== §3

void Textual()
{
    Heading("3. text");

    // A String is UTF-8, counted, and immutable. A literal is one interned
    // object however often it is written.
    String greeting = "hello";
    Say("length in bytes", (long)greeting.ByteLength());
    Say("byte at", (long)greeting.ByteAt(1u));
    Say("substring", greeting.Substring(1u, 3u));
    Say("upper", greeting.ToUpperAscii());
    Say("padded", "[" + greeting.PadLeft(8u) + "]");
    Say("replaced", greeting.Replace("l", "L"));
    Say("compare", (long)greeting.CompareTo("hellp"));
    Say("contains", greeting.Contains("ell"));
    Say("index of", greeting.IndexOf("l"));

    // Escapes, and the two that are not one character.
    Say("escapes", "tab[\t] quote[\"] backslash[\\] newline is next");

    // Splitting and joining.
    var parts = "a,b,c".Split(",");
    Say("split", $"{parts.Length} parts, second is {parts[1u]}");
    Say("joined", "-".Join(parts));

    // §3.5: one allocation that grows, for text built a piece at a time.
    var builder = new StringBuilder();
    for (int i = 0; i < 4; i++)
    {
        builder.Append(Text.FromInteger((long)i));
        builder.Append(";");
    }
    Say("builder", builder.ToText());

    // §3.8: interpolation. The whole thing is joined in one allocation, where
    // the chain of `+` it replaces allocated once per operator.
    int clicks = 7;
    double ratio = 0.25;
    bool on = true;
    Say("interpolated", $"{greeting}: {clicks} at {ratio}, on={on}");
    Say("braces", $"{{literal}} and {clicks}");
    Say("empty", $"[{""}]");

    // §3.7: the conversions the interpolation is sugar over.
    Say("from integer", Text.FromInteger(-42));
    Say("from double", Text.FromDouble(1.5));
    Say("from bool", Text.FromBool(false));
    Say("from char", Text.FromChar('A'));
    Say("to hex", Convert.FromLong(255, 16u));
    Say("parsed", (long)Convert.ToLong("123").ValueOr(-1));

    // §3.4: UTF-16, for the platform APIs that want it. A `Utf16String` is a
    // second representation rather than a second string type: it converts on
    // the way out and on the way back.
    var wide = "hello".ToUtf16();
    Say("utf-16 units", (long)wide.UnitCount());
    Say("back again", wide.ToText());
    Say("from a buffer", Text.FromUtf16(wide.ToPointer(), wide.UnitCount()));

    // §3.6: other encodings, behind an interface, so what a file was written
    // in is a value rather than a branch.
    var latin = Encoding.Latin1();
    var bytes = latin.GetBytes("café");
    Say("latin-1 bytes", (long)bytes.Length);
    Say("decoded", latin.GetString(bytes));

    // §3.3: reaching C. `ToPointer` is a null-terminated view of the same
    // bytes rather than a copy.
    printf("  %-22s%s\n", "to a C pointer".ToPointer(), greeting.ToPointer());
    Say("strlen agrees", (long)strlen(greeting.ToPointer()));
}

// ==================================================================== §9

void Statements()
{
    Heading("9. statements and expressions");

    // `if`, and a condition that must be `bool`.
    int n = 7;
    if (n > 5)
    {
        Say("if", "greater");
    }
    else
    {
        Say("if", "not greater");
    }

    // The conditional, which evaluates only the arm it selects.
    Say("ternary", n > 5 ? "yes" : "no");
    Say("chained", n < 0 ? "negative" : n == 0 ? "zero" : "positive");

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
    Say("for", (long)total);

    // `while`, and §9.7 `do`, which runs its body before it asks.
    int j = 0;
    while (j < 5)
        j += 2;
    Say("while", (long)j);

    int tries = 0;
    do { tries++; } while (tries < 3);
    Say("do while", (long)tries);

    int never = 0;
    do { never++; } while (false);
    Say("do at least once", (long)never);

    // §9.6: every assignment operator, and stepping by one either way.
    int value = 10;
    value += 5;  value -= 3;  value *= 2;  value /= 4;  value %= 5;
    value <<= 3; value >>= 1; value |= 1;  value &= 14; value ^= 3;
    Say("compound", (long)value);

    int step = 0;
    step++;
    ++step;
    Say("postfix then prefix", (long)(step++ + ++step));
    step--;
    --step;
    Say("and back", (long)step);

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
    Say("switch", said);

    // Over a String, which C# allows and C does not.
    switch (said)
    {
        case "seven": Say("switch on text", "matched"); break;
        default: Say("switch on text", "missed"); break;
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
    Say("goto", (long)found);

    // §9.9: `nameof`, which is the name as written, checked to exist.
    Say("nameof local", nameof(value));
    Say("nameof function", nameof(Statements));
    Say("nameof type", nameof(Money));

    // §9.10: `checked`, which asks `+`, `-` and `*` to notice rather than
    // wrap. `unchecked` is the default and says so where it matters.
    int room = checked(2000000 + 2000000);
    Say("checked", (long)room);

    checked
    {
        Say("checked block", (long)(1000 * 1000));
    }

    unchecked
    {
        int wrapped = 2147483647;
        wrapped = wrapped + 1;      // defined: it wraps, as C# does
        Say("wrapped", (long)wrapped);
    }

    // §9.6.1: the value a type's storage holds before anything is put in it.
    Say("default(int)", (long)default(int));
    Say("default(bool)", default(bool));
    Point origin = default(Point);
    Say("default(Point)", $"({origin.X}, {origin.Y})");

    // §9.3: a const is folded, a static is storage, and both were settled
    // before this line ran.
    Steps++;
    Say("const / static", $"{Width} {Doubled} {Total} {Steps}");

    // A block is a scope, and an inner name may shadow nothing: a redeclared
    // local is an error, so this one is genuinely new.
    {
        int inner = 3;
        Say("block", (long)inner);
    }

    // The right operand of `&&` and `||` does not run when the left already
    // decides the answer -- which is the only reason `d != 0 && 100 / d > 1`
    // is safe to write.
    int d = 0;
    Say("short circuit", d != 0 && 100 / d > 1);
    Say("or", d == 0 || 100 / d > 1);
}

// ==================================================================== main

int Main(String[] args)
{
    Console.WriteLine("A tour of Stainless, in " + Family() + " form.");
    Say("arguments", (long)args.Length);

    Modules();
    Primitives();
    Values();
    Pointers();
    Variants();
    Results();
    Contracts();
    Arrays();
    Enumerations();
    Tuples();
    Functions();
    References();
    Textual();
    Statements();

    // The rest of the tour, in Library.sl.
    Members();
    Calls();
    Generics();
    Library();
    Reflected();
    Interop();
    Concurrency();

    Console.WriteLine("");
    Console.WriteLine("Done.");
    return 0;
}
