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

**Types** &nbsp; [FileAccess](#fileaccess-enum) &middot; [FileMode](#filemode-enum) &middot; [FileStream](#filestream-class) &middot; [IOError](#ioerror-enum) &middot; [IStream](#istream-interface) &middot; [MemoryStream](#memorystream-class) &middot; [SeekOrigin](#seekorigin-enum)

**Functions** &nbsp; [Describe](#describe-function) &middot; [ReadTextToEnd](#readtexttoend-function) &middot; [ReadToEnd](#readtoend-function) &middot; [SplitLines](#splitlines-function)

## Types

### FileAccess *enum*

```
enum FileAccess
```

What may be done with an open file. The members combine.

<sub>[stdlib/IO.sl:126](../../stdlib/IO.sl#L126)</sub>

#### None *case*

```
None = 0
```

Neither. Not useful for opening anything.

<sub>[stdlib/IO.sl:130](../../stdlib/IO.sl#L130)</sub>

#### Read *case*

```
Read = 1
```

Reading.

<sub>[stdlib/IO.sl:133](../../stdlib/IO.sl#L133)</sub>

#### Write *case*

```
Write = 2
```

Writing.

<sub>[stdlib/IO.sl:136](../../stdlib/IO.sl#L136)</sub>

#### ReadWrite *case*

```
ReadWrite = 3
```

Both, which is `Read | Write` written out.

<sub>[stdlib/IO.sl:139](../../stdlib/IO.sl#L139)</sub>

### FileMode *enum*

```
enum FileMode
```

What opening a file should do about whether it is already there.

<sub>[stdlib/IO.sl:115](../../stdlib/IO.sl#L115)</sub>

#### Open *case*

```
Open = 0
```

It must exist.

<sub>[stdlib/IO.sl:118](../../stdlib/IO.sl#L118)</sub>

#### Create *case*

```
Create = 1
```

Create it, or replace what is there.

<sub>[stdlib/IO.sl:120](../../stdlib/IO.sl#L120)</sub>

#### Append *case*

```
Append = 2
```

Create it if needed, and write at the end.

<sub>[stdlib/IO.sl:122](../../stdlib/IO.sl#L122)</sub>

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

`IsOpen()` remains, because a stream can be closed after it was opened, and
`Error()` remains for a failure during a read or a write -- those are
outcomes of an operation rather than of the opening, and there is nowhere
else to put them.

Closing is the destructor's job too, so a stream that goes out of scope
releases its handle whether or not `Close` was called.

<sub>[stdlib/IO.sl:236](../../stdlib/IO.sl#L236)</sub>

#### Open *method*

```
static Result<FileStream, IOError> Open(String path, FileMode mode, FileAccess access)
```

Opens a file, or says why it could not be opened.

<sub>[stdlib/IO.sl:255](../../stdlib/IO.sl#L255)</sub>

#### OpenRead *method*

```
static Result<FileStream, IOError> OpenRead(String path)
```

Opens an existing file for reading.

<sub>[stdlib/IO.sl:265](../../stdlib/IO.sl#L265)</sub>

#### Create *method*

```
static Result<FileStream, IOError> Create(String path)
```

Creates the file, or replaces what is there.

<sub>[stdlib/IO.sl:271](../../stdlib/IO.sl#L271)</sub>

#### OpenAppend *method*

```
static Result<FileStream, IOError> OpenAppend(String path)
```

Opens for writing at the end, creating the file if it is not there.

<sub>[stdlib/IO.sl:277](../../stdlib/IO.sl#L277)</sub>

#### IsOpen *method*

```
bool IsOpen()
```

Whether the file is still open. False after `Close`, and after an
open that failed.

<sub>[stdlib/IO.sl:286](../../stdlib/IO.sl#L286)</sub>

#### CanRead *method*

```
bool CanRead()
```

True while the file is open and was opened for reading. A file opened
for writing answers false, and `Read` on it fails rather than
returning nothing.

<sub>[stdlib/IO.sl:291](../../stdlib/IO.sl#L291)</sub>

#### CanWrite *method*

```
bool CanWrite()
```

True while the file is open and was opened for writing.

<sub>[stdlib/IO.sl:293](../../stdlib/IO.sl#L293)</sub>

#### CanSeek *method*

```
bool CanSeek()
```

True while the file is open. Every file is seekable, unlike a
connection.

<sub>[stdlib/IO.sl:296](../../stdlib/IO.sl#L296)</sub>

#### Read *method*

```
nuint Read(byte[] buffer, nuint offset, nuint count)
```

Reads up to `count` bytes into `buffer` at `offset`, answering how
many it read.

Zero means the end of the file, or a failure -- `Error()` is what tells
the two apart. A count reaching past the end of `buffer` is refused as
`Invalid` rather than overrunning it.

<sub>[stdlib/IO.sl:304](../../stdlib/IO.sl#L304)</sub>

#### Write *method*

```
nuint Write(byte[] buffer, nuint offset, nuint count)
```

Writes `count` bytes from `buffer` at `offset`, answering how many it
wrote.

Fewer than asked for means the write was cut short, and `Error()` says
why -- a full disk, usually. A count reaching past the end of `buffer`
is refused as `Invalid`.

<sub>[stdlib/IO.sl:331](../../stdlib/IO.sl#L331)</sub>

#### WriteText *method*

```
nuint WriteText(String text)
```

Writes the UTF-8 bytes of `text`, which is what a String already holds,
so nothing is converted or copied on the way.

<sub>[stdlib/IO.sl:354](../../stdlib/IO.sl#L354)</sub>

#### Position *method*

```
long Position()
```

How far into the file the next read or write will happen, or -1 when
the file is closed.

<sub>[stdlib/IO.sl:372](../../stdlib/IO.sl#L372)</sub>

#### Length *method*

```
long Length()
```

How many bytes the file holds, or -1 when it is closed. Asks the
system each time rather than caching, so it sees a file another
process has grown.

<sub>[stdlib/IO.sl:382](../../stdlib/IO.sl#L382)</sub>

#### Seek *method*

```
bool Seek(long offset, SeekOrigin origin)
```

Moves the position, answering whether it worked.

Seeking past the end is allowed and does not extend the file; the gap
becomes zeroes when something is written there.

<sub>[stdlib/IO.sl:393](../../stdlib/IO.sl#L393)</sub>

#### Flush *method*

```
void Flush()
```

Pushes buffered bytes to the system. Not the same as reaching the
disk -- the system's own cache is still in front of it -- so this is
what makes a write visible to other processes, not what makes it
survive a power cut.

<sub>[stdlib/IO.sl:411](../../stdlib/IO.sl#L411)</sub>

#### Close *method*

```
void Close()
```

Closes the file. Calling it twice is harmless, which matters because the
destructor calls it too.

<sub>[stdlib/IO.sl:419](../../stdlib/IO.sl#L419)</sub>

#### Error *method*

```
IOError Error()
```

The last error, or `None`. Set by every call that failed and left
alone by one that did not, so read it directly after the call it
belongs to.

<sub>[stdlib/IO.sl:431](../../stdlib/IO.sl#L431)</sub>

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
that was an error rather than an ending is what `Error()` says.

<sub>[stdlib/IO.sl:163](../../stdlib/IO.sl#L163)</sub>

#### CanRead *method*

```
bool CanRead()
```

Whether reading is allowed and possible now. False on a write-only
stream and on a closed one.

<sub>[stdlib/IO.sl:167](../../stdlib/IO.sl#L167)</sub>

#### CanWrite *method*

```
bool CanWrite()
```

Whether writing is allowed and possible now.

<sub>[stdlib/IO.sl:170](../../stdlib/IO.sl#L170)</sub>

#### CanSeek *method*

```
bool CanSeek()
```

Whether the position can be moved. False for a stream with no position
to move -- a socket, a pipe -- where `Seek` fails and `Position` and
`Length` answer -1.

<sub>[stdlib/IO.sl:175](../../stdlib/IO.sl#L175)</sub>

#### Read *method*

```
nuint Read(byte[] buffer, nuint offset, nuint count)
```

Reads up to `count` bytes into `buffer` starting at `offset`, and
returns how many it read. Zero means the end.

<sub>[stdlib/IO.sl:179](../../stdlib/IO.sl#L179)</sub>

#### Write *method*

```
nuint Write(byte[] buffer, nuint offset, nuint count)
```

Writes `count` bytes from `buffer` starting at `offset`, and returns
how many it wrote.

<sub>[stdlib/IO.sl:183](../../stdlib/IO.sl#L183)</sub>

#### Position *method*

```
long Position()
```

Where the next read or write will happen, or -1 when the stream has no
position.

<sub>[stdlib/IO.sl:187](../../stdlib/IO.sl#L187)</sub>

#### Length *method*

```
long Length()
```

How many bytes the stream holds, or -1 when it cannot say -- which is
every stream that is not seekable, and some that are.

<sub>[stdlib/IO.sl:191](../../stdlib/IO.sl#L191)</sub>

#### Seek *method*

```
bool Seek(long offset, SeekOrigin origin)
```

Moves the cursor. Reports whether it could.

<sub>[stdlib/IO.sl:194](../../stdlib/IO.sl#L194)</sub>

#### Flush *method*

```
void Flush()
```

Pushes buffered bytes onward. What "onward" means is the stream's: for
a file it is the system, not the disk.

<sub>[stdlib/IO.sl:198](../../stdlib/IO.sl#L198)</sub>

#### Close *method*

```
void Close()
```

Releases whatever the stream holds. Implementations make this
idempotent, and a destructor calls it, so a stream that goes out of
scope is not leaked.

<sub>[stdlib/IO.sl:203](../../stdlib/IO.sl#L203)</sub>

#### Error *method*

```
IOError Error()
```

The last error, or `IOError.None`. Cleared by the next successful call.

<sub>[stdlib/IO.sl:206](../../stdlib/IO.sl#L206)</sub>

### MemoryStream *class*

```
class MemoryStream : IStream
```

A stream over a growable byte buffer.

The same interface as a file, with nothing behind it but memory: useful for
building a payload before writing it, and for testing something that takes
an `IStream` without touching a disk.

<sub>[stdlib/IO.sl:441](../../stdlib/IO.sl#L441)</sub>

#### CanRead *method*

```
bool CanRead()
```

Always true.

<sub>[stdlib/IO.sl:466](../../stdlib/IO.sl#L466)</sub>

#### CanWrite *method*

```
bool CanWrite()
```

Always true.

<sub>[stdlib/IO.sl:468](../../stdlib/IO.sl#L468)</sub>

#### CanSeek *method*

```
bool CanSeek()
```

Always true.

<sub>[stdlib/IO.sl:470](../../stdlib/IO.sl#L470)</sub>

#### Read *method*

```
nuint Read(byte[] buffer, nuint offset, nuint count)
```

Reads up to `count` bytes into `buffer` at `offset`, answering how
many it read. Zero means the position has reached the end; there is no
failure to distinguish it from.

<sub>[stdlib/IO.sl:475](../../stdlib/IO.sl#L475)</sub>

#### Write *method*

```
nuint Write(byte[] buffer, nuint offset, nuint count)
```

Writes `count` bytes from `buffer` at `offset`, growing the buffer as
needed and answering `count`.

Writing over the middle replaces those bytes rather than inserting, so
the length only grows when the position passes the old end.

<sub>[stdlib/IO.sl:494](../../stdlib/IO.sl#L494)</sub>

#### WriteText *method*

```
void WriteText(String text)
```

Appends the UTF-8 bytes of `text`.

<sub>[stdlib/IO.sl:510](../../stdlib/IO.sl#L510)</sub>

#### Position *method*

```
long Position()
```

Where the next read or write will happen.

<sub>[stdlib/IO.sl:525](../../stdlib/IO.sl#L525)</sub>

#### Length *method*

```
long Length()
```

How many bytes have been written, measured to the furthest the
position has ever reached -- not the capacity of the buffer behind it.

<sub>[stdlib/IO.sl:528](../../stdlib/IO.sl#L528)</sub>

#### Seek *method*

```
bool Seek(long offset, SeekOrigin origin)
```

Moves the position, answering whether it worked.

Unlike a file, seeking past the end is refused: there is nothing there
to leave a gap in.

<sub>[stdlib/IO.sl:534](../../stdlib/IO.sl#L534)</sub>

#### Flush *method*

```
void Flush()
```

Does nothing. There is nothing behind the buffer to push bytes to.

<sub>[stdlib/IO.sl:549](../../stdlib/IO.sl#L549)</sub>

#### Close *method*

```
void Close()
```

Nothing to release; a memory stream stays usable after it.

<sub>[stdlib/IO.sl:552](../../stdlib/IO.sl#L552)</sub>

#### Error *method*

```
IOError Error()
```

Always `None`. Nothing a memory stream does can fail.

<sub>[stdlib/IO.sl:555](../../stdlib/IO.sl#L555)</sub>

#### ToArray *method*

```
byte[] ToArray()
```

A copy of what has been written, from the start to the high-water mark.

<sub>[stdlib/IO.sl:558](../../stdlib/IO.sl#L558)</sub>

#### ToText *method*

```
String ToText()
```

The contents as text, read as UTF-8.

<sub>[stdlib/IO.sl:567](../../stdlib/IO.sl#L567)</sub>

### SeekOrigin *enum*

```
enum SeekOrigin
```

Where a seek offset is measured from.

<sub>[stdlib/IO.sl:143](../../stdlib/IO.sl#L143)</sub>

#### Start *case*

```
Start = 0
```

From the beginning, so the offset is the position. Negative is refused.

<sub>[stdlib/IO.sl:146](../../stdlib/IO.sl#L146)</sub>

#### Current *case*

```
Current = 1
```

From where the stream is now. Negative moves back.

<sub>[stdlib/IO.sl:149](../../stdlib/IO.sl#L149)</sub>

#### End *case*

```
End = 2
```

From the end, so a negative offset is the usual direction and zero is
the end itself.

<sub>[stdlib/IO.sl:153](../../stdlib/IO.sl#L153)</sub>

## Functions

### Describe *function*

```
String Describe(IOError error)
```

A sentence describing an error, for a message a person will read.

<sub>[stdlib/IO.sl:95](../../stdlib/IO.sl#L95)</sub>

### ReadTextToEnd *function*

```
Result<String, IOError> ReadTextToEnd(IStream stream)
```

Reads a stream to its end and reads the bytes as UTF-8.

<sub>[stdlib/IO.sl:613](../../stdlib/IO.sl#L613)</sub>

### ReadToEnd *function*

```
Result<byte[], IOError> ReadToEnd(IStream stream)
```

Reads a stream to its end.

<sub>[stdlib/IO.sl:593](../../stdlib/IO.sl#L593)</sub>

### SplitLines *function*

```
List<String> SplitLines(String text)
```

Splits text into lines, accepting either line ending and dropping a final
empty line, which is what a trailing newline produces.

<sub>[stdlib/IO.sl:626](../../stdlib/IO.sl#L626)</sub>

