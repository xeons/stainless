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

module Standard.IO;

import Standard.Collections;

// ------------------------------------------------------------------ stream

/// A sequence of bytes that can be read, written, or both.
///
/// Read and Write report how many bytes they moved, which for a read is how
/// end-of-file is seen: fewer than asked for, and zero at the end. Whether
/// that was an error rather than an ending is what `Error` says.
public interface IStream
{
    /// Whether reading is allowed and possible now. False on a write-only
    /// stream and on a closed one.
    bool CanRead { get; }

    /// Whether writing is allowed and possible now.
    bool CanWrite { get; }

    /// Whether the position can be moved. False for a stream with no position
    /// to move -- a socket, a pipe -- where `Seek` fails and `Position` and
    /// `Length` answer -1.
    bool CanSeek { get; }

    /// Reads up to `count` bytes into `buffer` starting at `offset`, and
    /// returns how many it read. Zero means the end.
    nuint Read(byte[] buffer, nuint offset, nuint count);

    /// Writes `count` bytes from `buffer` starting at `offset`, and returns
    /// how many it wrote.
    nuint Write(byte[] buffer, nuint offset, nuint count);

    /// Where the next read or write will happen, or -1 when the stream has no
    /// position.
    long Position { get; }

    /// How many bytes the stream holds, or -1 when it cannot say -- which is
    /// every stream that is not seekable, and some that are.
    long Length { get; }

    /// Moves the cursor. Reports whether it could.
    bool Seek(long offset, SeekOrigin origin);

    /// Pushes buffered bytes onward. What "onward" means is the stream's: for
    /// a file it is the system, not the disk.
    void Flush();

    /// Releases whatever the stream holds. Implementations make this
    /// idempotent, and a destructor calls it, so a stream that goes out of
    /// scope is not leaked.
    void Close();

    /// The last error, or `IOError.None`. Cleared by the next successful call.
    IOError Error { get; }
}
