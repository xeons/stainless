/* The C side. Each keyword is the real one, so clang decides the convention. */

#if defined(_WIN32) || defined(__i386__)
#  define STD  __stdcall
#  define FAST __fastcall
#  define VEC  __vectorcall
#  define CDL  __cdecl
#else
#  define STD
#  define FAST
#  define VEC
#  define CDL
#endif

int STD  add_stdcall(int a, int b)    { return a + b; }
int FAST add_fastcall(int a, int b)   { return a + b; }
int VEC  add_vectorcall(int a, int b) { return a + b; }
int CDL  add_cdecl(int a, int b)      { return a + b; }

/* Digits in order, so an argument that arrives in the wrong slot is visible. */
int STD five_stdcall(int a, int b, int c, int d, int e)
{
    return a * 10000 + b * 1000 + c * 100 + d * 10 + e;
}

int FAST five_fastcall(int a, int b, int c, int d, int e)
{
    return a * 10000 + b * 1000 + c * 100 + d * 10 + e;
}

long long STD wide_stdcall(long long a, int b) { return a + b; }
