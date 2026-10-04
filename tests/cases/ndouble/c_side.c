/* The C side: whatever clang makes of long double for this target is the answer. */
#include <stddef.h>

typedef struct { int tag; long double value; } Tagged;

size_t      ld_size(void)               { return sizeof(long double); }
size_t      ld_align(void)              { return _Alignof(long double); }
size_t      tagged_size(void)           { return sizeof(Tagged); }
size_t      tagged_value_at(void)       { return offsetof(Tagged, value); }
long double ld_scale(long double x, int by) { return x * by; }
long double ld_third(void)              { return 1.0L / 3.0L; }
long double tagged_sum(Tagged t)        { return t.value + t.tag; }
Tagged      tagged_make(int tag)        { Tagged t; t.tag = tag; t.value = tag * 0.5L; return t; }
