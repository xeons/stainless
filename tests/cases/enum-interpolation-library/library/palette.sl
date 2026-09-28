// SPDX-License-Identifier: 0BSD
//
// Enums a consumer knows only from the metadata: their members' names, and
// whether they are flags.
module Library.Palette;

public enum Colour : short { Red = -1, Green, Blue }

[Flags]
public enum Access
{
    None = 0,
    Read = 1,
    Write = 2,
    Execute = 4,
}

public String DescribeAccess(Access access) => $"library {access}";
