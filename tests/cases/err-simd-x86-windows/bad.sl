// 32-bit Windows passes three vectors in SSE registers and the rest behind
// pointers, and a signature that needs the fourth is refused.
module ErrSimdX86Windows;

extern "C" vfloat4 four(vfloat4 a, vfloat4 b, vfloat4 c, vfloat4 d);    // SL0933

// Three, or the fourth by reference, are fine.
extern "C" vfloat4 three(vfloat4 a, vfloat4 b, vfloat4 c);
extern "C" vfloat4 fourth_by_reference(vfloat4 a, vfloat4 b, vfloat4 c, ref vfloat4 d);

int Main() => 0;
