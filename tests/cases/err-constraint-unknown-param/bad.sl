// SPDX-License-Identifier: 0BSD
module Bad;

public interface IShape { double Area(); }

public class Holder<T> where U : IShape { T item; }

int Main() {
    Holder<int> h;
    return 0;
}
