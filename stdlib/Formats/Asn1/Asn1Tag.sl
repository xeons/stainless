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

module Standard.Formats.Asn1;

/// The identifier of an encoded value: a class, a number, and whether the
/// contents are themselves encoded values.
///
/// ```csharp
/// var version = new Asn1Tag(TagClass.ContextSpecific, 0, true);   // [0] EXPLICIT
/// if ((try reader.PeekTag()).HasSameClassAndValue(version)) { ... }
/// ```
///
/// A value, as .NET's is. `==` compares all three parts; a reader matches on
/// class and number and checks the constructed bit against the type, which is
/// what `HasSameClassAndValue` asks.
public struct Asn1Tag
{
    private TagClass _tagClass;
    private int _tagValue;
    private bool _isConstructed;

    /// A tag in any class.
    ///
    /// @param tagClass       which namespace `tagValue` is in
    /// @param tagValue       the number, which MUST NOT be negative; aborts when it is
    /// @param isConstructed  whether the contents are encoded values
    public Asn1Tag(TagClass tagClass, int tagValue, bool isConstructed = false)
    {
        if (tagValue < 0)
            sl_fail("Asn1Tag: a tag number MUST NOT be negative");
        _tagClass = tagClass;
        _tagValue = tagValue;
        _isConstructed = isConstructed;
    }

    /// A tag in the `Universal` class.
    ///
    /// @param universalTagNumber  the type it names
    /// @param isConstructed       whether the contents are encoded values
    public Asn1Tag(UniversalTagNumber universalTagNumber, bool isConstructed = false)
    {
        _tagClass = TagClass.Universal;
        _tagValue = (int)universalTagNumber;
        _isConstructed = isConstructed;
    }

    /// Which namespace the number is in.
    public TagClass TagClass => _tagClass;

    /// The number within its class.
    public int TagValue => _tagValue;

    /// Whether the contents are a series of encoded values.
    public bool IsConstructed => _isConstructed;

    /// `BOOLEAN`.
    public static Asn1Tag Boolean => new Asn1Tag(UniversalTagNumber.Boolean);

    /// `INTEGER`.
    public static Asn1Tag Integer => new Asn1Tag(UniversalTagNumber.Integer);

    /// `BIT STRING`, in the primitive form DER requires.
    public static Asn1Tag PrimitiveBitString => new Asn1Tag(UniversalTagNumber.BitString);

    /// `BIT STRING`, in the constructed form only BER allows.
    public static Asn1Tag ConstructedBitString => new Asn1Tag(UniversalTagNumber.BitString, true);

    /// `OCTET STRING`, in the primitive form DER requires.
    public static Asn1Tag PrimitiveOctetString => new Asn1Tag(UniversalTagNumber.OctetString);

    /// `OCTET STRING`, in the constructed form only BER allows.
    public static Asn1Tag ConstructedOctetString =>
        new Asn1Tag(UniversalTagNumber.OctetString, true);

    /// `NULL`.
    public static Asn1Tag Null => new Asn1Tag(UniversalTagNumber.Null);

    /// `OBJECT IDENTIFIER`.
    public static Asn1Tag ObjectIdentifier => new Asn1Tag(UniversalTagNumber.ObjectIdentifier);

    /// `ENUMERATED`.
    public static Asn1Tag Enumerated => new Asn1Tag(UniversalTagNumber.Enumerated);

    /// `SEQUENCE` and `SEQUENCE OF`, which are always constructed.
    public static Asn1Tag Sequence => new Asn1Tag(UniversalTagNumber.Sequence, true);

    /// `SET` and `SET OF`, which are always constructed.
    public static Asn1Tag SetOf => new Asn1Tag(UniversalTagNumber.Set, true);

    /// `UTCTime`.
    public static Asn1Tag UtcTime => new Asn1Tag(UniversalTagNumber.UtcTime);

    /// `GeneralizedTime`.
    public static Asn1Tag GeneralizedTime => new Asn1Tag(UniversalTagNumber.GeneralizedTime);

    /// This tag with the constructed bit set.
    public Asn1Tag AsConstructed() => new Asn1Tag(_tagClass, _tagValue, true);

    /// This tag with the constructed bit clear.
    public Asn1Tag AsPrimitive() => new Asn1Tag(_tagClass, _tagValue, false);

    /// Whether `other` has this class and number, whatever its constructed bit.
    public bool HasSameClassAndValue(Asn1Tag other) =>
        _tagClass == other._tagClass && _tagValue == other._tagValue;

    /// Whether all three parts are the same.
    public bool Equals(Asn1Tag other) =>
        HasSameClassAndValue(other) && _isConstructed == other._isConstructed;

    /// The identifier octets: one when the number is under 31, and a number
    /// in base 128 after a marker otherwise.
    public nuint EncodedLength
    {
        get
        {
            if (_tagValue < 31)
                return 1u;

            nuint length = 1u;
            uint rest = (uint)_tagValue;
            while (rest > 0u)
            {
                length++;
                rest >>= 7;
            }
            return length;
        }
    }

    /// The tag written for a person: `Universal 16 constructed`, `[0]`.
    public String ToString()
    {
        String number = FromInteger((long)_tagValue);
        String shape = _isConstructed ? " constructed" : "";
        switch (_tagClass)
        {
            case TagClass.Universal:
                return $"Universal {number}{shape}";
            case TagClass.Application:
                return $"Application {number}{shape}";
            case TagClass.ContextSpecific:
                return $"[{number}]{shape}";
            default:
                return $"Private {number}{shape}";
        }
    }

    public static bool operator ==(Asn1Tag left, Asn1Tag right) => left.Equals(right);

    public static bool operator !=(Asn1Tag left, Asn1Tag right) => !left.Equals(right);
}
