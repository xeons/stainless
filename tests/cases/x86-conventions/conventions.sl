// A calling convention is only real if a C function compiled with it can be
// called. Each of these is defined in cconv.c with the matching keyword, so a
// convention the compiler gets wrong is a link error or a wrong answer rather
// than something that merely parsed.
module ConventionProbe;

extern "C" int printf(byte* format, ...);

extern "C" __stdcall    int add_stdcall(int a, int b);
extern "C" __fastcall   int add_fastcall(int a, int b);
extern "C" __vectorcall int add_vectorcall(int a, int b);
extern "C" __cdecl      int add_cdecl(int a, int b);

// More arguments than the two a fastcall keeps in registers, so the rest have
// to reach the stack in the right order.
extern "C" __stdcall  int five_stdcall(int a, int b, int c, int d, int e);
extern "C" __fastcall int five_fastcall(int a, int b, int c, int d, int e);

// A `long long` is two stack slots on x86, which is what the decorated byte
// count has to account for.
extern "C" __stdcall long wide_stdcall(long a, int b);

int Main() {
    printf("stdcall     = %d   (want 7)\n", add_stdcall(3, 4));
    printf("fastcall    = %d   (want 7)\n", add_fastcall(3, 4));
    printf("vectorcall  = %d   (want 7)\n", add_vectorcall(3, 4));
    printf("cdecl       = %d   (want 7)\n", add_cdecl(3, 4));

    printf("five std    = %d  (want 54321)\n", five_stdcall(5, 4, 3, 2, 1));
    printf("five fast   = %d  (want 54321)\n", five_fastcall(5, 4, 3, 2, 1));

    printf("wide std    = %d  (want 1007)\n", (int)wide_stdcall(1000, 7));
    return 0;
}
