// What a SIMD vector refuses.
module ErrSimd;

int Next() => 0;

int Main()
{
    vfloat4 a = new vfloat4(1, 2, 3);                   // SL0929: three lanes of four
    vfloat4 b = new vfloat4(new vint2(1, 2), 3, 4);     // SL0929: int lanes in a float vector
    vfloat4 c = new vfloat4(x: 1);                      // SL0929: a named lane
    float q = a.q;                                      // SL0930: no lane q
    float w = new vfloat2(1, 2).z;                      // SL0930: two lanes have no z
    float e = a[4];                                     // SL0490: past the last lane
    a.xx = new vfloat2(1, 2);                           // SL0931: a lane written twice
    vfloat4[] all = new vfloat4[2];
    all[Next()].xy += new vfloat2(1, 2);                // SL0931: worked out twice
    bool less = a < b;                                  // SL0232: not ordered as a whole
    vfloat4 mixed = a + new vint4(1);                   // SL0232: two kinds of vector
    vfloat4 bits = a & b;                               // SL0232: float lanes have no bits
    vint4 shifted = 1 << new vint4(2);                  // SL0232: shifts its left side
    vint4 implicit = new vbyte4(1);                     // SL0265: no implicit lane change
    vfloat4 flipped = !a;                               // SL0232: not a bool
    vfloat4 unknown = vfloat4.Spin(a);                  // SL0934: no such function
    vint4 rooted = vint4.Sqrt(new vint4(4));            // SL0934: for float lanes
    vfloat3 crossed = vfloat4.Cross(a, b);              // SL0934: three lanes only
    float dot = vfloat4.Dot(a);                         // SL0934: two arguments
    int length = new vint2(3, 4).Length;                // SL0934: a square root of ints
    vfloat4 unit = vfloat4.Unit;                        // SL0934: Zero and One only
    return 0;
}
