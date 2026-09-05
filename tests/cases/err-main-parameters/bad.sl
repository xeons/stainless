// SPDX-License-Identifier: 0BSD
module Bad;

// `Main` takes either nothing or a String[] -- the arguments the program was
// started with. An int is neither, and guessing what it was meant to be would
// be worse than saying so.
int Main(int count) {
    return count;
}
