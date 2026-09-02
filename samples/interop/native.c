/* SPDX-License-Identifier: 0BSD */
/* Plain C. No Stainless header exists, because Stainless has no headers --
   these declarations are the ordinary C ones you would write for any library. */
#include <stdio.h>

typedef struct Point { double X; double Y; } Point;
typedef struct Pair  { int A; int B; } Pair;

/* Defined in Stainless with export "C". */
Point  sl_scale(Point p, double factor);
int    sl_add_pair(Pair p);
double sl_hypot_sq(double x, double y);

/* Called from Stainless with extern "C". */
Point c_make_point(double x, double y)
{
    Point p = { x, y };
    printf("  [C]  c_make_point(%g, %g)\n", x, y);
    return p;
}

void c_report(const char *label, Point p)
{
    printf("  [C]  %s = (%g, %g)\n", label, p.X, p.Y);
}

void c_drive(void)
{
    Point p = c_make_point(1.5, 2.5);
    Point scaled = sl_scale(p, 4.0);           /* struct in and out, across the boundary */
    c_report("scaled by Stainless", scaled);

    Pair pair = { 40, 2 };
    printf("  [C]  sl_add_pair({40,2}) = %d\n", sl_add_pair(pair));
    printf("  [C]  sl_hypot_sq(3,4)    = %g\n", sl_hypot_sq(3.0, 4.0));
}
