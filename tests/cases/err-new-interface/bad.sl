// SPDX-License-Identifier: 0BSD
module Bad;

public interface IShape { double Area(); }

int Main() {
    IShape s = new IShape();
    return 0;
}
