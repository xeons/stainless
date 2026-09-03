// SPDX-License-Identifier: 0BSD
module Switching;

import Standard.Collections;
import Standard.Console;

extern "C" int printf(byte* format, ...);

public enum Level : byte { Low = 1, Warning = 10, Severe, Fatal = 200 }

const int Threshold = 3;

// Every section returns, and there is a default, so the function needs no
// trailing return.
String Name(Level level) {
    switch (level) {
        case Level.Low:     return "low";
        case Level.Warning: return "warning";
        case Level.Severe:  return "severe";
        default:            return "fatal";
    }
}

// Stacked labels share one body, which is how a switch says "either of these".
String Parity(int n) {
    switch (n) {
        case 0:
        case 2:
        case 4:
            return "even";
        case 1:
        case 3:
            return "odd";
        default:
            return "big";
    }
}

// A switch over a String, and over a constant label rather than a literal.
int Rank(String word) {
    int score = 0;
    switch (word) {
        case "alpha":
            score = 1;
            break;
        case "beta":
        case "gamma":
            score = 2;
            break;
        default:
            score = Threshold;
            break;
    }
    return score;
}

// break belongs to the switch; continue passes through it to the loop.
int Count(int[] values) {
    int total = 0;
    for (nuint i = 0; i < values.Length; i = i + 1) {
        switch (values[i]) {
            case -1:
                continue;           // to the loop's step, not out of the switch
            case 0:
                break;              // out of the switch, into the rest of the body
            default:
                total = total + values[i];
                break;
        }
        total = total + 100;
    }
    return total;
}

// A switch inside a loop inside a switch: each break finds its own construct.
String Nested(int outer) {
    var text = new StringBuilder();
    switch (outer) {
        case 1:
            for (int i = 0; i < 4; i = i + 1) {
                if (i == 3) { break; }      // leaves the loop
                text.AppendInteger(i);
            }
            text.Append("|");
            break;
        default:
            text.Append("other");
            break;
    }
    return text.ToText();
}

int Main() {
    printf("levels=%s %s %s %s\n",
        Name(Level.Low).ToPointer(), Name(Level.Warning).ToPointer(),
        Name(Level.Severe).ToPointer(), Name(Level.Fatal).ToPointer());

    printf("parity=%s %s %s\n",
        Parity(4).ToPointer(), Parity(3).ToPointer(), Parity(9).ToPointer());

    printf("rank=%d %d %d\n", Rank("alpha"), Rank("gamma"), Rank("delta"));

    var values = new int[5];
    values[0] = 5;
    values[1] = -1;         // continue: contributes nothing at all
    values[2] = 0;          // break: contributes only the trailing 100
    values[3] = 7;
    values[4] = -1;
    printf("count=%d\n", Count(values));

    printf("nested=%s %s\n", Nested(1).ToPointer(), Nested(2).ToPointer());

    // char and bool switch too; a char is an integer as far as dispatch goes.
    char c = 'b';
    switch (c) {
        case 'a': printf("char=first\n"); break;
        case 'b': printf("char=second\n"); break;
        default:  printf("char=other\n"); break;
    }

    bool flag = true;
    switch (flag) {
        case true:  printf("flag=yes\n"); break;
        case false: printf("flag=no\n"); break;
    }

    // A switch with no default simply does nothing when nothing matches.
    switch (99) {
        case 1: printf("unreachable\n"); break;
    }

    printf("done\n");
    return 0;
}
