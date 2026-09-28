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

/// The body of a response, read from its connection once.
///
/// `_body` is what a reader gets: the body as it arrived, or decoded from
/// gzip or deflate. `_raw` is the body as it arrived either way, which is
/// what says whether it ended cleanly and so whether its connection can be
/// reused.
internal sealed class HttpResponseContent : HttpContent
{
    private IStream _body;
    private IHttpBodyStream _raw;
    private bool _taken = false;

    internal HttpResponseContent(IStream body, IHttpBodyStream raw)
    {
        _body = body;
        _raw = raw;
    }

    internal IHttpBodyStream RawHttpBody => _raw;

    /// Reads the body through `decoder`, which reads `RawHttpBody`, from now
    /// on.
    internal void DecodeHttpContent(IStream decoder) => _body = new HttpDecodedBody(decoder, _raw);

    /// The decompressor's error, when a decoder failed.
    internal CompressionError HttpCompressionError
    {
        get
        {
            if (_body is HttpDecodedBody decoded)
                return decoded.CompressionErrorCode;
            return CompressionError.None;
        }
    }

    protected override HttpError SerializeToStream(IStream stream)
    {
        if (_taken)
            return HttpError.ContentFailure;
        _taken = true;

        HttpCopyOutcome outcome = CopyHttpStream(_body, stream);
        switch (outcome)
        {
            case HttpCopyOutcome.Done:
                if (_raw.HttpErrorCode != HttpError.None)
                    return _raw.HttpErrorCode;
                DrainHttpBody(_raw);
                return HttpError.None;
            case HttpCopyOutcome.ReadFailed:
                _raw.Close();
                if (_raw.HttpErrorCode != HttpError.None)
                    return _raw.HttpErrorCode;
                return HttpError.DecompressionFailed;
            default:
                _raw.Close();
                return HttpError.ContentFailure;
        }
    }

    protected override bool TryComputeLength(out long length)
    {
        length = 0;
        return false;
    }

    protected override IStream? CreateContentReadStream()
    {
        _taken = true;
        return _body;
    }

    protected override bool CanReplayContent => false;

    /// Closes the body, and with it the connection unless the body had been
    /// read to its end.
    public override void Dispose()
    {
        _body.Close();
        _raw.Close();
    }
}

/// Reads what is left of a body that is not wanted, so that its connection
/// can carry the next request, up to a limit past which closing is cheaper.
internal void DrainHttpBody(IHttpBodyStream body)
{
    if (body.IsHttpBodyComplete || !body.CanRead)
        return;
    var scratch = new byte[HttpCopyBlockSize];
    long drained = 0;
    while (drained <= HttpMaxDrainLength)
    {
        nuint got = body.Read(scratch, 0u, scratch.Length);
        if (got == 0u)
            return;
        drained += (long)got;
    }
    body.Close();
}

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
