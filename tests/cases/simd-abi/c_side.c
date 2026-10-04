/* The C side: whatever clang does with a vector on this target is the answer. */
typedef unsigned char vbyte2 __attribute__((ext_vector_type(2)));
typedef unsigned char vbyte3 __attribute__((ext_vector_type(3)));
typedef unsigned char vbyte8 __attribute__((ext_vector_type(8)));
typedef unsigned char vbyte64 __attribute__((ext_vector_type(64)));
typedef short vshort2 __attribute__((ext_vector_type(2)));
typedef short vshort3 __attribute__((ext_vector_type(3)));
typedef int vint2 __attribute__((ext_vector_type(2)));
typedef int vint4 __attribute__((ext_vector_type(4)));
typedef long long vlong3 __attribute__((ext_vector_type(3)));
typedef float vfloat2 __attribute__((ext_vector_type(2)));
typedef float vfloat3 __attribute__((ext_vector_type(3)));
typedef float vfloat4 __attribute__((ext_vector_type(4)));
typedef float vfloat8 __attribute__((ext_vector_type(8)));
typedef double vdouble2 __attribute__((ext_vector_type(2)));
typedef double vdouble3 __attribute__((ext_vector_type(3)));
typedef double vdouble4 __attribute__((ext_vector_type(4)));

vbyte2   step_byte2(vbyte2 a, vbyte2 b)       { return a + b; }
vbyte3   step_byte3(vbyte3 a, vbyte3 b)       { return a + b; }
vbyte8   step_byte8(vbyte8 a, vbyte8 b)       { return a + b; }
vbyte64  step_byte64(vbyte64 a, vbyte64 b)    { return a + b; }
vshort2  step_short2(vshort2 a, vshort2 b)    { return a + b; }
vshort3  step_short3(vshort3 a, vshort3 b)    { return a + b; }
vint2    step_int2(vint2 a, vint2 b)          { return a + b; }
vint4    step_int4(vint4 a, vint4 b)          { return a + b; }
vlong3   step_long3(vlong3 a, vlong3 b)       { return a + b; }
vfloat2  step_float2(vfloat2 a, vfloat2 b)    { return a + b; }
vfloat3  step_float3(vfloat3 a, vfloat3 b)    { return a + b; }
vfloat4  step_float4(vfloat4 a, vfloat4 b)    { return a + b; }
vfloat8  step_float8(vfloat8 a, vfloat8 b)    { return a + b; }
vdouble2 step_double2(vdouble2 a, vdouble2 b) { return a + b; }
vdouble3 step_double3(vdouble3 a, vdouble3 b) { return a + b; }
vdouble4 step_double4(vdouble4 a, vdouble4 b) { return a + b; }

/* Scalars between vectors, so a register a vector took is one a scalar did not. */
vfloat4 scaled_sum(int k, vfloat4 a, double d, vfloat4 b) { return a * (float)k + b * (float)d; }

typedef struct { vfloat4 v; } HoldFloat4;
typedef struct { vbyte3 v; } HoldByte3;
typedef struct { vfloat2 v; float w; } HoldFloat2Plus;
typedef struct { vfloat4 a; vfloat4 b; } TwoFloat4;
typedef struct { vdouble4 v; } HoldDouble4;
typedef struct { vint2 v; } HoldInt2;

HoldFloat4     hold_float4(HoldFloat4 h)          { h.v = h.v * 2; return h; }
HoldByte3      hold_byte3(HoldByte3 h)            { h.v = h.v + 1; return h; }
HoldFloat2Plus hold_float2_plus(HoldFloat2Plus h) { h.v = h.v + h.w; h.w = -h.w; return h; }
TwoFloat4      two_float4(TwoFloat4 t)            { TwoFloat4 r; r.a = t.b; r.b = t.a; return r; }
HoldDouble4    hold_double4(HoldDouble4 h)        { h.v = h.v.wzyx; return h; }
HoldInt2       hold_int2(HoldInt2 h)              { h.v = h.v.yx; return h; }

/* Stainless's, called from here. */
vfloat4 sl_scale(vfloat4 v, float by);
vdouble4 sl_flip(vdouble4 v);
vbyte2 sl_bump(vbyte2 v);
vfloat3 sl_rotate(vfloat3 v);

vfloat4  call_scale(vfloat4 v)  { return sl_scale(v, 3.0f) + 1.0f; }
vdouble4 call_flip(vdouble4 v)  { return sl_flip(v) * 10.0; }
vbyte2   call_bump(vbyte2 v)    { return sl_bump(v) + 100; }
vfloat3  call_rotate(vfloat3 v) { return sl_rotate(v) * 2.0f; }
