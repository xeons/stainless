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
    int   sl_file_close(byte* handle);
    nuint sl_file_read(byte* handle, byte* buffer, nuint count, int* error);
    nuint sl_file_write(byte* handle, byte* buffer, nuint count, int* error);
    long  sl_file_seek(byte* handle, long offset, int origin, int* error);
    long  sl_file_position(byte* handle);
    long  sl_file_length(byte* handle);
    int   sl_file_flush(byte* handle);
}

/// A sentence describing an error, for a message a person will read.
///
/// @see IOError
public String DescribeIOError(IOError error)
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

// ------------------------------------------------------------------ helpers

/// Reads a stream to its end.
///
/// @failure IOError.Closed        the stream was closed before the read
///                               finished
/// @failure IOError.AccessDenied  the stream refused to be read
/// @failure IOError.Unknown       the stream failed for a reason with no case
///                               of its own
/// @see IO.ReadTextToEnd
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

    var failure = stream.Error;
    if (failure != IOError.None)
        return Fail(failure);
    return Ok(collected.ToArray());
}

/// Reads a stream to its end and reads the bytes as UTF-8.
///
/// @failure IOError.Closed        the stream was closed before the read
///                               finished
/// @failure IOError.AccessDenied  the stream refused to be read
/// @failure IOError.Unknown       the stream failed for a reason with no case
///                               of its own
/// @see IO.ReadToEnd
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
///
/// @returns the lines, each without its ending
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
