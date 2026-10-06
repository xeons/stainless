// What a SIMD vector refuses.
module ErrSimd;

int Next() => 0;

int Main()
{
    vfloat4 a = new vfloat4(1, 2, 3);                   // SLT0087: three lanes of four
    vfloat4 b = new vfloat4(new vint2(1, 2), 3, 4);     // SLT0087: int lanes in a float vector
    vfloat4 c = new vfloat4(x: 1);                      // SLT0087: a named lane
    float q = a.q;                                      // SLN0013: no lane q
    float w = new vfloat2(1, 2).z;                      // SLN0013: two lanes have no z
    float e = a[4];                                     // SLT0053: past the last lane
    a.xx = new vfloat2(1, 2);                           // SLT0088: a lane written twice
    vfloat4[] all = new vfloat4[2];
    all[Next()].xy += new vfloat2(1, 2);                // SLT0088: worked out twice
    bool less = a < b;                                  // SLT0006: not ordered as a whole
    vfloat4 mixed = a + new vint4(1);                   // SLT0006: two kinds of vector
    vfloat4 bits = a & b;                               // SLT0006: float lanes have no bits
    vint4 shifted = 1 << new vint4(2);                  // SLT0006: shifts its left side
    vint4 implicit = new vbyte4(1);                     // SLT0018: no implicit lane change
    vfloat4 flipped = !a;                               // SLT0006: not a bool
    vfloat4 unknown = vfloat4.Spin(a);                  // SLT0089: no such function
    vint4 rooted = vint4.Sqrt(new vint4(4));            // SLT0089: for float lanes
    vfloat3 crossed = vfloat4.Cross(a, b);              // SLT0089: three lanes only
    float dot = vfloat4.Dot(a);                         // SLT0089: two arguments
    int length = new vint2(3, 4).Length;                // SLT0089: a square root of ints
    vfloat4 unit = vfloat4.Unit;                        // SLT0089: Zero and One only
    return 0;
}
