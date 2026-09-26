// SPDX-License-Identifier: 0BSD
module Bad;

// A number's format is checked where it is written: `Q` is no standard
// format, a double has no hexadecimal, and a String takes no format at all.
int Main()
{
    int n = 1;
    double d = 2.0;
    String s = $"{n:Q} {d:X} {"text":D}";
    return (int)s.ByteLength();
}
