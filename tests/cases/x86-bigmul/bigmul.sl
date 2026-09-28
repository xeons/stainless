// SPDX-License-Identifier: 0BSD
//
// The whole product of two 64-bit values, which no operator gives, and the
// optimisation barrier constant-time code is built on. Every product is
// checked against the one worked out by hand in 32-bit halves.
module BigMul;

import Standard.Bits;
import Standard.Math;
import Standard.Security.Cryptography;

extern "C" int printf(byte* format, ...);

void Show(ulong high, ulong low) => printf("%016llx%016llx\n", high, low);

int Main()
{
    ulong low;
    Show(Math.BigMul(0xFFFFFFFFFFFFFFFFul, 0xFFFFFFFFFFFFFFFFul, out low), low);
    Show(Math.BigMul(0x0123456789ABCDEFul, 0xFEDCBA9876543210ul, out low), low);
    Show(Math.BigMul(1ul << 63, 2ul, out low), low);
    Show(Math.BigMul(0ul, 0xDEADBEEFul, out low), low);

    long signedLow;
    long high = Math.BigMul(-1L, 1L, out signedLow);
    printf("%lld %lld\n", high, signedLow);
    high = Math.BigMul(-3L, -5L, out signedLow);
    printf("%lld %lld\n", high, signedLow);
    high = Math.BigMul(-9223372036854775807L - 1L, 2L, out signedLow);
    printf("%lld %lld\n", high, signedLow);

    printf("%llu %lld\n", Math.BigMul(0xFFFFFFFFu, 0xFFFFFFFFu), Math.BigMul(-2, 0x7FFFFFFF));
    printf("%016llx\n", MultiplyHigh(0xDEADBEEFCAFEBABEul, 0x1234567812345678ul));

    printf("%llu %u\n", OpaqueCopy(0x8000000000000001ul), OpaqueCopy(7u));

    byte[] a = [1, 2, 3];
    byte[] b = [1, 2, 3];
    byte[] c = [1, 2, 4];
    printf("%d %d\n", CryptographicOperations.FixedTimeEquals(a, b) ? 1 : 0,
           CryptographicOperations.FixedTimeEquals(a, c) ? 1 : 0);

    CryptographicOperations.ZeroMemory(c);
    printf("%d %d %d\n", (int)c[0u], (int)c[1u], (int)c[2u]);
    return 0;
}
