/* SPDX-License-Identifier: 0BSD */
#include <stdio.h>
#include <string.h>
#include "library.h"

int main(void)
{
    printf("sizes=%d %d %d\n",
           (int)sizeof(Library_Unions_Word),
           (int)sizeof(Library_Unions_Wide),
           (int)sizeof(Library_Unions_Tagged));

    printf("agree=%d %d %d\n",
           (int)WordSize() == (int)sizeof(Library_Unions_Word),
           (int)WideSize() == (int)sizeof(Library_Unions_Wide),
           (int)TaggedSize() == (int)sizeof(Library_Unions_Tagged));

    /* Built in C, read in Stainless. */
    Library_Unions_Word word;
    word.Signed = -1;
    printf("unsigned=%u\n", (unsigned)ReadUnsigned(word));

    word.Real = 1.0f;
    printf("bits=%d\n", ReadBits(word));

    Library_Unions_Wide wide;
    wide.D = 0.0;
    wide.P.A = 7;
    wide.P.B = 9;
    printf("pairB=%d\n", ReadPairB(wide));

    Library_Unions_Tagged tagged;
    tagged.Which = Library_Unions_Kind_AsInt;
    tagged.Value.Signed = 42;
    printf("tagged=%d\n", TaggedInt(tagged));

    /* And built in Stainless, read in C: the same bits either way. */
    Library_Unions_Word made = MakeReal(2.5f);
    printf("made=%g %d\n", made.Real, made.Signed);
    return 0;
}
