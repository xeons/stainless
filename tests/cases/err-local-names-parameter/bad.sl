// SPDX-License-Identifier: 0BSD
module Bad;

int Twice(int count)
{
    int count = 2;          // a local may not take a parameter's name
    return count;
}

int Main() => Twice(1);
