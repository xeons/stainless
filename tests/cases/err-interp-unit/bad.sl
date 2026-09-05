// SPDX-License-Identifier: 0BSD
module Bad;

// A `char` is one UTF-8 code unit and a `char16` one UTF-16 unit. A unit is not
// a character -- which is the distinction SL0527 exists to keep everywhere else
// -- so an interpolation will not quietly cross it either.
int Main() {
    char letter = 'x';
    String written = $"letter {letter}";
    return (int)written.ByteLength();
}
