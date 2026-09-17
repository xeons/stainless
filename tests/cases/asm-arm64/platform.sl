// SPDX-License-Identifier: 0BSD
module AsmArm64;

// x18 is the platform register, and Linux lets a block use it as a temporary.
long Platform(long value)
{
    long result = 0;
    asm (in x18 = value, out x0 = result) { mov x0, x18 }
    return result;
}
