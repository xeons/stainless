// SPDX-License-Identifier: 0BSD
module Bad;

int Main()
{
    sbyte tooLow = -129;        // one past the floor
    byte negative = -1;         // an unsigned type has no negative
    short wide = -32769;
    int past = 5000000000;      // wider than an int, and not asking to be cut
    long beyond = 9223372036854775808;
    float plain = 1.5;          // a double literal; the hint says to write 1.5f
    return 0;
}
