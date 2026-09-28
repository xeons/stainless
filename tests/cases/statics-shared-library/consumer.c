/* SPDX-License-Identifier: 0BSD */
#include <stdio.h>
#include "library.h"

int main(void)
{
    printf("names=%d length=%d held=%d\n", NameCount(), NameLength(), IsHeld());
    fflush(stdout);
    return 0;
}
