// SPDX-License-Identifier: 0BSD
//
// `$"a {b} c"`.
//
// Sugar over what was already there -- the same `Text.From*` conversions, and
// a String at the end -- with one difference that is not cosmetic: the whole
// thing is joined in a single allocation, where the chain of `+` it replaces
// allocated once per operator and threw all but the last away.
module Interpolation;

import Standard.Console;
import Standard.Collections;

extern "C" int printf(byte* format, ...);

public class Point {
    public int X { get; }
    public int Y { get; }

    public Point(int x, int y) {
        X = x;
        Y = y;
    }

    public String Show() { return $"({X}, {Y})"; }
}

int Main() {
    // --------------------------------------------------------------- basics

    String who = "Ada";
    int clicks = 7;

    Console.WriteLine($"no holes at all");
    Console.WriteLine($"hello {who}");
    Console.WriteLine($"{who} first");
    Console.WriteLine($"count {clicks}");
    Console.WriteLine($"{who}{who}{who}");
    Console.WriteLine($"[{""}]");

    // An interpolation with nothing in it is an empty String.
    var nothing = $"";
    printf("empty     = %llu\n", (ulong)nothing.ByteLength());

    // ---------------------------------------------------------- every type

    long big = 9000000000;
    nuint size = 42u;
    byte small = 200u;
    double ratio = 0.25;
    bool ready = true;
    char32 star = '*';

    Console.WriteLine($"long {big}, nuint {size}, byte {small}");
    Console.WriteLine($"double {ratio}, bool {ready}, char {star}");
    Console.WriteLine($"negative {-5}, zero {0}");

    // A char32 writes the character, not the number. Its value as a number is
    // one cast away, and that cast is what says which was meant.
    Console.WriteLine($"star {star} is {(long)star}");

    // Beyond ASCII, to prove the encoder rather than the byte.
    char32 accented = 'e';
    char32 japanese = '日';
    Console.WriteLine($"utf8 {accented} {japanese} {'é'}");

    // ------------------------------------------------------- expressions

    Console.WriteLine($"sum {clicks + 1}, product {clicks * 2}, half {clicks / 2}");
    Console.WriteLine($"call {who.ToUpperAscii()}, length {who.ByteLength()}");
    Console.WriteLine($"ternary {(clicks > 5 ? "big" : "small")}");

    var numbers = [10, 20, 30];
    Console.WriteLine($"indexed {numbers[1u]}, length {numbers.Length}");

    var point = new Point(3, 4);
    Console.WriteLine($"member {point.X} and {point.Y}");
    Console.WriteLine($"nested {point.Show()}");

    // An interpolation inside an interpolation's hole, which is the thing the
    // lexer's brace counting is for.
    Console.WriteLine($"deep {$"inner {clicks}"}");

    // A string with braces of its own inside a hole.
    Console.WriteLine($"quoted {"has {braces}"}");

    // --------------------------------------------------------------- braces

    Console.WriteLine($"literal {{ and }}");
    Console.WriteLine($"{{{clicks}}}");
    Console.WriteLine($"{{{{double}}}}");

    // --------------------------------------------------------------- escapes

    Console.WriteLine($"tab\there, quote \" here");
    Console.WriteLine($"newline in {who}\nsecond line");

    // ------------------------------------------------- the same as before

    // What it replaces, side by side. The point is that they agree.
    String chained = "clicks: " + Text.FromInteger((long)clicks)
                   + " for " + who;
    String written = $"clicks: {clicks} for {who}";

    printf("agree     = %d\n", chained == written);
    Console.WriteLine(written);

    // In a loop, where the allocation difference is what matters and the
    // result is what can be checked.
    var built = new StringBuilder();
    for (int i = 0; i < 5; i += 1) { built.Append($"<{i}>"); }
    Console.WriteLine($"loop {built.ToText()}");

    // As an argument, as a return value, as a field's value.
    Console.WriteLine(Describe(clicks));

    var labels = new List<String>();
    for (int i = 1; i <= 3; i += 1) { labels.Add($"item {i}"); }
    Console.WriteLine($"joined {" | ".Join(ToArray(labels))}");

    printf("done\n");
    return 0;
}

String Describe(int count) {
    if (count == 1) { return $"{count} click"; }
    return $"{count} clicks";
}

/// A List as an array, since `Join` takes one.
public String[] ToArray(List<String> items) {
    var all = new String[items.Count()];
    for (nuint i = 0u; i < items.Count(); i += 1u) { all[i] = items.At(i); }
    return all;
}
