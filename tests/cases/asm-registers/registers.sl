// SPDX-License-Identifier: 0BSD
//
// What each kind of operand carries into and out of an x64 register: widths,
// signedness, pointers, the vector registers, and a place evaluated once.
module AsmRegisters;

extern "C" int printf(byte* format, ...);

public enum Level : int { Low = 1, High = 7 }

public struct Pair
{
    public long First;
    public long Second;
}

public class Box
{
    public int Value;
}

long Add(long a, long b)
{
    long total = 0;
    asm (in rcx = a, in rdx = b, out rax = total)
    {
        mov rax, rcx    # a comment in the x86 spelling
        add rax, rdx    // and in the spelling every target takes
    }
    return total;
}

// Several outputs, stored in the order they are written.
void Divide(long dividend, long divisor, out long quotient, out long remainder)
{
    quotient = dividend;
    remainder = 0;
    asm (inout rax = quotient, in rcx = divisor, out rdx = remainder)
    {
        cqo
        idiv rcx
    }
}

// An 'out' parameter written only by the block is still written.
void Halves(long value, out int low, out int high)
{
    asm (in rcx = value, out eax = low, out edx = high)
    {
        mov rax, rcx
        mov rdx, rcx
        shr rdx, 32
    }
}

nuint Next(nuint limit)
{
    Counter.Calls++;
    return limit;
}

public static class Counter
{
    public static int Calls = 0;
}

int Main()
{
    printf("add %lld\n", Add(40, 2));

    long quotient = 0;
    long remainder = 0;
    Divide(-17, 5, out quotient, out remainder);
    printf("divide %lld %lld\n", quotient, remainder);

    int low = 0;
    int high = 0;
    Halves(0x0000000500000009, out low, out high);
    printf("halves %d %d\n", high, low);

    // Narrower than the register: extended by the value's own signedness.
    int negative = -7;
    long wide = 0;
    asm (in rcx = negative, out rax = wide) { mov rax, rcx }
    printf("int in rcx %lld\n", wide);

    uint large = 0xFFFFFFF0;
    asm (in r9 = large, out rax = wide) { mov rax, r9 }
    printf("uint in r9 %lld\n", wide);

    byte small = 200;
    asm (in cl = small, out rax = wide) { movzx rax, cl }
    printf("byte in cl %lld\n", wide);

    // A literal takes the register's width where it fits.
    asm (in al = 250, out rcx = wide) { movzx rcx, al }
    printf("literal in al %lld\n", wide);

    // Narrower going out: the low bits.
    short word = 0;
    asm (out ax = word) { mov rax, 0x1234FFFE }
    printf("short from ax %d\n", word);

    int truncated = 0;
    asm (out rax = truncated) { mov rax, 0x100000003 }
    printf("int from rax %d\n", truncated);

    // A bool is whether the register is anything but zero.
    bool carried = false;
    asm (out al = carried) { mov al, 4 }
    printf("bool out %d\n", carried ? 1 : 0);

    bool asked = true;
    asm (in cl = asked, out eax = low) { movzx eax, cl }
    printf("bool in %d\n", low);

    // A character and an enum are their integers.
    char letter = 'q';
    asm (inout al = letter) { sub al, 32 }
    printf("char %c\n", letter);

    Level level = Level.High;
    asm (in ecx = level, out eax = low) { lea eax, [rcx + rcx] }
    printf("enum %d\n", low);

    // A pointer, and the memory behind it.
    var values = new long[4];
    values[0] = 11;
    values[1] = 22;
    values[2] = 33;
    values[3] = 44;
    asm (in rsi = &values[0], in rcx = 4, out rax = wide)
    {
        xor eax, eax
    registers_sum:
        add rax, qword ptr [rsi]
        add rsi, 8
        dec rcx
        jnz registers_sum
    }
    printf("pointer sum %lld\n", wide);

    // The vector registers, which carry a float or a double.
    double scaled = 2.25;
    double factor = 4.0;
    asm (inout xmm0 = scaled, in xmm1 = factor) { mulsd xmm0, xmm1 }
    printf("double %g\n", scaled);

    float half = 1.25f;
    asm (inout xmm2 = half) { addss xmm2, xmm2 }
    printf("float %g\n", (double)half);

    asm (in xmm3 = 3, out xmm0 = scaled) { movsd xmm0, xmm3 }
    printf("literal in xmm3 %g\n", scaled);

    // Places: an element, fields of a struct and a class.
    Pair pair;
    pair.First = 0;
    pair.Second = 0;
    var box = new Box();
    asm (out rax = pair.First, out rdx = pair.Second, out ecx = box.Value)
    {
        mov rax, 100
        mov rdx, 200
        mov ecx, 300
    }
    printf("places %lld %lld %d\n", pair.First, pair.Second, box.Value);

    // An 'inout' place is evaluated once, not once to read and once to write.
    asm (inout rax = values[Next(2)]) { add rax, 1 }
    printf("once %lld after %d call\n", values[2], Counter.Calls);

    // Braces inside a block are counted, so balanced ones are fine anywhere.
    asm { nop  // {balanced}
    }
    asm () { }

    // The same numbered label in two blocks, which a named one could not be.
    asm (out rax = wide)
    {
        mov rax, 1
        jmp 1f
        mov rax, 2
    1:
    }
    asm (inout rax = wide)
    {
        jmp 1f
        mov rax, 5
    1:
        add rax, 10
    }
    printf("labels %lld\n", wide);

    // One register in from one place and out to another, the wider name
    // going in and the narrower coming out.
    long given = 0x100000029;
    int left = 0;
    asm (in rcx = given, out ecx = left)
    {
        inc rcx
    }
    printf("in and out %d\n", left);
    return 0;
}
