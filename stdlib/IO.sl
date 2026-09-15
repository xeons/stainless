// Stainless - an experimental general-purpose language.
// Copyright (C) 2026 Brandon Scott
//
// This file is part of the Stainless runtime library. It is free
// software: you can redistribute it and/or modify it under the terms of
// the GNU General Public License as published by the Free Software
// Foundation, either version 3 of the License, or (at your option) any
// later version.
//
// It is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
// for more details.
//
// As an additional permission under section 7 of that License, compiling
// a program with Stainless does not by itself place that program under
// the GNU General Public License. See LICENSE.RUNTIME.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

/// Streams, and the vocabulary the rest of the I/O modules share.
///
/// **How failure is reported.** Stainless does not unwind, so an operation that
/// can fail says so in its return type:
///
///   - An operation that produces something returns `Result<T, IOError>`, the
///     language's own type. `Value` is unreadable until the compiler has seen
///     `Ok` checked, so there is no failed result to read by mistake.
///   - An operation that produces nothing returns an `IOError` directly, and
///     `IOError.None` is success.
///   - A stream carries its last error instead, because a stream is used in a
///     loop and checking after each step would drown the code it is in.
///
/// That is three shapes rather than one, and it is deliberate: a single shape
/// would make the common cases read worse than the rare one.
module Standard.IO;

import Standard.Collections;

extern "C"
{
    byte* sl_file_open(byte* path, int mode, int access, int* error);
    void  sl_file_close(byte* handle);
    nuint sl_file_read(byte* handle, byte* buffer, nuint count, int* error);
    nuint sl_file_write(byte* handle, byte* buffer, nuint count, int* error);
    long  sl_file_seek(byte* handle, long offset, int origin, int* error);
    long  sl_file_position(byte* handle);
    long  sl_file_length(byte* handle);
    void  sl_file_flush(byte* handle);
}

// ------------------------------------------------------------------ errors

/// Why an operation did not work. `None` is success.
///
/// These are the distinctions a program can act on, not the platform's whole
/// error list: the values are the same on every platform, which `errno` is not.
public enum IOError
{
    /// Nothing went wrong.
    None = 0,

    /// No such file, or a directory along the path is missing.
    NotFound = 1,

    /// It is there and this process may not touch it that way.
    AccessDenied = 2,

    /// Creating something that is already there.
    AlreadyExists = 3,

    /// A path used a file as though it were a directory.
    NotADirectory = 4,

    /// A directory was given where a file was wanted.
    IsADirectory = 5,

    /// The request made no sense -- a count past the end of a buffer, a
    /// negative seek, a mode the operation cannot take.
    Invalid = 6,

    /// The end of the file. A read that returns zero is the usual way this is
    /// seen, so this value is rarer than it looks.
    EndOfFile = 7,

    /// The stream was closed before the call.
    Closed = 8,

    /// The platform said something this enum has no name for.
    Unknown = 9,
}

/// A sentence describing an error, for a message a person will read.
public String Describe(IOError error)
{
    switch (error)
    {
        case IOError.None:           return "no error";
        case IOError.NotFound:       return "no such file or directory";
        case IOError.AccessDenied:   return "access denied";
        case IOError.AlreadyExists:  return "it already exists";
        case IOError.NotADirectory:  return "that is not a directory";
        case IOError.IsADirectory:   return "that is a directory";
        case IOError.Invalid:        return "the request made no sense";
        case IOError.EndOfFile:      return "the end of the file";
        case IOError.Closed:         return "the stream is closed";
        default:                     return "it failed for an unknown reason";
    }
}

// ------------------------------------------------------------------- modes

/// What opening a file should do about whether it is already there.
public enum FileMode
{
    /// It must exist.
    Open = 0,
    /// Create it, or replace what is there.
    Create = 1,
    /// Create it if needed, and write at the end.
    Append = 2,
}

/// What may be done with an open file. The members combine.
[Flags]
public enum FileAccess
{
    /// Neither. Not useful for opening anything.
    None = 0,

    /// Reading.
    Read = 1,

    /// Writing.
    Write = 2,

    /// Both, which is `Read | Write` written out.
    ReadWrite = 3,
}

/// Where a seek offset is measured from.
public enum SeekOrigin
{
    /// From the beginning, so the offset is the position. Negative is refused.
    Start = 0,

    /// From where the stream is now. Negative moves back.
    Current = 1,

    /// From the end, so a negative offset is the usual direction and zero is
    /// the end itself.
    End = 2,
}

// ------------------------------------------------------------------ stream

/// A sequence of bytes that can be read, written, or both.
///
/// Read and Write report how many bytes they moved, which for a read is how
/// end-of-file is seen: fewer than asked for, and zero at the end. Whether
/// that was an error rather than an ending is what `Error()` says.
public interface IStream
{
    /// Whether reading is allowed and possible now. False on a write-only
    /// stream and on a closed one.
    bool CanRead();

    /// Whether writing is allowed and possible now.
    bool CanWrite();

    /// Whether the position can be moved. False for a stream with no position
    /// to move -- a socket, a pipe -- where `Seek` fails and `Position` and
    /// `Length` answer -1.
    bool CanSeek();

    /// Reads up to `count` bytes into `buffer` starting at `offset`, and
    /// returns how many it read. Zero means the end.
    nuint Read(byte[] buffer, nuint offset, nuint count);

    /// Writes `count` bytes from `buffer` starting at `offset`, and returns
    /// how many it wrote.
    nuint Write(byte[] buffer, nuint offset, nuint count);

    /// Where the next read or write will happen, or -1 when the stream has no
    /// position.
    long Position();

    /// How many bytes the stream holds, or -1 when it cannot say -- which is
    /// every stream that is not seekable, and some that are.
    long Length();

    /// Moves the cursor. Reports whether it could.
    bool Seek(long offset, SeekOrigin origin);

    /// Pushes buffered bytes onward. What "onward" means is the stream's: for
    /// a file it is the system, not the disk.
    void Flush();

    /// Releases whatever the stream holds. Implementations make this
    /// idempotent, and a destructor calls it, so a stream that goes out of
    /// scope is not leaked.
    void Close();

    /// The last error, or `IOError.None`. Cleared by the next successful call.
    IOError Error();
}

// ------------------------------------------------------------- file stream

/// A stream over a file.
///
/// Made through `FileStream.Open` and its three shorthands, each of which
/// returns a `Result<FileStream, IOError>`:
///
///     var file = try FileStream.Create("notes.txt");
///
/// The constructor is private, and that is the point. A constructor has to
/// return its own type, so it cannot say why an open failed -- the best it can
/// do is hand back a stream holding nothing, which is a value a caller can go
/// on using while nothing forces the check that would have caught it. A Result
/// cannot be read without naming which case it is.
///
/// The factories are static methods here rather than functions in the module
/// because that is where a reader looks for how to make one, and because a
/// static method is inside the type: it can use the private constructor, which
/// is what lets the failing path be closed off rather than merely discouraged.
///
/// `IsOpen()` remains, because a stream can be closed after it was opened, and
/// `Error()` remains for a failure during a read or a write -- those are
/// outcomes of an operation rather than of the opening, and there is nowhere
/// else to put them.
///
/// Closing is the destructor's job too, so a stream that goes out of scope
/// releases its handle whether or not `Close` was called.
public class FileStream : IStream
{
    byte* _handle;
    FileAccess _access;
    IOError _error;
    bool _closed;

    // Private: the four factories below are the way in, and each of them
    // reports a failure rather than returning a stream that holds nothing.
    FileStream(String path, FileMode mode, FileAccess access)
    {
        int code = 0;
        _handle = sl_file_open(path.ToPointer(), (int)mode, (int)access, &code);
        this._access = access;
        _error = (IOError)code;
        _closed = _handle == null;
    }

    /// Opens a file, or says why it could not be opened.
    public static Result<FileStream, IOError> Open(
            String path, FileMode mode, FileAccess access)
    {
        var stream = new FileStream(path, mode, access);
        if (!stream.IsOpen())
            return Fail(stream.Error());
        return Ok(stream);
    }

    /// Opens an existing file for reading.
    public static Result<FileStream, IOError> OpenRead(String path)
    {
        return Open(path, FileMode.Open, FileAccess.Read);
    }

    /// Creates the file, or replaces what is there.
    public static Result<FileStream, IOError> Create(String path)
    {
        return Open(path, FileMode.Create, FileAccess.Write);
    }

    /// Opens for writing at the end, creating the file if it is not there.
    public static Result<FileStream, IOError> OpenAppend(String path)
    {
        return Open(path, FileMode.Append, FileAccess.Write);
    }

    ~FileStream() { Close(); }

    /// Whether the file is still open. False after `Close`, and after an
    /// open that failed.
    public bool IsOpen() => !_closed;

    /// True while the file is open and was opened for reading. A file opened
    /// for writing answers false, and `Read` on it fails rather than
    /// returning nothing.
    public bool CanRead() => !_closed && _access.HasFlag(FileAccess.Read);
    /// True while the file is open and was opened for writing.
    public bool CanWrite() => !_closed && _access.HasFlag(FileAccess.Write);
    /// True while the file is open. Every file is seekable, unlike a
    /// connection.
    public bool CanSeek() => !_closed;

    /// Reads up to `count` bytes into `buffer` at `offset`, answering how
    /// many it read.
    ///
    /// Zero means the end of the file, or a failure -- `Error()` is what tells
    /// the two apart. A count reaching past the end of `buffer` is refused as
    /// `Invalid` rather than overrunning it.
    public nuint Read(byte[] buffer, nuint offset, nuint count)
    {
        if (_closed)
        {
            _error = IOError.Closed;
            return 0;
        }
        if (count == 0)
            return 0;
        if (offset + count > buffer.Length)
        {
            _error = IOError.Invalid;
            return 0;
        }

        int code = 0;
        nuint read = sl_file_read(_handle, &buffer[offset], count, &code);
        _error = (IOError)code;
        return read;
    }

    /// Writes `count` bytes from `buffer` at `offset`, answering how many it
    /// wrote.
    ///
    /// Fewer than asked for means the write was cut short, and `Error()` says
    /// why -- a full disk, usually. A count reaching past the end of `buffer`
    /// is refused as `Invalid`.
    public nuint Write(byte[] buffer, nuint offset, nuint count)
    {
        if (_closed)
        {
            _error = IOError.Closed;
            return 0;
        }
        if (count == 0)
            return 0;
        if (offset + count > buffer.Length)
        {
            _error = IOError.Invalid;
            return 0;
        }

        int code = 0;
        nuint written = sl_file_write(_handle, &buffer[offset], count, &code);
        _error = (IOError)code;
        return written;
    }

    /// Writes the UTF-8 bytes of `text`, which is what a String already holds,
    /// so nothing is converted or copied on the way.
    public nuint WriteText(String text)
    {
        if (_closed)
        {
            _error = IOError.Closed;
            return 0;
        }
        if (text.ByteLength() == 0)
            return 0;

        int code = 0;
        nuint written = sl_file_write(_handle, text.ToPointer(), text.ByteLength(), &code);
        _error = (IOError)code;
        return written;
    }

    /// How far into the file the next read or write will happen, or -1 when
    /// the file is closed.
    public long Position()
    {
        if (_closed)
            return -1;
        return sl_file_position(_handle);
    }

    /// How many bytes the file holds, or -1 when it is closed. Asks the
    /// system each time rather than caching, so it sees a file another
    /// process has grown.
    public long Length()
    {
        if (_closed)
            return -1;
        return sl_file_length(_handle);
    }

    /// Moves the position, answering whether it worked.
    ///
    /// Seeking past the end is allowed and does not extend the file; the gap
    /// becomes zeroes when something is written there.
    public bool Seek(long offset, SeekOrigin origin)
    {
        if (_closed)
        {
            _error = IOError.Closed;
            return false;
        }

        int code = 0;
        long landed = sl_file_seek(_handle, offset, (int)origin, &code);
        _error = (IOError)code;
        return landed >= 0;
    }

    /// Pushes buffered bytes to the system. Not the same as reaching the
    /// disk -- the system's own cache is still in front of it -- so this is
    /// what makes a write visible to other processes, not what makes it
    /// survive a power cut.
    public void Flush()
    {
        if (!_closed)
            sl_file_flush(_handle);
    }

    /// Closes the file. Calling it twice is harmless, which matters because the
    /// destructor calls it too.
    public void Close()
    {
        if (_closed)
            return;
        sl_file_close(_handle);
        _handle = null;
        _closed = true;
    }

    /// The last error, or `None`. Set by every call that failed and left
    /// alone by one that did not, so read it directly after the call it
    /// belongs to.
    public IOError Error() => _error;
}

// ----------------------------------------------------------- memory stream

/// A stream over a growable byte buffer.
///
/// The same interface as a file, with nothing behind it but memory: useful for
/// building a payload before writing it, and for testing something that takes
/// an `IStream` without touching a disk.
public class MemoryStream : IStream
{
    byte[] _bytes;
    nuint _length;
    nuint _at;

    /// An empty stream, positioned at the beginning.
    public MemoryStream()
    {
        _bytes = new byte[64];
        _length = 0;
        _at = 0;
    }

    /// Starts with a copy of `initial`, positioned at the beginning.
    public MemoryStream(byte[] initial)
    {
        _bytes = new byte[initial.Length + 1];
        for (nuint i = 0; i < initial.Length; i++)
            _bytes[i] = initial[i];
        _length = initial.Length;
        _at = 0;
    }

    /// Always true.
    public bool CanRead() => true;
    /// Always true.
    public bool CanWrite() => true;
    /// Always true.
    public bool CanSeek() => true;

    /// Reads up to `count` bytes into `buffer` at `offset`, answering how
    /// many it read. Zero means the position has reached the end; there is no
    /// failure to distinguish it from.
    public nuint Read(byte[] buffer, nuint offset, nuint count)
    {
        if (offset + count > buffer.Length)
            return 0;

        nuint available = _length - _at;
        nuint taking = count < available ? count : available;

        for (nuint i = 0; i < taking; i++)
            buffer[offset + i] = _bytes[_at + i];
        _at = _at + taking;
        return taking;
    }

    /// Writes `count` bytes from `buffer` at `offset`, growing the buffer as
    /// needed and answering `count`.
    ///
    /// Writing over the middle replaces those bytes rather than inserting, so
    /// the length only grows when the position passes the old end.
    public nuint Write(byte[] buffer, nuint offset, nuint count)
    {
        if (offset + count > buffer.Length)
            return 0;

        Reserve(_at + count);
        for (nuint i = 0; i < count; i++)
            _bytes[_at + i] = buffer[offset + i];

        _at = _at + count;
        if (_at > _length)
            _length = _at;
        return count;
    }

    /// Appends the UTF-8 bytes of `text`.
    public void WriteText(String text)
    {
        nuint size = text.ByteLength();
        Reserve(_at + size);

        var source = text.ToPointer();
        for (nuint i = 0; i < size; i++)
            _bytes[_at + i] = source[i];

        _at = _at + size;
        if (_at > _length)
            _length = _at;
    }

    /// Where the next read or write will happen.
    public long Position() => (long)_at;
    /// How many bytes have been written, measured to the furthest the
    /// position has ever reached -- not the capacity of the buffer behind it.
    public long Length() => (long)_length;

    /// Moves the position, answering whether it worked.
    ///
    /// Unlike a file, seeking past the end is refused: there is nothing there
    /// to leave a gap in.
    public bool Seek(long offset, SeekOrigin origin)
    {
        long target = offset;
        if (origin == SeekOrigin.Current)
            target = (long)_at + offset;
        if (origin == SeekOrigin.End)
            target = (long)_length + offset;

        if (target < 0 || target > (long)_length)
            return false;
        _at = (nuint)target;
        return true;
    }

    /// Does nothing. There is nothing behind the buffer to push bytes to.
    public void Flush() { }

    /// Nothing to release; a memory stream stays usable after it.
    public void Close() { }

    /// Always `None`. Nothing a memory stream does can fail.
    public IOError Error() => IOError.None;

    /// A copy of what has been written, from the start to the high-water mark.
    public byte[] ToArray()
    {
        var copy = new byte[_length];
        for (nuint i = 0; i < _length; i++)
            copy[i] = _bytes[i];
        return copy;
    }

    /// The contents as text, read as UTF-8.
    public String ToText()
    {
        if (_length == 0)
            return "";
        return Text.FromBytes(&_bytes[0], _length);
    }

    void Reserve(nuint wanted)
    {
        if (wanted <= _bytes.Length)
            return;

        nuint size = _bytes.Length * 2;
        while (size < wanted)
            size = size * 2;

        var bigger = new byte[size];
        for (nuint i = 0; i < _length; i++)
            bigger[i] = _bytes[i];
        _bytes = bigger;
    }
}

// ------------------------------------------------------------------ helpers

/// Reads a stream to its end.
public Result<byte[], IOError> ReadToEnd(IStream stream)
{
    var collected = new MemoryStream();
    var buffer = new byte[4096];

    for (;;)
    {
        nuint got = stream.Read(buffer, 0, buffer.Length);
        if (got == 0)
            break;
        collected.Write(buffer, 0, got);
    }

    var failure = stream.Error();
    if (failure != IOError.None)
        return Fail(failure);
    return Ok(collected.ToArray());
}

/// Reads a stream to its end and reads the bytes as UTF-8.
public Result<String, IOError> ReadTextToEnd(IStream stream)
{
    var raw = ReadToEnd(stream);
    if (!raw.Ok)
        return Fail(raw.Error);

    if (raw.Value.Length == 0)
        return Ok("");
    return Ok(Text.FromBytes(&raw.Value[0], raw.Value.Length));
}

/// Splits text into lines, accepting either line ending and dropping a final
/// empty line, which is what a trailing newline produces.
public List<String> SplitLines(String text)
{
    var lines = new List<String>();
    var bytes = text.ToPointer();
    nuint size = text.ByteLength();

    nuint start = 0;
    for (nuint i = 0; i < size; i++)
    {
        if (bytes[i] != 10)
            continue;

        nuint stop = i;
        if (stop > start && bytes[stop - 1] == 13)
            stop = stop - 1;

        lines.Add(Text.FromBytes(&bytes[start], stop - start));
        start = i + 1;
    }

    if (start < size)
        lines.Add(Text.FromBytes(&bytes[start], size - start));
    return lines;
}
