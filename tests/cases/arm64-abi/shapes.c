/*
 * The same shapes in C, compiled for the same target by clang.
 *
 * Nothing builds this file: an assemble-only case has no program to run and no
 * consumer to link. It is here because ir.txt's expectations came from it, and
 * a pinned signature with no stated source is a number somebody once believed.
 * Regenerate with:
 *
 *   clang --target=aarch64-unknown-linux-gnu -S -emit-llvm -O0 shapes.c -o -
 */
struct Tri   { int A, B, C; };
struct Trio  { float A, B, C; };
struct Quad  { double A, B, C, D; };
struct Big   { long long A, B; signed char C; };
struct Twins { unsigned char *A, *B; };
struct Small { signed char A, B, C; };

int          sum_tri(struct Tri v);
float        sum_trio(struct Trio v);
double       sum_quad(struct Quad v);
long long    sum_big(struct Big v);
long long    count_twins(struct Twins v);
int          sum_small(struct Small v);

struct Small make_small(void);
struct Tri   make_tri(void);
struct Trio  make_trio(void);
struct Quad  make_quad(void);
struct Big   make_big(void);
struct Twins make_twins(void);

void use(void)
{
    struct Tri t; struct Trio r; struct Quad q; struct Big b;
    struct Twins w; struct Small s;

    sum_tri(t); sum_trio(r); sum_quad(q); sum_big(b);
    count_twins(w); sum_small(s);
    make_small(); make_tri(); make_trio(); make_quad(); make_big(); make_twins();
}
