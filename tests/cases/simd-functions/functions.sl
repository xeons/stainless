// A vector's built-in functions, static on its type, and what it answers
// about itself.
module SimdFunctions;

import Standard.Console;

int Main()
{
    vfloat4 a = new vfloat4(1, -2, 3, -4);
    vfloat4 b = new vfloat4(0.5f, 2, -1, 4);

    Console.WriteLine($"dot: {vfloat4.Dot(a, b)}");
    Console.WriteLine($"sum: {a.Sum}, squared: {a.LengthSquared}, length: {new vfloat2(3, 4).Length}");
    Console.WriteLine($"distance: {vfloat3.Distance(new vfloat3(1, 1, 1), new vfloat3(3, 4, 7))}");
    Console.WriteLine($"normalized: {vfloat2.Normalize(new vfloat2(0, 5))}");
    Console.WriteLine($"cross: {vfloat3.Cross(new vfloat3(1, 0, 0), new vfloat3(0, 1, 0))} {vdouble3.Cross(new vdouble3(1, 2, 3), new vdouble3(4, 5, 6))}");

    Console.WriteLine($"min: {vfloat4.Min(a, b)}, max: {vfloat4.Max(a, b)}");
    Console.WriteLine($"clamp: {vfloat4.Clamp(a, -1, 2)}");
    Console.WriteLine($"abs: {vfloat4.Abs(a)} {vint4.Abs(new vint4(-3, 3, 0, -2147483647))}");
    Console.WriteLine($"sqrt: {vfloat4.Sqrt(new vfloat4(1, 4, 9, 2.25f))}");
    Console.WriteLine($"rounding: {vfloat4.Floor(new vfloat4(1.5f, -1.5f, 2.5f, -0.5f))} {vfloat4.Ceiling(new vfloat4(1.5f, -1.5f, 2.5f, -0.5f))} {vfloat4.Round(new vfloat4(1.5f, -1.5f, 2.5f, -0.5f))} {vfloat4.Truncate(new vfloat4(1.5f, -1.5f, 2.5f, -0.5f))}");
    Console.WriteLine($"fma: {vfloat2.FusedMultiplyAdd(new vfloat2(2, 3), new vfloat2(4, 5), new vfloat2(1))}");
    Console.WriteLine($"lerp: {vfloat2.Lerp(new vfloat2(0, 10), new vfloat2(10, 20), 0.25f)}");

    vint4 less = vfloat4.LessThan(a, b);
    Console.WriteLine($"less: {less}, all: {vint4.All(less)}, any: {vint4.Any(less)}");
    Console.WriteLine($"equal: {vfloat4.Equal(a, a)} {vint4.All(vfloat4.Equal(a, a))}");
    Console.WriteLine($"selected: {vfloat4.Select(less, a, b)}");
    Console.WriteLine($"unsigned order: {vuint2.GreaterThan(new vuint2(4000000000, 1), new vuint2(1, 2))}");
    Console.WriteLine($"masks of bytes: {vbyte4.LessThanOrEqual(new vbyte4(200, 1, 7, 9), new vbyte4(100))}");

    Console.WriteLine($"integer dot: {vint3.Dot(new vint3(1, 2, 3), new vint3(4, 5, 6))}, min: {vuint2.Min(new vuint2(4000000000, 7), new vuint2(5, 9))}");
    Console.WriteLine($"constants: {vfloat3.Zero} {vdouble2.One} {vbyte4.One}");
    return 0;
}
