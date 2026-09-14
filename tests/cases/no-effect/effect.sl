// An expression may stand alone as a statement, and most expressions are a
// mistake there. The ones that count as doing something are a fixed list --
// assignment, a call, ++ and --, new, and a conditional or a ?. whose inside
// qualifies -- and everything else is warned about. Documented in §9.13.
//
// This program still compiles and runs: SL0222 is a warning, because the code
// is well typed and the author may have meant it.
module NoEffect;

extern "C" int puts(byte* text);

int Next() { return 7; }

int Main() {
    int count = 1;

    // Each of these could have had an effect, so none of them is warned about.
    count = Next();
    count++;
    Next();

    // Neither of these could. Both are SL0222.
    count + 1;
    count;

    puts("done");
    return 0;
}
