// SPDX-License-Identifier: 0BSD
module Ternary;

import Standard.Console;

extern "C" int printf(byte* format, ...);

class Tag {
    String name;
    Tag(String n) { name = n; }
    public String Name() { return name; }
}

int Max(int a, int b) { return a > b ? a : b; }

// Nested, to prove the false arm groups to the right.
String Band(int score) {
    return score >= 90 ? "high" : score >= 50 ? "middle" : "low";
}

int Main() {
    printf("max=%d\n", Max(3, 9));
    printf("min=%d\n", 3 < 9 ? 3 : 9);

    // Mixed widths meet at the wider type.
    long wide = true ? 1 : 2L;
    printf("wide=%lld\n", wide);

    // Only the chosen arm runs: the other would divide by zero.
    int zero = 0;
    printf("guard=%d\n", zero == 0 ? -1 : 100 / zero);

    Console.WriteLine(Band(95));
    Console.WriteLine(Band(70));
    Console.WriteLine(Band(10));

    // A managed arm: each yields an owned reference, merged into one.
    var a = new Tag("first");
    var b = new Tag("second");
    Console.WriteLine((1 < 2 ? a : b).Name());
    Console.WriteLine((1 > 2 ? a : new Tag("fresh")).Name());

    printf("done\n");
    return 0;
}
