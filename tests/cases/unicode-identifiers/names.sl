// SPDX-License-Identifier: 0BSD
module Names;

// An identifier may hold any letter, as in C#. What a linker symbol and an
// LLVM name may hold is ASCII, and the framework's IsLetterOrDigit answers
// true for every letter Unicode has -- so these passed straight through into
// generated IR and were rejected there, in a message naming a file that is in
// no source tree. Anything past ASCII is spelled as its code point now, so two
// identifiers that differ still do.

extern "C" int printf(byte* format, ...);

struct Poiñt {
    public int X;
    public int Ünit;
}

int café() { return 40; }

int Sum(int é, int è) { return é + è; }

int Main() {
    int élève = 1;

    Poiñt p;
    p.X = 1;
    p.Ünit = 2;

    // Two names long enough that the IR trims them, differing only past the
    // cut: what tells one local from another is the number the emitter
    // appends, not the name it is given to read by.
    int aVeryLongNameThatGoesOnAndOnWellPastAnythingReadableAndKeepsGoingA = 100;
    int aVeryLongNameThatGoesOnAndOnWellPastAnythingReadableAndKeepsGoingB = 200;

    printf("%d %d %d %d\n",
        café() + élève + Sum(1, 0),
        p.X + p.Ünit,
        aVeryLongNameThatGoesOnAndOnWellPastAnythingReadableAndKeepsGoingA,
        aVeryLongNameThatGoesOnAndOnWellPastAnythingReadableAndKeepsGoingB);
    return 0;
}
