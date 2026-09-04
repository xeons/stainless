// SPDX-License-Identifier: 0BSD
module Bad;

int Main() {
    int x = 1;
    if (x) { return 1; }    // Stainless has no truthiness
    return 0;
}
