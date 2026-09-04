// SPDX-License-Identifier: 0BSD
//
// A parse error of its own, because a parse error stops the compilation before
// anything is bound and would hide every other case's diagnostics.
module Bad;

int Main() {
    var numbers = new int[4];
    var nothing = numbers[];
    return 0;
}
