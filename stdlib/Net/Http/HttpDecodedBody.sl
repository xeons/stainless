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

module Standard.Net.Http;

import Standard.IO;
import Standard.IO.Compression;

/// A body read through a decoder. When the decoded data ends, what is left of
/// the body as it arrived — a chunked body's last chunk, say — is read too,
/// so that the connection is given back rather than left waiting.
internal sealed class HttpDecodedBody : IStream
{
    private IStream _decoder;
    private IHttpBodyStream _raw;

    internal HttpDecodedBody(IStream decoder, IHttpBodyStream raw)
    {
        _decoder = decoder;
        _raw = raw;
    }

    internal CompressionError CompressionErrorCode
    {
        get
        {
            if (_decoder is GZipStream gzip)
                return gzip.CompressionErrorCode;
            if (_decoder is HttpDeflateDecoder deflate)
                return deflate.CompressionErrorCode;
            return CompressionError.None;
        }
    }

    public bool CanRead => _decoder.CanRead;

    public bool CanWrite => false;

    public bool CanSeek => false;

    public nuint Read(byte[] buffer, nuint offset, nuint count)
    {
        nuint got = _decoder.Read(buffer, offset, count);
        if (got == 0u && count > 0u && _decoder.Error == IOError.None)
            DrainHttpBody(_raw);
        return got;
    }

    public nuint Write(byte[] buffer, nuint offset, nuint count) => 0u;

    public long Position => -1;

    public long Length => -1;

    public bool Seek(long offset, SeekOrigin origin) => false;

    public void Flush() { }

    public void Close()
    {
        _decoder.Close();
        _raw.Close();
    }

    public IOError Error => _decoder.Error;
}
