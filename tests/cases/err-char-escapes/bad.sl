// \u and \U name a Unicode scalar value, and not every number is one.
//
// This is its own case rather than part of err-code-units because a lexer
// error stops the compilation before anything binds, so a file holding both
// would only ever report these.
module BadEscapes;

public void Main() {
    // Past the end of Unicode, which stops at U+10FFFF.
    char32 pastTheEnd = '\U00110000';

    // Half of a UTF-16 surrogate pair, which is a code unit and not a scalar.
    char16 halfAPair = '\uDC00';

    // The same inside a string, where it would have to be encoded as UTF-8
    // and cannot be.
    String text = "lone \uD800 surrogate";
}
