// SPDX-License-Identifier: 0BSD
//
// The asm statement on 32-bit x86: its register names, a pointer the width of
// one, a double in a vector register, and the clobber list proved the way
// asm-clobbers proves it on x64 — values live across a block that destroys
// eax, ecx, edx and every xmm register, built optimised.
module AsmX86;

extern "C" int printf(byte* format, ...);
extern "C" int opaque_int(int value);
extern "C" double opaque_double(double value);

int Across(int a, int b, int c, double x, double y)
{
    int p = a * 3 + b;
    int q = b * 5 + c;
    int r = c * 7 + a;
    double u = x * 1.5 + y;
    double v = y * 2.5 + x;

    asm
    {
        mov eax, -1
        mov ecx, -1
        mov edx, -1
        pcmpeqd xmm0, xmm0
        pcmpeqd xmm1, xmm1
        pcmpeqd xmm2, xmm2
        pcmpeqd xmm3, xmm3
        pcmpeqd xmm4, xmm4
        pcmpeqd xmm5, xmm5
        pcmpeqd xmm6, xmm6
        pcmpeqd xmm7, xmm7
    }

    return p + q * 100 + r * 10000 + (int)((u + v * 100.0) * 10.0);
}

int Main()
{
    int total = 0;
    asm (in ecx = 40, in edx = 2, out eax = total) { lea eax, [ecx + edx] }
    printf("add %d\n", total);

    // Narrower than the register, extended by signedness.
    short negative = -3;
    asm (in cx = negative, out eax = total) { movsx eax, cx }
    printf("short in cx %d\n", total);
    asm (in ecx = negative, out eax = total) { mov eax, ecx }
    printf("short in ecx %d\n", total);

    int high = 0;
    total = 100;
    asm (inout eax = total, in ecx = 7, out edx = high)
    {
        cdq
        idiv ecx
    }
    printf("divide %d %d\n", total, high);

    var values = new int[3];
    values[0] = 5;
    values[1] = 6;
    values[2] = 7;
    asm (in esi = &values[0], out eax = total)
    {
        mov eax, dword ptr [esi]
        add eax, dword ptr [esi + 4]
        add eax, dword ptr [esi + 8]
    }
    printf("pointer sum %d\n", total);

    double scaled = 1.5;
    asm (inout xmm0 = scaled, in xmm7 = 3) { mulsd xmm0, xmm7 }
    printf("double %g\n", scaled);

    printf("across %d\n", Across(
        opaque_int(1), opaque_int(2), opaque_int(3),
        opaque_double(1.0), opaque_double(2.0)));
    return 0;
}
