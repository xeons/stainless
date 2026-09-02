// SPDX-License-Identifier: 0BSD
module Bad;

int Main() {
    var values = new int[10];
    // The trip count has to be known before the loop is split.
    parallel for (int i = 0; i < 10; i = i * 2) { values[i] = 1; }
    return 0;
}
