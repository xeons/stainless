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

    public int Get() => _value;
    public void Bump() => _value += 1;
}

int Main()
{
    printf("start\n");
    var a = new Cell(41);
    a.Bump();
    printf("  a = %d\n", a.Get());

    var b = a;
    b.Bump();
    printf("  a = %d (b is the same object)\n", a.Get());

    printf("end\n");
    return 0;
}
