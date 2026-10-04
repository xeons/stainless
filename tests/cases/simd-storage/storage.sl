// SIMD vectors as values among others: converted, written as text, held in
// structs, classes, arrays, lists and statics, passed and returned.
module SimdStorage;

import Standard.Collections;
import Standard.Console;

public struct Particle
{
    public byte Tag;
    public vfloat4 Position;
    public vfloat2 Velocity;
}

public sealed class Body
{
    public sbyte Kind;
    public vdouble4 Momentum;
    public vlong8 Counters;
}

static vfloat4 s_origin = new vfloat4(0, 0, 0, 1);
static readonly vint4 s_steps = new vint4(1, 2, 3, 4);

vfloat4 Scale(vfloat4 v, float by) => v * by;

vfloat4 Accumulate(ref vfloat4 total, vfloat4 add)
{
    total += add;
    return total;
}

bool IsAligned(void* address, nuint alignment) => (nuint)address % alignment == 0;

int Main()
{
    vfloat4 f = new vfloat4(1.75f, -2.5f, 3e9f, -0.0f);
    Console.WriteLine($"floats: {f}");
    Console.WriteLine($"truncated: {(vint4)f}");
    Console.WriteLine($"unsigned: {(vuint4)new vfloat4(-1, 1, 5e9f, 2)}");
    Console.WriteLine($"widened: {(vlong4)new vint4(-1, 2, -3, 4)}");
    Console.WriteLine($"narrowed: {(vbyte4)new vint4(256, 257, -1, 300)}");
    Console.WriteLine($"to doubles: {(vdouble2)new vfloat2(0.5f, 0.25f)}");
    Console.WriteLine($"from ints: {(vfloat3)new vint3(1, -2, 3)}");
    Console.WriteLine($"formatted: {new vdouble2(3.14159, 2.71828):F2}");

    Particle p;
    p.Tag = 7;
    p.Position = new vfloat4(1, 2, 3, 4);
    p.Velocity = new vfloat2(0.5f, -0.5f);
    p.Position.y = 20;
    p.Position.xy += p.Velocity;
    Console.WriteLine($"particle: {p.Tag} {p.Position} {p.Velocity}");
    Console.WriteLine($"particle layout: {sizeof(Particle)} bytes, position at {offsetof(Particle, Position)}");

    var body = new Body();
    body.Momentum = new vdouble4(1, 2, 3, 4);
    body.Momentum.w = 40;
    body.Counters = new vlong8(5);
    body.Counters[7] = 70;
    Console.WriteLine($"body: {body.Momentum} {body.Counters}");
    Console.WriteLine($"momentum aligned: {IsAligned(&body.Momentum, alignof(vdouble4))}, counters aligned: {IsAligned(&body.Counters, alignof(vlong8))}");

    vfloat4[] path = new vfloat4[3];
    for (int i = 0; i < 3; i++)
        path[i] = new vfloat4(i) + s_origin;
    path[1].z = 9;
    Console.WriteLine($"path: {path[0]} {path[1]} {path[2]}");
    Console.WriteLine($"path aligned: {IsAligned(&path[1], alignof(vfloat4))}");

    var list = new List<vfloat3>();
    list.Add(new vfloat3(1, 2, 3));
    list.Add(new vfloat3(4, 5, 6));
    Console.WriteLine($"list: {list.Count} {list[0]} {list[1]}");

    s_origin.x = 5;
    Console.WriteLine($"statics: {s_origin} {s_steps}");

    vfloat4 total = new vfloat4();
    Accumulate(ref total, new vfloat4(1));
    vfloat4 after = Accumulate(ref total, Scale(new vfloat4(1, 2, 3, 4), 2));
    Console.WriteLine($"by reference: {total} {after}");

    vbyte64 wide = new vbyte64(3);
    wide[63] = 9;
    Console.WriteLine($"wide: {wide[0]} {wide[63]} {sizeof(vbyte64)} {alignof(vbyte64) >= 16}");
    return 0;
}
