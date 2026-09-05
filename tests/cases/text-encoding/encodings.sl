// Text as bytes, in whichever encoding somebody else chose.
//
// A `String` is UTF-8 and there is one string type, so every other encoding is
// a crossing rather than a second kind of text. The interface is .NET's shape
// with the static instances replaced by functions, because a static needs a
// Sendable type and an initializer that `--shared` has nowhere to run.
//
// The round trips are the point: text that survives a crossing and comes back
// is the only evidence that both halves agree.
module TextEncoding;

import Standard.Console;
import Standard.Text;
import Standard.Encoding;
import Standard.Convert;

void Say(String label, String value) {
    Console.WriteLine(label + " " + value);
}

void SayNumber(String label, long value) {
    Console.WriteLine(label + " " + Text.FromInteger(value));
}

void SayBool(String label, bool value) {
    Console.WriteLine(label + " " + Text.FromBool(value));
}

/// A round trip through one encoding, reported by whether it came back.
void RoundTrip(String label, IEncoding encoding, String text) {
    var bytes = encoding.GetBytes(text);
    var back = encoding.GetString(bytes);

    Console.WriteLine(label + " " + encoding.Name()
        + " " + Text.FromInteger((long)bytes.Length)
        + " " + Text.FromBool(back == text));
}

int Main() {
    // --------------------------------------------------------- round trips
    var sample = "héllo €";

    RoundTrip("utf8", Encoding.Utf8(), sample);
    RoundTrip("utf16", Encoding.Utf16(), sample);
    RoundTrip("utf16be", Encoding.Utf16BigEndian(), sample);
    RoundTrip("utf32", Encoding.Utf32(), sample);
    RoundTrip("utf32be", Encoding.Utf32BigEndian(), sample);
    RoundTrip("latin1", Encoding.Latin1(), "héllo");
    RoundTrip("cp1252", Encoding.Windows1252(), "héllo €");
    RoundTrip("ascii", Encoding.Ascii(), "hello");

    // A character outside the eight-bit world becomes `?` on the way out, so
    // the round trip does not come back and that is the honest answer.
    RoundTrip("latin1-lossy", Encoding.Latin1(), "€");

    // ------------------------------------------------------------ the bytes
    var utf16 = Encoding.Utf16().GetBytes("A");
    SayNumber("utf16-A-0", (long)utf16[0]);
    SayNumber("utf16-A-1", (long)utf16[1]);

    var utf16be = Encoding.Utf16BigEndian().GetBytes("A");
    SayNumber("utf16be-A-0", (long)utf16be[0]);
    SayNumber("utf16be-A-1", (long)utf16be[1]);

    SayNumber("utf32-count", (long)Encoding.Utf32().GetByteCount("héllo"));
    SayNumber("utf8-count", (long)Encoding.Utf8().GetByteCount("héllo"));
    SayNumber("latin1-count", (long)Encoding.Latin1().GetByteCount("héllo"));

    // Windows-1252 is Latin-1 with punctuation where the C1 controls were.
    var euro = Encoding.Windows1252().GetBytes("€");
    SayNumber("cp1252-euro", (long)euro[0]);
    Say("cp1252-back", Encoding.Windows1252().GetString([0x93, 0x94]));

    // --------------------------------------------------------- representable
    SayBool("ascii-can-a", Encoding.Ascii().CanRepresent((char32)97));
    SayBool("ascii-can-e", Encoding.Ascii().CanRepresent((char32)233));
    SayBool("latin1-can-e", Encoding.Latin1().CanRepresent((char32)233));
    SayBool("latin1-can-euro", Encoding.Latin1().CanRepresent((char32)0x20AC));
    SayBool("cp1252-can-euro", Encoding.Windows1252().CanRepresent((char32)0x20AC));
    SayBool("utf8-can-emoji", Encoding.Utf8().CanRepresent((char32)128512));

    // ------------------------------------------------------------- strictness
    var good = Encoding.Utf8().TryGetString([0x68, 0x69]);
    SayBool("strict-ok", good.Ok);

    // A lead byte with no continuation: the bytes ran out.
    var truncated = Encoding.Utf8().TryGetString([0xC3]);
    SayBool("strict-short", truncated.Ok);

    // 0xC0 0x80 is an overlong NUL -- it decodes, and is refused anyway,
    // because two spellings of one character is how a filter gets walked past.
    var overlong = Encoding.Utf8().TryGetString([0xC0, 0x80]);
    SayBool("strict-overlong", overlong.Ok);

    // Lossy, by contrast, always answers.
    Say("lossy-count",
        Text.FromInteger((long)Encoding.Utf8().GetString([0xC3]).CodePointCount()));

    // An odd number of bytes is half a UTF-16 unit.
    var odd = Encoding.Utf16().TryGetString([0x41]);
    SayBool("strict-odd", odd.Ok);

    // A single-byte encoding cannot fail: every byte means something.
    var never = Encoding.Latin1().TryGetString([0x00, 0xFF, 0x80]);
    SayBool("latin1-never-fails", never.Ok);

    // ------------------------------------------------------------- preambles
    SayNumber("utf8-bom", (long)Encoding.Utf8().Preamble().Length);
    SayNumber("latin1-bom", (long)Encoding.Latin1().Preamble().Length);

    var marked = Encoding.Detect([0xEF, 0xBB, 0xBF, 0x68]);
    if (marked != null) { Say("detect-utf8", marked.Name()); }

    var wide = Encoding.Detect([0xFF, 0xFE, 0x41, 0x00]);
    if (wide != null) { Say("detect-utf16", wide.Name()); }

    // A UTF-32LE mark begins with a UTF-16LE one, so the longer test has to
    // come first or every UTF-32 file reads as UTF-16.
    var widest = Encoding.Detect([0xFF, 0xFE, 0x00, 0x00]);
    if (widest != null) { Say("detect-utf32", widest.Name()); }

    var plain = Encoding.Detect([0x68, 0x69]);
    SayBool("detect-none", plain == null);

    var stripped = Encoding.WithoutPreamble(Encoding.Utf8(), [0xEF, 0xBB, 0xBF, 0x68]);
    SayNumber("stripped", (long)stripped.Length);

    // ------------------------------------------------------------- base64
    Say("b64-empty", "[" + Convert.ToBase64([]) + "]");
    Say("b64-1", Convert.ToBase64([102]));
    Say("b64-2", Convert.ToBase64([102, 111]));
    Say("b64-3", Convert.ToBase64([102, 111, 111]));
    Say("b64-text", Convert.ToBase64Text("Hello, World!"));
    Say("b64-url", Convert.ToBase64Url([251, 255, 190]));
    Say("b64-std", Convert.ToBase64([251, 255, 190]));

    var decoded = Convert.FromBase64("SGVsbG8sIFdvcmxkIQ==");
    switch (decoded) {
        case Ok ok: Say("b64-back", Encoding.Utf8().GetString(ok.Value)); break;
        case Fail: Say("b64-back", "failed"); break;
    }

    // Wrapped at a column, which is how base64 arrives in the wild.
    var wrapped = Convert.FromBase64("SGVs\nbG8s\nIFdv\ncmxk\nIQ==");
    switch (wrapped) {
        case Ok ok: Say("b64-wrapped", Encoding.Utf8().GetString(ok.Value)); break;
        case Fail: Say("b64-wrapped", "failed"); break;
    }

    // Both alphabets decode, so a JWT and a MIME body go through one door.
    var urlBack = Convert.FromBase64("-_--");
    SayBool("b64-url-back", urlBack.Ok);

    SayBool("b64-bad", Convert.FromBase64("a").Ok);
    SayBool("b64-junk", Convert.FromBase64("!!!!").Ok);

    // ---------------------------------------------------------------- hex
    Say("hex", Convert.ToHex([0x00, 0x0F, 0xA5, 0xFF]));
    Say("hex-upper", Convert.ToHex([0x0F, 0xA5], true));
    Say("hex-empty", "[" + Convert.ToHex([]) + "]");

    var unhex = Convert.FromHex("000fa5FF");
    switch (unhex) {
        case Ok ok:
            SayNumber("unhex-len", (long)ok.Value.Length);
            SayNumber("unhex-2", (long)ok.Value[2]);
            break;
        case Fail: Say("unhex", "failed"); break;
    }

    SayBool("hex-odd", Convert.FromHex("abc").Ok);
    SayBool("hex-junk", Convert.FromHex("zz").Ok);

    // ------------------------------------------------------------- numbers
    ShowLong("int", Convert.ToLong("1234"));
    ShowLong("int-neg", Convert.ToLong("-1234"));
    ShowLong("int-plus", Convert.ToLong("+7"));
    ShowLong("int-min", Convert.ToLong("-9223372036854775808"));
    ShowLong("int-max", Convert.ToLong("9223372036854775807"));
    ShowLong("hex-num", Convert.ToLong("1f", 16));
    ShowLong("hex-num-upper", Convert.ToLong("1F", 16));
    ShowLong("binary", Convert.ToLong("1011", 2));
    ShowLong("base36", Convert.ToLong("zz", 36));

    SayBool("int-empty", Convert.ToLong("").Ok);
    SayBool("int-space", Convert.ToLong(" 1").Ok);
    SayBool("int-junk", Convert.ToLong("12a").Ok);
    SayBool("int-overflow", Convert.ToLong("9223372036854775808").Ok);
    SayBool("int-sign-only", Convert.ToLong("-").Ok);

    var narrow = Convert.ToInt("2147483648");
    SayBool("int32-overflow", narrow.Ok);

    var fits = Convert.ToInt("-2147483648");
    switch (fits) {
        case Ok ok: SayNumber("int32-min", (long)ok.Value); break;
        case Fail: Say("int32-min", "failed"); break;
    }

    var unsigned = Convert.ToULong("18446744073709551615");
    SayBool("ulong-max", unsigned.Ok);
    SayBool("ulong-negative", Convert.ToULong("-1").Ok);

    Say("radix-16", Convert.FromLong(255, 16));
    Say("radix-2", Convert.FromLong(11, 2));
    Say("radix-36", Convert.FromLong(1295, 36));
    Say("radix-neg", Convert.FromLong(-255, 16));
    Say("radix-zero", Convert.FromLong(0, 16));

    ShowDouble("double", Convert.ToDouble("1.5"));
    ShowDouble("double-neg", Convert.ToDouble("-0.25"));
    ShowDouble("double-int", Convert.ToDouble("42"));
    ShowDouble("double-exp", Convert.ToDouble("1.5e2"));
    ShowDouble("double-negexp", Convert.ToDouble("15e-1"));

    SayBool("double-junk", Convert.ToDouble("1.2.3").Ok);
    SayBool("double-empty", Convert.ToDouble("").Ok);
    SayBool("double-dot", Convert.ToDouble(".").Ok);
    SayBool("double-bad-exp", Convert.ToDouble("1e").Ok);

    return 0;
}

void ShowLong(String label, Result<long, ConvertError> result) {
    switch (result) {
        case Ok ok: SayNumber(label, ok.Value); break;
        case Fail: Say(label, "failed"); break;
    }
}

void ShowDouble(String label, Result<double, ConvertError> result) {
    switch (result) {
        case Ok ok: Say(label, Text.FromDouble(ok.Value)); break;
        case Fail: Say(label, "failed"); break;
    }
}
