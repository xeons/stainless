// `T[N]`: an inline fixed-size array, laid out where it is written.
//
// This is C's array, not C#'s. A `T[]` is a reference to a counted heap object;
// a `T[N]` *is* its elements, so a struct holding one is exactly as wide as the
// C struct it mirrors. Every size and offset below was read off clang.
module FixedArrays;

import Standard.Console;

public const int MaxPath = 260;

/// `WIN32_FIND_DATAW`, which is the struct that could not be written before:
/// it ends in two inline `WCHAR` arrays and its size, 592, is what Windows
/// expects to fill.
public struct FindData {
    public uint            Attributes;
    public uint            CreatedLow;
    public uint            CreatedHigh;
    public uint            AccessedLow;
    public uint            AccessedHigh;
    public uint            WrittenLow;
    public uint            WrittenHigh;
    public uint            SizeHigh;
    public uint            SizeLow;
    public uint            Reserved0;
    public uint            Reserved1;
    public char16[MaxPath] FileName;
    public char16[14]      AlternateName;
}

public struct Matrix { public double[9] Cell; }

/// Nested lengths, which C writes outermost-first after the name.
public struct Grid { public int[3][2] Rows; }

void Show(String name, nuint value) {
    Console.WriteLine(name + " = " + Text.FromInteger(value));
}

/// An inline array cannot be passed by value — C decays one to a pointer and
/// copying every element would be neither that nor cheap — so `ref` is how it
/// crosses, which is `int (*)[9]` on both sides.
double Total(ref Matrix matrix) {
    double sum = 0.0;
    for (nuint i = 0u; i < matrix.Cell.Length; i = i + 1u) { sum = sum + matrix.Cell[i]; }
    return sum;
}

int Main() {
    // --- layout ------------------------------------------------------------
    Show("sizeof(FindData)", sizeof(FindData));
    Show("alignof(FindData)", alignof(FindData));
    Show("offsetof(FileName)", offsetof(FindData, FileName));
    Show("offsetof(AlternateName)", offsetof(FindData, AlternateName));

    Show("sizeof(Matrix)", sizeof(Matrix));
    Show("alignof(Matrix)", alignof(Matrix));
    Show("sizeof(Grid)", sizeof(Grid));

    // --- the length is part of the type ------------------------------------
    //
    // So it is a constant, not a load, and it is known without a value to ask.
    FindData data;
    Show("FileName.Length", data.FileName.Length);
    Show("AlternateName.Length", data.AlternateName.Length);

    // --- reading and writing -----------------------------------------------
    data.Attributes = 16u;
    data.FileName[0] = 104u;    // h
    data.FileName[1] = 105u;    // i
    data.FileName[2] = 0u;
    Console.WriteLine("name: " + Text.FromNullTerminatedUtf16(&data.FileName[0]));

    Matrix m;
    for (nuint i = 0u; i < m.Cell.Length; i = i + 1u) { m.Cell[i] = (double)i * 2.0; }
    Console.WriteLine("total: " + Text.FromDouble(Total(ref m)));

    // --- it is a value, so a copy is a copy ---------------------------------
    Matrix copy = m;
    copy.Cell[0] = 99.0;
    Console.WriteLine("original " + Text.FromDouble(m.Cell[0])
        + ", copy " + Text.FromDouble(copy.Cell[0]));

    // --- a bare local -------------------------------------------------------
    int[4] counters;
    counters[0] = 1;
    counters[3] = 8;
    Console.WriteLine("counters: " + Text.FromInteger((long)counters[0])
        + " " + Text.FromInteger((long)counters[3]));

    // --- nested -------------------------------------------------------------
    Grid grid;
    grid.Rows[1][2] = 7;
    Console.WriteLine("grid[1][2] = " + Text.FromInteger((long)grid.Rows[1][2]));
    Console.WriteLine("outer length " + Text.FromInteger(grid.Rows.Length)
        + ", inner length " + Text.FromInteger(grid.Rows[0].Length));

    // --- `new T[n]` is still a heap array ------------------------------------
    var heap = new int[10];
    heap[9] = 3;
    Console.WriteLine("heap array length " + Text.FromInteger(heap.Length)
        + ", last " + Text.FromInteger((long)heap[9]));
    return 0;
}
