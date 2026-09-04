// SPDX-License-Identifier: 0BSD
module Bad;

extern "C" int printf(byte* format, ...);

int Main() {
    String name = "world" + "!";
    printf("%s\n", name);   // needs name.ToPointer()
    return 0;
}
