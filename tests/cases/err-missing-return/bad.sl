// SPDX-License-Identifier: 0BSD
module Bad;

int Pick(bool flag) {
    if (flag) { return 1; }
    // falls off the end
}

int Main() { return Pick(true); }
