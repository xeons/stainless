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

module Standard.Encoding;

import Standard.Text;

/// A decode in progress, across as many pieces as the bytes arrive in.
///
/// .NET's `Decoder`, narrowed to what this language needs: it answers with a
/// `String` rather than filling a `char` buffer, so there is no count to ask
/// for first and no `GetCharCount` beside it.
///
/// An encoder has no counterpart here. .NET needs one because a caller can
/// write half a surrogate pair; a caller here writes a `String`, which is
/// whole by construction, so there is never anything for a writer to hold.
public interface IDecoder
{
    /// The text that `count` bytes from `index` complete, with any unfinished
    /// character at the end kept back for the next call.
    ///
    /// `flush` says no more bytes are coming, so anything still held is
    /// malformed and becomes U+FFFD rather than waiting for the rest.
    String GetString(byte[] bytes, nuint index, nuint count, bool flush);

    /// Forgets what is held, for a decoder being pointed at something new.
    void Reset();
}
