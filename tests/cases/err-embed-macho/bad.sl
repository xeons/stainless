// Each way a Mach-O target refuses an `[Embed]` section, one static per line.
// The program is only bound, so no SDK is needed on any host.
module ErrEmbedMachO;

// SL0830: not 'segment,section'.
[Embed("ok.bin", Section = ".rodata")]
static readonly byte[] NoSegment;

[Embed("ok.bin", Section = "__DATA,__blob,regular", Access = "rw")]
static byte[] TwoCommas;

// SL0830: a header keeps sixteen bytes of each name.
[Embed("ok.bin", Section = "__DATA,__seventeen_bytes", Access = "rw")]
static byte[] TooLong;

// SL0830: a segment whose permissions the linker sets.
[Embed("ok.bin", Section = "__BLOBS,__blob")]
static readonly byte[] OtherSegment;

// SL0711: __TEXT is executable, whatever the section is called.
[Embed("ok.bin", Section = "__TEXT,__const")]
static readonly byte[] ExecutableConstant;

// SL0711: zero-fill holds no bytes.
[Embed("ok.bin", Section = "__DATA,__bss", Access = "rw")]
static byte[] ZeroFill;

// SL0708: no segment an embed can use is both writable and executable.
[Embed("ok.bin", Access = "rwx")]
static byte[] Both;

int Main() => 0;
