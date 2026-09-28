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

module Standard.IO.Compression;

import Standard.IO;

/// Raw deflate (RFC 1951) over another stream, with no header and no
/// checksum: what zip entries and HTTP's `Content-Encoding: deflate` from a
/// misreading server hold.
///
///     var packed = new MemoryStream();
///     var deflate = new DeflateStream(packed, CompressionLevel.Optimal, true);
///     deflate.Write(data, 0, data.Length);
///     deflate.Close();                // the final block is written here
///
/// With nothing to check the data against, a corrupt stream is caught only
/// where it breaks the format; `GZipStream` and `ZLibStream` also verify
/// what was decoded. A raw stream also has no end marker beyond its final
/// block, and reading ahead means bytes after it on the same source are
/// lost to whoever reads next.
public class DeflateStream : IStream
{
    CompressionStreamCore _core;

    /// Decompresses from `stream`, or compresses onto it at
    /// `CompressionLevel.Optimal`, and closes it on `Close`.
    public DeflateStream(IStream stream, CompressionMode mode)
    {
        _core = new CompressionStreamCore(stream, CompressionFormat.Raw, mode,
                                          CompressionLevel.Optimal, false);
    }

    /// Decompresses from `stream`, or compresses onto it at
    /// `CompressionLevel.Optimal`.
    ///
    /// @param stream     the compressed side
    /// @param mode       which way the data moves
    /// @param leaveOpen  true to leave `stream` open after `Close`
    public DeflateStream(IStream stream, CompressionMode mode, bool leaveOpen)
    {
        _core = new CompressionStreamCore(stream, CompressionFormat.Raw, mode,
                                          CompressionLevel.Optimal, leaveOpen);
    }

    /// Compresses onto `stream` at `level`, and closes it on `Close`.
    public DeflateStream(IStream stream, CompressionLevel level)
    {
        _core = new CompressionStreamCore(stream, CompressionFormat.Raw,
                                          CompressionMode.Compress, level, false);
    }

    /// Compresses onto `stream` at `level`.
    ///
    /// @param stream     where the compressed bytes go
    /// @param level      how hard to work at it
    /// @param leaveOpen  true to leave `stream` open after `Close`
    public DeflateStream(IStream stream, CompressionLevel level, bool leaveOpen)
    {
        _core = new CompressionStreamCore(stream, CompressionFormat.Raw,
                                          CompressionMode.Compress, level, leaveOpen);
    }

    ~DeflateStream() { Close(); }

    /// The stream the compressed bytes come from or go to.
    public IStream BaseStream => _core.BaseStream;

    /// Why the data was refused, exactly, where `Error` says only
    /// `IOError.InvalidData`. `None` while nothing has been.
    public CompressionError CompressionErrorCode => _core.DataError;

    /// True while open, decompressing, and the stream underneath can be read.
    public bool CanRead => _core.CanRead;

    /// True while open, compressing, and the stream underneath can be written.
    public bool CanWrite => _core.CanWrite;

    /// Always false. Neither direction has a position to move to.
    public bool CanSeek => false;

    /// Decompresses up to `count` bytes into `buffer` at `offset`, answering
    /// how many. Fewer than asked for is normal; zero is the end of the data
    /// or a failure, which `Error` tells apart. A compressing stream reads
    /// nothing and reports `IOError.Invalid`.
    public nuint Read(byte[] buffer, nuint offset, nuint count) =>
        _core.Read(buffer, offset, count);

    /// Compresses `count` bytes from `buffer` at `offset`, answering `count`,
    /// or zero when writing onward failed. Output is written onward as it
    /// fills, and not all of it until `Flush` or `Close`.
    public nuint Write(byte[] buffer, nuint offset, nuint count) =>
        _core.Write(buffer, offset, count);

    /// Not a position.
    public long Position => -1;

    /// Not a length either.
    public long Length => -1;

    /// Always false.
    public bool Seek(long offset, SeekOrigin origin) => false;

    /// Compressing, writes everything so far onward as whole bytes a reader
    /// can decode, and flushes the stream underneath. Each flush costs a few
    /// bytes of output, so it is for a protocol that needs the data to
    /// arrive, not for a loop. Decompressing, does nothing.
    public void Flush() => _core.Flush();

    /// Compressing, writes the final block, which a stream that is never
    /// closed does not have. Then closes the stream underneath unless it was
    /// to be left open. Idempotent, and the destructor calls it.
    public void Close() => _core.Close();

    /// The last error, or `IOError.None`. `IOError.InvalidData` means the
    /// compressed data was refused, and `CompressionErrorCode` says why; any
    /// other value came from the stream underneath.
    public IOError Error => _core.Error;
}
