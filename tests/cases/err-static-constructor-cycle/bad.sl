// SPDX-License-Identifier: 0BSD
//
// Each type's static constructor reads the other's statics, so each type
// would have to be set up before the other.
module ErrStaticConstructorCycle;

class First
{
    public static int Value = 1;
    static First() { Value = Second.Value + 1; }
}

class Second
{
    public static int Value = 2;
    static Second() { Value = First.Value + 1; }
}

int Main() => 0;
