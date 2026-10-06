// What a module-level `const` may and may not hold.
module ErrConst;

// Fine: a number, a bool, a char, an enum member, and a negated literal --
// which the parser sees as a unary minus over a literal rather than as one.
const int Limit = 64;
const int Backwards = -21;
const uint Mask = 0x8000u;
const double Half = 0.5;
const double Below = -0.5;
const bool Always = true;
const char Newline = '\n';
const int FromCharacter = 'A';

const String Greeting = "hello";

// Not fine: an object is built at run time, and a constant is inlined at
// every use. `static readonly` is the one with storage.
sealed class Box { }
const Box Empty = null;                             // SLT0048

// Not fine either: the initializer is not a literal.
const int Computed = 32 + 32;                       // SLT0001

// A literal that cannot be negated.
const bool Negated = -true;                         // SLT0001

// A literal of the wrong kind. Without this check each of these would be a
// silent zero rather than an error.
const int NotANumber = null;                        // SLT0049
const int NotAnInt = 1.5;                           // SLT0049
const bool NotABool = 1;                            // SLT0049
const double NotAReal = false;                      // SLT0049

int Main() => Limit + Backwards;
