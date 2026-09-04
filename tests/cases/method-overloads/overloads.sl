// SPDX-License-Identifier: 0BSD
//
// Methods overload by parameter type, which is also what lets one class
// implement two instantiations of the same generic interface: each interface
// has its own dispatch table, so two methods of one name sit in different slots.
module Overloads;

import Standard.Console;

interface IEq<T> { bool Same(T other); }

class Both : IEq<int>, IEq<String> {
    public int N;
    public String S;

    public Both(int n, String s) { N = n; S = s; }

    public bool Same(int other) { return N == other; }
    public bool Same(String other) { return S == other; }
}

class Printer {
    public String Show(int n)    { return "int " + Text.FromInteger(n); }
    public String Show(String s) { return "text " + s; }
    public String Show(double d) { return "double " + Text.FromDouble(d); }

    // A call without a receiver picks an overload the same way.
    public String Pair(int n) { return Show(n) + "/" + Show(n + 1); }
}

// An interface that restates a method it inherits declares one signature
// twice; the nearest declaration is what a call through it means.
interface ISized { int Size(); }
interface ISizedMore : ISized { int Size(); int Extra(); }

class Sized : ISizedMore {
    public int Size()  { return 3; }
    public int Extra() { return 9; }
}

struct Vec {
    public double X;
    public double Y;

    public Vec Scaled(double by) { Vec v; v.X = X * by; v.Y = Y * by; return v; }
    public Vec Scaled(int by)    { return Scaled((double)by); }
    public double Dot(Vec other) { return X * other.X + Y * other.Y; }
}

int Main() {
    var both = new Both(7, "seven");

    Console.WriteLine(both.Same(7) ? "int:yes" : "int:no");
    Console.WriteLine(both.Same(8) ? "int:yes" : "int:no");
    Console.WriteLine(both.Same("seven") ? "text:yes" : "text:no");
    Console.WriteLine(both.Same("other") ? "text:yes" : "text:no");

    // Each interface reaches its own method.
    IEq<int> asNumber = both;
    IEq<String> asText = both;
    Console.WriteLine(asNumber.Same(7) ? "via-int:yes" : "via-int:no");
    Console.WriteLine(asText.Same("seven") ? "via-text:yes" : "via-text:no");
    Console.WriteLine(asText.Same("other") ? "via-text:yes" : "via-text:no");

    var printer = new Printer();
    Console.WriteLine(printer.Show(3));
    Console.WriteLine(printer.Show("x"));
    Console.WriteLine(printer.Show(2.5));
    Console.WriteLine(printer.Pair(1));

    // A struct overloads too, and one overload may call another.
    Vec vector;
    vector.X = 3;
    vector.Y = 4;
    Console.WriteLine(Text.FromDouble(vector.Scaled(2).Dot(vector.Scaled(0.5))));

    ISizedMore sized = new Sized();
    Console.WriteLine(Text.FromInteger(sized.Size() + sized.Extra()));

    return 0;
}
