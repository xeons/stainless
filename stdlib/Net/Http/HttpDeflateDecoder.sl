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

/// A `deflate` body, which RFC 9110 says is zlib and some servers send as
/// raw deflate: the first two bytes decide, as browsers decide.
internal sealed class HttpDeflateDecoder : IStream
{
    private IStream _source;
    private IStream? _decoder;
    private ZLibStream? _zlib;
    private DeflateStream? _deflate;
    private bool _failed = false;

    internal HttpDeflateDecoder(IStream source) => _source = source;

    internal CompressionError CompressionErrorCode
    {
        get
        {
            if (_zlib is ZLibStream zlib)
                return zlib.CompressionErrorCode;
            if (_deflate is DeflateStream deflate)
                return deflate.CompressionErrorCode;
            return CompressionError.None;
        }
    }

    public bool CanRead => !_failed;

    public bool CanWrite => false;

    public bool CanSeek => false;

    public nuint Read(byte[] buffer, nuint offset, nuint count)
    {
        if (_decoder == null && !ChooseHttpDeflateDecoder())
            return 0u;
        IStream? decoder = _decoder;
        return decoder == null ? 0u : decoder.Read(buffer, offset, count);
    }

    private bool ChooseHttpDeflateDecoder()
    {
        var first = new byte[2u];
        nuint got = 0u;
        while (got < 2u)
        {
            nuint read = _source.Read(first, got, 2u - got);
            if (read == 0u)
                break;
            got += read;
        }
        if (got == 0u && _source.Error != IOError.None)
        {
            _failed = true;
            return false;
        }

        var prefix = new byte[got];
        for (nuint i = 0u; i < got; i++)
            prefix[i] = first[i];
        var replay = new HttpPrefixedStream(prefix, _source);

        // RFC 1950: method 8 in the low nibble, and a header divisible by 31.
        bool zlib = got == 2u && (first[0u] & 0x0F) == 8 && (((uint)first[0u] << 8) | (uint)first[1u]) % 31u == 0u;
        if (zlib)
        {
            var decoder = new ZLibStream(replay, CompressionMode.Decompress);
            _zlib = decoder;
            _decoder = decoder;
        }
        else
        {
            var decoder = new DeflateStream(replay, CompressionMode.Decompress);
            _deflate = decoder;
            _decoder = decoder;
        }
        return true;
    }

    public nuint Write(byte[] buffer, nuint offset, nuint count) => 0u;

    public long Position => -1;

    public long Length => -1;

    public bool Seek(long offset, SeekOrigin origin) => false;

    public void Flush() { }

    public void Close()
    {
        IStream? decoder = _decoder;
        if (decoder != null)
            decoder.Close();
        else
            _source.Close();
    }

    public IOError Error
    {
        get
        {
            if (_failed)
                return _source.Error;
            IStream? decoder = _decoder;
            return decoder == null ? IOError.None : decoder.Error;
        }
    }
}
