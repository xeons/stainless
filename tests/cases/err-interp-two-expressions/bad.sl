// SPDX-License-Identifier: 0BSD
module Bad;

// A hole holds one expression. Two would mean the second was silently dropped.
int Main() {
    int a = 1;
    int b = 2;
    String written = $"both {a b}";
    return (int)written.ByteLength();
}
