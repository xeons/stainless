// SPDX-License-Identifier: 0BSD
module Enums;

extern "C" int printf(byte* format, ...);

public enum Color { Red, Green, Blue }

// An explicit underlying type, and explicit values that the rest continue from.
public enum Level : byte { Low = 1, Warning = 10, Severe, Fatal = 200 }

String Describe(Color c) {
    if (c == Color.Red) return "red";
    if (c == Color.Green) return "green";
    return "blue";
}

int Main() {
    var c = Color.Green;

    printf("green=%d\n", Describe(c) == "green" ? 1 : 0);
    printf("blue=%d\n", Describe(Color.Blue) == "blue" ? 1 : 0);

    // Distinct values, auto-numbered from zero.
    printf("red=%d green=%d blue=%d\n",
        (int)Color.Red, (int)Color.Green, (int)Color.Blue);

    // A chosen underlying type, and a member that continues from the one before.
    printf("low=%d warning=%d severe=%d fatal=%d\n",
        (int)Level.Low, (int)Level.Warning, (int)Level.Severe, (int)Level.Fatal);

    printf("size=%d\n", (int)sizeof(Level));

    // Ordered comparison, which is what a severity is for.
    Level at = Level.Severe;
    printf("atLeastWarning=%d\n", at >= Level.Warning ? 1 : 0);
    printf("belowFatal=%d\n", at < Level.Fatal ? 1 : 0);

    // Round trip through the underlying type, both casts explicit.
    int raw = (int)Color.Blue;
    Color back = (Color)raw;
    printf("roundTrip=%d\n", back == Color.Blue ? 1 : 0);

    printf("done\n");
    return 0;
}
