// SPDX-License-Identifier: 0BSD
module Flagging;

import Standard.Console;

extern "C" int printf(byte* format, ...);

// [Flags] says the members combine as bits rather than naming alternatives.
// It needs no import: it is a rule about enums, not a library to opt into.
[Flags]
public enum Access : byte {
    None    = 0,
    Read    = 1,
    Write   = 2,
    Execute = 4,
    All     = 7,
}

[Flags]
public enum Style : uint {
    Plain     = 0,
    Bold      = 1,
    Italic    = 2,
    Underline = 4,
}

// Without [Flags] an enum is a choice, and bitwise operators are rejected.
public enum Colour { Red, Green, Blue }

String Describe(Access mode) {
    var text = new StringBuilder();
    if (mode.HasFlag(Access.Read)) { text.Append("r"); }
    if (mode.HasFlag(Access.Write)) { text.Append("w"); }
    if (mode.HasFlag(Access.Execute)) { text.Append("x"); }
    if (mode == Access.None) { text.Append("-"); }
    return text.ToText();
}

int Main() {
    var mode = Access.Read | Access.Write;

    printf("mode=%s\n", Describe(mode).ToPointer());
    printf("all=%s none=%s\n",
        Describe(Access.All).ToPointer(), Describe(Access.None).ToPointer());

    // Clearing a bit: complement then mask.
    var readOnly = mode & ~Access.Write;
    printf("readonly=%s\n", Describe(readOnly).ToPointer());

    // Toggling with xor, twice, gets back where it started.
    var toggled = mode ^ Access.Execute;
    printf("toggled=%s back=%s\n",
        Describe(toggled).ToPointer(), Describe(toggled ^ Access.Execute).ToPointer());

    // Compound assignment works, because it is the same operator underneath.
    var building = Access.None;
    building |= Access.Read;
    building |= Access.Execute;
    building &= ~Access.Read;
    printf("built=%s\n", Describe(building).ToPointer());

    // HasFlag on a combination asks for every bit, as in C#.
    printf("has-rw=%d has-all=%d\n",
        mode.HasFlag(Access.Read | Access.Write) ? 1 : 0,
        mode.HasFlag(Access.All) ? 1 : 0);

    // A wider underlying type behaves the same.
    var style = Style.Bold | Style.Underline;
    printf("style=%d bold=%d italic=%d\n",
        (int)style, style.HasFlag(Style.Bold) ? 1 : 0, style.HasFlag(Style.Italic) ? 1 : 0);

    // A flags enum still compares and still switches.
    switch (readOnly) {
        case Access.Read: printf("switch=read\n"); break;
        default:          printf("switch=other\n"); break;
    }

    // The strong typing is unchanged: no implicit conversion in either direction.
    printf("raw=%d\n", (int)(Access.Read | Access.Execute));

    var colour = Colour.Green;
    printf("colour=%d\n", colour == Colour.Green ? 1 : 0);

    printf("done\n");
    return 0;
}
