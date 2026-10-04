// Vectors across extern "C", both ways, in every shape the conventions treat
// differently: two, four and eight bytes, three lanes, sixteen bytes, wider
// than sixteen, and inside structs.
module SimdAbi;

import Standard.Console;

public struct HoldFloat4 { public vfloat4 V; }
public struct HoldByte3 { public vbyte3 V; }
public struct HoldFloat2Plus { public vfloat2 V; public float W; }
public struct TwoFloat4 { public vfloat4 A; public vfloat4 B; }
public struct HoldDouble4 { public vdouble4 V; }
public struct HoldInt2 { public vint2 V; }

extern "C"
{
    vbyte2 step_byte2(vbyte2 a, vbyte2 b);
    vbyte3 step_byte3(vbyte3 a, vbyte3 b);
    vbyte8 step_byte8(vbyte8 a, vbyte8 b);
    vbyte64 step_byte64(vbyte64 a, vbyte64 b);
    vshort2 step_short2(vshort2 a, vshort2 b);
    vshort3 step_short3(vshort3 a, vshort3 b);
    vint2 step_int2(vint2 a, vint2 b);
    vint4 step_int4(vint4 a, vint4 b);
    vlong3 step_long3(vlong3 a, vlong3 b);
    vfloat2 step_float2(vfloat2 a, vfloat2 b);
    vfloat3 step_float3(vfloat3 a, vfloat3 b);
    vfloat4 step_float4(vfloat4 a, vfloat4 b);
    vfloat8 step_float8(vfloat8 a, vfloat8 b);
    vdouble2 step_double2(vdouble2 a, vdouble2 b);
    vdouble3 step_double3(vdouble3 a, vdouble3 b);
    vdouble4 step_double4(vdouble4 a, vdouble4 b);
    vfloat4 scaled_sum(int k, vfloat4 a, double d, vfloat4 b);

    HoldFloat4 hold_float4(HoldFloat4 h);
    HoldByte3 hold_byte3(HoldByte3 h);
    HoldFloat2Plus hold_float2_plus(HoldFloat2Plus h);
    TwoFloat4 two_float4(TwoFloat4 t);
    HoldDouble4 hold_double4(HoldDouble4 h);
    HoldInt2 hold_int2(HoldInt2 h);

    vfloat4 call_scale(vfloat4 v);
    vdouble4 call_flip(vdouble4 v);
    vbyte2 call_bump(vbyte2 v);
    vfloat3 call_rotate(vfloat3 v);
}

export "C" vfloat4 sl_scale(vfloat4 v, float by) => v * by;
export "C" vdouble4 sl_flip(vdouble4 v) => v.wzyx;
export "C" vbyte2 sl_bump(vbyte2 v) => v + 1;
export "C" vfloat3 sl_rotate(vfloat3 v) => v.yzx;

int Main()
{
    Console.WriteLine($"byte2: {step_byte2(new vbyte2(1, 2), new vbyte2(10, 20))}");
    Console.WriteLine($"byte3: {step_byte3(new vbyte3(1, 2, 3), new vbyte3(10, 20, 30))}");
    Console.WriteLine($"byte8: {step_byte8(new vbyte8(1, 2, 3, 4, 5, 6, 7, 8), new vbyte8(10))}");

    vbyte64 wide = new vbyte64(1);
    wide[63] = 7;
    vbyte64 wider = step_byte64(wide, new vbyte64(2));
    Console.WriteLine($"byte64: {wider[0]} {wider[62]} {wider[63]}");

    Console.WriteLine($"short2: {step_short2(new vshort2(-1, 2), new vshort2(100, -200))}");
    Console.WriteLine($"short3: {step_short3(new vshort3(1, 2, 3), new vshort3(-10, -20, -30))}");
    Console.WriteLine($"int2: {step_int2(new vint2(1, 2), new vint2(30, 40))}");
    Console.WriteLine($"int4: {step_int4(new vint4(1, 2, 3, 4), new vint4(10, 20, 30, 40))}");
    Console.WriteLine($"long3: {step_long3(new vlong3(1, 2, 3), new vlong3(10000000000, 20, 30))}");
    Console.WriteLine($"float2: {step_float2(new vfloat2(0.5f, 1.5f), new vfloat2(2, 4))}");
    Console.WriteLine($"float3: {step_float3(new vfloat3(1, 2, 3), new vfloat3(0.25f))}");
    Console.WriteLine($"float4: {step_float4(new vfloat4(1, 2, 3, 4), new vfloat4(4, 3, 2, 1))}");
    Console.WriteLine($"float8: {step_float8(new vfloat8(1, 2, 3, 4, 5, 6, 7, 8), new vfloat8(0.5f))}");
    Console.WriteLine($"double2: {step_double2(new vdouble2(1, 2), new vdouble2(0.125))}");
    Console.WriteLine($"double3: {step_double3(new vdouble3(1, 2, 3), new vdouble3(10, 20, 30))}");
    Console.WriteLine($"double4: {step_double4(new vdouble4(1, 2, 3, 4), new vdouble4(-1))}");
    Console.WriteLine($"between scalars: {scaled_sum(3, new vfloat4(1, 2, 3, 4), 0.5, new vfloat4(2))}");

    HoldFloat4 f4;
    f4.V = new vfloat4(1, 2, 3, 4);
    Console.WriteLine($"in a struct: {hold_float4(f4).V}");

    HoldByte3 b3;
    b3.V = new vbyte3(7, 8, 9);
    Console.WriteLine($"three bytes in a struct: {hold_byte3(b3).V}");

    HoldFloat2Plus plus;
    plus.V = new vfloat2(1, 2);
    plus.W = 0.5f;
    var plused = hold_float2_plus(plus);
    Console.WriteLine($"beside a float: {plused.V} {plused.W}");

    TwoFloat4 two;
    two.A = new vfloat4(1);
    two.B = new vfloat4(2);
    var swapped = two_float4(two);
    Console.WriteLine($"two in a struct: {swapped.A} {swapped.B}");

    HoldDouble4 d4;
    d4.V = new vdouble4(1, 2, 3, 4);
    Console.WriteLine($"wide in a struct: {hold_double4(d4).V}");

    HoldInt2 i2;
    i2.V = new vint2(5, 6);
    Console.WriteLine($"eight bytes in a struct: {hold_int2(i2).V}");

    Console.WriteLine($"called back: {call_scale(new vfloat4(1, 2, 3, 4))} {call_flip(new vdouble4(1, 2, 3, 4))}");
    Console.WriteLine($"called back narrow: {call_bump(new vbyte2(1, 2))} {call_rotate(new vfloat3(1, 2, 3))}");
    return 0;
}
