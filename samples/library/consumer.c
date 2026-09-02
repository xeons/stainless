/* SPDX-License-Identifier: 0BSD */
/*
 * An ordinary C program. It knows nothing about Stainless.
 *
 *   stainless build samples/library/src --shared  *       -o samples/library/build/stainless_math.dll  *       --header samples/library/build/stainless_math.h
 *
 *   clang samples/library/consumer.c samples/library/build/stainless_math.lib  *       -o samples/library/build/consumer.exe
 */
#include <stdio.h>
#include "build/stainless_math.h"

int main(void)
{
    printf("Add(40, 2)        = %d\n", Add(40, 2));
    printf("Hypotenuse(3, 4)  = %g\n", Hypotenuse(3.0, 4.0));

    Library_Math_Point p = { 1.5, 2.5 };
    Library_Math_Point scaled = Scale(p, 4.0);
    printf("Scale({1.5,2.5},4)= (%g, %g)\n", scaled.X, scaled.Y);

    Library_Math_Pair pair = { 20, 22 };
    printf("SumPair({20,22})  = %d\n", SumPair(pair));
    return 0;
}
