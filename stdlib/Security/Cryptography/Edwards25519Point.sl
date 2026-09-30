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

import Standard.Bits;

// ============================================================ edwards25519

/// A point on edwards25519, −x² + y² = 1 + d x² y², in extended coordinates:
/// (X : Y : Z : T) with x = X/Z, y = Y/Z and xy = T/Z.
///
/// The formulas are RFC 8032 §5.1.4's. Addition is complete on this curve —
/// it is right for any two points, doubling and the identity included — so
/// nothing here tests for a special case, and nothing branches on a
/// coordinate.
///
/// **Constant time, except where the name says otherwise.** `MultiplyScalar`
/// is for a secret scalar and reads its table by mask.
/// `MultiplyDoubleVariableTime` skips a zero digit and indexes by one, and
/// MUST only be given public scalars; verification is where it is used.
struct Edwards25519Point
{
    private Field25519 _x;
    private Field25519 _y;
    private Field25519 _z;
    private Field25519 _t;

    Edwards25519Point(Field25519 x, Field25519 y, Field25519 z, Field25519 t)
    {
        _x = x;
        _y = y;
        _z = z;
        _t = t;
    }

    static Edwards25519Point Identity =>
        new Edwards25519Point(Field25519.Zero, Field25519.One, Field25519.One, Field25519.Zero);

    /// B, the point whose y is 4/5 and whose x is even.
    static Edwards25519Point Base =>
        new Edwards25519Point(new Field25519(0x62D608F25D51Au, 0x412A4B4F6592Au,
                                             0x75B7171A4B31Du, 0x1FF60527118FEu,
                                             0x216936D3CD6E5u),
                              new Field25519(0x6666666666658u, 0x4CCCCCCCCCCCCu,
                                             0x1999999999999u, 0x3333333333333u,
                                             0x6666666666666u),
                              Field25519.One,
                              new Field25519(0x68AB3A5B7DDA3u, 0x00EEA2A5EADBBu,
                                             0x2AF8DF483C27Eu, 0x332B375274732u,
                                             0x67875F0FD78B7u));

    public static Edwards25519Point operator +(Edwards25519Point left, Edwards25519Point right)
    {
        Field25519 a = (left._y - left._x) * (right._y - right._x);
        Field25519 b = (left._y + left._x) * (right._y + right._x);
        Field25519 c = left._t * Field25519.EdwardsDoubleD * right._t;
        Field25519 d = (left._z + left._z) * right._z;
        Field25519 e = b - a;
        Field25519 f = d - c;
        Field25519 g = d + c;
        Field25519 h = b + a;
        return new Edwards25519Point(e * f, g * h, f * g, e * h);
    }

    public static Edwards25519Point operator -(Edwards25519Point value) =>
        new Edwards25519Point(-value._x, value._y, value._z, -value._t);

    /// Whether this is the identity: X is zero and Y equals Z. Variable time,
    /// for public points.
    bool IsIdentity => _x.IsZero && (_y - _z).IsZero;

    /// Whether eight times the point is the identity, which on a curve of
    /// cofactor 8 is what small order means. Variable time, for public points.
    bool IsOfSmallOrder() => Double().Double().Double().IsIdentity;

    /// The point added to itself, in four squarings and four products.
    Edwards25519Point Double()
    {
        Field25519 a = _x.Square();
        Field25519 b = _y.Square();
        Field25519 zSquared = _z.Square();
        Field25519 c = zSquared + zSquared;
        Field25519 h = a + b;
        Field25519 e = h - (_x + _y).Square();
        Field25519 g = a - b;
        Field25519 f = c + g;
        return new Edwards25519Point(e * f, g * h, f * g, e * h);
    }

    /// `whenZero` when `choice` is 0 and `whenOne` when it is 1. `choice`
    /// MUST be 0 or 1.
    static Edwards25519Point ConditionalSelect(Edwards25519Point whenZero,
                                               Edwards25519Point whenOne, ulong choice) =>
        new Edwards25519Point(Field25519.ConditionalSelect(whenZero._x, whenOne._x, choice),
                              Field25519.ConditionalSelect(whenZero._y, whenOne._y, choice),
                              Field25519.ConditionalSelect(whenZero._z, whenOne._z, choice),
                              Field25519.ConditionalSelect(whenZero._t, whenOne._t, choice));

    /// `scalar` times `point`, for a secret 32-byte little-endian scalar.
    ///
    /// A fixed window of four bits: sixteen multiples of the point, then 64
    /// rounds of four doublings and one addition. The multiple each round
    /// adds is found by reading every entry and keeping one by mask, so
    /// neither the time nor the memory touched depends on the scalar.
    static Edwards25519Point MultiplyScalar(Edwards25519Point point, ReadOnlySpan<byte> scalar)
    {
        Edwards25519Point[16] table;
        table[0u] = Identity;
        table[1u] = point;
        for (nuint i = 2u; i < 16u; i++)
            table[i] = table[i - 1u] + point;

        Edwards25519Point result = Identity;
        for (nuint window = 64u; window > 0u; window--)
        {
            result = result.Double().Double().Double().Double();

            ulong digit = ReadScalarDigit(scalar, window - 1u);
            Edwards25519Point chosen = Identity;
            for (nuint i = 0u; i < 16u; i++)
                chosen = ConditionalSelect(chosen, table[i], (((ulong)i ^ digit) - 1u) >> 63);

            result = result + chosen;
        }

        return result;
    }

    /// `left` times `leftPoint` plus `right` times B, for public scalars.
    ///
    /// Straus's method: one run of doublings shared between the two
    /// products, with each addition skipped when its digit is zero. That is
    /// the variable time, and why a secret MUST NOT come here.
    static Edwards25519Point MultiplyDoubleVariableTime(ReadOnlySpan<byte> left,
                                                        Edwards25519Point leftPoint,
                                                        ReadOnlySpan<byte> right)
    {
        Edwards25519Point basePoint = Base;
        Edwards25519Point[16] leftTable;
        Edwards25519Point[16] rightTable;
        leftTable[0u] = Identity;
        leftTable[1u] = leftPoint;
        rightTable[0u] = Identity;
        rightTable[1u] = basePoint;
        for (nuint i = 2u; i < 16u; i++)
        {
            leftTable[i] = leftTable[i - 1u] + leftPoint;
            rightTable[i] = rightTable[i - 1u] + basePoint;
        }

        Edwards25519Point result = Identity;
        for (nuint window = 64u; window > 0u; window--)
        {
            result = result.Double().Double().Double().Double();

            ulong leftDigit = ReadScalarDigit(left, window - 1u);
            if (leftDigit != 0u)
                result = result + leftTable[(nuint)leftDigit];

            ulong rightDigit = ReadScalarDigit(right, window - 1u);
            if (rightDigit != 0u)
                result = result + rightTable[(nuint)rightDigit];
        }

        return result;
    }

    /// The point's 32-byte encoding: y, little-endian, with the sign of x in
    /// the top bit.
    byte[] Encode()
    {
        Field25519 inverse = _z.Invert();
        Field25519 x = _x * inverse;
        byte[] bytes = (_y * inverse).ToBytes();
        bytes[31u] = (byte)((ulong)bytes[31u] | (x.SignBit << 7));
        return bytes;
    }

    /// The point `bytes` encodes into `point`, and whether it encodes one.
    ///
    /// **Strict.** A y at or above p is refused rather than reduced, so each
    /// point has one encoding; so is a y with no x on the curve, and an x of
    /// zero marked negative. RFC 8032 §5.1.3 asks for all three.
    static bool TryDecode(ReadOnlySpan<byte> bytes, out Edwards25519Point point)
    {
        point = Identity;
        Field25519 y = Field25519.FromBytes(bytes, 0u);

        byte[] canonical = y.ToBytes();
        for (nuint i = 0u; i < 31u; i++)
        {
            if (canonical[i] != bytes[i])
                return false;
        }
        if ((uint)canonical[31u] != ((uint)bytes[31u] & 0x7Fu))
            return false;

        Field25519 ySquared = y.Square();
        Field25519 numerator = ySquared - Field25519.One;
        Field25519 denominator = Field25519.EdwardsD * ySquared + Field25519.One;
        if (!Field25519.TrySquareRootOfRatio(numerator, denominator, out Field25519 x))
            return false;

        ulong sign = (ulong)bytes[31u] >> 7;
        if (x.IsZero && sign == 1u)
            return false;

        x = Field25519.ConditionalSelect(x, -x, sign);
        point = new Edwards25519Point(x, y, Field25519.One, x * y);
        return true;
    }

    /// Four bits of a 32-byte little-endian scalar: the `index`th nibble,
    /// counting from the least significant.
    static ulong ReadScalarDigit(ReadOnlySpan<byte> scalar, nuint index) =>
        ((ulong)scalar[index / 2u] >> (int)(4u * (index % 2u))) & 15u;
}
