// SPDX-License-Identifier: 0BSD
module Flow;

extern "C" int printf(byte* format, ...);

int Fib(int n) {
    if (n < 2) { return n; }
    return Fib(n - 1) + Fib(n - 2);
}

int Guard(int d) {
    if (d != 0 && 100 / d > 1) { return 1; }
    return 0;
}

int Main() {
    printf("fib=%d\n", Fib(20));

    var total = 0;
    for (int i = 0; i < 10; i = i + 1) {
        if (i == 3) { continue; }
        if (i == 8) { break; }
        total = total + i;
    }
    printf("for=%d\n", total);

    var j = 0;
    var sum = 0;
    while (j < 5) {
        sum = sum + j * 2;
        j = j + 1;
    }
    printf("while=%d\n", sum);
    printf("guard=%d\n", Guard(0));

    if (total > 20) { printf("branch=high\n"); } else { printf("branch=low\n"); }
    return 0;
}
