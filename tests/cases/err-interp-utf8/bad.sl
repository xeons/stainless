// SPDX-License-Identifier: 0BSD
module Bad;

// `u8` names bytes fixed when the program compiles, and an interpolation is
// built when it runs.
int Main()
{
    int n = 1;
    ReadOnlySpan<byte> bytes = $"n = {n}"u8;
    return (int)bytes.Length;
}
