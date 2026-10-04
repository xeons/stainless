/* What clang makes of a struct aligned to a cache line and to a page. */
#include <stddef.h>

typedef struct { _Alignas(64) long long tag; double value; } Line;
typedef struct { _Alignas(4096) int first; } Page;

size_t line_size(void)  { return sizeof(Line); }
size_t line_align(void) { return _Alignof(Line); }
size_t page_size(void)  { return sizeof(Page); }
double line_value(const Line *line) { return line->value; }
