/* The C side: C's own va_arg and vsnprintf, and calls into Stainless's variadics. */
#include <stdarg.h>
#include <stdio.h>

long long sl_sum(int count, ...);
double sl_mixed(int count, ...);
long long sl_forward(int count, ...);

/* Twelve integers: past the six System V and the eight AAPCS registers. */
long long call_sum(void) { return sl_sum(12, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12); }

/* Ten doubles between ten integers: past the eight SSE and eight SIMD registers. */
double call_mixed(void)
{
    return sl_mixed(10, 1LL, 0.5, 2LL, 0.25, 3LL, 0.125, 4LL, 1.0, 5LL, 2.0,
                    6LL, 4.0, 7LL, 8.0, 8LL, 16.0, 9LL, 32.0, 10LL, 64.0);
}

long long call_forward(void) { return sl_forward(3, 100, 200, 300); }

/* Read with C's own va_arg, from a list Stainless started. */
long long c_vsum(int count, va_list ap)
{
    long long total = 0;
    for (int i = 0; i < count; i++)
        total += va_arg(ap, int);
    return total;
}

int c_format(char *buffer, size_t size, const char *format, va_list ap)
{
    return vsnprintf(buffer, size, format, ap);
}
