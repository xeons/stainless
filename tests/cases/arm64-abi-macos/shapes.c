/*
 * The same shapes in C, compiled for the same target by clang.
 *
 * Nothing builds this file: an assemble-only case has no program to run and no
 * consumer to link. It is here because ir.txt's expectations came from it.
 * Regenerate with any clang; assembling Darwin IR needs no SDK:
 *
 *   clang --target=arm64-apple-macosx13.0 -ffreestanding -S -emit-llvm -O0 shapes.c -o -
 *
 * An empty struct is zero bytes in C and one in Stainless, as in C++. Darwin
 * leaves both out, and clang++ writes the same declarations for it.
 */
struct Tri   { int A, B, C; };
struct Trio  { float A, B, C; };
struct Quad  { double A, B, C, D; };
struct Big   { long long A, B; signed char C; };
struct Twins { unsigned char *A, *B; };
struct Small { signed char A, B, C; };
struct Empty { };

int          sum_tri(struct Tri v);
float        sum_trio(struct Trio v);
double       sum_quad(struct Quad v);
long long    count_twins(struct Twins v);
long long    sum_big(struct Big v);
int          sum_small(struct Small v);

struct Small make_small(void);
struct Tri   make_tri(void);
struct Trio  make_trio(void);
struct Big   make_big(void);
struct Twins make_twins(void);

signed char    take_sbyte(signed char v);
unsigned char  take_byte(unsigned char v);
short          take_short(short v);
unsigned short take_ushort(unsigned short v);
_Bool          take_bool(_Bool v);
char           take_char(char v);
unsigned short take_char16(unsigned short v);   /* char16_t */
int            take_int(int v);

int          skip_empty(int a, struct Empty e, int b);
struct Empty make_empty(void);

int report(const char *format, ...);

short widen_byte(unsigned char v) { return v; }
_Bool is_negative(signed char v) { return v < 0; }
int between(int a, struct Empty e, int b) { return b - a; }

typedef unsigned short (*Narrowed)(signed char v);

void use(Narrowed through)
{
    struct Tri t; struct Trio r; struct Quad q; struct Big b;
    struct Twins w; struct Small s; struct Empty e;

    sum_tri(t); sum_trio(r); sum_quad(q); sum_big(b);
    count_twins(w); sum_small(s);
    make_small(); make_tri(); make_trio(); make_big(); make_twins();

    take_sbyte(-1); take_byte(200); take_short(-2); take_ushort(60000);
    take_bool(1); take_char('a'); take_char16('b'); take_int(3);

    skip_empty(1, e, 2); make_empty();
    through(-4);

    report("%d", r, s, b, 'c', 1.5f, (_Bool)1, (signed char)-5, e, 0);
}
