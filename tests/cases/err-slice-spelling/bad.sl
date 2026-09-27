// SPDX-License-Identifier: 0BSD
module Bad;

// A slice's type is `Span<T>`; `[:]` is only for cutting one.
int Total(int[:] values) => 0;

int Main()
{
    int[] numbers = [1, 2, 3];
    int[:] all = numbers[:];
    return 0;
}

// Inside an interpolation's hole as much as anywhere.
nuint Count(int[] numbers) => $"{((int[:])numbers).Length}".Length;
