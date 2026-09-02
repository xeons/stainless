// SPDX-License-Identifier: 0BSD
module Bad;

int Main() {
    int total = 0;
    parallel for (int i = 0; i < 100; i = i + 1) {
        total = total + i;      // every chunk racing on one variable
    }
    return total;
}
