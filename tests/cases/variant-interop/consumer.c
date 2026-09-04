/* SPDX-License-Identifier: 0BSD */
/* Reading a Stainless variant from C: check the tag, then read the payload
   through a struct of that case's fields. Nothing is generated for this; the
   header states the layout and the C rules do the rest. */
#include <stdio.h>
#include <string.h>
#include "library.h"

struct circle { double radius; };
struct rect { double width, height; };

int main(void)
{
    Library_Shapes_Shape circle = MakeCircle(2.0);
    Library_Shapes_Shape rect = MakeRect(3.0, 4.0);
    Library_Shapes_Shape empty = MakeEmpty();

    printf("sizeof=%d align=%d\n",
           (int)sizeof(Library_Shapes_Shape), (int)_Alignof(Library_Shapes_Shape));
    printf("tags=%d,%d,%d\n", circle.tag, rect.tag, empty.tag);

    struct circle c;
    memcpy(&c, circle.payload, sizeof c);
    printf("radius=%g\n", c.radius);

    struct rect r;
    memcpy(&r, rect.payload, sizeof r);
    printf("rect=%g,%g\n", r.width, r.height);

    /* And back the other way: a variant built in C, handed to Stainless. */
    Library_Shapes_Shape made;
    memset(&made, 0, sizeof made);
    made.tag = 1;
    struct rect eight = { 2.0, 4.0 };
    memcpy(made.payload, &eight, sizeof eight);

    printf("area=%g %g %g\n", Area(circle), Area(rect), Area(made));
    return 0;
}
