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

/// One PEM block that `PemEncoding.Find` found: its label, its data decoded,
/// and where each part is in the text it was found in.
///
/// Every `Range` counts bytes of the text's UTF-8, which for the block itself
/// is ASCII and so counts characters too.
public struct PemFields
{
    private String _label;
    private byte[] _data;
    private Range _location;
    private Range _labelLocation;
    private Range _base64Location;

    PemFields(String label, byte[] data, Range location, Range labelLocation, Range base64Location)
    {
        _label = label;
        _data = data;
        _location = location;
        _labelLocation = labelLocation;
        _base64Location = base64Location;
    }

    /// What follows `BEGIN `: `CERTIFICATE`, `PRIVATE KEY`.
    public String Label => _label;

    /// The base64 between the boundaries, decoded.
    public byte[] Data => _data;

    /// The whole block, from the first `-` of `-----BEGIN` to the last of
    /// `-----END ...-----`. Its end is where to look for the next one.
    public Range Location => _location;

    /// Where the label is, in the `BEGIN` boundary.
    public Range LabelLocation => _labelLocation;

    /// Where the base64 is, from its first character to its last, whitespace
    /// inside it included and around it not.
    public Range Base64Location => _base64Location;
}
