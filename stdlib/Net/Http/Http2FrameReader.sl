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

/// Reads frames from a stream, one whole frame at a time.
internal sealed class Http2FrameReader
{
    private HttpBufferedReader _reader;

    internal Http2FrameReader(HttpBufferedReader reader) => _reader = reader;

    internal HttpBufferedReader Buffered => _reader;

    /// The next frame, whose payload may be at most `maxLength`. The type is
    /// whatever was on the wire, including one this end does not know.
    internal Http2ReadStatus ReadHttp2Frame(nuint maxLength, out Http2Frame? frame)
    {
        frame = null;
        var header = new byte[Http2FrameHeaderLength];
        nuint got = ReadAllHttp2Bytes(header, Http2FrameHeaderLength);
        if (got == 0u && !_reader.HasFailed)
            return Http2ReadStatus.EndOfStream;
        if (got < Http2FrameHeaderLength)
            return Http2ReadStatus.Failed;

        nuint length = ((nuint)header[0u] << 16) | ((nuint)header[1u] << 8) | (nuint)header[2u];
        uint streamId = ReadHttp2UInt32(header, 5u) & Http2MaxStreamId;
        var type = (Http2FrameType)header[3u];
        if (length > maxLength)
        {
            frame = new Http2Frame(type, (uint)header[4u], streamId, new byte[0u]);
            return Http2ReadStatus.TooLarge;
        }
        var payload = new byte[length];
        if (ReadAllHttp2Bytes(payload, length) < length)
            return Http2ReadStatus.Failed;
        frame = new Http2Frame(type, (uint)header[4u], streamId, payload);
        return Http2ReadStatus.Frame;
    }

    /// Reads exactly `count` bytes unless the stream ends first, and answers
    /// how many it read.
    internal nuint ReadAllHttp2Bytes(byte[] into, nuint count)
    {
        nuint at = 0u;
        while (at < count)
        {
            nuint got = _reader.ReadHttpBytes(into, at, count - at);
            if (got == 0u)
                return at;
            at += got;
        }
        return at;
    }
}
