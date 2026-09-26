// SPDX-License-Identifier: 0BSD
module Bad;

// A ':' in a hole starts its format, so a conditional has to be in
// parentheses, as in C#.
int Main()
{
    bool b = true;
    String s = $"{b ? 1 : 2}";
    return (int)s.ByteLength();
}
