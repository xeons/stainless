// SPDX-License-Identifier: 0BSD
module Bad;

enum Color { Red, Green }

int Main() {
    var mixed = Color.Red + Color.Green;    // colours do not add
    return 0;
}
