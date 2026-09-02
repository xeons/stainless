// SPDX-License-Identifier: 0BSD
module Bad;

extern "C" int puts(byte* text);

int Main() {
    String built = "hello" + " there";
    puts(built);        // a String is an object, not a byte pointer
    return 0;
}
