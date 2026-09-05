// `String`, now that it has an API.
//
// Everything here is written in Stainless, in stdlib/Text.sl, as a second
// declaration of a type the compiler had already created -- which is the point
// of the exercise as much as the methods are. `String` is intrinsic: the
// runtime owns its layout and its allocation. It no longer owns its behaviour.
//
// The multi-byte cases are here because a byte-oriented API on UTF-8 is only
// correct if it never lands inside a sequence. Searching for whole text cannot,
// which is the property being checked; walking with CodePointAt is how a caller
// gets character positions when it needs them.
module TextStrings;

import Standard.Console;
import Standard.Text;

void Say(String label, String value) {
    Console.WriteLine(label + " " + value);
}

void SayNumber(String label, long value) {
    Console.WriteLine(label + " " + Text.FromInteger(value));
}

void SayBool(String label, bool value) {
    Console.WriteLine(label + " " + Text.FromBool(value));
}

int Main() {
    // ------------------------------------------------------------- testing
    SayBool("starts", "hello world".StartsWith("hello"));
    SayBool("starts-no", "hello world".StartsWith("world"));
    SayBool("starts-empty", "hello".StartsWith(""));
    SayBool("ends", "hello world".EndsWith("world"));
    SayBool("ends-no", "hello world".EndsWith("hello"));
    SayBool("contains", "hello world".Contains("lo wo"));
    SayBool("contains-no", "hello world".Contains("xyz"));
    SayBool("contains-char", "hello".Contains('e'));

    // ----------------------------------------------------------- searching
    SayNumber("index", "abcabc".IndexOf("bc"));
    SayNumber("index-from", "abcabc".IndexOf("bc", 2u));
    SayNumber("index-none", "abcabc".IndexOf("zz"));
    SayNumber("last-index", "abcabc".LastIndexOf("bc"));
    SayNumber("index-char", "abcabc".IndexOf('c'));
    SayNumber("last-char", "abcabc".LastIndexOf('c'));
    SayNumber("index-empty", "abc".IndexOf(""));

    // A search for whole text can only land on a character boundary, however
    // many bytes the characters before it took.
    SayNumber("index-utf8", "héllo wörld".IndexOf("wörld"));

    // ------------------------------------------------------------- slicing
    Say("substring", "hello world".Substring(6u));
    Say("substring-past", "hello".Substring(99u));
    Say("before", "key=value".Before("="));
    Say("after", "key=value".After("="));
    Say("before-none", "keyvalue".Before("="));
    Say("after-none", "keyvalue".After("="));
    Say("after-last", "a.b.c".AfterLast("."));

    // ------------------------------------------------------------ trimming
    Say("trim", "[" + "  padded  ".Trim() + "]");
    Say("trim-start", "[" + "  padded  ".TrimStart() + "]");
    Say("trim-end", "[" + "  padded  ".TrimEnd() + "]");
    Say("trim-none", "[" + "tight".Trim() + "]");
    Say("trim-all", "[" + "   ".Trim() + "]");

    // ---------------------------------------------------------- rebuilding
    Say("replace", "one two one".Replace("one", "1"));
    Say("replace-grow", "aaa".Replace("a", "aa"));
    Say("replace-none", "abc".Replace("z", "y"));
    Say("repeat", "ab".Repeat(3u));
    Say("repeat-zero", "[" + "ab".Repeat(0u) + "]");
    Say("pad-left", "[" + "7".PadLeft(4u) + "]");
    Say("pad-right", "[" + "7".PadRight(4u) + "]");
    Say("pad-wide", "[" + "seven".PadLeft(3u) + "]");

    // ----------------------------------------------------------- splitting
    Say("split", "|".Join("a,b,c".Split(',')));
    Say("split-empty-parts", "|".Join("a,,b".Split(',')));
    Say("split-string", "|".Join("a::b::c".Split("::")));
    Say("split-none", "|".Join("abc".Split(',')));
    Say("join-empty", "[" + ",".Join([]) + "]");

    var lines = "one\ntwo\r\nthree\n".SplitLines();
    SayNumber("lines", (long)lines.Length);
    Say("lines-joined", "|".Join(lines));

    // ---------------------------------------------------------------- case
    Say("upper", "Hello, World!".ToUpperAscii());
    Say("lower", "Hello, World!".ToLowerAscii());
    Say("upper-utf8", "héllo".ToUpperAscii());
    SayBool("equals-ci", "HELLO".EqualsIgnoreCaseAscii("hello"));
    SayBool("equals-ci-no", "HELLO".EqualsIgnoreCaseAscii("hallo"));

    // --------------------------------------------------------- comparison
    SayNumber("compare-lt", (long)"apple".CompareTo("banana"));
    SayNumber("compare-gt", (long)"banana".CompareTo("apple"));
    SayNumber("compare-eq", (long)"apple".CompareTo("apple"));
    SayNumber("compare-prefix", (long)"app".CompareTo("apple"));

    // -------------------------------------------------------- code points
    var text = "aé€";
    SayNumber("bytes", (long)text.ByteLength());
    SayNumber("points", (long)text.CodePointCount());

    var walked = new StringBuilder();
    for (nuint at = 0u; at < text.ByteLength(); at = text.NextCodePoint(at)) {
        walked.Append(Text.FromInteger((long)(uint)text.CodePointAt(at)));
        walked.Append(" ");
    }
    Say("walked", walked.ToText().TrimEnd());

    SayNumber("byte-at", (long)text.ByteAt(0u));

    // --------------------------------------------------------- conversion
    var raw = "abc".ToBytes();
    SayNumber("to-bytes", (long)raw.Length);
    SayNumber("to-bytes-first", (long)raw[0]);

    return 0;
}
