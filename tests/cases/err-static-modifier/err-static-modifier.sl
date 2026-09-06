// SPDX-License-Identifier: 0BSD
//
// The two refusals that happen while reading the word `static`, rather than
// while working out what it meant. They are in a case of their own because a
// file that does not parse never reaches the binder, so a parse refusal would
// hide every other one.
module ErrStaticModifier;

// SL0578: a module is already what a static class would be, and a class that
// could hold no values would be one.
public static class Holder {
    public int x;
}

// SL0376: the other thing `static` introduces is storage, and storage has to
// be readonly because nothing would synchronize a mutable global.
static int Count = 0;
