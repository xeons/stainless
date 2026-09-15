/*
 * The C half: three functions and a way to look one up by name.
 *
 * This is what a dynamic loader hands back. Nothing here includes stainless.h,
 * and nothing here is called directly by the Stainless side -- the only thing
 * it exports is `lookup`, which answers a `void*` exactly as GetProcAddress and
 * dlsym do. So the test is the real shape: a pointer of unknown provenance,
 * cast to a delegate, and called.
 *
 * Two of the three are __stdcall on x86, which is where the convention is the
 * whole test. A __stdcall callee removes the arguments, so calling one through
 * a cdecl pointer loses the stack rather than a value -- the failure is a crash
 * or a wrong answer several calls later, never a diagnostic.
 */
#include <stdint.h>
#include <string.h>

#if defined(__i386__) || defined(_M_IX86)
#  if defined(_MSC_VER) || defined(__clang__)
#    define WINDOWSISH __stdcall
#  else
#    define WINDOWSISH __attribute__((stdcall))
#  endif
#else
#  define WINDOWSISH
#endif

/* Plenty of arguments, because the convention decides who removes them and one
 * argument would hide a four-byte mistake. */
int WINDOWSISH scaled_sum(int a, int b, int c, int d)
{
    return (a + b + c + d) * 2;
}

int WINDOWSISH difference(int a, int b)
{
    return a - b;
}

/* The platform's own convention, to prove the two are kept apart rather than
 * both being emitted the same way. */
int plain_product(int a, int b)
{
    return a * b;
}

void *lookup(const char *name)
{
    if (strcmp(name, "scaled_sum") == 0)   return (void *)scaled_sum;
    if (strcmp(name, "difference") == 0)   return (void *)difference;
    if (strcmp(name, "plain_product") == 0) return (void *)plain_product;
    return 0;
}
