module Counter;

extern "C" int printf(byte* format, ...);

class Cell {
    int value;

    Cell(int start) {
        value = start;
    }

    ~Cell() {
        printf("  ~Cell(%d)\n", value);
    }

    public int Get() { return value; }
    public void Bump() { value = value + 1; }
}

int Main() {
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
