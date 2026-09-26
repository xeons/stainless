// SPDX-License-Identifier: 0BSD
module Bad;

// `new(...)` and a bare `default` take their type from where they are going,
// so each needs somewhere that says.

class Point
{
    public int X;

    public Point()
    {
        X = 0;
    }
}

public int Main()
{
    var made = new();
    var zero = default;
    new();
    int x = new().X;
    bool same = default == default;
    var pair = (default, 1);
    return 0;
}
