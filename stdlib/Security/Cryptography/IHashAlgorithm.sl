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

module Standard.Security.Cryptography;

import Standard.Text;
import Standard.Bits;

// ================================================================== hashing

/// A hash function, one block at a time.
///
/// This is .NET's `IncrementalHash` rather than its `HashAlgorithm`: append
/// what there is, and ask for the digest when there is no more. `ComputeHash`
/// on the base class is the one-shot for the common case, and the static
/// `HashData` on each algorithm is the same thing without an object.
///
/// Implement it to add an algorithm; `Hmac` takes any implementation, so a
/// hash written outside this module gets a MAC for free.
///
/// @see Hmac
public interface IHashAlgorithm
{
    /// What the algorithm is called, as a standard names it -- `SHA-256`,
    /// `HMAC-SHA-256`. This is the spelling that goes in a protocol field,
    /// so it keeps the hyphens and the capitals.
    String Name { get; }

    /// How many bytes the digest is.
    nuint HashSizeInBytes { get; }

    /// How many bytes the compression function eats at a time. HMAC needs it,
    /// which is why it is on the interface rather than inside.
    nuint BlockSizeInBytes { get; }

    /// Adds bytes to what is being hashed.
    void AppendData(byte[:] data);

    /// The digest of everything appended since the last reset, and a reset.
    /// Calling it twice in a row gives the digest of the empty input the
    /// second time, which is what the reset means.
    byte[] GetHashAndReset();

    /// Throws away what has been appended and starts again.
    void Reset();
}
