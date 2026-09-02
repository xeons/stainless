// SPDX-License-Identifier: 0BSD
module Bad;

int Main() {
    var numbers = new int[4];
    return numbers["two"];
}
