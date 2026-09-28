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

import Standard.Collections;
import Standard.IO;

// HTTP/2 frames (RFC 9113 §4 and §6): their types, flags, settings and
// error codes, how one is read, and how one is written.

/// What every client connection starts with (RFC 9113 §3.4).
internal static readonly String s_http2ClientPreface = "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n";

/// The frame header's length.
internal const nuint Http2FrameHeaderLength = 9u;

/// The largest payload a peer may send before its settings say more.
internal const nuint Http2DefaultMaxFrameSize = 16384u;

/// The largest `SETTINGS_MAX_FRAME_SIZE` may be.
internal const nuint Http2MaxAllowedFrameSize = 16777215u;

/// Every window starts here (RFC 9113 §6.9.2).
internal const long Http2DefaultWindowSize = 65535;

/// The largest a flow-control window may grow.
internal const long Http2MaxWindowSize = 2147483647;

/// The largest stream identifier.
internal const uint Http2MaxStreamId = 2147483647u;

internal const uint Http2FlagEndStream = 0x01u;
internal const uint Http2FlagAck = 0x01u;
internal const uint Http2FlagEndHeaders = 0x04u;
internal const uint Http2FlagPadded = 0x08u;
internal const uint Http2FlagPriority = 0x20u;

/// A frame's type (RFC 9113 §6).
internal enum Http2FrameType
{
    Data = 0,
    Headers = 1,
    Priority = 2,
    RstStream = 3,
    Settings = 4,
    PushPromise = 5,
    Ping = 6,
    GoAway = 7,
    WindowUpdate = 8,
    Continuation = 9,
}

/// A setting's identifier (RFC 9113 §6.5.2).
internal enum Http2Setting
{
    HeaderTableSize = 1,
    EnablePush = 2,
    MaxConcurrentStreams = 3,
    InitialWindowSize = 4,
    MaxFrameSize = 5,
    MaxHeaderListSize = 6,
}

/// Why a stream or a connection was ended (RFC 9113 §7).
internal enum Http2ErrorCode
{
    NoError = 0,
    ProtocolError = 1,
    InternalError = 2,
    FlowControlError = 3,
    SettingsTimeout = 4,
    StreamClosed = 5,
    FrameSizeError = 6,
    RefusedStream = 7,
    Cancel = 8,
    CompressionError = 9,
    ConnectError = 10,
    EnhanceYourCalm = 11,
    InadequateSecurity = 12,
    Http11Required = 13,
}

/// An HTTP/2 error code's name, as RFC 9113 spells it.
internal String DescribeHttp2ErrorCode(uint code)
{
    switch (code)
    {
        case 0u: return "NO_ERROR";
        case 1u: return "PROTOCOL_ERROR";
        case 2u: return "INTERNAL_ERROR";
        case 3u: return "FLOW_CONTROL_ERROR";
        case 4u: return "SETTINGS_TIMEOUT";
        case 5u: return "STREAM_CLOSED";
        case 6u: return "FRAME_SIZE_ERROR";
        case 7u: return "REFUSED_STREAM";
        case 8u: return "CANCEL";
        case 9u: return "COMPRESSION_ERROR";
        case 10u: return "CONNECT_ERROR";
        case 11u: return "ENHANCE_YOUR_CALM";
        case 12u: return "INADEQUATE_SECURITY";
        case 13u: return "HTTP_1_1_REQUIRED";
    }
    return "error 0x" + FormatHttpHexadecimal((ulong)code);
}

/// One frame as read: its header, and its payload whole.
internal sealed class Http2Frame
{
    internal Http2FrameType Type;
    internal uint Flags;
    internal uint StreamId;
    internal byte[] Payload;

    internal Http2Frame(Http2FrameType type, uint flags, uint streamId, byte[] payload)
    {
        Type = type;
        Flags = flags;
        StreamId = streamId;
        Payload = payload;
    }

    internal nuint Length => Payload.Length;

    internal bool HasFlag(uint flag) => (Flags & flag) != 0u;

    /// A big-endian 32-bit word of the payload at `offset`.
    internal uint ReadHttp2Word(nuint offset) => ReadHttp2UInt32(Payload, offset);
}

/// A big-endian 32-bit word of `data` at `offset`.
internal uint ReadHttp2UInt32(byte[] data, nuint offset) =>
    ((uint)data[offset] << 24) | ((uint)data[offset + 1u] << 16) |
    ((uint)data[offset + 2u] << 8) | (uint)data[offset + 3u];

/// How reading a frame ended.
internal enum Http2ReadStatus
{
    Frame,

    /// The stream ended cleanly between frames.
    EndOfStream,

    /// The stream ended inside a frame, or failed.
    Failed,

    /// The frame's length was past the limit; its payload is not read.
    TooLarge,
}

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

/// A growable run of bytes that frames are built in.
internal sealed class Http2Buffer
{
    private byte[] _bytes;
    private nuint _length = 0u;

    internal Http2Buffer(nuint capacity) => _bytes = new byte[capacity == 0u ? 64u : capacity];

    internal nuint Length => _length;

    /// The storage; only the first `Length` bytes mean anything.
    internal byte[] Storage => _bytes;

    internal void Clear() => _length = 0u;

    internal void WriteByte(uint value)
    {
        ReserveHttp2Bytes(1u);
        _bytes[_length] = (byte)(value & 0xFFu);
        _length++;
    }

    internal void WriteUInt16(uint value)
    {
        WriteByte(value >> 8);
        WriteByte(value);
    }

    internal void WriteUInt24(uint value)
    {
        WriteByte(value >> 16);
        WriteByte(value >> 8);
        WriteByte(value);
    }

    internal void WriteUInt32(uint value)
    {
        WriteUInt16(value >> 16);
        WriteUInt16(value & 0xFFFFu);
    }

    internal void WriteArray(byte[] data, nuint offset, nuint count)
    {
        if (count == 0u)
            return;
        ReserveHttp2Bytes(count);
        memcpy(&_bytes[_length], &data[offset], count);
        _length += count;
    }

    internal void WriteText(String text)
    {
        nuint count = text.ByteLength();
        if (count == 0u)
            return;
        ReserveHttp2Bytes(count);
        memcpy(&_bytes[_length], text.ToPointer(), count);
        _length += count;
    }

    /// Appends a frame header.
    internal void WriteHttp2FrameHeader(nuint length, Http2FrameType type, uint flags,
                                        uint streamId)
    {
        WriteUInt24((uint)length);
        WriteByte((uint)type);
        WriteByte(flags);
        WriteUInt32(streamId & Http2MaxStreamId);
    }

    internal byte[] ToArray()
    {
        var copy = new byte[_length];
        if (_length > 0u)
            memcpy(&copy[0u], &_bytes[0u], _length);
        return copy;
    }

    private void ReserveHttp2Bytes(nuint more)
    {
        if (_length + more <= _bytes.Length)
            return;
        nuint size = _bytes.Length * 2u;
        while (size < _length + more)
            size *= 2u;
        var grown = new byte[size];
        if (_length > 0u)
            memcpy(&grown[0u], &_bytes[0u], _length);
        _bytes = grown;
    }
}

// ------------------------------------------------------------ frame writing

/// Appends a SETTINGS frame of `settings`, pairs of identifier and value.
internal void WriteHttp2Settings(Http2Buffer output, List<uint> settings)
{
    output.WriteHttp2FrameHeader(settings.Count / 2u * 6u, Http2FrameType.Settings, 0u, 0u);
    for (nuint i = 0u; i + 1u < settings.Count; i += 2u)
    {
        output.WriteUInt16(settings[i]);
        output.WriteUInt32(settings[i + 1u]);
    }
}

internal void WriteHttp2SettingsAck(Http2Buffer output) =>
    output.WriteHttp2FrameHeader(0u, Http2FrameType.Settings, Http2FlagAck, 0u);

internal void WriteHttp2WindowUpdate(Http2Buffer output, uint streamId, uint increment)
{
    output.WriteHttp2FrameHeader(4u, Http2FrameType.WindowUpdate, 0u, streamId);
    output.WriteUInt32(increment & Http2MaxStreamId);
}

internal void WriteHttp2RstStream(Http2Buffer output, uint streamId, uint code)
{
    output.WriteHttp2FrameHeader(4u, Http2FrameType.RstStream, 0u, streamId);
    output.WriteUInt32(code);
}

internal void WriteHttp2Ping(Http2Buffer output, byte[] opaque, bool ack)
{
    output.WriteHttp2FrameHeader(8u, Http2FrameType.Ping, ack ? Http2FlagAck : 0u, 0u);
    output.WriteArray(opaque, 0u, 8u);
}

internal void WriteHttp2GoAway(Http2Buffer output, uint lastStreamId, uint code, String debug)
{
    output.WriteHttp2FrameHeader(8u + debug.ByteLength(), Http2FrameType.GoAway, 0u, 0u);
    output.WriteUInt32(lastStreamId & Http2MaxStreamId);
    output.WriteUInt32(code);
    output.WriteText(debug);
}

internal void WriteHttp2Data(Http2Buffer output, uint streamId, byte[] data, nuint offset,
                             nuint count,
                             bool endStream)
{
    output.WriteHttp2FrameHeader(count, Http2FrameType.Data, endStream ? Http2FlagEndStream : 0u,
                                 streamId);
    output.WriteArray(data, offset, count);
}

/// Appends a header block as one HEADERS frame and as many CONTINUATION
/// frames after it as `maxFrameSize` needs.
internal void WriteHttp2HeaderBlock(Http2Buffer output, uint streamId, Http2Buffer block,
                                    bool endStream,
                                    nuint maxFrameSize)
{
    nuint total = block.Length;
    nuint at = 0u;
    bool first = true;
    while (first || at < total)
    {
        nuint part = total - at;
        if (part > maxFrameSize)
            part = maxFrameSize;
        bool last = at + part == total;
        uint flags = last ? Http2FlagEndHeaders : 0u;
        if (first && endStream)
            flags |= Http2FlagEndStream;
        Http2FrameType type = first ? Http2FrameType.Headers : Http2FrameType.Continuation;
        output.WriteHttp2FrameHeader(part, type, flags, streamId);
        output.WriteArray(block.Storage, at, part);
        at += part;
        first = false;
    }
}
