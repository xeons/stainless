/* SPDX-License-Identifier: 0BSD */
/* An ordinary C program, built against the generated header. */
#include <stdio.h>
#include "library.h"

int main(void)
{
    printf("add=%d\n", Add(40, 2));

    Library_Math_Point p = { 1.5, 2.5 };
    Library_Math_Point scaled = Scale(p, 4.0);
    printf("scale=%g,%g\n", scaled.X, scaled.Y);

    Library_Math_Pair pair = { 20, 22 };
    printf("pair=%d\n", SumPair(pair));
    return 0;
}
