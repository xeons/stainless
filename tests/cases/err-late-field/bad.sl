// SPDX-License-Identifier: 0BSD
module Bad;

// 'late' is for a class's field that is a reference never null.
public class Holder
{
    late int _count;
    late String? _maybe;
    late String _name;

    public Holder() => _name = "fine";
}

public struct Point
{
    public late String Label;
}

int Main() => 0;
