// SPDX-License-Identifier: 0BSD
//
// Every kind of thing the debug metadata has to describe, in one program: a
// struct laid out by value, a class with an object header in front of its
// fields, an enum with its members, an array, a weak reference, a generic
// instantiated twice, and a closure. debug.txt names what must come out.
module Debug;

import Standard.Console;
import Standard.Collections;

public struct Point {
    public double X;
    public double Y;
}

public enum Level : byte {
    Quiet = 0,
    Loud  = 7,
}

public class Node {
    public int Value;
    public weak Node? Parent;
    public Point Where;

    public Node(int value) { Value = value; }

    public int Doubled() {
        int scaled = Value * 2;
        return scaled;
    }
}

public class Box<T> {
    T held;
    public Box(T initial) { held = initial; }
    public T Get() { return held; }
}

int Sum(int[] values) {
    int total = 0;
    for (nuint i = 0; i < values.Length; i = i + 1) { total = total + values[i]; }
    return total;
}

int Main() {
    Point origin;
    origin.X = 1.5;
    origin.Y = 2.5;

    var node = new Node(21);
    node.Where = origin;

    Level level = Level.Loud;
    byte raw = (byte)level;

    var numbers = new int[3];
    numbers[0] = 1;
    numbers[1] = 2;
    numbers[2] = 39;

    var boxed = new Box<int>(4);
    var named = new Box<String>("text");

    Console.WriteLine(Text.FromInteger(node.Doubled()));
    Console.WriteLine(Text.FromInteger(Sum(numbers)));
    Console.WriteLine(Text.FromInteger((int)raw));
    Console.WriteLine(Text.FromInteger(boxed.Get()));
    Console.WriteLine(named.Get());
    return 0;
}
