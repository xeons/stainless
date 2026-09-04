// SPDX-License-Identifier: 0BSD
module Bad;

extern "C" int printf(byte* format, ...);

int Main() {
    // A switch is a target for 'break' but never for 'continue'; with no
    // enclosing loop there is nothing for this to continue.
    switch (1) {
        case 1:
            continue;
        default:
            break;
    }
    return 0;
}
