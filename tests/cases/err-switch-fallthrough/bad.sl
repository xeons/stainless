// SPDX-License-Identifier: 0BSD
module Bad;

extern "C" int printf(byte* format, ...);

int Main() {
    switch (1) {
        case 1:
            printf("one\n");
            // No break: a section may not run off its end.
        default:
            printf("other\n");
            break;
    }
    return 0;
}
