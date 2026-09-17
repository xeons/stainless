// SPDX-License-Identifier: 0BSD
//
// The test that proves the clobber list, and so has to be built optimised,
// which the harness does.
//
// Seven values are live across a block that overwrites every register a C call
// may change and restores none of them. With nothing in between but arithmetic,
// the register allocator's first choice for each value is a volatile register;
// if the block were not declared to clobber them, the values would still be
// read from there afterwards. Each system has its own set — Windows preserves
// rsi, rdi and xmm6 up, System V none of those — so each gets the block that
// destroys exactly its own set, and destroying a register the platform says is
// preserved would be the block's bug rather than the compiler's.
//
// The inputs come through C functions the optimiser cannot see into, or every
// one of these would be a constant and nothing would be live at all.
module AsmClobbers;

extern "C" int printf(byte* format, ...);
extern "C" long opaque_long(long value);
extern "C" double opaque_double(double value);

long Across(long a, long b, long c, long d, double x, double y, double z)
{
    long p = a * 3 + b;
    long q = b * 5 + c;
    long r = c * 7 + d;
    long s = d * 11 + a;
    double u = x * 1.5 + y;
    double v = y * 2.5 + z;
    double w = z * 3.5 + x;

#if WINDOWS
    asm
    {
        mov rax, -1
        mov rcx, -1
        mov rdx, -1
        mov r8, -1
        mov r9, -1
        mov r10, -1
        mov r11, -1
        pcmpeqd xmm0, xmm0
        pcmpeqd xmm1, xmm1
        pcmpeqd xmm2, xmm2
        pcmpeqd xmm3, xmm3
        pcmpeqd xmm4, xmm4
        pcmpeqd xmm5, xmm5
    }
#else
    asm
    {
        mov rax, -1
        mov rcx, -1
        mov rdx, -1
        mov rsi, -1
        mov rdi, -1
        mov r8, -1
        mov r9, -1
        mov r10, -1
        mov r11, -1
        pcmpeqd xmm0, xmm0
        pcmpeqd xmm1, xmm1
        pcmpeqd xmm2, xmm2
        pcmpeqd xmm3, xmm3
        pcmpeqd xmm4, xmm4
        pcmpeqd xmm5, xmm5
        pcmpeqd xmm6, xmm6
        pcmpeqd xmm7, xmm7
        pcmpeqd xmm8, xmm8
        pcmpeqd xmm9, xmm9
        pcmpeqd xmm10, xmm10
        pcmpeqd xmm11, xmm11
        pcmpeqd xmm12, xmm12
        pcmpeqd xmm13, xmm13
        pcmpeqd xmm14, xmm14
        pcmpeqd xmm15, xmm15
    }
#endif

    return p + q * 1000 + r * 1000000 + s * 1000000000 +
           (long)((u + v * 100.0 + w * 10000.0) * 10.0);
}

int Main()
{
    long total = Across(
        opaque_long(1), opaque_long(2), opaque_long(3), opaque_long(4),
        opaque_double(1.0), opaque_double(2.0), opaque_double(3.0));

    printf("%lld\n", total);
    return 0;
}
