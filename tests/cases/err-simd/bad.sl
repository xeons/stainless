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
    bool less = a < b;                                  // SL0932: not ordered as a whole
    vfloat4 mixed = a + new vint4(1);                   // SL0932: two kinds of vector
    vfloat4 bits = a & b;                               // SL0932: float lanes have no bits
    vint4 shifted = 1 << new vint4(2);                  // SL0932: shifts its left side
    vint4 implicit = new vbyte4(1);                     // SL0265: no implicit lane change
    vfloat4 flipped = !a;                               // SL0232: not a bool
    return 0;
}
