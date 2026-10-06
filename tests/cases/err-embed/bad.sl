// Each way an `[Embed]` can be refused, one static per line. ok.bin exists, so
// a line using it is refused for the reason it is about and not for a missing
// file.
module ErrEmbed;

static readonly String Named = "ok.bin";

// SLD0011: no path at all, which is the one field an embed cannot do without.
[Embed]
static readonly byte[] None;

// SLC0019: more values than the attribute has fields.
[Embed("ok.bin", ".a", "r", "spare")]
static readonly byte[] TooMany;

// SLD0012: a string literal, and nothing that merely has a string's value.
[Embed(Named)]
static readonly byte[] Constant;

[Embed("ok" + ".bin")]
static readonly byte[] Joined;

// SLD0014: the file itself.
[Embed("not-here.bin")]
static readonly byte[] Missing;

[Embed(".")]
static readonly byte[] ADirectory;

[Embed("")]
static readonly byte[] Empty;

// SLD0015: the access letters.
[Embed("ok.bin", Access = "w")]
static byte[] NoRead;

[Embed("ok.bin", Access = "rr")]
static byte[] Repeated;

[Embed("ok.bin", Access = "rz")]
static byte[] UnknownLetter;

// SLD0016: writable and executable, with no section named.
[Embed("ok.bin", Access = "rwx")]
static byte[] Both;

// SLD0017: a name no directive can carry.
[Embed("ok.bin", Section = "")]
static readonly byte[] Blank;

[Embed("ok.bin", Section = ".my data")]
static readonly byte[] Spaced;

[Embed("ok.bin", Section = ".a,b")]
static readonly byte[] Comma;

[Embed("ok.bin", Section = ".a\"b")]
static readonly byte[] Quoted;

// SLD0019: a section whose permissions are already decided — by the target, or
// by the first embed placed in it. Mach-O names a section after its segment,
// and err-embed-macho has the rest of what it refuses.
#if MACOS
[Embed("ok.bin", Section = "__TEXT,__const")]
static readonly byte[] MachOCode;
#endif

[Embed("ok.bin", Section = ".text")]
static readonly byte[] Code;

[Embed("ok.bin", Section = ".bss")]
static readonly byte[] Zeroed;

[Embed("ok.bin", Section = ".shared")]
static readonly byte[] First;

[Embed("ok.bin", Section = ".shared", Access = "rw")]
static byte[] Second;

// SLC0092, SLC0093, SLC0094: the general rules about an attribute's arguments,
// here as an embed writes them.
[Embed("ok.bin", Alignment = "8")]
static readonly byte[] NoSuchField;

[Embed("ok.bin", Access = "r", Access = "r")]
static readonly byte[] Twice;

[Embed("ok.bin", Section = ".a", "rw")]
static byte[] PositionalLast;

// SLD0020: an embed is bytes, and this is not.
[Embed("ok.bin")]
static readonly String NotBytes;

// SLD0021: two answers to the question of what the static holds.
[Embed("ok.bin")]
static readonly byte[] AlsoAssigned = null;

// SLO0014: the other half of the same rule — no attribute and no value.
static readonly int Uninitialized;

// SLC0096: an instance field is not a static, and neither is a type.
public class Holder
{
    [Embed("ok.bin")]
    public byte[] Instance;
}

[Embed("ok.bin")]
public class Marked { }

int Main()
{
    return 0;
}
