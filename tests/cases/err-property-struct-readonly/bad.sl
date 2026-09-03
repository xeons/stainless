// SPDX-License-Identifier: 0BSD
module Bad;

public struct Rect {
    public int Width { get; set; }

    // A struct has no constructor, so nothing could ever fill this in.
    public int Height { get; }
}

int Main() { return 0; }
