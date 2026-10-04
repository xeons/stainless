// SIMD vectors: made, read by lane and by swizzle, written, and operated on
// lane by lane.
module SimdBasics;

import Standard.Console;

void Show(String label, vfloat4 v) =>
    Console.WriteLine($"{label}: {v.x} {v.y} {v.z} {v.w}");

void ShowInts(String label, vint4 v) =>
    Console.WriteLine($"{label}: {v[0]} {v[1]} {v[2]} {v[3]}");

int Main()
{
    vfloat4 a = new vfloat4(1, 2, 3, 4);
    vfloat4 b = new vfloat4(0.5f);
    Show("made", a);
    Show("filled", b);
    Show("zero", new vfloat4());

    Show("sum", a + b);
    Show("difference", a - b);
    Show("product", a * b);
    Show("quotient", a / new vfloat4(2));
    Show("scaled", a * 10);
    Show("scaled first", 2 * a);
    Show("negated", -a);

    vfloat3 back = a.zyx;
    Console.WriteLine($"swizzled: {back.x} {back.y} {back.z}");
    vfloat4 joined = new vfloat4(back, 9);
    Show("joined", joined);
    vfloat4 halves = new vfloat4(a.lo, a.hi.yx);
    Show("halves", halves);

    vfloat4 c = a;
    c.x = 100;
    c.zw = new vfloat2(7, 8);
    c.y += 0.25f;
    Show("written", c);
    c.xy += new vfloat2(1, 1);
    Show("added to lanes", c);
    c *= 2;
    Show("compound", c);

    for (int i = 0; i < 4; i++)
        c[i] = i * 3;
    Show("by index", c);

    Console.WriteLine($"equal: {a == new vfloat4(1, 2, 3, 4)}, unequal: {a != b}, same: {a != a}");

    vint4 n = new vint4(7, -8, 9, 10);
    ShowInts("ints", n);
    ShowInts("divided", n / new vint4(2));
    ShowInts("remainder", n % 3);
    ShowInts("masked", n & 6);
    ShowInts("shifted", n << 2);
    ShowInts("arithmetic shift", n >> 1);
    ShowInts("unsigned shift", n >>> 28);
    ShowInts("complement", ~n);

    vbyte16 bytes = new vbyte16(250);
    bytes += new vbyte16(10);
    Console.WriteLine($"bytes wrap: {bytes[0]} {bytes[15]}");

    vdouble2 d = new vdouble2(1.5, 2.5);
    vdouble2 squared = d * d;
    Console.WriteLine($"doubles: {squared.x} {squared.y}");

    Console.WriteLine($"sizes: {sizeof(vfloat3)} {sizeof(vfloat4)} {sizeof(vbyte64)} {sizeof(vdouble3)}");
    return 0;
}
