# Standard.IO.Compression

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

Deflate, gzip and zlib: RFC 1951, 1952 and 1950, as streams and as
one-shot calls.

```csharp
var file = try FileStream.OpenRead("log.gz");
var gunzip = new GZipStream(file, CompressionMode.Decompress);
var text = try IO.ReadTextToEnd(gunzip);

byte[] packed = Compression.CompressGZip(data, CompressionLevel.SmallestSize);
var unpacked = Compression.DecompressGZip(packed);
```

**The shape is `System.IO.Compression`'s**: `DeflateStream`,
`GZipStream` and `ZLibStream` wrap another `IStream`, and are made with a
`CompressionMode` or a `CompressionLevel` and a `leaveOpen` flag. `Crc32`
and `Adler32` are the two checksums the formats use, and are public
because other formats — zip, PNG — use them too.

**How failure is reported follows `Standard.IO`.** A stream carries its
last error in `Error`, and a corrupt or truncated stream reads as
`IOError.InvalidData` there, as .NET throws `InvalidDataException`. The
exact reason is a `CompressionError` in `CompressionErrorCode`, alongside,
as `TcpClient` keeps the exact socket error beside the rounded one. The
one-shot `Decompress` functions return `Result<byte[], CompressionError>`,
since over memory the data is the only thing that can be wrong.

**Bad data is refused, never trusted.** Every code set is checked for
being over-subscribed or incomplete, every distance against the data
produced so far, every stored length against its complement, and every
trailer against the data. A refusal is a reported error, never an abort
and never a loop.

**Decompressing reads ahead.** The source is read in blocks of 16 KiB, so
up to that much past the end of the compressed data can be taken from it
and not given back. That is harmless when the compressed data is all the
source holds — a file, or an HTTP body behind a stream that stops at its
length or its last chunk — and it is why a raw `DeflateStream` cannot be
followed by other data on the same stream. .NET's streams do the same.

**Concatenated gzip members read as one stream**, as `gzip -d` reads them.
After a member, anything that does not begin another is ignored.

## Contents

**Types** &nbsp; [Adler32](#adler32-class) &middot; [CompressionError](#compressionerror-enum) &middot; [CompressionLevel](#compressionlevel-enum) &middot; [CompressionMode](#compressionmode-enum) &middot; [Crc32](#crc32-class) &middot; [DeflateStream](#deflatestream-class) &middot; [GZipStream](#gzipstream-class) &middot; [ZLibStream](#zlibstream-class)

**Functions** &nbsp; [CompressDeflate](#compressdeflate-function) &middot; [CompressDeflate](#compressdeflate-function) &middot; [CompressGZip](#compressgzip-function) &middot; [CompressGZip](#compressgzip-function) &middot; [CompressZLib](#compresszlib-function) &middot; [CompressZLib](#compresszlib-function) &middot; [DecompressDeflate](#decompressdeflate-function) &middot; [DecompressGZip](#decompressgzip-function) &middot; [DecompressZLib](#decompresszlib-function)

## Types

### Adler32 *class*

```
sealed class Adler32
```

Adler-32, the checksum a zlib stream ends with (RFC 1950 §8.2).

    uint check = Adler32.Compute("Wikipedia"u8);    // 0x11E60398

Two sums modulo 65521, the second a running total of the first. Weaker
than CRC-32 on short inputs and faster everywhere, which is why zlib
chose it.

<sub>[stdlib/IO/Compression/Adler32.sl:33](../../stdlib/IO/Compression/Adler32.sl#L33)</sub>

#### Value *property*

```
uint Value { get; }
```

The checksum of everything appended since construction or `Reset`.

<sub>[stdlib/IO/Compression/Adler32.sl:52](../../stdlib/IO/Compression/Adler32.sl#L52)</sub>

#### Compute *method*

```
static uint Compute(ReadOnlySpan<byte> data)
```

The checksum of `data` on its own.

<sub>[stdlib/IO/Compression/Adler32.sl:55](../../stdlib/IO/Compression/Adler32.sl#L55)</sub>

#### Append *method*

```
void Append(ReadOnlySpan<byte> data)
```

Adds `data` to what has been checked so far.

<sub>[stdlib/IO/Compression/Adler32.sl:63](../../stdlib/IO/Compression/Adler32.sl#L63)</sub>

#### Reset *method*

```
void Reset()
```

Forgets everything appended, as though the object were new.

<sub>[stdlib/IO/Compression/Adler32.sl:92](../../stdlib/IO/Compression/Adler32.sl#L92)</sub>

### CompressionError *enum*

```
enum CompressionError
```

Why compressed data was refused. `None` is success.

A stream rounds every one of these to `IOError.InvalidData` for a reader
that knows only `IStream`, and keeps the exact one in
`CompressionErrorCode`; the one-shot functions report it directly.

<sub>[stdlib/IO/Compression/CompressionError.sl:29](../../stdlib/IO/Compression/CompressionError.sl#L29)</sub>

#### None *case*

```
None = 0
```

Nothing went wrong.

<sub>[stdlib/IO/Compression/CompressionError.sl:32](../../stdlib/IO/Compression/CompressionError.sl#L32)</sub>

#### Truncated *case*

```
Truncated = 1
```

The data ended in the middle of a block, a header or a trailer.

<sub>[stdlib/IO/Compression/CompressionError.sl:35](../../stdlib/IO/Compression/CompressionError.sl#L35)</sub>

#### InvalidHeader *case*

```
InvalidHeader = 2
```

A gzip or zlib header that is not one: the wrong magic, a method
other than deflate, reserved bits set, or a zlib check that fails.

<sub>[stdlib/IO/Compression/CompressionError.sl:39](../../stdlib/IO/Compression/CompressionError.sl#L39)</sub>

#### DictionaryRequired *case*

```
DictionaryRequired = 3
```

A zlib stream that needs a preset dictionary. Nothing here can supply
one.

<sub>[stdlib/IO/Compression/CompressionError.sl:43](../../stdlib/IO/Compression/CompressionError.sl#L43)</sub>

#### InvalidBlockType *case*

```
InvalidBlockType = 4
```

A block of type 3, which RFC 1951 reserves.

<sub>[stdlib/IO/Compression/CompressionError.sl:46](../../stdlib/IO/Compression/CompressionError.sl#L46)</sub>

#### StoredLengthMismatch *case*

```
StoredLengthMismatch = 5
```

A stored block whose length and its complement disagree.

<sub>[stdlib/IO/Compression/CompressionError.sl:49](../../stdlib/IO/Compression/CompressionError.sl#L49)</sub>

#### InvalidCodeLengths *case*

```
InvalidCodeLengths = 6
```

A dynamic block's code lengths do not describe a usable code: too
many or too few symbols, an over-subscribed or incomplete set, a
repeat with nothing to repeat, or no end-of-block code.

<sub>[stdlib/IO/Compression/CompressionError.sl:54](../../stdlib/IO/Compression/CompressionError.sl#L54)</sub>

#### InvalidCode *case*

```
InvalidCode = 7
```

A bit pattern that no code in the block's tables stands for, or a
length or distance symbol the format reserves.

<sub>[stdlib/IO/Compression/CompressionError.sl:58](../../stdlib/IO/Compression/CompressionError.sl#L58)</sub>

#### InvalidDistance *case*

```
InvalidDistance = 8
```

A match reaching back past the start of the data.

<sub>[stdlib/IO/Compression/CompressionError.sl:61](../../stdlib/IO/Compression/CompressionError.sl#L61)</sub>

#### ChecksumMismatch *case*

```
ChecksumMismatch = 9
```

The CRC-32 or Adler-32 in the trailer does not match the data.

<sub>[stdlib/IO/Compression/CompressionError.sl:64](../../stdlib/IO/Compression/CompressionError.sl#L64)</sub>

#### LengthMismatch *case*

```
LengthMismatch = 10
```

The length in a gzip trailer does not match the data.

<sub>[stdlib/IO/Compression/CompressionError.sl:67](../../stdlib/IO/Compression/CompressionError.sl#L67)</sub>

### CompressionLevel *enum*

```
enum CompressionLevel
```

How hard a compressor works, as .NET's enum of the name.

Every level writes a stream any decompressor reads; the level trades time
for size and nothing else.

<sub>[stdlib/IO/Compression/CompressionLevel.sl:28](../../stdlib/IO/Compression/CompressionLevel.sl#L28)</sub>

#### Optimal *case*

```
Optimal = 0
```

A balance, as zlib's level 6: lazy matching over hash chains of up to
128.

<sub>[stdlib/IO/Compression/CompressionLevel.sl:32](../../stdlib/IO/Compression/CompressionLevel.sl#L32)</sub>

#### Fastest *case*

```
Fastest = 1
```

The quickest that still compresses, as zlib's level 1: greedy matching
over chains of four.

<sub>[stdlib/IO/Compression/CompressionLevel.sl:36](../../stdlib/IO/Compression/CompressionLevel.sl#L36)</sub>

#### NoCompression *case*

```
NoCompression = 2
```

Stored blocks only. The stream is valid and a little larger than its
input.

<sub>[stdlib/IO/Compression/CompressionLevel.sl:40](../../stdlib/IO/Compression/CompressionLevel.sl#L40)</sub>

#### SmallestSize *case*

```
SmallestSize = 3
```

The smallest this compressor makes, as zlib's level 9: lazy matching
over chains of up to 4096.

<sub>[stdlib/IO/Compression/CompressionLevel.sl:44](../../stdlib/IO/Compression/CompressionLevel.sl#L44)</sub>

### CompressionMode *enum*

```
enum CompressionMode
```

Which way a compression stream moves data, as .NET's enum of the name.

<sub>[stdlib/IO/Compression/CompressionMode.sl:25](../../stdlib/IO/Compression/CompressionMode.sl#L25)</sub>

#### Decompress *case*

```
Decompress = 0
```

Reading compressed bytes from the stream underneath and handing out
what they expand to.

<sub>[stdlib/IO/Compression/CompressionMode.sl:29](../../stdlib/IO/Compression/CompressionMode.sl#L29)</sub>

#### Compress *case*

```
Compress = 1
```

Taking bytes by `Write` and writing their compressed form to the
stream underneath.

<sub>[stdlib/IO/Compression/CompressionMode.sl:33](../../stdlib/IO/Compression/CompressionMode.sl#L33)</sub>

### Crc32 *class*

```
sealed class Crc32
```

CRC-32 as gzip, zip and PNG compute it: IEEE 802.3, reflected, polynomial
`0xEDB88320`, starting from all ones and inverted at the end.

    uint check = Crc32.Compute("123456789"u8);     // 0xCBF43926

**The table is built per object**, 256 words, rather than held in a
static: this module is compiled into every program, and a static would
run its initializer before every `Main`. Building it costs about as much
as checking two kilobytes, so an object that is kept and appended to is
the cheap way to check many small pieces.

<sub>[stdlib/IO/Compression/Crc32.sl:36](../../stdlib/IO/Compression/Crc32.sl#L36)</sub>

#### Value *property*

```
uint Value { get; }
```

The checksum of everything appended since construction or `Reset`.
Reading it changes nothing, so appending may go on afterwards.

<sub>[stdlib/IO/Compression/Crc32.sl:62](../../stdlib/IO/Compression/Crc32.sl#L62)</sub>

#### Compute *method*

```
static uint Compute(ReadOnlySpan<byte> data)
```

The checksum of `data` on its own.

<sub>[stdlib/IO/Compression/Crc32.sl:65](../../stdlib/IO/Compression/Crc32.sl#L65)</sub>

#### Append *method*

```
void Append(ReadOnlySpan<byte> data)
```

Adds `data` to what has been checked so far.

<sub>[stdlib/IO/Compression/Crc32.sl:73](../../stdlib/IO/Compression/Crc32.sl#L73)</sub>

#### Reset *method*

```
void Reset()
```

Forgets everything appended, as though the object were new.

<sub>[stdlib/IO/Compression/Crc32.sl:90](../../stdlib/IO/Compression/Crc32.sl#L90)</sub>

### DeflateStream *class*

```
class DeflateStream : IStream
```

Raw deflate (RFC 1951) over another stream, with no header and no
checksum: what zip entries and HTTP's `Content-Encoding: deflate` from a
misreading server hold.

    var packed = new MemoryStream();
    var deflate = new DeflateStream(packed, CompressionLevel.Optimal, true);
    deflate.Write(data, 0, data.Length);
    deflate.Close();                // the final block is written here

With nothing to check the data against, a corrupt stream is caught only
where it breaks the format; `GZipStream` and `ZLibStream` also verify
what was decoded. A raw stream also has no end marker beyond its final
block, and reading ahead means bytes after it on the same source are
lost to whoever reads next.

<sub>[stdlib/IO/Compression/DeflateStream.sl:40](../../stdlib/IO/Compression/DeflateStream.sl#L40)</sub>

#### BaseStream *property*

```
IStream BaseStream { get; }
```

The stream the compressed bytes come from or go to.

<sub>[stdlib/IO/Compression/DeflateStream.sl:85](../../stdlib/IO/Compression/DeflateStream.sl#L85)</sub>

#### CompressionErrorCode *property*

```
CompressionError CompressionErrorCode { get; }
```

Why the data was refused, exactly, where `Error` says only
`IOError.InvalidData`. `None` while nothing has been.

<sub>[stdlib/IO/Compression/DeflateStream.sl:89](../../stdlib/IO/Compression/DeflateStream.sl#L89)</sub>

#### CanRead *property*

```
bool CanRead { get; }
```

True while open, decompressing, and the stream underneath can be read.

<sub>[stdlib/IO/Compression/DeflateStream.sl:92](../../stdlib/IO/Compression/DeflateStream.sl#L92)</sub>

#### CanWrite *property*

```
bool CanWrite { get; }
```

True while open, compressing, and the stream underneath can be written.

<sub>[stdlib/IO/Compression/DeflateStream.sl:95](../../stdlib/IO/Compression/DeflateStream.sl#L95)</sub>

#### CanSeek *property*

```
bool CanSeek { get; }
```

Always false. Neither direction has a position to move to.

<sub>[stdlib/IO/Compression/DeflateStream.sl:98](../../stdlib/IO/Compression/DeflateStream.sl#L98)</sub>

#### Read *method*

```
nuint Read(byte[] buffer, nuint offset, nuint count)
```

Decompresses up to `count` bytes into `buffer` at `offset`, answering
how many. Fewer than asked for is normal; zero is the end of the data
or a failure, which `Error` tells apart. A compressing stream reads
nothing and reports `IOError.Invalid`.

<sub>[stdlib/IO/Compression/DeflateStream.sl:104](../../stdlib/IO/Compression/DeflateStream.sl#L104)</sub>

#### Write *method*

```
nuint Write(byte[] buffer, nuint offset, nuint count)
```

Compresses `count` bytes from `buffer` at `offset`, answering `count`,
or zero when writing onward failed. Output is written onward as it
fills, and not all of it until `Flush` or `Close`.

<sub>[stdlib/IO/Compression/DeflateStream.sl:110](../../stdlib/IO/Compression/DeflateStream.sl#L110)</sub>

#### Position *property*

```
long Position { get; }
```

Not a position.

<sub>[stdlib/IO/Compression/DeflateStream.sl:114](../../stdlib/IO/Compression/DeflateStream.sl#L114)</sub>

#### Length *property*

```
long Length { get; }
```

Not a length either.

<sub>[stdlib/IO/Compression/DeflateStream.sl:117](../../stdlib/IO/Compression/DeflateStream.sl#L117)</sub>

#### Seek *method*

```
bool Seek(long offset, SeekOrigin origin)
```

Always false.

<sub>[stdlib/IO/Compression/DeflateStream.sl:120](../../stdlib/IO/Compression/DeflateStream.sl#L120)</sub>

#### Flush *method*

```
void Flush()
```

Compressing, writes everything so far onward as whole bytes a reader
can decode, and flushes the stream underneath. Each flush costs a few
bytes of output, so it is for a protocol that needs the data to
arrive, not for a loop. Decompressing, does nothing.

<sub>[stdlib/IO/Compression/DeflateStream.sl:126](../../stdlib/IO/Compression/DeflateStream.sl#L126)</sub>

#### Close *method*

```
void Close()
```

Compressing, writes the final block, which a stream that is never
closed does not have. Then closes the stream underneath unless it was
to be left open. Idempotent, and the destructor calls it.

<sub>[stdlib/IO/Compression/DeflateStream.sl:131](../../stdlib/IO/Compression/DeflateStream.sl#L131)</sub>

#### Error *property*

```
IOError Error { get; }
```

The last error, or `IOError.None`. `IOError.InvalidData` means the
compressed data was refused, and `CompressionErrorCode` says why; any
other value came from the stream underneath.

<sub>[stdlib/IO/Compression/DeflateStream.sl:136](../../stdlib/IO/Compression/DeflateStream.sl#L136)</sub>

### GZipStream *class*

```
class GZipStream : IStream
```

gzip (RFC 1952) over another stream: a header, deflate data, and a
trailer holding the CRC-32 and the length of what was compressed.

    var file = try FileStream.OpenRead("notes.txt.gz");
    var text = try IO.ReadTextToEnd(new GZipStream(file, CompressionMode.Decompress));

Decompressing reads every header field and skips them — the name, the
comment, the extra field — and verifies the header CRC when there is one
and the trailer always. Several members one after another read as one
stream, as `gzip -d` reads them; after a member, bytes that do not start
another are ignored. Compressing writes the smallest header there is: no
name, no time, and an operating system of "unknown".

<sub>[stdlib/IO/Compression/GZipStream.sl:38](../../stdlib/IO/Compression/GZipStream.sl#L38)</sub>

#### BaseStream *property*

```
IStream BaseStream { get; }
```

The stream the compressed bytes come from or go to.

<sub>[stdlib/IO/Compression/GZipStream.sl:83](../../stdlib/IO/Compression/GZipStream.sl#L83)</sub>

#### CompressionErrorCode *property*

```
CompressionError CompressionErrorCode { get; }
```

Why the data was refused, exactly, where `Error` says only
`IOError.InvalidData`. `None` while nothing has been.

<sub>[stdlib/IO/Compression/GZipStream.sl:87](../../stdlib/IO/Compression/GZipStream.sl#L87)</sub>

#### CanRead *property*

```
bool CanRead { get; }
```

True while open, decompressing, and the stream underneath can be read.

<sub>[stdlib/IO/Compression/GZipStream.sl:90](../../stdlib/IO/Compression/GZipStream.sl#L90)</sub>

#### CanWrite *property*

```
bool CanWrite { get; }
```

True while open, compressing, and the stream underneath can be written.

<sub>[stdlib/IO/Compression/GZipStream.sl:93](../../stdlib/IO/Compression/GZipStream.sl#L93)</sub>

#### CanSeek *property*

```
bool CanSeek { get; }
```

Always false. Neither direction has a position to move to.

<sub>[stdlib/IO/Compression/GZipStream.sl:96](../../stdlib/IO/Compression/GZipStream.sl#L96)</sub>

#### Read *method*

```
nuint Read(byte[] buffer, nuint offset, nuint count)
```

Decompresses up to `count` bytes into `buffer` at `offset`, answering
how many. Fewer than asked for is normal; zero is the end of the data
or a failure, which `Error` tells apart. A compressing stream reads
nothing and reports `IOError.Invalid`.

<sub>[stdlib/IO/Compression/GZipStream.sl:102](../../stdlib/IO/Compression/GZipStream.sl#L102)</sub>

#### Write *method*

```
nuint Write(byte[] buffer, nuint offset, nuint count)
```

Compresses `count` bytes from `buffer` at `offset`, answering `count`,
or zero when writing onward failed. Output is written onward as it
fills, and not all of it until `Flush` or `Close`.

<sub>[stdlib/IO/Compression/GZipStream.sl:108](../../stdlib/IO/Compression/GZipStream.sl#L108)</sub>

#### Position *property*

```
long Position { get; }
```

Not a position.

<sub>[stdlib/IO/Compression/GZipStream.sl:112](../../stdlib/IO/Compression/GZipStream.sl#L112)</sub>

#### Length *property*

```
long Length { get; }
```

Not a length either.

<sub>[stdlib/IO/Compression/GZipStream.sl:115](../../stdlib/IO/Compression/GZipStream.sl#L115)</sub>

#### Seek *method*

```
bool Seek(long offset, SeekOrigin origin)
```

Always false.

<sub>[stdlib/IO/Compression/GZipStream.sl:118](../../stdlib/IO/Compression/GZipStream.sl#L118)</sub>

#### Flush *method*

```
void Flush()
```

Compressing, writes everything so far onward as whole bytes a reader
can decode, and flushes the stream underneath. Each flush costs a few
bytes of output, so it is for a protocol that needs the data to
arrive, not for a loop. Decompressing, does nothing.

<sub>[stdlib/IO/Compression/GZipStream.sl:124](../../stdlib/IO/Compression/GZipStream.sl#L124)</sub>

#### Close *method*

```
void Close()
```

Compressing, writes the final block, which a stream that is never
closed does not have. Then closes the stream underneath unless it was
to be left open. Idempotent, and the destructor calls it.

<sub>[stdlib/IO/Compression/GZipStream.sl:129](../../stdlib/IO/Compression/GZipStream.sl#L129)</sub>

#### Error *property*

```
IOError Error { get; }
```

The last error, or `IOError.None`. `IOError.InvalidData` means the
compressed data was refused, and `CompressionErrorCode` says why; any
other value came from the stream underneath.

<sub>[stdlib/IO/Compression/GZipStream.sl:134](../../stdlib/IO/Compression/GZipStream.sl#L134)</sub>

### ZLibStream *class*

```
class ZLibStream : IStream
```

zlib (RFC 1950) over another stream: two header bytes, deflate data, and
the Adler-32 of what was compressed. What HTTP's
`Content-Encoding: deflate` means, and what PNG's image data is.

    var packed = new MemoryStream();
    var zlib = new ZLibStream(packed, CompressionLevel.SmallestSize, true);
    zlib.Write(data, 0, data.Length);
    zlib.Close();

Decompressing checks the header and the trailer, and refuses a stream
that needs a preset dictionary, which nothing here can supply.

<sub>[stdlib/IO/Compression/ZLibStream.sl:37](../../stdlib/IO/Compression/ZLibStream.sl#L37)</sub>

#### BaseStream *property*

```
IStream BaseStream { get; }
```

The stream the compressed bytes come from or go to.

<sub>[stdlib/IO/Compression/ZLibStream.sl:82](../../stdlib/IO/Compression/ZLibStream.sl#L82)</sub>

#### CompressionErrorCode *property*

```
CompressionError CompressionErrorCode { get; }
```

Why the data was refused, exactly, where `Error` says only
`IOError.InvalidData`. `None` while nothing has been.

<sub>[stdlib/IO/Compression/ZLibStream.sl:86](../../stdlib/IO/Compression/ZLibStream.sl#L86)</sub>

#### CanRead *property*

```
bool CanRead { get; }
```

True while open, decompressing, and the stream underneath can be read.

<sub>[stdlib/IO/Compression/ZLibStream.sl:89](../../stdlib/IO/Compression/ZLibStream.sl#L89)</sub>

#### CanWrite *property*

```
bool CanWrite { get; }
```

True while open, compressing, and the stream underneath can be written.

<sub>[stdlib/IO/Compression/ZLibStream.sl:92](../../stdlib/IO/Compression/ZLibStream.sl#L92)</sub>

#### CanSeek *property*

```
bool CanSeek { get; }
```

Always false. Neither direction has a position to move to.

<sub>[stdlib/IO/Compression/ZLibStream.sl:95](../../stdlib/IO/Compression/ZLibStream.sl#L95)</sub>

#### Read *method*

```
nuint Read(byte[] buffer, nuint offset, nuint count)
```

Decompresses up to `count` bytes into `buffer` at `offset`, answering
how many. Fewer than asked for is normal; zero is the end of the data
or a failure, which `Error` tells apart. A compressing stream reads
nothing and reports `IOError.Invalid`.

<sub>[stdlib/IO/Compression/ZLibStream.sl:101](../../stdlib/IO/Compression/ZLibStream.sl#L101)</sub>

#### Write *method*

```
nuint Write(byte[] buffer, nuint offset, nuint count)
```

Compresses `count` bytes from `buffer` at `offset`, answering `count`,
or zero when writing onward failed. Output is written onward as it
fills, and not all of it until `Flush` or `Close`.

<sub>[stdlib/IO/Compression/ZLibStream.sl:107](../../stdlib/IO/Compression/ZLibStream.sl#L107)</sub>

#### Position *property*

```
long Position { get; }
```

Not a position.

<sub>[stdlib/IO/Compression/ZLibStream.sl:111](../../stdlib/IO/Compression/ZLibStream.sl#L111)</sub>

#### Length *property*

```
long Length { get; }
```

Not a length either.

<sub>[stdlib/IO/Compression/ZLibStream.sl:114](../../stdlib/IO/Compression/ZLibStream.sl#L114)</sub>

#### Seek *method*

```
bool Seek(long offset, SeekOrigin origin)
```

Always false.

<sub>[stdlib/IO/Compression/ZLibStream.sl:117](../../stdlib/IO/Compression/ZLibStream.sl#L117)</sub>

#### Flush *method*

```
void Flush()
```

Compressing, writes everything so far onward as whole bytes a reader
can decode, and flushes the stream underneath. Each flush costs a few
bytes of output, so it is for a protocol that needs the data to
arrive, not for a loop. Decompressing, does nothing.

<sub>[stdlib/IO/Compression/ZLibStream.sl:123](../../stdlib/IO/Compression/ZLibStream.sl#L123)</sub>

#### Close *method*

```
void Close()
```

Compressing, writes the final block, which a stream that is never
closed does not have. Then closes the stream underneath unless it was
to be left open. Idempotent, and the destructor calls it.

<sub>[stdlib/IO/Compression/ZLibStream.sl:128](../../stdlib/IO/Compression/ZLibStream.sl#L128)</sub>

#### Error *property*

```
IOError Error { get; }
```

The last error, or `IOError.None`. `IOError.InvalidData` means the
compressed data was refused, and `CompressionErrorCode` says why; any
other value came from the stream underneath.

<sub>[stdlib/IO/Compression/ZLibStream.sl:133](../../stdlib/IO/Compression/ZLibStream.sl#L133)</sub>

## Functions

### CompressDeflate *function*

```
byte[] CompressDeflate(ReadOnlySpan<byte> data)
```

`data` as raw deflate at `CompressionLevel.Optimal`.

**See also** &nbsp; [Compression.DecompressDeflate](#decompressdeflate-function)

<sub>[stdlib/IO/Compression/Compression.sl:78](../../stdlib/IO/Compression/Compression.sl#L78)</sub>

### CompressDeflate *function*

```
byte[] CompressDeflate(ReadOnlySpan<byte> data, CompressionLevel level)
```

`data` as raw deflate at `level`.

**Parameters**

- `data` — what to compress
- `level` — how hard to work at it

<sub>[stdlib/IO/Compression/Compression.sl:85](../../stdlib/IO/Compression/Compression.sl#L85)</sub>

### CompressGZip *function*

```
byte[] CompressGZip(ReadOnlySpan<byte> data)
```

`data` as one gzip member at `CompressionLevel.Optimal`.

**See also** &nbsp; [Compression.DecompressGZip](#decompressgzip-function)

<sub>[stdlib/IO/Compression/Compression.sl:91](../../stdlib/IO/Compression/Compression.sl#L91)</sub>

### CompressGZip *function*

```
byte[] CompressGZip(ReadOnlySpan<byte> data, CompressionLevel level)
```

`data` as one gzip member at `level`.

**Parameters**

- `data` — what to compress
- `level` — how hard to work at it

<sub>[stdlib/IO/Compression/Compression.sl:98](../../stdlib/IO/Compression/Compression.sl#L98)</sub>

### CompressZLib *function*

```
byte[] CompressZLib(ReadOnlySpan<byte> data)
```

`data` as a zlib stream at `CompressionLevel.Optimal`.

**See also** &nbsp; [Compression.DecompressZLib](#decompresszlib-function)

<sub>[stdlib/IO/Compression/Compression.sl:104](../../stdlib/IO/Compression/Compression.sl#L104)</sub>

### CompressZLib *function*

```
byte[] CompressZLib(ReadOnlySpan<byte> data, CompressionLevel level)
```

`data` as a zlib stream at `level`.

**Parameters**

- `data` — what to compress
- `level` — how hard to work at it

<sub>[stdlib/IO/Compression/Compression.sl:111](../../stdlib/IO/Compression/Compression.sl#L111)</sub>

### DecompressDeflate *function*

```
Result<byte[], CompressionError> DecompressDeflate(ReadOnlySpan<byte> data)
```

What raw deflate `data` expands to. Bytes after the final block are
ignored.

**Fails with**

- [CompressionError.Truncated](#truncated-case) — the data ends inside a block
- [CompressionError.InvalidBlockType](#invalidblocktype-case) — a block of the reserved type
- [CompressionError.StoredLengthMismatch](#storedlengthmismatch-case) — a stored block's length and complement disagree
- [CompressionError.InvalidCodeLengths](#invalidcodelengths-case) — a dynamic block's code is unusable
- [CompressionError.InvalidCode](#invalidcode-case) — a pattern no code stands for
- [CompressionError.InvalidDistance](#invaliddistance-case) — a match before the start

<sub>[stdlib/IO/Compression/Compression.sl:125](../../stdlib/IO/Compression/Compression.sl#L125)</sub>

### DecompressGZip *function*

```
Result<byte[], CompressionError> DecompressGZip(ReadOnlySpan<byte> data)
```

What gzip `data` expands to, every member of it in order.

**Fails with**

- [CompressionError.Truncated](#truncated-case) — the data ends inside a member
- [CompressionError.InvalidHeader](#invalidheader-case) — not a gzip header, or its CRC does not match
- [CompressionError.InvalidBlockType](#invalidblocktype-case) — a block of the reserved type
- [CompressionError.StoredLengthMismatch](#storedlengthmismatch-case) — a stored block's length and complement disagree
- [CompressionError.InvalidCodeLengths](#invalidcodelengths-case) — a dynamic block's code is unusable
- [CompressionError.InvalidCode](#invalidcode-case) — a pattern no code stands for
- [CompressionError.InvalidDistance](#invaliddistance-case) — a match before the start
- [CompressionError.ChecksumMismatch](#checksummismatch-case) — the CRC-32 does not match
- [CompressionError.LengthMismatch](#lengthmismatch-case) — the length does not match

<sub>[stdlib/IO/Compression/Compression.sl:143](../../stdlib/IO/Compression/Compression.sl#L143)</sub>

### DecompressZLib *function*

```
Result<byte[], CompressionError> DecompressZLib(ReadOnlySpan<byte> data)
```

What zlib `data` expands to. Bytes after the trailer are ignored.

**Fails with**

- [CompressionError.Truncated](#truncated-case) — the data ends early
- [CompressionError.InvalidHeader](#invalidheader-case) — not a zlib header
- [CompressionError.DictionaryRequired](#dictionaryrequired-case) — it needs a preset dictionary
- [CompressionError.InvalidBlockType](#invalidblocktype-case) — a block of the reserved type
- [CompressionError.StoredLengthMismatch](#storedlengthmismatch-case) — a stored block's length and complement disagree
- [CompressionError.InvalidCodeLengths](#invalidcodelengths-case) — a dynamic block's code is unusable
- [CompressionError.InvalidCode](#invalidcode-case) — a pattern no code stands for
- [CompressionError.InvalidDistance](#invaliddistance-case) — a match before the start
- [CompressionError.ChecksumMismatch](#checksummismatch-case) — the Adler-32 does not match

<sub>[stdlib/IO/Compression/Compression.sl:159](../../stdlib/IO/Compression/Compression.sl#L159)</sub>

