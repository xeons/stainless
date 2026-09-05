// SPDX-License-Identifier: 0BSD
module Bad;

// A lambda has no type of its own -- it becomes whatever it is assigned to --
// and `var` is the one place with nothing to tell it what that is.
//
// This used to bind cleanly and emit `store ptr 0`, which clang rejected as a
// compiler bug rather than as the mistake it is.
int Main() {
    var f = x => x;
    return 0;
}
