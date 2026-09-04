/* SPDX-License-Identifier: 0BSD */
/* An ordinary C program, built against the generated header. */
#include <stdio.h>
#include "library.h"

static int bump(int value) { return value + 3; }

int main(void)
{
    printf("add=%d\n", Add(40, 2));

    Library_Math_Point p = { 1.5, 2.5 };
    Library_Math_Point scaled = Scale(p, 4.0);
    printf("scale=%g,%g\n", scaled.X, scaled.Y);

    Library_Math_Pair pair = { 20, 22 };
    printf("pair=%d\n", SumPair(pair));

    /*
     * The handle is opaque here exactly as it is there: the header declares the
     * tag and never defines it, so C can hold one and pass it back and cannot
     * look inside. The typedef is the same one the Stainless source writes.
     */
    int cells[3] = { 10, 20, 30 };
    Library_Math_Slot slot = SlotAt(cells, 1);
    printf("slot=%d\n", SlotRead(slot));

    printf("measure=%d\n", (int)Measure((uint8_t*)"handles"));
    printf("bumped=%d\n", bump(SlotRead(slot)));
    return 0;
}
