# Standard.IO

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

Streams, and the vocabulary the rest of the I/O modules share.

**How failure is reported.** Stainless does not unwind, so an operation that
can fail says so in its return type:

  - An operation that produces something returns `Result<T, IOError>`, the
    language's own type. `Value` is unreadable until the compiler has seen
    `Ok` checked, so there is no failed result to read by mistake.
  - An operation that produces nothing returns an `IOError` directly, and
    `IOError.None` is success.
  - A stream carries its last error instead, because a stream is used in a
    loop and checking after each step would drown the code it is in.

That is three shapes rather than one, and it is deliberate: a single shape
would make the common cases read worse than the rare one.

## Contents

**Types** &nbsp; [FileAccess](#fileaccess-enum) &middot; [FileMode](#filemode-enum) &middot; [FileStream](#filestream-class) &middot; [IOError](#ioerror-enum) &middot; [IStream](#istream-interface) &middot; [MemoryStream](#memorystream-class) &middot; [SeekOrigin](#seekorigin-enum) &middot; [StreamReader](#streamreader-class) &middot; [StreamWriter](#streamwriter-class) &middot; [StringReader](#stringreader-class) &middot; [StringWriter](#stringwriter-class) &middot; [TextReader](#textreader-class) &middot; [TextWriter](#textwriter-class)

**Functions** &nbsp; [DescribeIOError](#describeioerror-function) &middot; [ReadTextToEnd](#readtexttoend-function) &middot; [ReadToEnd](#readtoend-function) &middot; [SplitLines](#splitlines-function)

## Types

### FileAccess *enum*

```
enum FileAccess
```

What may be done with an open file. The members combine.

<sub>[stdlib/IO/FileAccess.sl:27](../../stdlib/IO/FileAccess.sl#L27)</sub>

#### None *case*

```
None = 0
```

Neither. Not useful for opening anything.

<sub>[stdlib/IO/FileAccess.sl:31](../../stdlib/IO/FileAccess.sl#L31)</sub>

#### Read *case*

```
Read = 1
```

Reading.

<sub>[stdlib/IO/FileAccess.sl:34](../../stdlib/IO/FileAccess.sl#L34)</sub>

#### Write *case*

```
Write = 2
```

Writing.

<sub>[stdlib/IO/FileAccess.sl:37](../../stdlib/IO/FileAccess.sl#L37)</sub>

#### ReadWrite *case*

```
ReadWrite = 3
```

Both, which is `Read | Write` written out.

<sub>[stdlib/IO/FileAccess.sl:40](../../stdlib/IO/FileAccess.sl#L40)</sub>

### FileMode *enum*

```
enum FileMode
```

What opening a file should do about whether it is already there.

<sub>[stdlib/IO/FileMode.sl:29](../../stdlib/IO/FileMode.sl#L29)</sub>

#### Open *case*

```
Open = 0
```

It must exist.

<sub>[stdlib/IO/FileMode.sl:32](../../stdlib/IO/FileMode.sl#L32)</sub>

#### Create *case*

```
Create = 1
```

Create it, or replace what is there.

<sub>[stdlib/IO/FileMode.sl:34](../../stdlib/IO/FileMode.sl#L34)</sub>

#### Append *case*

```
Append = 2
```

Create it if needed, and write at the end.

<sub>[stdlib/IO/FileMode.sl:36](../../stdlib/IO/FileMode.sl#L36)</sub>

### FileStream *class*

```
class FileStream : IStream
```

A stream over a file.

Made through `FileStream.Open` and its three shorthands, each of which
returns a `Result<FileStream, IOError>`:

    var file = try FileStream.Create("notes.txt");

The constructor is private, and that is the point. A constructor has to
return its own type, so it cannot say why an open failed -- the best it can
do is hand back a stream holding nothing, which is a value a caller can go
on using while nothing forces the check that would have caught it. A Result
cannot be read without naming which case it is.

The factories are static methods here rather than functions in the module
because that is where a reader looks for how to make one, and because a
static method is inside the type: it can use the private constructor, which
is what lets the failing path be closed off rather than merely discouraged.

`IsOpen` remains, because a stream can be closed after it was opened, and
`Error` remains for a failure during a read or a write -- those are
outcomes of an operation rather than of the opening, and there is nowhere
else to put them.

Closing is the destructor's job too, so a stream that goes out of scope
releases its handle whether or not `Close` was called.

<sub>[stdlib/IO/FileStream.sl:53](../../stdlib/IO/FileStream.sl#L53)</sub>

#### Open *method*

```
static Result<FileStream, IOError> Open(String path, FileMode mode, FileAccess access)
```

Opens a file, or says why it could not be opened.

**Parameters**

- `path` — the file to open
- `mode` — what to do about whether it is already there
- `access` — what may be done with it once it is open

**Fails with**

- [IOError.NotFound](#notfound-case) — `FileMode.Open` and there is no file there, or a directory along the path is missing
- [IOError.AccessDenied](#accessdenied-case) — the file or its directory refuses it
- [IOError.IsADirectory](#isadirectory-case) — a writing mode on a path that names a directory
- [IOError.Unknown](#unknown-case) — the platform reported something with no case of its own -- too many open files among them

<sub>[stdlib/IO/FileStream.sl:85](../../stdlib/IO/FileStream.sl#L85)</sub>

#### OpenRead *method*

```
static Result<FileStream, IOError> OpenRead(String path)
```

Opens an existing file for reading.

**Fails with**

- [IOError.NotFound](#notfound-case) — there is no file at that path
- [IOError.AccessDenied](#accessdenied-case) — the file refuses to be read
- [IOError.Unknown](#unknown-case) — the platform reported something with no case of its own

**See also** &nbsp; [FileStream.Open](#open-method)

<sub>[stdlib/IO/FileStream.sl:101](../../stdlib/IO/FileStream.sl#L101)</sub>

#### Create *method*

```
static Result<FileStream, IOError> Create(String path)
```

Creates the file, or replaces what is there.

**Fails with**

- [IOError.NotFound](#notfound-case) — a directory along the path is missing
- [IOError.AccessDenied](#accessdenied-case) — the file or its directory refuses it
- [IOError.IsADirectory](#isadirectory-case) — the path names a directory
- [IOError.Unknown](#unknown-case) — the platform reported something with no case of its own

**See also** &nbsp; [FileStream.Open](#open-method)

<sub>[stdlib/IO/FileStream.sl:114](../../stdlib/IO/FileStream.sl#L114)</sub>

#### OpenAppend *method*

```
static Result<FileStream, IOError> OpenAppend(String path)
```

Opens for writing at the end, creating the file if it is not there.

**Fails with**

- [IOError.NotFound](#notfound-case) — a directory along the path is missing
- [IOError.AccessDenied](#accessdenied-case) — the file or its directory refuses it
- [IOError.IsADirectory](#isadirectory-case) — the path names a directory
- [IOError.Unknown](#unknown-case) — the platform reported something with no case of its own

**See also** &nbsp; [FileStream.Open](#open-method)

<sub>[stdlib/IO/FileStream.sl:127](../../stdlib/IO/FileStream.sl#L127)</sub>

#### IsOpen *property*

```
bool IsOpen { get; }
```

Whether the file is still open. False after `Close`, and after an
open that failed.

<sub>[stdlib/IO/FileStream.sl:136](../../stdlib/IO/FileStream.sl#L136)</sub>

#### CanRead *property*

```
bool CanRead { get; }
```

True while the file is open and was opened for reading. A file opened
for writing answers false, and `Read` on it fails rather than
returning nothing.

<sub>[stdlib/IO/FileStream.sl:141](../../stdlib/IO/FileStream.sl#L141)</sub>

#### CanWrite *property*

```
bool CanWrite { get; }
```

True while the file is open and was opened for writing.

<sub>[stdlib/IO/FileStream.sl:143](../../stdlib/IO/FileStream.sl#L143)</sub>

#### CanSeek *property*

```
bool CanSeek { get; }
```

True while the file is open. Every file is seekable, unlike a
connection.

<sub>[stdlib/IO/FileStream.sl:146](../../stdlib/IO/FileStream.sl#L146)</sub>

#### Read *method*

```
nuint Read(byte[] buffer, nuint offset, nuint count)
```

Reads up to `count` bytes into `buffer` at `offset`, answering how
many it read.

Zero means the end of the file, or a failure -- `Error` is what tells
the two apart. A count reaching past the end of `buffer` is refused as
`Invalid` rather than overrunning it.

<sub>[stdlib/IO/FileStream.sl:154](../../stdlib/IO/FileStream.sl#L154)</sub>

#### Write *method*

```
nuint Write(byte[] buffer, nuint offset, nuint count)
```

Writes `count` bytes from `buffer` at `offset`, answering how many it
wrote.

Fewer than asked for means the write was cut short, and `Error` says
why -- a full disk, usually. A count reaching past the end of `buffer`
is refused as `Invalid`.

<sub>[stdlib/IO/FileStream.sl:181](../../stdlib/IO/FileStream.sl#L181)</sub>

#### WriteText *method*

```
nuint WriteText(String text)
```

Writes the UTF-8 bytes of `text`, which is what a String already holds,
so nothing is converted or copied on the way.

<sub>[stdlib/IO/FileStream.sl:204](../../stdlib/IO/FileStream.sl#L204)</sub>

#### Position *property*

```
long Position { get; }
```

How far into the file the next read or write will happen, or -1 when
the file is closed.

<sub>[stdlib/IO/FileStream.sl:222](../../stdlib/IO/FileStream.sl#L222)</sub>

#### Length *property*

```
long Length { get; }
```

How many bytes the file holds, or -1 when it is closed. Asks the
system each time rather than caching, so it sees a file another
process has grown.

<sub>[stdlib/IO/FileStream.sl:235](../../stdlib/IO/FileStream.sl#L235)</sub>

#### Seek *method*

```
bool Seek(long offset, SeekOrigin origin)
```

Moves the position, answering whether it worked.

Seeking past the end is allowed and does not extend the file; the gap
becomes zeroes when something is written there.

<sub>[stdlib/IO/FileStream.sl:249](../../stdlib/IO/FileStream.sl#L249)</sub>

#### Flush *method*

```
void Flush()
```

Pushes buffered bytes to the system. Not the same as reaching the
disk -- the system's own cache is still in front of it -- so this is
what makes a write visible to other processes, not what makes it
survive a power cut. `Error` says whether the system took them.

<sub>[stdlib/IO/FileStream.sl:267](../../stdlib/IO/FileStream.sl#L267)</sub>

#### Close *method*

```
void Close()
```

Closes the file. Calling it twice is harmless, which matters because the
destructor calls it too.

Bytes still buffered are written here, so a write can fail here: a
caller that needs to know its data arrived MUST read `Error` after the
first `Close`. A second call leaves it alone.

<sub>[stdlib/IO/FileStream.sl:279](../../stdlib/IO/FileStream.sl#L279)</sub>

#### Error *property*

```
IOError Error { get; }
```

The last error, or `None`. Set by every call that failed and left
alone by one that did not, so read it directly after the call it
belongs to.

<sub>[stdlib/IO/FileStream.sl:291](../../stdlib/IO/FileStream.sl#L291)</sub>

### IOError *enum*

```
enum IOError
```

Why an operation did not work. `None` is success.

These are the distinctions a program can act on, not the platform's whole
error list: the values are the same on every platform, which `errno` is not.

<sub>[stdlib/IO/IOError.sl:32](../../stdlib/IO/IOError.sl#L32)</sub>

#### None *case*

```
None = 0
```

Nothing went wrong.

<sub>[stdlib/IO/IOError.sl:35](../../stdlib/IO/IOError.sl#L35)</sub>

#### NotFound *case*

```
NotFound = 1
```

No such file, or a directory along the path is missing.

<sub>[stdlib/IO/IOError.sl:38](../../stdlib/IO/IOError.sl#L38)</sub>

#### AccessDenied *case*

```
AccessDenied = 2
```

It is there and this process may not touch it that way.

<sub>[stdlib/IO/IOError.sl:41](../../stdlib/IO/IOError.sl#L41)</sub>

#### AlreadyExists *case*

```
AlreadyExists = 3
```

Creating something that is already there.

<sub>[stdlib/IO/IOError.sl:44](../../stdlib/IO/IOError.sl#L44)</sub>

#### NotADirectory *case*

```
NotADirectory = 4
```

A path used a file as though it were a directory.

<sub>[stdlib/IO/IOError.sl:47](../../stdlib/IO/IOError.sl#L47)</sub>

#### IsADirectory *case*

```
IsADirectory = 5
```

A directory was given where a file was wanted.

<sub>[stdlib/IO/IOError.sl:50](../../stdlib/IO/IOError.sl#L50)</sub>

#### Invalid *case*

```
Invalid = 6
```

The request made no sense -- a count past the end of a buffer, a
negative seek, a mode the operation cannot take.

<sub>[stdlib/IO/IOError.sl:54](../../stdlib/IO/IOError.sl#L54)</sub>

#### EndOfFile *case*

```
EndOfFile = 7
```

The end of the file. A read that returns zero is the usual way this is
seen, so this value is rarer than it looks.

<sub>[stdlib/IO/IOError.sl:58](../../stdlib/IO/IOError.sl#L58)</sub>

#### Closed *case*

```
Closed = 8
```

The stream was closed before the call.

<sub>[stdlib/IO/IOError.sl:61](../../stdlib/IO/IOError.sl#L61)</sub>

#### Unknown *case*

```
Unknown = 9
```

The platform said something this enum has no name for.

<sub>[stdlib/IO/IOError.sl:64](../../stdlib/IO/IOError.sl#L64)</sub>

### IStream *interface*

```
interface IStream
```

A sequence of bytes that can be read, written, or both.

Read and Write report how many bytes they moved, which for a read is how
end-of-file is seen: fewer than asked for, and zero at the end. Whether
that was an error rather than an ending is what `Error` says.

<sub>[stdlib/IO/IStream.sl:33](../../stdlib/IO/IStream.sl#L33)</sub>

#### CanRead *property*

```
bool CanRead { get; }
```

Whether reading is allowed and possible now. False on a write-only
stream and on a closed one.

<sub>[stdlib/IO/IStream.sl:37](../../stdlib/IO/IStream.sl#L37)</sub>

#### CanWrite *property*

```
bool CanWrite { get; }
```

Whether writing is allowed and possible now.

<sub>[stdlib/IO/IStream.sl:40](../../stdlib/IO/IStream.sl#L40)</sub>

#### CanSeek *property*

```
bool CanSeek { get; }
```

Whether the position can be moved. False for a stream with no position
to move -- a socket, a pipe -- where `Seek` fails and `Position` and
`Length` answer -1.

<sub>[stdlib/IO/IStream.sl:45](../../stdlib/IO/IStream.sl#L45)</sub>

#### Read *method*

```
nuint Read(byte[] buffer, nuint offset, nuint count)
```

Reads up to `count` bytes into `buffer` starting at `offset`, and
returns how many it read. Zero means the end.

<sub>[stdlib/IO/IStream.sl:49](../../stdlib/IO/IStream.sl#L49)</sub>

#### Write *method*

```
nuint Write(byte[] buffer, nuint offset, nuint count)
```

Writes `count` bytes from `buffer` starting at `offset`, and returns
how many it wrote.

<sub>[stdlib/IO/IStream.sl:53](../../stdlib/IO/IStream.sl#L53)</sub>

#### Position *property*

```
long Position { get; }
```

Where the next read or write will happen, or -1 when the stream has no
position.

<sub>[stdlib/IO/IStream.sl:57](../../stdlib/IO/IStream.sl#L57)</sub>

#### Length *property*

```
long Length { get; }
```

How many bytes the stream holds, or -1 when it cannot say -- which is
every stream that is not seekable, and some that are.

<sub>[stdlib/IO/IStream.sl:61](../../stdlib/IO/IStream.sl#L61)</sub>

#### Seek *method*

```
bool Seek(long offset, SeekOrigin origin)
```

Moves the cursor. Reports whether it could.

<sub>[stdlib/IO/IStream.sl:64](../../stdlib/IO/IStream.sl#L64)</sub>

#### Flush *method*

```
void Flush()
```

Pushes buffered bytes onward. What "onward" means is the stream's: for
a file it is the system, not the disk.

<sub>[stdlib/IO/IStream.sl:68](../../stdlib/IO/IStream.sl#L68)</sub>

#### Close *method*

```
void Close()
```

Releases whatever the stream holds. Implementations make this
idempotent, and a destructor calls it, so a stream that goes out of
scope is not leaked.

<sub>[stdlib/IO/IStream.sl:73](../../stdlib/IO/IStream.sl#L73)</sub>

#### Error *property*

```
IOError Error { get; }
```

The last error, or `IOError.None`. Cleared by the next successful call.

<sub>[stdlib/IO/IStream.sl:76](../../stdlib/IO/IStream.sl#L76)</sub>

### MemoryStream *class*

```
class MemoryStream : IStream
```

A stream over a growable byte buffer.

The same interface as a file, with nothing behind it but memory: useful for
building a payload before writing it, and for testing something that takes
an `IStream` without touching a disk.

<sub>[stdlib/IO/MemoryStream.sl:33](../../stdlib/IO/MemoryStream.sl#L33)</sub>

#### CanRead *property*

```
bool CanRead { get; }
```

Always true.

<sub>[stdlib/IO/MemoryStream.sl:58](../../stdlib/IO/MemoryStream.sl#L58)</sub>

#### CanWrite *property*

```
bool CanWrite { get; }
```

Always true.

<sub>[stdlib/IO/MemoryStream.sl:60](../../stdlib/IO/MemoryStream.sl#L60)</sub>

#### CanSeek *property*

```
bool CanSeek { get; }
```

Always true.

<sub>[stdlib/IO/MemoryStream.sl:62](../../stdlib/IO/MemoryStream.sl#L62)</sub>

#### Read *method*

```
nuint Read(byte[] buffer, nuint offset, nuint count)
```

Reads up to `count` bytes into `buffer` at `offset`, answering how
many it read. Zero means the position has reached the end; there is no
failure to distinguish it from.

<sub>[stdlib/IO/MemoryStream.sl:67](../../stdlib/IO/MemoryStream.sl#L67)</sub>

#### Write *method*

```
nuint Write(byte[] buffer, nuint offset, nuint count)
```

Writes `count` bytes from `buffer` at `offset`, growing the buffer as
needed and answering `count`.

Writing over the middle replaces those bytes rather than inserting, so
the length only grows when the position passes the old end.

<sub>[stdlib/IO/MemoryStream.sl:86](../../stdlib/IO/MemoryStream.sl#L86)</sub>

#### WriteText *method*

```
void WriteText(String text)
```

Appends the UTF-8 bytes of `text`.

<sub>[stdlib/IO/MemoryStream.sl:102](../../stdlib/IO/MemoryStream.sl#L102)</sub>

#### Position *property*

```
long Position { get; }
```

Where the next read or write will happen.

<sub>[stdlib/IO/MemoryStream.sl:117](../../stdlib/IO/MemoryStream.sl#L117)</sub>

#### Length *property*

```
long Length { get; }
```

How many bytes have been written, measured to the furthest the
position has ever reached -- not the capacity of the buffer behind it.

<sub>[stdlib/IO/MemoryStream.sl:120](../../stdlib/IO/MemoryStream.sl#L120)</sub>

#### Seek *method*

```
bool Seek(long offset, SeekOrigin origin)
```

Moves the position, answering whether it worked.

Unlike a file, seeking past the end is refused: there is nothing there
to leave a gap in.

<sub>[stdlib/IO/MemoryStream.sl:126](../../stdlib/IO/MemoryStream.sl#L126)</sub>

#### Flush *method*

```
void Flush()
```

Does nothing. There is nothing behind the buffer to push bytes to.

<sub>[stdlib/IO/MemoryStream.sl:141](../../stdlib/IO/MemoryStream.sl#L141)</sub>

#### Close *method*

```
void Close()
```

Nothing to release; a memory stream stays usable after it.

<sub>[stdlib/IO/MemoryStream.sl:144](../../stdlib/IO/MemoryStream.sl#L144)</sub>

#### Error *property*

```
IOError Error { get; }
```

Always `None`. Nothing a memory stream does can fail.

<sub>[stdlib/IO/MemoryStream.sl:147](../../stdlib/IO/MemoryStream.sl#L147)</sub>

#### ToArray *method*

```
byte[] ToArray()
```

A copy of what has been written, from the start to the high-water mark.

<sub>[stdlib/IO/MemoryStream.sl:150](../../stdlib/IO/MemoryStream.sl#L150)</sub>

#### ToText *method*

```
String ToText()
```

The contents as text, read as UTF-8.

<sub>[stdlib/IO/MemoryStream.sl:159](../../stdlib/IO/MemoryStream.sl#L159)</sub>

### SeekOrigin *enum*

```
enum SeekOrigin
```

Where a seek offset is measured from.

<sub>[stdlib/IO/SeekOrigin.sl:27](../../stdlib/IO/SeekOrigin.sl#L27)</sub>

#### Start *case*

```
Start = 0
```

From the beginning, so the offset is the position. Negative is refused.

<sub>[stdlib/IO/SeekOrigin.sl:30](../../stdlib/IO/SeekOrigin.sl#L30)</sub>

#### Current *case*

```
Current = 1
```

From where the stream is now. Negative moves back.

<sub>[stdlib/IO/SeekOrigin.sl:33](../../stdlib/IO/SeekOrigin.sl#L33)</sub>

#### End *case*

```
End = 2
```

From the end, so a negative offset is the usual direction and zero is
the end itself.

<sub>[stdlib/IO/SeekOrigin.sl:37](../../stdlib/IO/SeekOrigin.sl#L37)</sub>

### StreamReader *class*

```
class StreamReader : TextReader
```

A reader over a stream, decoding as it goes.

It reads a buffer at a time and decodes each one through an `IDecoder`,
which keeps the bytes a buffer ended in the middle of and finishes the
character when the next buffer arrives. That is what makes this a stream
reader rather than a way of spelling `ReadToEnd`: a log being followed, or
a file larger than memory, works.

A byte order mark at the very start is dropped, in whatever encoding: it
says how the text is stored and is not part of the first line.

`ReadLine` answers null at the end and also when the stream fails; `Error`
tells the two apart.

**See also** &nbsp; [StreamWriter](#streamwriter-class)

<sub>[stdlib/IO/StreamReader.sl:43](../../stdlib/IO/StreamReader.sl#L43)</sub>

#### Encoding *property*

```
IEncoding Encoding { get; }
```

The encoding the text is being read as.

<sub>[stdlib/IO/StreamReader.sl:96](../../stdlib/IO/StreamReader.sl#L96)</sub>

#### Error *property*

```
IOError Error { get; }
```

Why the stream stopped, when it was a failure rather than the end.
`None` until then.

<sub>[stdlib/IO/StreamReader.sl:100](../../stdlib/IO/StreamReader.sl#L100)</sub>

#### ReadLine *method*

```
override String? ReadLine()
```

*No documentation.*

<sub>[stdlib/IO/StreamReader.sl:165](../../stdlib/IO/StreamReader.sl#L165)</sub>

#### ReadToEnd *method*

```
override String ReadToEnd()
```

*No documentation.*

<sub>[stdlib/IO/StreamReader.sl:203](../../stdlib/IO/StreamReader.sl#L203)</sub>

#### Close *method*

```
override void Close()
```

Closes the stream under it as well, which is what a reader owning one
is for.

<sub>[stdlib/IO/StreamReader.sl:233](../../stdlib/IO/StreamReader.sl#L233)</sub>

### StreamWriter *class*

```
class StreamWriter : TextWriter
```

A writer over a stream, encoding as it goes.

Unlike the reader this is genuinely incremental: every encoding here is
stateless, so each piece of text can be encoded and written on its own.

**See also** &nbsp; [StreamReader](#streamreader-class)

<sub>[stdlib/IO/StreamWriter.sl:34](../../stdlib/IO/StreamWriter.sl#L34)</sub>

#### Encoding *property*

```
IEncoding Encoding { get; }
```

The encoding the text is being written in.

<sub>[stdlib/IO/StreamWriter.sl:57](../../stdlib/IO/StreamWriter.sl#L57)</sub>

#### WritePreamble *method*

```
void WritePreamble()
```

The bytes that mark this encoding, written at the position the stream
is at. Call it before anything else or not at all.

<sub>[stdlib/IO/StreamWriter.sl:61](../../stdlib/IO/StreamWriter.sl#L61)</sub>

#### Write *method*

```
override void Write(String text)
```

*No documentation.*

<sub>[stdlib/IO/StreamWriter.sl:68](../../stdlib/IO/StreamWriter.sl#L68)</sub>

#### Flush *method*

```
override void Flush()
```

*No documentation.*

<sub>[stdlib/IO/StreamWriter.sl:78](../../stdlib/IO/StreamWriter.sl#L78)</sub>

#### Close *method*

```
override void Close()
```

Flushes and closes the stream under it.

<sub>[stdlib/IO/StreamWriter.sl:85](../../stdlib/IO/StreamWriter.sl#L85)</sub>

### StringReader *class*

```
class StringReader : TextReader
```

A reader over text already in memory.

**See also** &nbsp; [StringWriter](#stringwriter-class)

<sub>[stdlib/IO/StringReader.sl:31](../../stdlib/IO/StringReader.sl#L31)</sub>

#### ReadLine *method*

```
override String? ReadLine()
```

*No documentation.*

<sub>[stdlib/IO/StringReader.sl:42](../../stdlib/IO/StringReader.sl#L42)</sub>

#### ReadToEnd *method*

```
override String ReadToEnd()
```

*No documentation.*

<sub>[stdlib/IO/StringReader.sl:65](../../stdlib/IO/StringReader.sl#L65)</sub>

#### Close *method*

```
override void Close()
```

*No documentation.*

<sub>[stdlib/IO/StringReader.sl:75](../../stdlib/IO/StringReader.sl#L75)</sub>

### StringWriter *class*

```
class StringWriter : TextWriter
```

A writer that keeps what it is given, for a caller that wanted a
`TextWriter` and a string rather than a file.

**See also** &nbsp; [StringReader](#stringreader-class)

<sub>[stdlib/IO/StringWriter.sl:32](../../stdlib/IO/StringWriter.sl#L32)</sub>

#### Write *method*

```
override void Write(String text)
```

*No documentation.*

<sub>[stdlib/IO/StringWriter.sl:41](../../stdlib/IO/StringWriter.sl#L41)</sub>

#### Flush *method*

```
override void Flush()
```

Nothing is held anywhere else, so this does nothing.

<sub>[stdlib/IO/StringWriter.sl:47](../../stdlib/IO/StringWriter.sl#L47)</sub>

#### Close *method*

```
override void Close()
```

Nothing is held anywhere else, so this does nothing either. What was
written stays readable.

<sub>[stdlib/IO/StringWriter.sl:51](../../stdlib/IO/StringWriter.sl#L51)</sub>

#### ToText *method*

```
String ToText()
```

What has been written so far. The writer stays usable afterwards.

<sub>[stdlib/IO/StringWriter.sl:54](../../stdlib/IO/StringWriter.sl#L54)</sub>

### TextReader *class*

```
abstract class TextReader
```

Text arriving from somewhere, a line at a time.

**See also** &nbsp; [TextWriter](#textwriter-class)

<sub>[stdlib/IO/TextReader.sl:33](../../stdlib/IO/TextReader.sl#L33)</sub>

#### ReadLine *method*

```
abstract String? ReadLine()
```

One line without its terminator, or null once there are no more.

Null rather than empty, because a blank line and no line at all are
different answers and a loop reading to the end has to tell them apart.

<sub>[stdlib/IO/TextReader.sl:39](../../stdlib/IO/TextReader.sl#L39)</sub>

#### ReadToEnd *method*

```
abstract String ReadToEnd()
```

Everything not yet read, as one string.

<sub>[stdlib/IO/TextReader.sl:42](../../stdlib/IO/TextReader.sl#L42)</sub>

#### Close *method*

```
abstract void Close()
```

Whatever the reader holds open.

<sub>[stdlib/IO/TextReader.sl:45](../../stdlib/IO/TextReader.sl#L45)</sub>

#### ReadLines *method*

```
String[] ReadLines()
```

Every remaining line, which is `ReadLine` until it says there are none.

<sub>[stdlib/IO/TextReader.sl:48](../../stdlib/IO/TextReader.sl#L48)</sub>

### TextWriter *class*

```
abstract class TextWriter
```

Text going somewhere, a piece at a time.

**See also** &nbsp; [TextReader](#textreader-class)

<sub>[stdlib/IO/TextWriter.sl:33](../../stdlib/IO/TextWriter.sl#L33)</sub>

#### Write *method*

```
abstract void Write(String text)
```

Text, with nothing after it.

<sub>[stdlib/IO/TextWriter.sl:39](../../stdlib/IO/TextWriter.sl#L39)</sub>

#### Flush *method*

```
abstract void Flush()
```

Pushes whatever is held onward.

<sub>[stdlib/IO/TextWriter.sl:42](../../stdlib/IO/TextWriter.sl#L42)</sub>

#### Close *method*

```
abstract void Close()
```

Flushes and releases what the writer holds.

<sub>[stdlib/IO/TextWriter.sl:45](../../stdlib/IO/TextWriter.sl#L45)</sub>

#### NewLine *property*

```
String NewLine { get; set; }
```

What ends a line here.

<sub>[stdlib/IO/TextWriter.sl:48](../../stdlib/IO/TextWriter.sl#L48)</sub>

#### WriteLine *method*

```
void WriteLine(String text)
```

Text and a line ending.

<sub>[stdlib/IO/TextWriter.sl:55](../../stdlib/IO/TextWriter.sl#L55)</sub>

#### WriteLine *method*

```
void WriteLine()
```

A line ending on its own.

<sub>[stdlib/IO/TextWriter.sl:62](../../stdlib/IO/TextWriter.sl#L62)</sub>

#### WriteLines *method*

```
void WriteLines(String[] lines)
```

Each of `lines`, each ended.

<sub>[stdlib/IO/TextWriter.sl:68](../../stdlib/IO/TextWriter.sl#L68)</sub>

## Functions

### DescribeIOError *function*

```
String DescribeIOError(IOError error)
```

A sentence describing an error, for a message a person will read.

**See also** &nbsp; [IOError](#ioerror-enum)

<sub>[stdlib/IO/IO.sl:56](../../stdlib/IO/IO.sl#L56)</sub>

### ReadTextToEnd *function*

```
Result<String, IOError> ReadTextToEnd(IStream stream)
```

Reads a stream to its end and reads the bytes as UTF-8.

**Fails with**

- [IOError.Closed](#closed-case) — the stream was closed before the read finished
- [IOError.AccessDenied](#accessdenied-case) — the stream refused to be read
- [IOError.Unknown](#unknown-case) — the stream failed for a reason with no case of its own

**See also** &nbsp; [IO.ReadToEnd](#readtoend-function)

<sub>[stdlib/IO/IO.sl:110](../../stdlib/IO/IO.sl#L110)</sub>

### ReadToEnd *function*

```
Result<byte[], IOError> ReadToEnd(IStream stream)
```

Reads a stream to its end.

**Fails with**

- [IOError.Closed](#closed-case) — the stream was closed before the read finished
- [IOError.AccessDenied](#accessdenied-case) — the stream refused to be read
- [IOError.Unknown](#unknown-case) — the stream failed for a reason with no case of its own

**See also** &nbsp; [IO.ReadTextToEnd](#readtexttoend-function)

<sub>[stdlib/IO/IO.sl:83](../../stdlib/IO/IO.sl#L83)</sub>

### SplitLines *function*

```
List<String> SplitLines(String text)
```

Splits text into lines, accepting either line ending and dropping a final
empty line, which is what a trailing newline produces.

**Returns** &nbsp; the lines, each without its ending

<sub>[stdlib/IO/IO.sl:125](../../stdlib/IO/IO.sl#L125)</sub>

