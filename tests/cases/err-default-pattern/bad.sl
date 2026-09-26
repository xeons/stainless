// SPDX-License-Identifier: 0BSD
module Bad;

// `case default:` is a `default:` label written wrong.

public int Main()
{
    int x = 3;
    switch (x)
    {
        case default:
            return 1;
    }

    return 0;
}
