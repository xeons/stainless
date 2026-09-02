// SPDX-License-Identifier: 0BSD
module Bad;

int Work() { return 1; }

int Main() {
    int result = 0;
    parallel {
        spawn result = Work();
        return result;          // would skip the join
    }
}
