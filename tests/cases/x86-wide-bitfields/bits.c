/* The C side: whatever clang makes of these on this target is the answer. */
#include <string.h>

typedef struct { long long X : 3; int Y : 5; }                    A;
typedef struct { char C; long long X : 40; }                      B;
typedef struct { int I; long long X : 33; char D; }               C;
typedef struct { long long X : 30; long long Y : 30; int Z; }     D;
typedef struct { unsigned char C; unsigned long long X : 5; }     E;
typedef struct { int P : 20; long long Q : 20; }                  F;
typedef struct { char C; long long X : 3; }                       G;
typedef enum : long long { Big = 1 }                              Wide;
typedef struct { char C; Wide W; }                                H;

int c_size(int which)
{
    switch (which)
    {
        case 0: return (int)sizeof(A);
        case 1: return (int)sizeof(B);
        case 2: return (int)sizeof(C);
        case 3: return (int)sizeof(D);
        case 4: return (int)sizeof(E);
        case 5: return (int)sizeof(F);
        case 6: return (int)sizeof(G);
        case 7: return (int)sizeof(H);
        default: return -1;
    }
}

/* The bytes of each struct with the same values Stainless puts in its own. */
void c_fill(int which, unsigned char *into)
{
    switch (which)
    {
        case 0: { A v; memset(&v, 0, sizeof v); v.X = -1; v.Y = 9; memcpy(into, &v, sizeof v); break; }
        case 1: { B v; memset(&v, 0, sizeof v); v.C = 1; v.X = 0x123456789LL; memcpy(into, &v, sizeof v); break; }
        case 2: { C v; memset(&v, 0, sizeof v); v.I = 2; v.X = -0xABCDEFLL; v.D = 3; memcpy(into, &v, sizeof v); break; }
        case 3: { D v; memset(&v, 0, sizeof v); v.X = 0x1AAAAAAA; v.Y = 0x15555555; v.Z = 4; memcpy(into, &v, sizeof v); break; }
        case 4: { E v; memset(&v, 0, sizeof v); v.C = 5; v.X = 21; memcpy(into, &v, sizeof v); break; }
        case 5: { F v; memset(&v, 0, sizeof v); v.P = 0x12345; v.Q = 0x6789A; memcpy(into, &v, sizeof v); break; }
        case 6: { G v; memset(&v, 0, sizeof v); v.C = 6; v.X = 3; memcpy(into, &v, sizeof v); break; }
        case 7: { H v; memset(&v, 0, sizeof v); v.C = 7; v.W = Big; memcpy(into, &v, sizeof v); break; }
    }
}
