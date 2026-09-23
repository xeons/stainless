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

<sub>[stdlib/IO.sl:128](../../stdlib/IO.sl#L128)</sub>

#### None *case*

```
None = 0
```

Neither. Not useful for opening anything.

<sub>[stdlib/IO.sl:132](../../stdlib/IO.sl#L132)</sub>

#### Read *case*

```
Read = 1
```

Reading.

<sub>[stdlib/IO.sl:135](../../stdlib/IO.sl#L135)</sub>

#### Write *case*

```
Write = 2
```

Writing.

<sub>[stdlib/IO.sl:138](../../stdlib/IO.sl#L138)</sub>

#### ReadWrite *case*

```
ReadWrite = 3
```

Both, which is `Read | Write` written out.

<sub>[stdlib/IO.sl:141](../../stdlib/IO.sl#L141)</sub>

### FileMode *enum*

```
enum FileMode
```

What opening a file should do about whether it is already there.

<sub>[stdlib/IO.sl:117](../../stdlib/IO.sl#L117)</sub>

#### Open *case*

```
Open = 0
```

It must exist.

<sub>[stdlib/IO.sl:120](../../stdlib/IO.sl#L120)</sub>

#### Create *case*

```
Create = 1
```

Create it, or replace what is there.

<sub>[stdlib/IO.sl:122](../../stdlib/IO.sl#L122)</sub>

#### Append *case*

```
Append = 2
```

Create it if needed, and write at the end.

<sub>[stdlib/IO.sl:124](../../stdlib/IO.sl#L124)</sub>

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

<sub>[stdlib/IO.sl:238](../../stdlib/IO.sl#L238)</sub>

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

<sub>[stdlib/IO.sl:270](../../stdlib/IO.sl#L270)</sub>

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

<sub>[stdlib/IO.sl:286](../../stdlib/IO.sl#L286)</sub>

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

<sub>[stdlib/IO.sl:299](../../stdlib/IO.sl#L299)</sub>

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

<sub>[stdlib/IO.sl:312](../../stdlib/IO.sl#L312)</sub>

#### IsOpen *property*

```
bool IsOpen { get; }
```

Whether the file is still open. False after `Close`, and after an
open that failed.

<sub>[stdlib/IO.sl:321](../../stdlib/IO.sl#L321)</sub>

#### CanRead *property*

```
bool CanRead { get; }
```

True while the file is open and was opened for reading. A file opened
for writing answers false, and `Read` on it fails rather than
returning nothing.

<sub>[stdlib/IO.sl:326](../../stdlib/IO.sl#L326)</sub>

#### CanWrite *property*

```
bool CanWrite { get; }
```

True while the file is open and was opened for writing.

<sub>[stdlib/IO.sl:328](../../stdlib/IO.sl#L328)</sub>

#### CanSeek *property*

```
bool CanSeek { get; }
```

True while the file is open. Every file is seekable, unlike a
connection.

<sub>[stdlib/IO.sl:331](../../stdlib/IO.sl#L331)</sub>

#### Read *method*

```
nuint Read(byte[] buffer, nuint offset, nuint count)
```

Reads up to `count` bytes into `buffer` at `offset`, answering how
many it read.

Zero means the end of the file, or a failure -- `Error` is what tells
the two apart. A count reaching past the end of `buffer` is refused as
`Invalid` rather than overrunning it.

<sub>[stdlib/IO.sl:339](../../stdlib/IO.sl#L339)</sub>

#### Write *method*

```
nuint Write(byte[] buffer, nuint offset, nuint count)
```

Writes `count` bytes from `buffer` at `offset`, answering how many it
wrote.

Fewer than asked for means the write was cut short, and `Error` says
why -- a full disk, usually. A count reaching past the end of `buffer`
is refused as `Invalid`.

<sub>[stdlib/IO.sl:366](../../stdlib/IO.sl#L366)</sub>

#### WriteText *method*

```
nuint WriteText(String text)
```

Writes the UTF-8 bytes of `text`, which is what a String already holds,
so nothing is converted or copied on the way.

<sub>[stdlib/IO.sl:389](../../stdlib/IO.sl#L389)</sub>

#### Position *property*

```
long Position { get; }
```

How far into the file the next read or write will happen, or -1 when
the file is closed.

<sub>[stdlib/IO.sl:407](../../stdlib/IO.sl#L407)</sub>

#### Length *property*

```
long Length { get; }
```

How many bytes the file holds, or -1 when it is closed. Asks the
system each time rather than caching, so it sees a file another
process has grown.

<sub>[stdlib/IO.sl:420](../../stdlib/IO.sl#L420)</sub>

#### Seek *method*

```
bool Seek(long offset, SeekOrigin origin)
```

Moves the position, answering whether it worked.

Seeking past the end is allowed and does not extend the file; the gap
becomes zeroes when something is written there.

<sub>[stdlib/IO.sl:434](../../stdlib/IO.sl#L434)</sub>

#### Flush *method*

```
void Flush()
```

Pushes buffered bytes to the system. Not the same as reaching the
disk -- the system's own cache is still in front of it -- so this is
what makes a write visible to other processes, not what makes it
survive a power cut. `Error` says whether the system took them.

<sub>[stdlib/IO.sl:452](../../stdlib/IO.sl#L452)</sub>

#### Close *method*

```
void Close()
```

Closes the file. Calling it twice is harmless, which matters because the
destructor calls it too.

Bytes still buffered are written here, so a write can fail here: a
caller that needs to know its data arrived MUST read `Error` after the
first `Close`. A second call leaves it alone.

<sub>[stdlib/IO.sl:464](../../stdlib/IO.sl#L464)</sub>

#### Error *property*

```
IOError Error { get; }
```

The last error, or `None`. Set by every call that failed and left
alone by one that did not, so read it directly after the call it
belongs to.

<sub>[stdlib/IO.sl:476](../../stdlib/IO.sl#L476)</sub>

### IOError *enum*

```
enum IOError
```

Why an operation did not work. `None` is success.

These are the distinctions a program can act on, not the platform's whole
error list: the values are the same on every platform, which `errno` is not.

<sub>[stdlib/IO.sl:59](../../stdlib/IO.sl#L59)</sub>

#### None *case*

```
None = 0
```

Nothing went wrong.

<sub>[stdlib/IO.sl:62](../../stdlib/IO.sl#L62)</sub>

#### NotFound *case*

```
NotFound = 1
```

No such file, or a directory along the path is missing.

<sub>[stdlib/IO.sl:65](../../stdlib/IO.sl#L65)</sub>

#### AccessDenied *case*

```
AccessDenied = 2
```

It is there and this process may not touch it that way.

<sub>[stdlib/IO.sl:68](../../stdlib/IO.sl#L68)</sub>

#### AlreadyExists *case*

```
AlreadyExists = 3
```

Creating something that is already there.

<sub>[stdlib/IO.sl:71](../../stdlib/IO.sl#L71)</sub>

#### NotADirectory *case*

```
NotADirectory = 4
```

A path used a file as though it were a directory.

<sub>[stdlib/IO.sl:74](../../stdlib/IO.sl#L74)</sub>

#### IsADirectory *case*

```
IsADirectory = 5
```

A directory was given where a file was wanted.

<sub>[stdlib/IO.sl:77](../../stdlib/IO.sl#L77)</sub>

#### Invalid *case*

```
Invalid = 6
```

The request made no sense -- a count past the end of a buffer, a
negative seek, a mode the operation cannot take.

<sub>[stdlib/IO.sl:81](../../stdlib/IO.sl#L81)</sub>

#### EndOfFile *case*

```
EndOfFile = 7
```

The end of the file. A read that returns zero is the usual way this is
seen, so this value is rarer than it looks.

<sub>[stdlib/IO.sl:85](../../stdlib/IO.sl#L85)</sub>

#### Closed *case*

```
Closed = 8
```

The stream was closed before the call.

<sub>[stdlib/IO.sl:88](../../stdlib/IO.sl#L88)</sub>

#### Unknown *case*

```
Unknown = 9
```

The platform said something this enum has no name for.

<sub>[stdlib/IO.sl:91](../../stdlib/IO.sl#L91)</sub>

### IStream *interface*

```
interface IStream
```

A sequence of bytes that can be read, written, or both.

Read and Write report how many bytes they moved, which for a read is how
end-of-file is seen: fewer than asked for, and zero at the end. Whether
that was an error rather than an ending is what `Error` says.

<sub>[stdlib/IO.sl:165](../../stdlib/IO.sl#L165)</sub>

#### CanRead *property*

```
bool CanRead { get; }
```

Whether reading is allowed and possible now. False on a write-only
stream and on a closed one.

<sub>[stdlib/IO.sl:169](../../stdlib/IO.sl#L169)</sub>

#### CanWrite *property*

```
bool CanWrite { get; }
```

Whether writing is allowed and possible now.

<sub>[stdlib/IO.sl:172](../../stdlib/IO.sl#L172)</sub>

#### CanSeek *property*

```
bool CanSeek { get; }
```

Whether the position can be moved. False for a stream with no position
to move -- a socket, a pipe -- where `Seek` fails and `Position` and
`Length` answer -1.

<sub>[stdlib/IO.sl:177](../../stdlib/IO.sl#L177)</sub>

#### Read *method*

```
nuint Read(byte[] buffer, nuint offset, nuint count)
```

Reads up to `count` bytes into `buffer` starting at `offset`, and
returns how many it read. Zero means the end.

<sub>[stdlib/IO.sl:181](../../stdlib/IO.sl#L181)</sub>

#### Write *method*

```
nuint Write(byte[] buffer, nuint offset, nuint count)
```

Writes `count` bytes from `buffer` starting at `offset`, and returns
how many it wrote.

<sub>[stdlib/IO.sl:185](../../stdlib/IO.sl#L185)</sub>

#### Position *property*

```
long Position { get; }
```

Where the next read or write will happen, or -1 when the stream has no
position.

<sub>[stdlib/IO.sl:189](../../stdlib/IO.sl#L189)</sub>

#### Length *property*

```
long Length { get; }
```

How many bytes the stream holds, or -1 when it cannot say -- which is
every stream that is not seekable, and some that are.

<sub>[stdlib/IO.sl:193](../../stdlib/IO.sl#L193)</sub>

#### Seek *method*

```
bool Seek(long offset, SeekOrigin origin)
```

Moves the cursor. Reports whether it could.

<sub>[stdlib/IO.sl:196](../../stdlib/IO.sl#L196)</sub>

#### Flush *method*

```
void Flush()
```

Pushes buffered bytes onward. What "onward" means is the stream's: for
a file it is the system, not the disk.

<sub>[stdlib/IO.sl:200](../../stdlib/IO.sl#L200)</sub>

#### Close *method*

```
void Close()
```

Releases whatever the stream holds. Implementations make this
idempotent, and a destructor calls it, so a stream that goes out of
scope is not leaked.

<sub>[stdlib/IO.sl:205](../../stdlib/IO.sl#L205)</sub>

#### Error *property*

```
IOError Error { get; }
```

The last error, or `IOError.None`. Cleared by the next successful call.

<sub>[stdlib/IO.sl:208](../../stdlib/IO.sl#L208)</sub>

### MemoryStream *class*

```
class MemoryStream : IStream
```

A stream over a growable byte buffer.

The same interface as a file, with nothing behind it but memory: useful for
building a payload before writing it, and for testing something that takes
an `IStream` without touching a disk.

<sub>[stdlib/IO.sl:486](../../stdlib/IO.sl#L486)</sub>

#### CanRead *property*

```
bool CanRead { get; }
```

Always true.

<sub>[stdlib/IO.sl:511](../../stdlib/IO.sl#L511)</sub>

#### CanWrite *property*

```
bool CanWrite { get; }
```

Always true.

<sub>[stdlib/IO.sl:513](../../stdlib/IO.sl#L513)</sub>

#### CanSeek *property*

```
bool CanSeek { get; }
```

Always true.

<sub>[stdlib/IO.sl:515](../../stdlib/IO.sl#L515)</sub>

#### Read *method*

```
nuint Read(byte[] buffer, nuint offset, nuint count)
```

Reads up to `count` bytes into `buffer` at `offset`, answering how
many it read. Zero means the position has reached the end; there is no
failure to distinguish it from.

<sub>[stdlib/IO.sl:520](../../stdlib/IO.sl#L520)</sub>

#### Write *method*

```
nuint Write(byte[] buffer, nuint offset, nuint count)
```

Writes `count` bytes from `buffer` at `offset`, growing the buffer as
needed and answering `count`.

Writing over the middle replaces those bytes rather than inserting, so
the length only grows when the position passes the old end.

<sub>[stdlib/IO.sl:539](../../stdlib/IO.sl#L539)</sub>

#### WriteText *method*

```
void WriteText(String text)
```

Appends the UTF-8 bytes of `text`.

<sub>[stdlib/IO.sl:555](../../stdlib/IO.sl#L555)</sub>

#### Position *property*

```
long Position { get; }
```

Where the next read or write will happen.

<sub>[stdlib/IO.sl:570](../../stdlib/IO.sl#L570)</sub>

#### Length *property*

```
long Length { get; }
```

How many bytes have been written, measured to the furthest the
position has ever reached -- not the capacity of the buffer behind it.

<sub>[stdlib/IO.sl:573](../../stdlib/IO.sl#L573)</sub>

#### Seek *method*

```
bool Seek(long offset, SeekOrigin origin)
```

Moves the position, answering whether it worked.

Unlike a file, seeking past the end is refused: there is nothing there
to leave a gap in.

<sub>[stdlib/IO.sl:579](../../stdlib/IO.sl#L579)</sub>

#### Flush *method*

```
void Flush()
```

Does nothing. There is nothing behind the buffer to push bytes to.

<sub>[stdlib/IO.sl:594](../../stdlib/IO.sl#L594)</sub>

#### Close *method*

```
void Close()
```

Nothing to release; a memory stream stays usable after it.

<sub>[stdlib/IO.sl:597](../../stdlib/IO.sl#L597)</sub>

#### Error *property*

```
IOError Error { get; }
```

Always `None`. Nothing a memory stream does can fail.

<sub>[stdlib/IO.sl:600](../../stdlib/IO.sl#L600)</sub>

#### ToArray *method*

```
byte[] ToArray()
```

A copy of what has been written, from the start to the high-water mark.

<sub>[stdlib/IO.sl:603](../../stdlib/IO.sl#L603)</sub>

#### ToText *method*

```
String ToText()
```

The contents as text, read as UTF-8.

<sub>[stdlib/IO.sl:612](../../stdlib/IO.sl#L612)</sub>

### SeekOrigin *enum*

```
enum SeekOrigin
```

Where a seek offset is measured from.

<sub>[stdlib/IO.sl:145](../../stdlib/IO.sl#L145)</sub>

#### Start *case*

```
Start = 0
```

From the beginning, so the offset is the position. Negative is refused.

<sub>[stdlib/IO.sl:148](../../stdlib/IO.sl#L148)</sub>

#### Current *case*

```
Current = 1
```

From where the stream is now. Negative moves back.

<sub>[stdlib/IO.sl:151](../../stdlib/IO.sl#L151)</sub>

#### End *case*

```
End = 2
```

From the end, so a negative offset is the usual direction and zero is
the end itself.

<sub>[stdlib/IO.sl:155](../../stdlib/IO.sl#L155)</sub>

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

<sub>[stdlib/TextIO.sl:142](../../stdlib/TextIO.sl#L142)</sub>

#### Encoding *property*

```
IEncoding Encoding { get; }
```

The encoding the text is being read as.

<sub>[stdlib/TextIO.sl:195](../../stdlib/TextIO.sl#L195)</sub>

#### Error *property*

```
IOError Error { get; }
```

Why the stream stopped, when it was a failure rather than the end.
`None` until then.

<sub>[stdlib/TextIO.sl:199](../../stdlib/TextIO.sl#L199)</sub>

#### ReadLine *method*

```
override String? ReadLine()
```

*No documentation.*

<sub>[stdlib/TextIO.sl:264](../../stdlib/TextIO.sl#L264)</sub>

#### ReadToEnd *method*

```
override String ReadToEnd()
```

*No documentation.*

<sub>[stdlib/TextIO.sl:302](../../stdlib/TextIO.sl#L302)</sub>

#### Close *method*

```
override void Close()
```

Closes the stream under it as well, which is what a reader owning one
is for.

<sub>[stdlib/TextIO.sl:332](../../stdlib/TextIO.sl#L332)</sub>

### StreamWriter *class*

```
class StreamWriter : TextWriter
```

A writer over a stream, encoding as it goes.

Unlike the reader this is genuinely incremental: every encoding here is
stateless, so each piece of text can be encoded and written on its own.

**See also** &nbsp; [StreamReader](#streamreader-class)

<sub>[stdlib/TextIO.sl:423](../../stdlib/TextIO.sl#L423)</sub>

#### Encoding *property*

```
IEncoding Encoding { get; }
```

The encoding the text is being written in.

<sub>[stdlib/TextIO.sl:446](../../stdlib/TextIO.sl#L446)</sub>

#### WritePreamble *method*

```
void WritePreamble()
```

The bytes that mark this encoding, written at the position the stream
is at. Call it before anything else or not at all.

<sub>[stdlib/TextIO.sl:450](../../stdlib/TextIO.sl#L450)</sub>

#### Write *method*

```
override void Write(String text)
```

*No documentation.*

<sub>[stdlib/TextIO.sl:457](../../stdlib/TextIO.sl#L457)</sub>

#### Flush *method*

```
override void Flush()
```

*No documentation.*

<sub>[stdlib/TextIO.sl:467](../../stdlib/TextIO.sl#L467)</sub>

#### Close *method*

```
override void Close()
```

Flushes and closes the stream under it.

<sub>[stdlib/TextIO.sl:474](../../stdlib/TextIO.sl#L474)</sub>

### StringReader *class*

```
class StringReader : TextReader
```

A reader over text already in memory.

**See also** &nbsp; [StringWriter](#stringwriter-class)

<sub>[stdlib/TextIO.sl:77](../../stdlib/TextIO.sl#L77)</sub>

#### ReadLine *method*

```
override String? ReadLine()
```

*No documentation.*

<sub>[stdlib/TextIO.sl:88](../../stdlib/TextIO.sl#L88)</sub>

#### ReadToEnd *method*

```
override String ReadToEnd()
```

*No documentation.*

<sub>[stdlib/TextIO.sl:111](../../stdlib/TextIO.sl#L111)</sub>

#### Close *method*

```
override void Close()
```

*No documentation.*

<sub>[stdlib/TextIO.sl:121](../../stdlib/TextIO.sl#L121)</sub>

### StringWriter *class*

```
class StringWriter : TextWriter
```

A writer that keeps what it is given, for a caller that wanted a
`TextWriter` and a string rather than a file.

**See also** &nbsp; [StringReader](#stringreader-class)

<sub>[stdlib/TextIO.sl:392](../../stdlib/TextIO.sl#L392)</sub>

#### Write *method*

```
override void Write(String text)
```

*No documentation.*

<sub>[stdlib/TextIO.sl:401](../../stdlib/TextIO.sl#L401)</sub>

#### Flush *method*

```
override void Flush()
```

Nothing is held anywhere else, so this does nothing.

<sub>[stdlib/TextIO.sl:407](../../stdlib/TextIO.sl#L407)</sub>

#### Close *method*

```
override void Close()
```

Nothing is held anywhere else, so this does nothing either. What was
written stays readable.

<sub>[stdlib/TextIO.sl:411](../../stdlib/TextIO.sl#L411)</sub>

#### ToText *method*

```
String ToText()
```

What has been written so far. The writer stays usable afterwards.

<sub>[stdlib/TextIO.sl:414](../../stdlib/TextIO.sl#L414)</sub>

### TextReader *class*

```
abstract class TextReader
```

Text arriving from somewhere, a line at a time.

**See also** &nbsp; [TextWriter](#textwriter-class)

<sub>[stdlib/TextIO.sl:45](../../stdlib/TextIO.sl#L45)</sub>

#### ReadLine *method*

```
abstract String? ReadLine()
```

One line without its terminator, or null once there are no more.

Null rather than empty, because a blank line and no line at all are
different answers and a loop reading to the end has to tell them apart.

<sub>[stdlib/TextIO.sl:51](../../stdlib/TextIO.sl#L51)</sub>

#### ReadToEnd *method*

```
abstract String ReadToEnd()
```

Everything not yet read, as one string.

<sub>[stdlib/TextIO.sl:54](../../stdlib/TextIO.sl#L54)</sub>

#### Close *method*

```
abstract void Close()
```

Whatever the reader holds open.

<sub>[stdlib/TextIO.sl:57](../../stdlib/TextIO.sl#L57)</sub>

#### ReadLines *method*

```
String[] ReadLines()
```

Every remaining line, which is `ReadLine` until it says there are none.

<sub>[stdlib/TextIO.sl:60](../../stdlib/TextIO.sl#L60)</sub>

### TextWriter *class*

```
abstract class TextWriter
```

Text going somewhere, a piece at a time.

**See also** &nbsp; [TextReader](#textreader-class)

<sub>[stdlib/TextIO.sl:346](../../stdlib/TextIO.sl#L346)</sub>

#### Write *method*

```
abstract void Write(String text)
```

Text, with nothing after it.

<sub>[stdlib/TextIO.sl:352](../../stdlib/TextIO.sl#L352)</sub>

#### Flush *method*

```
abstract void Flush()
```

Pushes whatever is held onward.

<sub>[stdlib/TextIO.sl:355](../../stdlib/TextIO.sl#L355)</sub>

#### Close *method*

```
abstract void Close()
```

Flushes and releases what the writer holds.

<sub>[stdlib/TextIO.sl:358](../../stdlib/TextIO.sl#L358)</sub>

#### NewLine *property*

```
String NewLine { get; set; }
```

What ends a line here.

<sub>[stdlib/TextIO.sl:361](../../stdlib/TextIO.sl#L361)</sub>

#### WriteLine *method*

```
void WriteLine(String text)
```

Text and a line ending.

<sub>[stdlib/TextIO.sl:368](../../stdlib/TextIO.sl#L368)</sub>

#### WriteLine *method*

```
void WriteLine()
```

A line ending on its own.

<sub>[stdlib/TextIO.sl:375](../../stdlib/TextIO.sl#L375)</sub>

#### WriteLines *method*

```
void WriteLines(String[] lines)
```

Each of `lines`, each ended.

<sub>[stdlib/TextIO.sl:381](../../stdlib/TextIO.sl#L381)</sub>

## Functions

### DescribeIOError *function*

```
String DescribeIOError(IOError error)
```

A sentence describing an error, for a message a person will read.

**See also** &nbsp; [IOError](#ioerror-enum)

<sub>[stdlib/IO.sl:97](../../stdlib/IO.sl#L97)</sub>

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

<sub>[stdlib/IO.sl:672](../../stdlib/IO.sl#L672)</sub>

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

<sub>[stdlib/IO.sl:645](../../stdlib/IO.sl#L645)</sub>

### SplitLines *function*

```
List<String> SplitLines(String text)
```

Splits text into lines, accepting either line ending and dropping a final
empty line, which is what a trailing newline produces.

**Returns** &nbsp; the lines, each without its ending

<sub>[stdlib/IO.sl:687](../../stdlib/IO.sl#L687)</sub>

