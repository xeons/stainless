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

/// A body held in memory: bytes, sent as they are.
///
/// Knows its length, so it is sent with `Content-Length`, and can be sent
/// again, so a redirect that keeps the body keeps it.
public class ByteArrayContent : HttpContent
{
    private byte[] _content;
    private nuint _offset;
    private nuint _count;

    /// The whole of `content`, which is not copied.
    public ByteArrayContent(byte[] content)
    {
        _content = content;
        _offset = 0u;
        _count = content.Length;
    }

    /// `count` bytes of `content` from `offset`, which MUST lie inside it.
    public ByteArrayContent(byte[] content, nuint offset, nuint count)
    {
        _content = content;
        _offset = offset;
        _count = count;
        if (offset > content.Length || count > content.Length - offset)
        {
            _offset = 0u;
            _count = 0u;
        }
    }

    protected override HttpError SerializeToStream(IStream stream)
    {
        if (_count == 0u)
            return HttpError.None;
        if (!WriteAllHttpBytes(stream, _content, _offset, _count))
            return HttpError.ContentFailure;
        return HttpError.None;
    }

    protected override bool TryComputeLength(out long length)
    {
        length = (long)_count;
        return true;
    }
}
