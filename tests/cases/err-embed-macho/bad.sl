// Each way a Mach-O target refuses an `[Embed]` section, one static per line.
// The program is only bound, so no SDK is needed on any host.
module ErrEmbedMachO;

// SLD0017: not 'segment,section'.
[Embed("ok.bin", Section = ".rodata")]
static readonly byte[] NoSegment;

[Embed("ok.bin", Section = "__DATA,__blob,regular", Access = "rw")]
static byte[] TwoCommas;

// SLD0017: a header keeps sixteen bytes of each name.
[Embed("ok.bin", Section = "__DATA,__seventeen_bytes", Access = "rw")]
static byte[] TooLong;

// SLD0017: a segment whose permissions the linker sets.
[Embed("ok.bin", Section = "__BLOBS,__blob")]
static readonly byte[] OtherSegment;

// SLD0019: __TEXT is executable, whatever the section is called.
[Embed("ok.bin", Section = "__TEXT,__const")]
static readonly byte[] ExecutableConstant;

// SLD0019: zero-fill holds no bytes.
[Embed("ok.bin", Section = "__DATA,__bss", Access = "rw")]
static byte[] ZeroFill;

// SLD0016: no segment an embed can use is both writable and executable.
[Embed("ok.bin", Access = "rwx")]
static byte[] Both;

int Main() => 0;
