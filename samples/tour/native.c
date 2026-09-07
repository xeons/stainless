/* SPDX-License-Identifier: 0BSD
 *
 * The C half of the tour (spec section 8). It is compiled alongside the .sl
 * files -- `stainless build` picks up every .c in the directory -- and it goes
 * both ways: Stainless calls in here, and this file calls back out through a
 * delegate and through an `export "C"` function.
 */

/* Declared in Platform.sl as `export "C" int tour_triple(int)`. */
int tour_triple(int value);

/* A delegate is one function pointer with the C calling convention, so a
 * plain function pointer parameter is what it arrives as. */
int c_apply_twice(int (*f)(int), int value) { return f(f(value)); }

/* A struct of plain data crosses by value, laid out exactly as C lays it out. */
struct PlainPair { int a; int b; };

int c_sum_pair(struct PlainPair pair)
{
    /* Calling back into Stainless from C, which is what the export table is
     * for. */
    return tour_triple(pair.a + pair.b);
}
