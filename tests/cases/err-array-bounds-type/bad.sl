// SPDX-License-Identifier: 0BSD
module Bad;

int Main()
{
    var numbers = new int[4];

    // Only a declared indexer takes more than one index; an array takes the
    // one number it is laid out by.
    numbers[1, 2] = 3;

    return numbers["two"];
}
