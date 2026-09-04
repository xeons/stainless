/* SPDX-License-Identifier: 0BSD */
#include <stdio.h>
#include <stddef.h>
#include <string.h>
#include "library.h"

#define SAME(what, a, b) \
    do { if ((size_t)(a) != (size_t)(b)) { \
        printf("%s: stainless %d, C %d\n", what, (int)(a), (int)(b)); ok = 0; } } while (0)

int main(void)
{
    int ok = 1;

    /* The header is what states the layout, so this compares what Stainless
       computed against what the C compiler made of the header it wrote. */
    SAME("Plain size", PlainSize(), sizeof(Library_Layout_Plain));
    SAME("Wire size",  WireSize(),  sizeof(Library_Layout_Wire));
    SAME("Wide size",  WideSize(),  sizeof(Library_Layout_Wide));
    SAME("Both size",  BothSize(),  sizeof(Library_Layout_Both));

    printf("sizes=%d %d %d %d\n",
           (int)sizeof(Library_Layout_Plain), (int)sizeof(Library_Layout_Wire),
           (int)sizeof(Library_Layout_Wide), (int)sizeof(Library_Layout_Both));

    printf("aligns=%d %d %d %d\n",
           (int)_Alignof(Library_Layout_Plain), (int)_Alignof(Library_Layout_Wire),
           (int)_Alignof(Library_Layout_Wide), (int)_Alignof(Library_Layout_Both));

    printf("plain=%d %d %d\n",
           (int)offsetof(Library_Layout_Plain, Tag),
           (int)offsetof(Library_Layout_Plain, Value),
           (int)offsetof(Library_Layout_Plain, Trailer));

    printf("wire=%d %d %d\n",
           (int)offsetof(Library_Layout_Wire, Tag),
           (int)offsetof(Library_Layout_Wire, Value),
           (int)offsetof(Library_Layout_Wire, Trailer));

    /* And a value built here, read there: the offsets have to agree in both
       directions or these come back wrong. */
    Library_Layout_Wire wire;
    memset(&wire, 0, sizeof wire);
    wire.Tag = 7;
    wire.Value = 123456;
    wire.Trailer = 9;

    Library_Layout_Wide wide;
    wide.X = 1.0;
    wide.Y = 2.5;

    printf("read=%d %d %g\n", WireValue(wire), (int)WireTrailer(wire), WideY(wide));
    printf("agree=%s\n", ok ? "yes" : "no");
    return 0;
}
