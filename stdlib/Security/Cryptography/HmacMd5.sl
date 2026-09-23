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

/// HMAC-MD5, as .NET spells `HMACMD5`. Here for the protocols that specify it
/// -- and unlike a bare MD5 digest it is not broken by the collision attacks,
/// because a collision an attacker cannot compute without the key is no use.
public static class HmacMd5
{
    /// A keyed hash to append to.
    public static Hmac Create(byte[:] key) => new Hmac(new Md5(), key);

    /// The MAC of `data` under `key`.
    public static byte[] HashData(byte[:] key, byte[:] data) =>
        Create(key).ComputeHash(data);
}
