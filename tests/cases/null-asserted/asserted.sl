// SPDX-License-Identifier: 0BSD
//
// Every form that drops a null by assertion — `x!`, `(C)x`, `(T[])x`, and a
// derived optional cast to its base — passes a value that is there untouched.
module NullAsserted;

import Standard.Console;

class Shape
{
    public virtual String Name => "shape";
}

class Circle : Shape
{
    public override String Name => "circle";
}

int Main()
{
    Circle? maybe = new Circle();
    Circle viaBang = maybe!;
    Circle viaCast = (Circle)maybe;
    Shape viaBase = (Shape)maybe;
    int[]? numbers = [1, 2, 3];
    int[] viaArray = (int[])numbers;
    Console.WriteLine($"{viaBang.Name} {viaCast.Name} {viaBase.Name} {viaArray.Length}");
    return 0;
}
