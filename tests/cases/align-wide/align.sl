// A struct aligned past the sixteen bytes malloc promises -- a cache line, a
// page -- is on its boundary wherever it lives: a local, a static, a field of
// an object, an array's elements, what a closure captured. The heap ones are
// placed by the runtime; every address is checked, not assumed.
module AlignWide;

import Standard.Console;

[Align(64)]
public struct Line
{
    public long Tag;
    public double Value;
}

[Align(4096)]
public struct Page
{
    public int First;
}

public class Holder
{
    public byte Before;
    public Line Line;
    public Holder() { Before = 1; }
}

extern "C"
{
    nuint line_size();
    nuint line_align();
    nuint page_size();
    double line_value(Line* line);
}

static Line Shared = default(Line);

bool OnBoundary(void* address, nuint alignment) => (nuint)address % alignment == 0;

int Main()
{
    Console.WriteLine($"layout agrees: {sizeof(Line) == line_size() && alignof(Line) == line_align() && sizeof(Page) == page_size()}");

    Line local;
    local.Value = 2.5;
    Page page;
    page.First = 7;
    Console.WriteLine($"local {OnBoundary(&local, 64)}, page {OnBoundary(&page, 4096)}, static {OnBoundary(&Shared, 64)}");
    Console.WriteLine($"C reads it {line_value(&local)}");

    // Objects and arrays come from the runtime, placed on the boundary.
    bool fields = true;
    for (int i = 0; i < 100; i++)
    {
        var holder = new Holder();
        holder.Line.Value = i;
        fields = fields && OnBoundary(&holder.Line, 64) && holder.Line.Value == i;
    }
    Console.WriteLine($"a field of a hundred objects {fields}");

    var lines = new Line[9];
    bool elements = true;
    for (int i = 0; i < 9; i++)
        elements = elements && OnBoundary(&lines[i], 64);
    var pages = new Page[3];
    Console.WriteLine($"array elements {elements}, pages {OnBoundary(&pages[0], 4096) && OnBoundary(&pages[2], 4096)}");

    // A closure holds what it captured in an object of its own.
    Line captured;
    captured.Value = 4.5;
    var read = () => captured.Value;
    Console.WriteLine($"captured {read()}");
    return 0;
}
