// SPDX-License-Identifier: 0BSD
//
// A block wherever a statement may go: in a loop, in a lambda, in a for
// parallel body and in spawned work. And the two instructions nobody can write
// any other way, whose values are not asserted because they are this machine's.
module AsmContexts;

extern "C" int printf(byte* format, ...);

public interface ITransform { long Apply(long value); }

long Square(long value)
{
    long result = 0;
    asm (in rcx = value, out rax = result) { mov rax, rcx
        imul rax, rcx }
    return result;
}

int Main()
{
    // cpuid leaf 0 names the vendor in twelve bytes of ebx, edx and ecx, and
    // every x64 processor has one.
    int highest = 0;
    int vendorB = 0;
    int vendorD = 0;
    int vendorC = 0;
    asm (inout eax = highest, out ebx = vendorB, out edx = vendorD, out ecx = vendorC)
    {
        cpuid
    }
    printf("cpuid leaves %s\n", highest > 0 ? "some".ToPointer() : "none".ToPointer());

    // rbx is callee-saved, and naming it is what makes the function save it,
    // so a block that leaves it changed is fine once it is an operand.
    long first = 0;
    long second = 0;
    long kept = 0;
    asm (out rax = first, out rdx = second) { rdtsc }
    asm (inout rax = second, inout rdx = first, out rbx = kept)
    {
        mov rbx, rax
        rdtsc
    }
    printf("rdtsc %s\n", second != 0 || first != 0 ? "ticks".ToPointer() : "still".ToPointer());

    long total = 0;
    for (long i = 1; i <= 10; i++)
    {
        asm (inout rax = total, in rcx = i) { add rax, rcx }
    }
    printf("loop %lld\n", total);

    ITransform cube = value =>
    {
        long result = 0;
        asm (in rcx = value, out rax = result)
        {
            mov rax, rcx
            imul rax, rcx
            imul rax, rcx
        }
        return result;
    };
    printf("lambda %lld\n", cube.Apply(3));

    var squares = new long[16];
    for parallel (int i = 0; i < 16; i++)
    {
        long wide = i;
        asm (in rdx = wide, out rax = squares[i]) { lea rax, [rdx + rdx] }
    }
    long doubled = 0;
    for (int i = 0; i < 16; i++)
        doubled += squares[i];
    printf("for parallel %lld\n", doubled);

    long left = 0;
    long right = 0;
    parallel
    {
        left = spawn Square(12);
        right = spawn Square(5);
    }
    printf("spawn %lld\n", left + right);
    return 0;
}
