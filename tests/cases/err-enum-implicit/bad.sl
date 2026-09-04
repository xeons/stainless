// SPDX-License-Identifier: 0BSD
module Bad;

enum Color { Red, Green }

int Main() {
    // An enum is a type, not a number wearing a name. Both directions need a cast.
    int n = Color.Red;
    return n;
}
