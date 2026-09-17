// Each way an `embed` can be refused, one per line. ok.bin exists, so a line
// using it is refused for the reason it is about and not for a missing file.
module ErrEmbed;

static readonly String Named = "ok.bin";

int Main()
{
    // SL0703: the shape of the call.
    var none = embed();
    var two = embed("ok.bin", "ok.bin");
    var unknown = embed("ok.bin", alignment: "8");
    var twice = embed("ok.bin", access: "r", access: "r");

    // SL0704: a string literal, and nothing that merely has a string's value.
    var constant = embed(Named);
    var joined = embed("ok" + ".bin");

    // SL0706: the file itself.
    var missing = embed("not-here.bin");
    var directory = embed(".");
    var empty = embed("");

    // SL0707: the access letters.
    var noRead = embed("ok.bin", access: "w");
    var repeated = embed("ok.bin", access: "rr");
    var unknownLetter = embed("ok.bin", access: "rz");

    // SL0708: writable and executable, with no section named.
    var both = embed("ok.bin", access: "rwx");

    // SL0709: a name no directive can carry.
    var blank = embed("ok.bin", section: "");
    var spaced = embed("ok.bin", section: ".my data");
    var comma = embed("ok.bin", section: ".a,b");
    var quoted = embed("ok.bin", section: ".a\"b");

    // SL0711: a section whose permissions are already decided — by the
    // target, or by the first embed placed in it.
    var code = embed("ok.bin", section: ".text");
    var zeroed = embed("ok.bin", section: ".bss");
    var first = embed("ok.bin", section: ".shared");
    var second = embed("ok.bin", section: ".shared", access: "rw");

    return 0;
}
