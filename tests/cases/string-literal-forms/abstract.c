/* SPDX-License-Identifier: 0BSD */

/* Both names are the bare words, which is what an `@` in front of one leaves. */
int class(int value);

int abstract(int value)
{
    return class(value) + 100;
}
