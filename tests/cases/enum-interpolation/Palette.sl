// SPDX-License-Identifier: 0BSD
//
// Enums declared in a module other than the one that writes them.
module Palette;

public enum Colour { Red, Green, Blue }

[Flags]
public enum Access : byte
{
    None = 0,
    Read = 1,
    Write = 2,
    ReadWrite = 3,
    Execute = 4,
}

public class Widget
{
    public enum State { Idle, Busy, Gone }
}
