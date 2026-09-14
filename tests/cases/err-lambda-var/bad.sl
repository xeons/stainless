// SPDX-License-Identifier: 0BSD
module Bad;

// A lambda that has not said what its parameters are has nothing for `var` to
// infer from, and neither has one whose result is whatever its `return`s agree
// on. `(int x) => x * 2` says enough and is a `var` of its own type; these two
// do not.
//
// The first used to bind cleanly and emit `store ptr 0`, which clang rejected
// as a compiler bug rather than as the mistake it is.
int Main() {
    var f = x => x;
    var g = (int x) => { return x * 2; };
    return 0;
}
