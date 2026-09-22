// SPDX-License-Identifier: 0BSD
module Counter;

extern "C" int printf(byte* format, ...);

class Cell
{
    int _value;

    Cell(int start)
    {
        _value = start;
    }

    ~Cell()
    {
        printf("  ~Cell(%d)\n", _value);
    }

    public int Value => _value;
    public void Increment() => _value++;
}

int Main()
{
    printf("start\n");
    var a = new Cell(41);
    a.Increment();
    printf("  a = %d\n", a.Value);

    var b = a;
    b.Increment();
    printf("  a = %d (b is the same object)\n", a.Value);

    printf("end\n");
    return 0;
}
