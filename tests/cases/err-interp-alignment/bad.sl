// SPDX-License-Identifier: 0BSD
module Bad;

// An alignment is a constant, as in C#; a width known only at run time is
// `Text.AlignText`.
int Main()
{
    int n = 1;
    int width = 8;
    String s = $"{n,width}";
    return (int)s.ByteLength();
}
