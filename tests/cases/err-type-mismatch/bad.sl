// SPDX-License-Identifier: 0BSD
module Bad;

int Main() {
    int x = 1.5;        // no implicit double -> int
    return x;
}
