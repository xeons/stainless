// SPDX-License-Identifier: 0BSD
//
// `x op= y` on a narrow integer is `x = (T)(x op y)`, as in C#: the operator
// works at `int` and the result is cast back, provided `y` itself fits `x` or
// the operator is a shift. The cast wraps, as every integer cast does.
module CompoundNarrowing;

import Standard.Console;

class Counter
{
    public byte Small { get; set; }
    public short[] Cells = new short[2];
}

struct Pixel
{
    public byte R;
    public byte G;
}

public int Main()
{
    byte b = 250;
    b += 10;
    b -= 1;
    Console.WriteLine($"byte {b}");

    short s = 30000;
    short step = 10000;
    s += step;
    Console.WriteLine($"short {s}");

    ushort us = 1;
    us <<= 17;
    ushort mask = 0xFFFF;
    mask >>= 4;
    mask &= 0x0F0F;
    Console.WriteLine($"ushort {us} {mask}");

    sbyte sb = -128;
    sb /= -1;
    sbyte half = 100;
    half *= 2;
    Console.WriteLine($"sbyte {sb} {half}");

    char c = 'a';
    c += (char)2;
    c++;
    Console.WriteLine($"char {(char32)c}");

    // A property, an element and a field of a struct.
    var counter = new Counter();
    counter.Small = 255;
    counter.Small += 2;
    counter.Cells[1] = 32767;
    counter.Cells[1] += 1;
    Pixel pixel;
    pixel.R = 200;
    pixel.G = 7;
    pixel.R += pixel.G;
    pixel.G |= 0x80;
    Console.WriteLine($"{counter.Small} {counter.Cells[1]} {pixel.R} {pixel.G}");
    return 0;
}
