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
