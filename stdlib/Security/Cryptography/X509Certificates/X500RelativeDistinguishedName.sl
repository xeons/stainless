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

/// One step of a distinguished name: a `SET` of attribute types and values,
/// almost always of one, such as `CN=www.example.com`.
///
/// .NET's `X500RelativeDistinguishedName`, with each type a dotted object
/// identifier. A value that is a character string is its text; any other is
/// `#` and the hexadecimal of its DER, as RFC 4514 writes one.
///
/// @see X500DistinguishedName.EnumerateRelativeDistinguishedNames
public sealed class X500RelativeDistinguishedName
{
    private byte[] _rawData;
    private String[] _types;
    private String[] _values;
    private bool[] _isText;

    internal X500RelativeDistinguishedName(byte[] rawData, String[] types, String[] values,
                                           bool[] isText)
    {
        _rawData = rawData;
        _types = types;
        _values = values;
        _isText = isText;
    }

    /// The `SET`, as DER.
    public byte[] RawData => _rawData;

    /// How many attributes it holds; one or more.
    public nuint Count => _types.Length;

    /// Whether it holds more than one attribute.
    public bool HasMultipleElements => _types.Length > 1u;

    /// The type of attribute `index`: `2.5.4.3` for a common name.
    ///
    /// @param index  below `Count`; aborts otherwise
    public String GetElementType(nuint index) => _types[index];

    /// The value of attribute `index`, as text or as `#` and hexadecimal.
    ///
    /// @param index  below `Count`; aborts otherwise
    public String GetElementValue(nuint index) => _values[index];

    /// Whether the value of attribute `index` is a character string.
    ///
    /// @param index  below `Count`; aborts otherwise
    public bool IsElementText(nuint index) => _isText[index];

    /// The type of the one attribute. A caller MUST ask
    /// `HasMultipleElements` first; this aborts when there are several.
    public String GetSingleElementType()
    {
        if (HasMultipleElements)
            sl_fail("X500RelativeDistinguishedName.GetSingleElementType: there are several");
        return _types[0u];
    }

    /// The text of the one attribute, or `None` when it is not a character
    /// string. Aborts when there are several, as `GetSingleElementType` does.
    public Optional<String> GetSingleElementValue()
    {
        if (HasMultipleElements)
            sl_fail("X500RelativeDistinguishedName.GetSingleElementValue: there are several");
        if (!_isText[0u])
            return None;
        return Some(_values[0u]);
    }
}
