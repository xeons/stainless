// SPDX-License-Identifier: 0BSD
module Bad;

int Main()
{
    int noDigits = 0x;          // a radix prefix and nothing after it
    int binary = 0b101f;        // a binary literal has no floating-point form
    var nonsense = 1lul;        // a run of suffix letters that is not a suffix
    var doubled = 1uu;
    var exponents = 1e5e5;      // two exponents, SLP0011
    return 0;
}
