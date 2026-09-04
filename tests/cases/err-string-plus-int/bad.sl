// SPDX-License-Identifier: 0BSD
module Bad;

int Main() {
    String label = "count: " + 42;   // no implicit number-to-String
    return 0;
}
