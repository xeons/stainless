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
