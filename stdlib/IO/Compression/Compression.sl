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

/// Deflate, gzip and zlib: RFC 1951, 1952 and 1950, as streams and as
/// one-shot calls.
///
/// ```csharp
/// var file = try FileStream.OpenRead("log.gz");
/// var gunzip = new GZipStream(file, CompressionMode.Decompress);
/// var text = try IO.ReadTextToEnd(gunzip);
///
/// byte[] packed = Compression.CompressGZip(data, CompressionLevel.SmallestSize);
/// var unpacked = Compression.DecompressGZip(packed);
/// ```
///
/// **The shape is `System.IO.Compression`'s**: `DeflateStream`,
/// `GZipStream` and `ZLibStream` wrap another `IStream`, and are made with a
/// `CompressionMode` or a `CompressionLevel` and a `leaveOpen` flag. `Crc32`
/// and `Adler32` are the two checksums the formats use, and are public
/// because other formats — zip, PNG — use them too.
///
/// **How failure is reported follows `Standard.IO`.** A stream carries its
/// last error in `Error`, and a corrupt or truncated stream reads as
/// `IOError.InvalidData` there, as .NET throws `InvalidDataException`. The
/// exact reason is a `CompressionError` in `CompressionErrorCode`, alongside,
/// as `TcpClient` keeps the exact socket error beside the rounded one. The
/// one-shot `Decompress` functions return `Result<byte[], CompressionError>`,
/// since over memory the data is the only thing that can be wrong.
///
/// **Bad data is refused, never trusted.** Every code set is checked for
/// being over-subscribed or incomplete, every distance against the data
/// produced so far, every stored length against its complement, and every
/// trailer against the data. A refusal is a reported error, never an abort
/// and never a loop.
///
/// **Decompressing reads ahead.** The source is read in blocks of 16 KiB, so
/// up to that much past the end of the compressed data can be taken from it
/// and not given back. That is harmless when the compressed data is all the
/// source holds — a file, or an HTTP body behind a stream that stops at its
/// length or its last chunk — and it is why a raw `DeflateStream` cannot be
/// followed by other data on the same stream. .NET's streams do the same.
///
/// **Concatenated gzip members read as one stream**, as `gzip -d` reads them.
/// After a member, anything that does not begin another is ignored.
module Standard.IO.Compression;

import Standard.IO;

extern "C"
{
    byte* memcpy(byte* to, byte* from, nuint count);
    byte* memmove(byte* to, byte* from, nuint count);
}

// ---------------------------------------------------------------- one-shot

/// `data` as raw deflate at `CompressionLevel.Optimal`.
///
/// @see Compression.DecompressDeflate
public byte[] CompressDeflate(ReadOnlySpan<byte> data) =>
    CompressWithFormat(data, CompressionFormat.Raw, CompressionLevel.Optimal);

/// `data` as raw deflate at `level`.
///
/// @param data   what to compress
/// @param level  how hard to work at it
public byte[] CompressDeflate(ReadOnlySpan<byte> data, CompressionLevel level) =>
    CompressWithFormat(data, CompressionFormat.Raw, level);

/// `data` as one gzip member at `CompressionLevel.Optimal`.
///
/// @see Compression.DecompressGZip
public byte[] CompressGZip(ReadOnlySpan<byte> data) =>
    CompressWithFormat(data, CompressionFormat.GZip, CompressionLevel.Optimal);

/// `data` as one gzip member at `level`.
///
/// @param data   what to compress
/// @param level  how hard to work at it
public byte[] CompressGZip(ReadOnlySpan<byte> data, CompressionLevel level) =>
    CompressWithFormat(data, CompressionFormat.GZip, level);

/// `data` as a zlib stream at `CompressionLevel.Optimal`.
///
/// @see Compression.DecompressZLib
public byte[] CompressZLib(ReadOnlySpan<byte> data) =>
    CompressWithFormat(data, CompressionFormat.ZLib, CompressionLevel.Optimal);

/// `data` as a zlib stream at `level`.
///
/// @param data   what to compress
/// @param level  how hard to work at it
public byte[] CompressZLib(ReadOnlySpan<byte> data, CompressionLevel level) =>
    CompressWithFormat(data, CompressionFormat.ZLib, level);

/// What raw deflate `data` expands to. Bytes after the final block are
/// ignored.
///
/// @failure CompressionError.Truncated             the data ends inside a block
/// @failure CompressionError.InvalidBlockType      a block of the reserved type
/// @failure CompressionError.StoredLengthMismatch  a stored block's length and
///                                                 complement disagree
/// @failure CompressionError.InvalidCodeLengths    a dynamic block's code is
///                                                 unusable
/// @failure CompressionError.InvalidCode           a pattern no code stands for
/// @failure CompressionError.InvalidDistance       a match before the start
public Result<byte[], CompressionError> DecompressDeflate(ReadOnlySpan<byte> data) =>
    DecompressWithFormat(data, CompressionFormat.Raw);

/// What gzip `data` expands to, every member of it in order.
///
/// @failure CompressionError.Truncated             the data ends inside a
///                                                 member
/// @failure CompressionError.InvalidHeader         not a gzip header, or its
///                                                 CRC does not match
/// @failure CompressionError.InvalidBlockType      a block of the reserved type
/// @failure CompressionError.StoredLengthMismatch  a stored block's length and
///                                                 complement disagree
/// @failure CompressionError.InvalidCodeLengths    a dynamic block's code is
///                                                 unusable
/// @failure CompressionError.InvalidCode           a pattern no code stands for
/// @failure CompressionError.InvalidDistance       a match before the start
/// @failure CompressionError.ChecksumMismatch      the CRC-32 does not match
/// @failure CompressionError.LengthMismatch        the length does not match
public Result<byte[], CompressionError> DecompressGZip(ReadOnlySpan<byte> data) =>
    DecompressWithFormat(data, CompressionFormat.GZip);

/// What zlib `data` expands to. Bytes after the trailer are ignored.
///
/// @failure CompressionError.Truncated             the data ends early
/// @failure CompressionError.InvalidHeader         not a zlib header
/// @failure CompressionError.DictionaryRequired    it needs a preset dictionary
/// @failure CompressionError.InvalidBlockType      a block of the reserved type
/// @failure CompressionError.StoredLengthMismatch  a stored block's length and
///                                                 complement disagree
/// @failure CompressionError.InvalidCodeLengths    a dynamic block's code is
///                                                 unusable
/// @failure CompressionError.InvalidCode           a pattern no code stands for
/// @failure CompressionError.InvalidDistance       a match before the start
/// @failure CompressionError.ChecksumMismatch      the Adler-32 does not match
public Result<byte[], CompressionError> DecompressZLib(ReadOnlySpan<byte> data) =>
    DecompressWithFormat(data, CompressionFormat.ZLib);

byte[] CompressWithFormat(ReadOnlySpan<byte> data, CompressionFormat format,
                          CompressionLevel level)
{
    var sink = new MemoryStream();
    var deflater = new Deflater(sink, format, level);
    deflater.WriteData(data);
    deflater.Finish();
    return sink.ToArray();
}

Result<byte[], CompressionError> DecompressWithFormat(ReadOnlySpan<byte> data,
                                                      CompressionFormat format)
{
    var inflater = new Inflater(new SpanSource(data), format);
    nuint capacity = data.Length * 4;
    if (capacity < 4096u)
        capacity = 4096;

    var output = new byte[capacity];
    nuint length = 0;
    for (;;)
    {
        if (length == output.Length)
        {
            var bigger = new byte[output.Length * 2];
            memcpy(&bigger[0], &output[0], length);
            output = bigger;
        }

        nuint got = inflater.Read(output, length, output.Length - length);
        if (got == 0)
            break;
        length += got;
    }

    CompressionError failure = inflater.DataError;
    if (failure != CompressionError.None)
        return Fail(failure);

    var exact = new byte[length];
    if (length > 0)
        memcpy(&exact[0], &output[0], length);
    return Ok(exact);
}

// A read-only stream over a span, for the one-shot calls to decompress from.
class SpanSource : IStream
{
    ReadOnlySpan<byte> _data;
    nuint _at;

    SpanSource(ReadOnlySpan<byte> data)
    {
        _data = data;
        _at = 0;
    }

    public bool CanRead => true;
    public bool CanWrite => false;
    public bool CanSeek => false;

    public nuint Read(byte[] buffer, nuint offset, nuint count)
    {
        nuint available = _data.Length - _at;
        nuint taking = count < available ? count : available;
        for (nuint i = 0; i < taking; i++)
            buffer[offset + i] = _data[_at + i];
        _at += taking;
        return taking;
    }

    public nuint Write(byte[] buffer, nuint offset, nuint count) => 0;
    public long Position => -1;
    public long Length => -1;
    public bool Seek(long offset, SeekOrigin origin) => false;
    public void Flush() { }
    public void Close() { }
    public IOError Error => IOError.None;
}
