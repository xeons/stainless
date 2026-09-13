// SPDX-License-Identifier: 0BSD
module Bad;

// A character literal is exactly one scalar, and an escape that names one is
// fixed width. Both were taken quietly before: '' became a zero, and a `\u`
// with two digits after it became U+0012 -- values that compile, run, and
// were written by nobody.

int Main() {
    var empty = '';
    var shortU = "\u12";
    var shortBigU = "\U0001F6";
    var noDigits = "\u";
    return 0;
}
