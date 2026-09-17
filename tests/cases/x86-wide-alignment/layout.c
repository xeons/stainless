/* The C side: whatever clang makes of these on this target is the answer. */
#include <stddef.h>

typedef struct { int A; long long B; }               IntLong;
typedef struct { unsigned char A; double B; int C; } ByteDouble;
typedef struct { unsigned long long A; unsigned char B; } LongByte;
typedef struct { unsigned char A; IntLong I; }       Nested;

int c_layout(int which)
{
    switch (which)
    {
        case 0:  return (int)sizeof(IntLong);
        case 1:  return (int)offsetof(IntLong, B);
        case 2:  return (int)_Alignof(IntLong);
        case 3:  return (int)sizeof(ByteDouble);
        case 4:  return (int)offsetof(ByteDouble, B);
        case 5:  return (int)offsetof(ByteDouble, C);
        case 6:  return (int)sizeof(LongByte);
        case 7:  return (int)sizeof(Nested);
        case 8:  return (int)offsetof(Nested, I);
        default: return -1;
    }
}

/* Read through a pointer Stainless filled, and through a copy it pushed. */
long long c_read_nested(const Nested *n)  { return n->A + n->I.A + n->I.B; }
double    c_read_by_value(ByteDouble v)   { return v.A + v.B + v.C; }
