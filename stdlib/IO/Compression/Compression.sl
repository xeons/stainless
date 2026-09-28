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

