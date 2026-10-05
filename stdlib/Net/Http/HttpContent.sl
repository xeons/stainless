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

import Standard.Encoding;
import Standard.IO;
import Standard.Limits;
import Standard.Text;

/// A body and the fields that describe it.
///
///     String text = try response.Content.ReadAsString();
///     IStream body = try response.Content.ReadAsStream();
///
/// .NET's `HttpContent`. A derived class says how to write itself with
/// `SerializeToStream` and whether it knows its length with
/// `TryComputeLength`; everything else is built on those two.
///
/// **A response's content reads once** unless it was buffered, which it is
/// unless the request asked for `ResponseHeadersRead`. `LoadIntoBuffer` reads
/// the rest of it into memory, after which every read starts again from the
/// beginning.
public abstract class HttpContent : IDisposable
{
    private late HttpContentHeaders _headers;
    private byte[] _buffer = new byte[0u];
    private bool _buffered = false;

    protected HttpContent() => _headers = new HttpContentHeaders(this);

    /// The fields describing this body.
    public HttpContentHeaders Headers => _headers;

    /// Writes the whole body to `stream`.
    ///
    /// @failure HttpError.ContentFailure  the body could not be read, or
    ///                                    `stream` would not take it
    protected abstract HttpError SerializeToStream(IStream stream);

    /// The body's length in bytes, when it is known without writing it.
    protected abstract bool TryComputeLength(out long length);

    /// A stream over the body that does not buffer it, or null to have it
    /// buffered first.
    protected virtual IStream? CreateContentReadStream() => null;

    // --------------------------------------------------------------- reading

    /// The whole body.
    ///
    /// @failure HttpError.ConnectionClosed  the connection ended mid-body
    /// @failure HttpError.Timeout           the request's timeout ran out
    /// @failure HttpError.ContentFailure    the body could not be read
    public Result<byte[], HttpError> ReadAsByteArray()
    {
        HttpError loaded = LoadIntoBuffer();
        if (loaded != HttpError.None)
            return Fail(loaded);
        return Ok(_buffer);
    }

    /// The whole body as text, decoded by the `charset` of `Content-Type`
    /// when this module knows it, by a byte order mark when there is one,
    /// and as UTF-8 otherwise. Malformed input becomes U+FFFD.
    ///
    /// @failure HttpError.ConnectionClosed  the connection ended mid-body
    /// @failure HttpError.Timeout           the request's timeout ran out
    public Result<String, HttpError> ReadAsString()
    {
        byte[] bytes = try ReadAsByteArray();
        if (bytes.Length == 0u)
            return Ok("");

        IEncoding? marked = Encoding.DetectEncoding(bytes);
        if (marked != null)
            return Ok(marked.GetString(Encoding.StripPreamble(marked, bytes)));

        IEncoding encoding = Encoding.CreateUtf8();
        var type = _headers.ContentType;
        if (type != null)
        {
            String? charSet = type.CharSet;
            if (charSet != null)
            {
                IEncoding? named = FindHttpEncoding(charSet);
                if (named != null)
                    encoding = named;
            }
        }
        return Ok(encoding.GetString(bytes));
    }

    /// A stream to read the body from. For a response that was not buffered
    /// this is the connection itself, and reads once.
    ///
    /// @failure HttpError.ContentFailure  the body could not be buffered
    public Result<IStream, HttpError> ReadAsStream()
    {
        if (_buffered)
            return Ok(new MemoryStream(_buffer));
        IStream? direct = CreateContentReadStream();
        if (direct != null)
            return Ok(direct);
        HttpError loaded = LoadIntoBuffer();
        if (loaded != HttpError.None)
            return Fail(loaded);
        return Ok(new MemoryStream(_buffer));
    }

    /// Writes the body to `destination`.
    ///
    /// @failure HttpError.ContentFailure  `destination` would not take it, or
    ///                                    the body could not be read
    public HttpError CopyTo(IStream destination)
    {
        if (_buffered)
        {
            if (!WriteAllHttpBytes(destination, _buffer, 0u, _buffer.Length))
                return HttpError.ContentFailure;
            return HttpError.None;
        }
        return SerializeToStream(destination);
    }

    /// Reads the whole body into memory, so that it can be read again.
    ///
    /// @failure HttpError.ContentFailure  the body could not be read
    public HttpError LoadIntoBuffer() => LoadIntoBuffer(Limits.MaxLong);

    /// Reads the whole body into memory, refusing one over `maxBufferSize`.
    ///
    /// @param maxBufferSize  the most bytes to hold
    /// @failure HttpError.ResponseTooLarge  the body is longer than that
    public HttpError LoadIntoBuffer(long maxBufferSize)
    {
        if (_buffered)
            return HttpError.None;
        var sink = new HttpBoundedBufferStream(maxBufferSize);
        HttpError written = SerializeToStream(sink);
        if (sink.IsOverLimit)
            return HttpError.ResponseTooLarge;
        if (written != HttpError.None)
            return written;
        _buffer = sink.ToArray();
        _buffered = true;
        return HttpError.None;
    }

    /// Releases what the body holds: a response's connection, which is
    /// closed rather than pooled if the body was not read to its end.
    public virtual void Dispose() { }

    // ------------------------------------------------------------ for the module

    internal bool TryComputeHttpContentLength(out long length)
    {
        if (_buffered)
        {
            length = (long)_buffer.Length;
            return true;
        }
        bool known = TryComputeLength(out long computed);
        length = computed;
        return known;
    }

    internal HttpError WriteHttpContent(IStream stream) => CopyTo(stream);

    internal bool IsHttpContentReplayable => _buffered || CanReplayContent;

    internal bool RewindHttpContent() => _buffered || TryRewindContent();

    /// Whether the body can be written a second time, for a redirect that
    /// keeps it or a retry.
    protected virtual bool CanReplayContent => true;

    /// Prepares the body to be written again. False when it cannot be.
    protected virtual bool TryRewindContent() => true;
}

/// The encoding a `charset` names, when this module knows it.
internal IEncoding? FindHttpEncoding(String charSet)
{
    String name = TrimHttpWhitespace(charSet).ToLowerAscii();
    switch (name)
    {
        case "utf-8":
        case "utf8":
            return Encoding.CreateUtf8();
        case "us-ascii":
        case "ascii":
            return Encoding.CreateAscii();
        case "iso-8859-1":
        case "latin1":
            return Encoding.CreateLatin1();
        case "windows-1252":
        case "cp1252":
            return Encoding.CreateWindows1252();
        case "utf-16":
        case "utf-16le":
            return Encoding.CreateUtf16();
        case "utf-16be":
            return Encoding.CreateUtf16BigEndian();
        case "utf-32":
        case "utf-32le":
            return Encoding.CreateUtf32();
        case "utf-32be":
            return Encoding.CreateUtf32BigEndian();
    }
    return null;
}
