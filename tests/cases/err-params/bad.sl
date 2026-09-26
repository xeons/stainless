// SPDX-License-Identifier: 0BSD
module Bad;

// `params` goes on the last parameter, by value, with no default, and it
// gathers into an array or a slice. A delegate has no declaration to gather
// against, and C has no such thing.
int NotLast(params int[] values, int after) => after;
int ByRef(ref params int[] values) => 0;
int Defaulted(params int[] values = null) => 0;
int NotAnArray(params int value) => value;
public delegate int Summing(params int[] values);
export "C" int Exported(params int[] values) => 0;

int Sum(params int[] values) => 0;

int Main()
{
    // An element that does not fit is reported against the element.
    return Sum(1, "two");
}
