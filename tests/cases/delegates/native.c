/* SPDX-License-Identifier: 0BSD */

/* A Stainless delegate arrives as an ordinary C function pointer. */
typedef int (*Transform)(int value);

int c_apply(Transform f, int value)
{
    return f(value) + 1;
}

int c_sum_with(Transform f, int count)
{
    int total = 0;
    for (int i = 0; i < count; i += 1) total += f(i);
    return total;
}
