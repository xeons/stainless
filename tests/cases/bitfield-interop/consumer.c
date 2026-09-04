/* SPDX-License-Identifier: 0BSD */
#include <stdio.h>
#include "library.h"

int main(void)
{
    printf("sizes=%d %d %d\n",
           (int)sizeof(Library_Bits_Header),
           (int)sizeof(Library_Bits_Signed),
           (int)sizeof(Library_Bits_Mixed));

    printf("agree=%d %d %d\n",
           (int)HeaderSize() == (int)sizeof(Library_Bits_Header),
           (int)SignedSize() == (int)sizeof(Library_Bits_Signed),
           (int)MixedSize() == (int)sizeof(Library_Bits_Mixed));

    /* Written in C, read in Stainless: the bits have to be in the same places. */
    Library_Bits_Header header;
    header.Version = 3;
    header.Kind = 9;
    header.Length = 1000000;
    printf("read=%u %u %u\n",
           (unsigned)ReadVersion(header), (unsigned)ReadKind(header),
           (unsigned)ReadLength(header));

    Library_Bits_Signed value;
    value.Small = 7;        /* three bits: reads back as -1 */
    value.Larger = -3;
    printf("signed=%d %d\n", ReadSmall(value), ReadLarger(value));

    Library_Bits_Mixed mixed;
    mixed.Flags = 5;
    mixed.Weight = 2.5;
    mixed.More = 21;
    printf("mixed=%g %u\n", ReadWeight(mixed), (unsigned)ReadMore(mixed));

    /* Built in Stainless, read in C. */
    Library_Bits_Header made = MakeHeader(5, 11, 70000);
    printf("made=%u %u %u\n",
           (unsigned)made.Version, (unsigned)made.Kind, (unsigned)made.Length);

    /* And one field written without disturbing the others. */
    Library_Bits_Header bumped = BumpKind(made);
    printf("bumped=%u %u %u\n",
           (unsigned)bumped.Version, (unsigned)bumped.Kind, (unsigned)bumped.Length);
    return 0;
}
