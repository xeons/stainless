// SPDX-License-Identifier: 0BSD
module Hello;

extern "C" int puts(byte* text);

int Main() {
    puts("Hello from Stainless.");
    return 0;
}
