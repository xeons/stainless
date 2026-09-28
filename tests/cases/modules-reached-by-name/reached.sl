// SPDX-License-Identifier: 0BSD
//
// Imports nothing. Only the modules a program reaches are compiled, and a
// qualified name reaches one as surely as an import does: in code, inside an
// interpolated string's hole, and through typeof.
module ReachedByName;

extern "C" int printf(byte* format, ...);

[Standard.Reflection.Reflect]
class Plain
{
    public int Count;
}

int Main()
{
    byte[] bytes = [0xCA, 0xFE];
    Standard.Console.WriteLine(Standard.Convert.ToHexString(bytes));
    Standard.Console.WriteLine($"{Standard.Math.Max(3, 7)}");

    var type = typeof(Plain);
    Standard.Console.WriteLine(type.Name);
    return 0;
}
