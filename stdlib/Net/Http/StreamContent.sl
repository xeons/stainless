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

/// A body read from a stream as it is sent.
///
/// A seekable stream knows its length, from where it stood when the content
/// was made to its end, and is sent with `Content-Length`; any other stream
/// is sent chunked. Only a seekable stream can be sent twice, so only its
/// body survives a `307` or `308`, or a retry.
public class StreamContent : HttpContent
{
    private IStream _content;
    private nuint _bufferSize;
    private long _start;
    private bool _consumed = false;

    /// A body read from `content` in blocks of 16 KiB.
    public StreamContent(IStream content) : this(content, HttpCopyBlockSize) { }

    /// A body read from `content` in blocks of `bufferSize` bytes.
    public StreamContent(IStream content, nuint bufferSize)
    {
        _content = content;
        _bufferSize = bufferSize == 0u ? HttpCopyBlockSize : bufferSize;
        _start = content.CanSeek ? content.Position : 0;
    }

    protected override HttpError SerializeToStream(IStream stream)
    {
        if (_consumed && !TryRewindContent())
            return HttpError.ContentFailure;
        _consumed = true;

        var block = new byte[_bufferSize];
        while (true)
        {
            nuint got = _content.Read(block, 0u, block.Length);
            if (got == 0u)
                return _content.Error == IOError.None ? HttpError.None : HttpError.ContentFailure;
            if (!WriteAllHttpBytes(stream, block, 0u, got))
                return HttpError.ContentFailure;
        }
    }

    protected override bool TryComputeLength(out long length)
    {
        length = 0;
        if (!_content.CanSeek)
            return false;
        long total = _content.Length;
        if (total < _start)
            return false;
        length = total - _start;
        return true;
    }

    protected override IStream? CreateContentReadStream() => _content;

    protected override bool CanReplayContent => _content.CanSeek;

    protected override bool TryRewindContent()
    {
        if (!_content.CanSeek)
            return !_consumed;
        return _content.Seek(_start, SeekOrigin.Start);
    }

    /// Closes the stream.
    public override void Dispose() => _content.Close();
}
