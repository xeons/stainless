// SPDX-License-Identifier: 0BSD
module RsaCase;

// crypto-rsa's known answers on a 32-bit target, where every 64-bit limb
// operation and every 64 by 64 multiplication is emulated in halves. Key
// generation is left out: it is the same arithmetic, and too slow to be
// worth the time here.

int Main()
{
    CheckRsaVectors();
    return 0;
}
