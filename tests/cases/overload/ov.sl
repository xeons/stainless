module Ov;

extern "C" int printf(byte* format, ...);

int Describe(int value)    { return value * 10; }
int Describe(double value) { return (int)value + 1000; }

int Main() {
    printf("%d\n", Describe(7));
    printf("%d\n", Describe(2.5));
    return 0;
}
