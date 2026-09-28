// SPDX-License-Identifier: 0BSD
module Bad;

public struct Rect
{
    public int Width { get; set; }

    // No constructor is declared, so nothing could ever fill this in.
    public int Height { get; }
}

int Main() => 0;
