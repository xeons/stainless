// What the three code unit types refuse.
//
// The rule is that char, char16 and char32 are three encodings rather than
// three widths of one type, so none of them becomes another without a cast --
// and a character literal has to fit the type it is given in a single unit.
module BadCodeUnits;

public void Main() {
    // U+00E9 is two bytes of UTF-8, so it is not one 'char'.
    char tooWide = 'é';

    // U+1F600 is a surrogate pair, so it is not one 'char16'.
    char16 stillTooWide = '😀';

    // Neither direction is implicit, however the sizes fall: widening does not
    // re-encode and narrowing does not check.
    char   narrow = 'A';
    char16 widened = narrow;

    char16 wide = 'é';
    char   narrowed = wide;

    char32 widest = '日';
    char16 shrunk = widest;
}
