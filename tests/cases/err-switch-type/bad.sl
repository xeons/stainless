// SPDX-License-Identifier: 0BSD
module Bad;

int Main() {
    double ratio = 0.5;

    // A switch needs constant labels, and a double has no exact ones.
    switch (ratio) {
        case 1: return 1;
        default: return 0;
    }
}
