// SPDX-License-Identifier: 0BSD
module Bad;

public delegate int Plain(int value);

int Main() {
    int factor = 3;
    // A delegate is one function pointer, with nowhere to keep the capture.
    Plain scaled = value => value * factor;
    return scaled(2);
}
