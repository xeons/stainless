// Stainless - an experimental systems language.
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

// Streams, and the vocabulary the rest of the I/O modules share.
//
// **How failure is reported.** Stainless does not unwind, so an operation that
// can fail says so in its return type:
//
//   - An operation that produces something returns `Result<T, IOError>`, the
//     language's own type. `Value` is unreadable until the compiler has seen
//     `Ok` checked, so there is no failed result to read by mistake.
//   - An operation that produces nothing returns an `IOError` directly, and
//     `IOError.None` is success.
//   - A stream carries its last error instead, because a stream is used in a
//     loop and checking after each step would drown the code it is in.
//
// That is three shapes rather than one, and it is deliberate: a single shape
// would make the common cases read worse than the rare one.
module Standard.IO;

import Standard.Collections;

extern "C" {
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
public enum IOError {
    None = 0,
    NotFound = 1,
    AccessDenied = 2,
    AlreadyExists = 3,
    NotADirectory = 4,
    IsADirectory = 5,
    Invalid = 6,
    EndOfFile = 7,
    Closed = 8,
    Unknown = 9,
}

/// A sentence describing an error, for a message a person will read.
public String Describe(IOError error) {
    switch (error) {
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
public enum FileMode {
    /// It must exist.
    Open = 0,
    /// Create it, or replace what is there.
    Create = 1,
    /// Create it if needed, and write at the end.
    Append = 2,
}

/// What may be done with an open file. The members combine.
[Flags]
public enum FileAccess {
    None = 0,
    Read = 1,
    Write = 2,
    ReadWrite = 3,
}

public enum SeekOrigin {
    Start = 0,
    Current = 1,
    End = 2,
}

// ------------------------------------------------------------------ stream

/// A sequence of bytes that can be read, written, or both.
///
/// Read and Write report how many bytes they moved, which for a read is how
/// end-of-file is seen: fewer than asked for, and zero at the end. Whether
/// that was an error rather than an ending is what `Error()` says.
public interface IStream {
    bool CanRead();
    bool CanWrite();
    bool CanSeek();

    /// Reads up to `count` bytes into `buffer` starting at `offset`, and
    /// returns how many it read. Zero means the end.
    nuint Read(byte[] buffer, nuint offset, nuint count);

    /// Writes `count` bytes from `buffer` starting at `offset`, and returns
    /// how many it wrote.
    nuint Write(byte[] buffer, nuint offset, nuint count);

    long Position();
    long Length();

    /// Moves the cursor. Reports whether it could.
    bool Seek(long offset, SeekOrigin origin);

    void Flush();
    void Close();

    /// The last error, or `IOError.None`. Cleared by the next successful call.
    IOError Error();
}

// ------------------------------------------------------------- file stream

/// A stream over a file.
///
/// Construction is the open, so a `FileStream` always exists and `IsOpen()`
/// says whether it holds a file. That avoids handing back a null a caller
/// cannot unwrap, and puts the reason in `Error()`.
///
///     var file = new FileStream("notes.txt", FileMode.Create, FileAccess.Write);
///     if (!file.IsOpen()) { Console.WriteError(Describe(file.Error())); }
///
/// Closing is also the destructor's job, so a stream that goes out of scope
/// releases its handle whether or not `Close` was called.
public class FileStream : IStream {
    byte* handle;
    FileAccess access;
    IOError error;
    bool closed;

    public FileStream(String path, FileMode mode, FileAccess access) {
        int code = 0;
        handle = sl_file_open(path.ToPointer(), (int)mode, (int)access, &code);
        this.access = access;
        error = (IOError)code;
        closed = handle == null;
    }

    ~FileStream() { Close(); }

    public bool IsOpen() { return !closed; }

    public bool CanRead() { return !closed && access.HasFlag(FileAccess.Read); }
    public bool CanWrite() { return !closed && access.HasFlag(FileAccess.Write); }
    public bool CanSeek() { return !closed; }

    public nuint Read(byte[] buffer, nuint offset, nuint count) {
        if (closed) { error = IOError.Closed; return 0; }
        if (count == 0) { return 0; }
        if (offset + count > buffer.Length) { error = IOError.Invalid; return 0; }

        int code = 0;
        nuint read = sl_file_read(handle, &buffer[offset], count, &code);
        error = (IOError)code;
        return read;
    }

    public nuint Write(byte[] buffer, nuint offset, nuint count) {
        if (closed) { error = IOError.Closed; return 0; }
        if (count == 0) { return 0; }
        if (offset + count > buffer.Length) { error = IOError.Invalid; return 0; }

        int code = 0;
        nuint written = sl_file_write(handle, &buffer[offset], count, &code);
        error = (IOError)code;
        return written;
    }

    /// Writes the UTF-8 bytes of `text`, which is what a String already holds,
    /// so nothing is converted or copied on the way.
    public nuint WriteText(String text) {
        if (closed) { error = IOError.Closed; return 0; }
        if (text.ByteLength() == 0) { return 0; }

        int code = 0;
        nuint written = sl_file_write(handle, text.ToPointer(), text.ByteLength(), &code);
        error = (IOError)code;
        return written;
    }

    public long Position() {
        if (closed) { return -1; }
        return sl_file_position(handle);
    }

    public long Length() {
        if (closed) { return -1; }
        return sl_file_length(handle);
    }

    public bool Seek(long offset, SeekOrigin origin) {
        if (closed) { error = IOError.Closed; return false; }

        int code = 0;
        long landed = sl_file_seek(handle, offset, (int)origin, &code);
        error = (IOError)code;
        return landed >= 0;
    }

    public void Flush() {
        if (!closed) { sl_file_flush(handle); }
    }

    /// Closes the file. Calling it twice is harmless, which matters because the
    /// destructor calls it too.
    public void Close() {
        if (closed) { return; }
        sl_file_close(handle);
        handle = null;
        closed = true;
    }

    public IOError Error() { return error; }
}

// ----------------------------------------------------------- memory stream

/// A stream over a growable byte buffer.
///
/// The same interface as a file, with nothing behind it but memory: useful for
/// building a payload before writing it, and for testing something that takes
/// an `IStream` without touching a disk.
public class MemoryStream : IStream {
    byte[] bytes;
    nuint length;
    nuint at;

    public MemoryStream() {
        bytes = new byte[64];
        length = 0;
        at = 0;
    }

    /// Starts with a copy of `initial`, positioned at the beginning.
    public MemoryStream(byte[] initial) {
        bytes = new byte[initial.Length + 1];
        for (nuint i = 0; i < initial.Length; i = i + 1) { bytes[i] = initial[i]; }
        length = initial.Length;
        at = 0;
    }

    public bool CanRead() { return true; }
    public bool CanWrite() { return true; }
    public bool CanSeek() { return true; }

    public nuint Read(byte[] buffer, nuint offset, nuint count) {
        if (offset + count > buffer.Length) { return 0; }

        nuint available = length - at;
        nuint taking = count < available ? count : available;

        for (nuint i = 0; i < taking; i = i + 1) { buffer[offset + i] = bytes[at + i]; }
        at = at + taking;
        return taking;
    }

    public nuint Write(byte[] buffer, nuint offset, nuint count) {
        if (offset + count > buffer.Length) { return 0; }

        Reserve(at + count);
        for (nuint i = 0; i < count; i = i + 1) { bytes[at + i] = buffer[offset + i]; }

        at = at + count;
        if (at > length) { length = at; }
        return count;
    }

    /// Appends the UTF-8 bytes of `text`.
    public void WriteText(String text) {
        nuint size = text.ByteLength();
        Reserve(at + size);

        var source = text.ToPointer();
        for (nuint i = 0; i < size; i = i + 1) { bytes[at + i] = source[i]; }

        at = at + size;
        if (at > length) { length = at; }
    }

    public long Position() { return (long)at; }
    public long Length() { return (long)length; }

    public bool Seek(long offset, SeekOrigin origin) {
        long target = offset;
        if (origin == SeekOrigin.Current) { target = (long)at + offset; }
        if (origin == SeekOrigin.End) { target = (long)length + offset; }

        if (target < 0 || target > (long)length) { return false; }
        at = (nuint)target;
        return true;
    }

    public void Flush() { }

    /// Nothing to release; a memory stream stays usable after it.
    public void Close() { }

    public IOError Error() { return IOError.None; }

    /// A copy of what has been written, from the start to the high-water mark.
    public byte[] ToArray() {
        var copy = new byte[length];
        for (nuint i = 0; i < length; i = i + 1) { copy[i] = bytes[i]; }
        return copy;
    }

    /// The contents as text, read as UTF-8.
    public String ToText() {
        if (length == 0) { return ""; }
        return Text.FromBytes(&bytes[0], length);
    }

    void Reserve(nuint wanted) {
        if (wanted <= bytes.Length) { return; }

        nuint size = bytes.Length * 2;
        while (size < wanted) { size = size * 2; }

        var bigger = new byte[size];
        for (nuint i = 0; i < length; i = i + 1) { bigger[i] = bytes[i]; }
        bytes = bigger;
    }
}

// ------------------------------------------------------------------ helpers

/// Reads a stream to its end.
public Result<byte[], IOError> ReadToEnd(IStream stream) {
    var collected = new MemoryStream();
    var buffer = new byte[4096];

    for (;;) {
        nuint got = stream.Read(buffer, 0, buffer.Length);
        if (got == 0) { break; }
        collected.Write(buffer, 0, got);
    }

    var failure = stream.Error();
    if (failure != IOError.None) { return Fail(failure); }
    return Ok(collected.ToArray());
}

/// Reads a stream to its end and reads the bytes as UTF-8.
public Result<String, IOError> ReadTextToEnd(IStream stream) {
    var raw = ReadToEnd(stream);
    if (!raw.Ok) { return Fail(raw.Error); }

    if (raw.Value.Length == 0) { return Ok(""); }
    return Ok(Text.FromBytes(&raw.Value[0], raw.Value.Length));
}

/// Splits text into lines, accepting either line ending and dropping a final
/// empty line, which is what a trailing newline produces.
public List<String> SplitLines(String text) {
    var lines = new List<String>();
    var bytes = text.ToPointer();
    nuint size = text.ByteLength();

    nuint start = 0;
    for (nuint i = 0; i < size; i = i + 1) {
        if (bytes[i] != 10) { continue; }

        nuint stop = i;
        if (stop > start && bytes[stop - 1] == 13) { stop = stop - 1; }

        lines.Add(Text.FromBytes(&bytes[start], stop - start));
        start = i + 1;
    }

    if (start < size) { lines.Add(Text.FromBytes(&bytes[start], size - start)); }
    return lines;
}
