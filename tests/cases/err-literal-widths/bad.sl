// SPDX-License-Identifier: 0BSD
module Bad;

const int Below = -1;
const int Beyond = 300;

public enum Level { Low = 1, High = 2 }

int Main()
{
    sbyte tooLow = -129;        // one past the floor
    byte negative = -1;         // an unsigned type has no negative
    short wide = -32769;
    int past = 5000000000;      // wider than an int, and not asking to be cut
    long beyond = 9223372036854775808;
    float plain = 1.5;          // a double literal; the hint says to write 1.5f

    // An arm takes its width from where the conditional is going, and an arm
    // that does not fit is refused there as it is anywhere else.
    bool flag = past > 0;
    nuint signedArm = flag ? 1 : -1;
    byte overArm = flag ? 1 : 300;

    // A `const` reaches a type that holds it, and is refused by the same rule
    // where it does not. An enum member is not a number here whatever it holds.
    nuint negativeConst = Below;
    byte overConst = Beyond;
    nuint fromEnum = Level.High;
    return 0;
}
