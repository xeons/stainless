// SPDX-License-Identifier: 0BSD
//
// The refusals that happen while reading the word `static`, rather than while
// working out what it meant. They are in a case of their own because a file
// that does not parse never reaches the binder, so a parse refusal would hide
// every other one.
module ErrStaticModifier;

// SL0578: only a class has instances for the word to be denying. A module is
// what this language has instead of a static class anyway, and it is better --
// a module is a scope, so its members need no prefix inside it.
public static struct Holder { public int x; }
public static interface IHolder { int Read(); }
public static enum Level { Low, High }
public static delegate void Notify(int value);

// SL0376: a static is written by its initializer, and there is no later moment
// at which one could be given a first value.
static int Counter;
