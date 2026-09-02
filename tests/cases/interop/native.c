/* SPDX-License-Identifier: 0BSD */
#include <stdio.h>

typedef struct Point { double X; double Y; } Point;
typedef struct Pair  { int A; int B; } Pair;

Point  sl_scale(Point p, double factor);
int    sl_add_pair(Pair p);

Point c_make_point(double x, double y)
{
    Point p = { x, y };
    return p;
}

void c_drive(void)
{
    Point p = c_make_point(1.5, 2.5);
    Point scaled = sl_scale(p, 4.0);
    printf("c:scaled=%g,%g\n", scaled.X, scaled.Y);

    Pair pair = { 40, 2 };
    printf("c:pair=%d\n", sl_add_pair(pair));
}
