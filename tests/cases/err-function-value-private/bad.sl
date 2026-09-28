// SPDX-License-Identifier: 0BSD
//
// A function that is not public is no more a value outside its module than
// it is a call.
module Bad;

public delegate int Transform(int value);

int Main()
{
    Transform hidden = Numbers.Hidden;
    return hidden(1);
}
