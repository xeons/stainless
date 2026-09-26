// SPDX-License-Identifier: 0BSD
module Bad;

// Type arguments go on a call to something generic, in the number it takes,
// or on a generic type in front of its member.

T Pick<T>(T a, T b) => a;

int Plain(int a) => a;

class Box<T>
{
    public int Size() => 1;
}

public int Main()
{
    Plain<int>(1);
    new Box<int>().Size<int>();
    Pick<int, long>(1, 2);
    var named = Pick<int>;
    var type = Box<int>;
    return 0;
}
