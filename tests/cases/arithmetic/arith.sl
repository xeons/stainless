// SPDX-License-Identifier: 0BSD
module Arith;

extern "C" int printf(byte* format, ...);

const int Limit = 100;

int Main() {
    printf("%d\n", 2 + 3 * 4);
    printf("%d\n", (2 + 3) * 4);
    printf("%d\n", 17 % 5);
    printf("%d\n", -7 / 2);
    printf("%d\n", 1 << 10);
    printf("%d\n", 255 & 0x0F);
    printf("%d\n", 0xF0 | 0x0F);
    printf("%d\n", 6 ^ 3);
    printf("%d\n", ~0);
    printf("%g\n", 1.0 / 4.0);
    printf("%g\n", 3 + 0.5);

    long big = 1;
    big = big << 40;
    printf("%lld\n", big);

    var x = 10;
    x += 5;
    x *= 2;
    x -= 4;
    printf("%d\n", x);

    printf("%d\n", Limit);
    printf("%d\n", (int)3.99);
    printf("%d\n", 1_000_000 / 1000);
    return 0;
}
