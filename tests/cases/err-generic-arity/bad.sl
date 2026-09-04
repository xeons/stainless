// SPDX-License-Identifier: 0BSD
module Bad;

public class Pair<A, B> { A first; B second; }

int Main() {
    Pair<int> p;        // takes two
    return 0;
}
