// SPDX-License-Identifier: 0BSD
module Bad;

class Owner { }

int Main()
{
    int v = 1;

    // A class named as a label asks what class a value is, which an int has
    // no answer to.
    switch (v)
    {
        case Owner: return 1;
        default: return 0;
    }
}
