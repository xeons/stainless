// SPDX-License-Identifier: 0BSD
module Cell;

extern "C" int printf(byte* format, ...);

class Counter {
    int value;

    Counter(int start) { value = start; }
    ~Counter() { printf("~Counter(%d)\n", value); }

    public int Get() { return value; }
    public void Bump() { value = value + 1; }
}

void Borrow(Counter c) {
    // Parameters are borrowed, so this must not destroy anything.
    c.Bump();
}

int Main() {
    printf("start\n");
    {
        var a = new Counter(40);
        var b = a;
        b.Bump();
        Borrow(a);
        printf("value=%d\n", a.Get());
        printf("leaving\n");
    }
    printf("done\n");
    return 0;
}
