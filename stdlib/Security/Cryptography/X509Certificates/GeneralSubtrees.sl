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

module Standard.Security.Cryptography.X509Certificates;

import Standard.Collections;

/// The subtrees of one side of a name constraints extension, as they are read.
internal sealed class GeneralSubtrees
{
    internal List<String> DnsNames;
    internal List<byte[]> IPRanges;
    internal List<X500DistinguishedName> DirectoryNames;
    internal List<String> EmailAddresses;
    internal bool HasUnenforced;

    internal GeneralSubtrees()
    {
        DnsNames = new List<String>();
        IPRanges = new List<byte[]>();
        DirectoryNames = new List<X500DistinguishedName>();
        EmailAddresses = new List<String>();
        HasUnenforced = false;
    }
}
