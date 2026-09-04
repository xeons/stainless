// SPDX-License-Identifier: 0BSD
module Bad;

public interface IShape { double Area(); }

public class Square : IShape {
    public int Area() { return 1; }     // wrong return type
}

int Main() { return 0; }
