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
