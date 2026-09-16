// SPDX-License-Identifier: 0BSD
module Bad;

public interface IShape { double Area(); }

public class Blob : IShape
{
    double _size;
    public Blob(double s) => _size = s;
}

int Main() => 0;
