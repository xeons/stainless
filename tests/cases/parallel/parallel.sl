// SPDX-License-Identifier: 0BSD
module Parallel;

import Standard.Console;
import Standard.Threading;

extern "C" int printf(byte* format, ...);

int Sum(int[] values, int from, int upto) {
    int total = 0;
    for (int i = from; i < upto; i = i + 1) { total = total + values[i]; }
    return total;
}

int Square(int value) { return value * value; }

String Label(int value) { return "n" + FromInteger(value); }

int Shade(int value) { return value * value + 1; }

// Every operation goes through an AtomicLong, so this really does synchronize
// itself -- which is what [Shared] asserts. Without it the spawn below is
// rejected, because a class crossing a thread boundary is a race by default.
[Shared]
class Accumulator {
    AtomicLong total;
    public Accumulator(AtomicLong cell) { total = cell; }
    public void Contribute(int amount) { total.Add(amount); }
}

int Main() {
    var values = new int[100];
    for (int i = 0; i < 100; i = i + 1) { values[i] = i; }

    // Two halves, each writing into a local the parent still owns. The join at
    // the closing brace is what makes that sound.
    int left = 0;
    int right = 0;

    parallel {
        spawn left = Sum(values, 0, 50);
        spawn right = Sum(values, 50, 100);
    }

    printf("halves=%d\n", left + right);

    // A spawn inside a loop needs one argument block per iteration; sharing one
    // would give every job the last iteration's values.
    var squares = new int[8];
    parallel {
        for (int i = 0; i < 8; i = i + 1) {
            spawn squares[i] = Square(i);
        }
    }

    int squareTotal = 0;
    for (int i = 0; i < 8; i = i + 1) { squareTotal = squareTotal + squares[i]; }
    printf("squares=%d\n", squareTotal);

    // A managed result, stored into an array element by the worker.
    var names = new String[4];
    parallel {
        for (int i = 0; i < 4; i = i + 1) {
            spawn names[i] = Label(i);
        }
    }

    var joined = new StringBuilder();
    for (int i = 0; i < 4; i = i + 1) { joined.Append(names[i]); }
    Console.WriteLine(joined.ToText());

    // A bare spawn, with a method call and a shared atomic for the result.
    var running = new AtomicLong(0);
    var accumulator = new Accumulator(running);

    parallel {
        for (int i = 1; i <= 10; i = i + 1) {
            spawn accumulator.Contribute(i);
        }
    }

    printf("accumulated=%lld\n", running.Load());

    // parallel for: the array is captured by address and written through.
    var pixels = new int[1000];
    for (int i = 0; i < 1000; i = i + 1) { pixels[i] = i; }

    parallel for (int i = 0; i < 1000; i = i + 1) {
        pixels[i] = Shade(pixels[i]);
    }

    long shaded = 0;
    for (int i = 0; i < 1000; i = i + 1) { shaded = shaded + pixels[i]; }
    printf("shaded=%lld\n", shaded);

    // An inclusive bound and a stride greater than one.
    var marks = new int[10];
    parallel for (int i = 0; i <= 8; i = i + 2) { marks[i] = 1; }

    int hits = 0;
    for (int i = 0; i < 10; i = i + 1) { hits = hits + marks[i]; }
    printf("hits=%d\n", hits);

    // An empty range runs nothing at all.
    parallel for (int i = 0; i < 0; i = i + 1) { marks[0] = 99; }
    printf("guard=%d\n", marks[0]);

    // Nested: each chunk of the outer loop runs an inner one of its own.
    var grid = new int[64];
    parallel for (int row = 0; row < 8; row = row + 1) {
        for (int column = 0; column < 8; column = column + 1) {
            grid[row * 8 + column] = row + column;
        }
    }

    int gridTotal = 0;
    for (int i = 0; i < 64; i = i + 1) { gridTotal = gridTotal + grid[i]; }
    printf("grid=%d\n", gridTotal);

    printf("done\n");
    return 0;
}
