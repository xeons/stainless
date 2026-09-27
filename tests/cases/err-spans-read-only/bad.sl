// SPDX-License-Identifier: 0BSD
module Bad;

public struct Point
{
    public double X;
    public double Y { get; set; }
}

void Bump(ref int n) { }
void Fill(out int n) { n = 0; }
void Clear(Span<int> values) { }

int Main()
{
    int[] numbers = [1, 2, 3];
    ReadOnlySpan<int> seen = numbers;

    seen[0] = 5;
    seen[1] += 1;
    seen[2]++;
    seen[0:2][0] = 7;               // cutting one keeps it read-only

    Bump(ref seen[0]);
    Fill(out seen[1]);

    Point[] points = new Point[2];
    ReadOnlySpan<Point> shown = points;
    shown[0].X = 1.0;
    shown[1].Y = 2.0;

    // It does not become writable again on its own.
    Span<int> back = seen;
    Clear(seen);

    return 0;
}
