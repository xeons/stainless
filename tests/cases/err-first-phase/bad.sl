// SPDX-License-Identifier: 0BSD
module Bad;

import Standard.Collections;

public class Shape
{
    public Shape() { }

    public virtual int Sides() => 0;
}

// SL0937: the object is reached before 'base(...)' has built it.
public class Reaching : Shape
{
    List<int> _items;

    public Reaching()
    {
        _items = new List<int>();
        int sides = Sides();
        base();
    }
}

// SL0938: a field with no zero value is given its value after the base.
public class Late : Shape
{
    String _name;

    public Late()
    {
        base();
        _name = "late";
    }
}

// SL0939: a field read before it has a value.
public class Early
{
    String _first;
    String _second;

    public Early()
    {
        _second = _first + "!";
        _first = "first";
    }
}

int Main() => 0;
