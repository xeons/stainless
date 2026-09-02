// SPDX-License-Identifier: 0BSD
module Bad;

int Twice(int n) { return n * 2; }

int Main() {
    return Twice(1.5);
}
