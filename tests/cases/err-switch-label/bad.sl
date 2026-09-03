// SPDX-License-Identifier: 0BSD
module Bad;

int Value() { return 3; }

int Main() {
    int n = 1;
    switch (n) {
        case Value(): return 1;     // a label has to be known at compile time
        default:      return 0;
    }
}
