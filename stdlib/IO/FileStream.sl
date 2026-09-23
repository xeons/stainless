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

module Standard.IO;

import Standard.Collections;

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
/// `IsOpen` remains, because a stream can be closed after it was opened, and
/// `Error` remains for a failure during a read or a write -- those are
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
    ///
    /// @param path    the file to open
    /// @param mode    what to do about whether it is already there
    /// @param access  what may be done with it once it is open
    /// @failure IOError.NotFound      `FileMode.Open` and there is no file
    ///                                there, or a directory along the path is
    ///                                missing
    /// @failure IOError.AccessDenied  the file or its directory refuses it
    /// @failure IOError.IsADirectory  a writing mode on a path that names a
    ///                                directory
    /// @failure IOError.Unknown       the platform reported something with no
    ///                                case of its own -- too many open files
    ///                                among them
    public static Result<FileStream, IOError> Open(
            String path, FileMode mode, FileAccess access)
    {
        var stream = new FileStream(path, mode, access);
        if (!stream.IsOpen)
            return Fail(stream.Error);
        return Ok(stream);
    }

    /// Opens an existing file for reading.
    ///
    /// @failure IOError.NotFound      there is no file at that path
    /// @failure IOError.AccessDenied  the file refuses to be read
    /// @failure IOError.Unknown       the platform reported something with no
    ///                                case of its own
    /// @see FileStream.Open
    public static Result<FileStream, IOError> OpenRead(String path)
    {
        return Open(path, FileMode.Open, FileAccess.Read);
    }

    /// Creates the file, or replaces what is there.
    ///
    /// @failure IOError.NotFound      a directory along the path is missing
    /// @failure IOError.AccessDenied  the file or its directory refuses it
    /// @failure IOError.IsADirectory  the path names a directory
    /// @failure IOError.Unknown       the platform reported something with no
    ///                                case of its own
    /// @see FileStream.Open
    public static Result<FileStream, IOError> Create(String path)
    {
        return Open(path, FileMode.Create, FileAccess.Write);
    }

    /// Opens for writing at the end, creating the file if it is not there.
    ///
    /// @failure IOError.NotFound      a directory along the path is missing
    /// @failure IOError.AccessDenied  the file or its directory refuses it
    /// @failure IOError.IsADirectory  the path names a directory
    /// @failure IOError.Unknown       the platform reported something with no
    ///                                case of its own
    /// @see FileStream.Open
    public static Result<FileStream, IOError> OpenAppend(String path)
    {
        return Open(path, FileMode.Append, FileAccess.Write);
    }

    ~FileStream() { Close(); }

    /// Whether the file is still open. False after `Close`, and after an
    /// open that failed.
    public bool IsOpen => !_closed;

    /// True while the file is open and was opened for reading. A file opened
    /// for writing answers false, and `Read` on it fails rather than
    /// returning nothing.
    public bool CanRead => !_closed && _access.HasFlag(FileAccess.Read);
    /// True while the file is open and was opened for writing.
    public bool CanWrite => !_closed && _access.HasFlag(FileAccess.Write);
    /// True while the file is open. Every file is seekable, unlike a
    /// connection.
    public bool CanSeek => !_closed;

    /// Reads up to `count` bytes into `buffer` at `offset`, answering how
    /// many it read.
    ///
    /// Zero means the end of the file, or a failure -- `Error` is what tells
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
        if (offset > buffer.Length || count > buffer.Length - offset)
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
    /// Fewer than asked for means the write was cut short, and `Error` says
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
        if (offset > buffer.Length || count > buffer.Length - offset)
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
    public long Position
    {
        get
        {
            if (_closed)
                return -1;
            return sl_file_position(_handle);
        }
    }

    /// How many bytes the file holds, or -1 when it is closed. Asks the
    /// system each time rather than caching, so it sees a file another
    /// process has grown.
    public long Length
    {
        get
        {
            if (_closed)
                return -1;
            return sl_file_length(_handle);
        }
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
    /// survive a power cut. `Error` says whether the system took them.
    public void Flush()
    {
        if (!_closed)
            _error = (IOError)sl_file_flush(_handle);
    }

    /// Closes the file. Calling it twice is harmless, which matters because the
    /// destructor calls it too.
    ///
    /// Bytes still buffered are written here, so a write can fail here: a
    /// caller that needs to know its data arrived MUST read `Error` after the
    /// first `Close`. A second call leaves it alone.
    public void Close()
    {
        if (_closed)
            return;
        _error = (IOError)sl_file_close(_handle);
        _handle = null;
        _closed = true;
    }

    /// The last error, or `None`. Set by every call that failed and left
    /// alone by one that did not, so read it directly after the call it
    /// belongs to.
    public IOError Error => _error;
}
