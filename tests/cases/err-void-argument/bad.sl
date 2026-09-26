// SPDX-License-Identifier: 0BSD
module Bad;

extern "C" int printf(byte* format, ...);

void Nothing() { }

int Main()
{
    // Nothing declares what a variadic argument must be, so 'void' has to
    // be refused as an argument rather than as a conversion.
    printf("%d\n", Nothing());

    // An array literal's elements settle its type, and 'void' is not one.
    var values = [1, Nothing()];
    return 0;
}
