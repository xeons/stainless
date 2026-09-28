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

// ================================================== the group of an EC curve

/// A point as `(X : Y : Z)`, each coordinate in Montgomery form. The affine
/// point is `(X/Z, Y/Z)`, and `Z = 0` is the point at infinity.
struct EcProjectivePoint
{
    public EcElement X;
    public EcElement Y;
    public EcElement Z;
}

/// A curve `y^2 = x^3 - 3x + b` of prime order over a prime field: P-256 or
/// P-384, which are the curves FIPS 186-5 and TLS name.
struct EcDomain
{
    /// The prime `p` the coordinates are taken modulo.
    public EcModulus Field;

    /// The group order `n` the scalars are taken modulo.
    public EcModulus Order;

    /// `b`, in Montgomery form modulo `p`.
    public EcElement B;

    /// The base point, with `Z` one.
    public EcProjectivePoint Generator;

    /// How many bytes a coordinate or a scalar takes: 32 or 48.
    public nuint Size;
}

/// P-256, from FIPS 186-5 and SEC 2 §2.4.2.
EcDomain CreateP256Domain() => CreateEcDomain(
    "FFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF",
    "FFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551",
    "5AC635D8AA3A93E7B3EBBD55769886BC651D06B0CC53B0F63BCE3C3E27D2604B",
    "6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296",
    "4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5");

/// P-384, from FIPS 186-5 and SEC 2 §2.5.1.
EcDomain CreateP384Domain() => CreateEcDomain(
    "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE" +
    "FFFFFFFF0000000000000000FFFFFFFF",
    "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFC7634D81F4372DDF" +
    "581A0DB248B0A77AECEC196ACCC52973",
    "B3312FA7E23EE7E4988E056BE3F82D19181D9C6EFE8141120314088F5013875A" +
    "C656398D8A2ED19D2A85C8EDD3EC2AEF",
    "AA87CA22BE8B05378EB1C71EF320AD746E1D3B628BA79B9859F741E082542A38" +
    "5502F25DBF55296C3A545E3872760AB7",
    "3617DE4A96262C6F5D9E98BF9292DC29F8F41DBD289A147CE9DA3113B5F0B8C0" +
    "0A60B1CE1D7E819D7A431D7C90EA0E5F");

EcDomain CreateEcDomain(String prime, String order, String b, String generatorX,
                        String generatorY)
{
    EcDomain domain;
    domain.Field = CreateEcModulus(prime);
    domain.Order = CreateEcModulus(order);
    domain.Size = domain.Field.Count * 8u;
    domain.B = ConvertEcElementToMontgomery(ParseEcElementHexadecimal(b), ref domain.Field);
    domain.Generator = CreateEcPointFromAffine(ParseEcElementHexadecimal(generatorX),
                                               ParseEcElementHexadecimal(generatorY),
                                               ref domain);
    return domain;
}

/// The point at infinity, `(0 : 1 : 0)`.
EcProjectivePoint CreateEcIdentity(ref EcDomain domain)
{
    EcProjectivePoint identity;
    identity.Y = domain.Field.One;
    return identity;
}

/// The point `(x, y)`, given as plain numbers below `p`.
EcProjectivePoint CreateEcPointFromAffine(EcElement x, EcElement y, ref EcDomain domain)
{
    EcProjectivePoint point;
    point.X = ConvertEcElementToMontgomery(x, ref domain.Field);
    point.Y = ConvertEcElementToMontgomery(y, ref domain.Field);
    point.Z = domain.Field.One;
    return point;
}

// ---------------------------------------------------------------- the group law

/// `left + right`, by algorithm 4 of Renes, Costello and Batina, "Complete
/// addition formulas for prime order elliptic curves" (2016), for `a = -3`.
///
/// The formula is complete: it is right for every pair of points, doubling
/// and the point at infinity included. So there is no case to branch on, and
/// nothing about the points decides what runs.
EcProjectivePoint AddEcPoints(EcProjectivePoint left, EcProjectivePoint right,
                              ref EcDomain domain)
{
    EcElement t0 = MultiplyEcElements(left.X, right.X, ref domain.Field);
    EcElement t1 = MultiplyEcElements(left.Y, right.Y, ref domain.Field);
    EcElement t2 = MultiplyEcElements(left.Z, right.Z, ref domain.Field);
    EcElement t3 = AddEcElements(left.X, left.Y, ref domain.Field);
    EcElement t4 = AddEcElements(right.X, right.Y, ref domain.Field);
    t3 = MultiplyEcElements(t3, t4, ref domain.Field);
    t4 = AddEcElements(t0, t1, ref domain.Field);
    t3 = SubtractEcElements(t3, t4, ref domain.Field);
    t4 = AddEcElements(left.Y, left.Z, ref domain.Field);
    EcElement x3 = AddEcElements(right.Y, right.Z, ref domain.Field);
    t4 = MultiplyEcElements(t4, x3, ref domain.Field);
    x3 = AddEcElements(t1, t2, ref domain.Field);
    t4 = SubtractEcElements(t4, x3, ref domain.Field);
    x3 = AddEcElements(left.X, left.Z, ref domain.Field);
    EcElement y3 = AddEcElements(right.X, right.Z, ref domain.Field);
    x3 = MultiplyEcElements(x3, y3, ref domain.Field);
    y3 = AddEcElements(t0, t2, ref domain.Field);
    y3 = SubtractEcElements(x3, y3, ref domain.Field);
    EcElement z3 = MultiplyEcElements(domain.B, t2, ref domain.Field);
    x3 = SubtractEcElements(y3, z3, ref domain.Field);
    z3 = AddEcElements(x3, x3, ref domain.Field);
    x3 = AddEcElements(x3, z3, ref domain.Field);
    z3 = SubtractEcElements(t1, x3, ref domain.Field);
    x3 = AddEcElements(t1, x3, ref domain.Field);
    y3 = MultiplyEcElements(domain.B, y3, ref domain.Field);
    t1 = AddEcElements(t2, t2, ref domain.Field);
    t2 = AddEcElements(t1, t2, ref domain.Field);
    y3 = SubtractEcElements(y3, t2, ref domain.Field);
    y3 = SubtractEcElements(y3, t0, ref domain.Field);
    t1 = AddEcElements(y3, y3, ref domain.Field);
    y3 = AddEcElements(t1, y3, ref domain.Field);
    t1 = AddEcElements(t0, t0, ref domain.Field);
    t0 = AddEcElements(t1, t0, ref domain.Field);
    t0 = SubtractEcElements(t0, t2, ref domain.Field);
    t1 = MultiplyEcElements(t4, y3, ref domain.Field);
    t2 = MultiplyEcElements(t0, y3, ref domain.Field);
    y3 = MultiplyEcElements(x3, z3, ref domain.Field);
    y3 = AddEcElements(y3, t2, ref domain.Field);
    x3 = MultiplyEcElements(t3, x3, ref domain.Field);
    x3 = SubtractEcElements(x3, t1, ref domain.Field);
    z3 = MultiplyEcElements(t4, z3, ref domain.Field);
    t1 = MultiplyEcElements(t3, t0, ref domain.Field);
    z3 = AddEcElements(z3, t1, ref domain.Field);

    EcProjectivePoint sum;
    sum.X = x3;
    sum.Y = y3;
    sum.Z = z3;
    return sum;
}

/// `point + point`, by algorithm 6 of the same paper. Complete as addition
/// is, and cheaper.
EcProjectivePoint DoubleEcPoint(EcProjectivePoint point, ref EcDomain domain)
{
    EcElement t0 = MultiplyEcElements(point.X, point.X, ref domain.Field);
    EcElement t1 = MultiplyEcElements(point.Y, point.Y, ref domain.Field);
    EcElement t2 = MultiplyEcElements(point.Z, point.Z, ref domain.Field);
    EcElement t3 = MultiplyEcElements(point.X, point.Y, ref domain.Field);
    t3 = AddEcElements(t3, t3, ref domain.Field);
    EcElement z3 = MultiplyEcElements(point.X, point.Z, ref domain.Field);
    z3 = AddEcElements(z3, z3, ref domain.Field);
    EcElement y3 = MultiplyEcElements(domain.B, t2, ref domain.Field);
    y3 = SubtractEcElements(y3, z3, ref domain.Field);
    EcElement x3 = AddEcElements(y3, y3, ref domain.Field);
    y3 = AddEcElements(x3, y3, ref domain.Field);
    x3 = SubtractEcElements(t1, y3, ref domain.Field);
    y3 = AddEcElements(t1, y3, ref domain.Field);
    y3 = MultiplyEcElements(x3, y3, ref domain.Field);
    x3 = MultiplyEcElements(x3, t3, ref domain.Field);
    t3 = AddEcElements(t2, t2, ref domain.Field);
    t2 = AddEcElements(t2, t3, ref domain.Field);
    z3 = MultiplyEcElements(domain.B, z3, ref domain.Field);
    z3 = SubtractEcElements(z3, t2, ref domain.Field);
    z3 = SubtractEcElements(z3, t0, ref domain.Field);
    t3 = AddEcElements(z3, z3, ref domain.Field);
    z3 = AddEcElements(z3, t3, ref domain.Field);
    t3 = AddEcElements(t0, t0, ref domain.Field);
    t0 = AddEcElements(t3, t0, ref domain.Field);
    t0 = SubtractEcElements(t0, t2, ref domain.Field);
    t0 = MultiplyEcElements(t0, z3, ref domain.Field);
    y3 = AddEcElements(y3, t0, ref domain.Field);
    t0 = MultiplyEcElements(point.Y, point.Z, ref domain.Field);
    t0 = AddEcElements(t0, t0, ref domain.Field);
    z3 = MultiplyEcElements(t0, z3, ref domain.Field);
    x3 = SubtractEcElements(x3, z3, ref domain.Field);
    z3 = MultiplyEcElements(t0, t1, ref domain.Field);
    z3 = AddEcElements(z3, z3, ref domain.Field);
    z3 = AddEcElements(z3, z3, ref domain.Field);

    EcProjectivePoint doubled;
    doubled.X = x3;
    doubled.Y = y3;
    doubled.Z = z3;
    return doubled;
}

// ------------------------------------------------------- scalar multiplication

/// `scalar * point`, in time that depends on neither.
///
/// A fixed window of four bits: sixteen multiples of the point are made
/// first, and each window's multiple is taken by reading all sixteen and
/// keeping one with a mask, so no address depends on the scalar. Every window
/// adds, a zero digit included, and the addition is complete, so the same
/// operations run for every scalar.
///
/// @param point   the point, which may be secret
/// @param scalar  a plain number below the order `n`
/// @param domain  the curve
EcProjectivePoint MultiplyEcPoint(EcProjectivePoint point, EcElement scalar, ref EcDomain domain)
{
    EcProjectivePoint[16] table;
    table[0u] = CreateEcIdentity(ref domain);
    table[1u] = point;
    for (nuint i = 2u; i < 16u; i++)
    {
        if ((i & 1u) == 0u)
        {
            table[i] = DoubleEcPoint(table[i / 2u], ref domain);
        }
        else
        {
            table[i] = AddEcPoints(table[i - 1u], point, ref domain);
        }
    }

    EcProjectivePoint result = table[0u];
    nuint windows = domain.Order.Count * 16u;
    for (nuint window = windows; window > 0u; window--)
    {
        nuint at = window - 1u;
        if (window != windows)
        {
            for (nuint i = 0u; i < 4u; i++)
                result = DoubleEcPoint(result, ref domain);
        }

        ulong digit = (scalar.Limbs[at / 16u] >> (uint)(4u * (at % 16u))) & 15u;
        EcProjectivePoint chosen;
        for (nuint i = 0u; i < 16u; i++)
        {
            ulong mask = ComputeEcZeroMask((ulong)i ^ digit);
            for (nuint limb = 0u; limb < 6u; limb++)
            {
                chosen.X.Limbs[limb] |= table[i].X.Limbs[limb] & mask;
                chosen.Y.Limbs[limb] |= table[i].Y.Limbs[limb] & mask;
                chosen.Z.Limbs[limb] |= table[i].Z.Limbs[limb] & mask;
            }
        }

        result = AddEcPoints(result, chosen, ref domain);
    }
    return result;
}

/// `first * G + second * point`, for verifying a signature.
///
/// **Variable time.** The digits choose what is added and from where, which
/// is safe only because every input to a verification is public.
EcProjectivePoint MultiplyEcPointsVariableTime(EcElement first, EcElement second,
                                               EcProjectivePoint point, ref EcDomain domain)
{
    EcProjectivePoint[16] generatorTable;
    EcProjectivePoint[16] pointTable;
    generatorTable[1u] = domain.Generator;
    pointTable[1u] = point;
    for (nuint i = 2u; i < 16u; i++)
    {
        if ((i & 1u) == 0u)
        {
            generatorTable[i] = DoubleEcPoint(generatorTable[i / 2u], ref domain);
            pointTable[i] = DoubleEcPoint(pointTable[i / 2u], ref domain);
        }
        else
        {
            generatorTable[i] = AddEcPoints(generatorTable[i - 1u], domain.Generator, ref domain);
            pointTable[i] = AddEcPoints(pointTable[i - 1u], point, ref domain);
        }
    }

    EcProjectivePoint result = CreateEcIdentity(ref domain);
    bool started = false;
    for (nuint window = domain.Order.Count * 16u; window > 0u; window--)
    {
        nuint at = window - 1u;
        if (started)
        {
            for (nuint i = 0u; i < 4u; i++)
                result = DoubleEcPoint(result, ref domain);
        }

        nuint shift = 4u * (at % 16u);
        nuint firstDigit = (nuint)((first.Limbs[at / 16u] >> (uint)shift) & 15u);
        nuint secondDigit = (nuint)((second.Limbs[at / 16u] >> (uint)shift) & 15u);
        if (firstDigit != 0u)
        {
            result = AddEcPoints(result, generatorTable[firstDigit], ref domain);
            started = true;
        }
        if (secondDigit != 0u)
        {
            result = AddEcPoints(result, pointTable[secondDigit], ref domain);
            started = true;
        }
    }
    return result;
}

// ------------------------------------------------------------ affine points

/// The affine coordinates of `point` as plain numbers, or false for the point
/// at infinity. Constant time in the coordinates; only whether the point is
/// infinity shows.
bool ConvertEcPointToAffine(EcProjectivePoint point, ref EcDomain domain, out EcElement x,
                            out EcElement y)
{
    EcElement inverse = InvertEcElement(point.Z, ref domain.Field);
    x = ConvertEcElementFromMontgomery(MultiplyEcElements(point.X, inverse, ref domain.Field),
                              ref domain.Field);
    y = ConvertEcElementFromMontgomery(MultiplyEcElements(point.Y, inverse, ref domain.Field),
                              ref domain.Field);
    return ComputeEcElementZeroMask(point.Z) == 0u;
}

/// `x^3 - 3x + b`, the right-hand side of the curve's equation, in Montgomery
/// form from `x` in Montgomery form.
EcElement ComputeEcCurveRightSide(EcElement x, ref EcDomain domain)
{
    EcElement cube = MultiplyEcElements(MultiplyEcElements(x, x, ref domain.Field), x,
                                        ref domain.Field);
    EcElement threeX = AddEcElements(AddEcElements(x, x, ref domain.Field), x, ref domain.Field);
    return AddEcElements(SubtractEcElements(cube, threeX, ref domain.Field), domain.B,
                      ref domain.Field);
}

/// Whether `(x, y)`, plain numbers, is a point on the curve: both below `p`
/// and the equation holding. Public keys only, so it may answer early.
bool IsOnEcCurveVariableTime(EcElement x, EcElement y, ref EcDomain domain)
{
    if (ComputeEcElementBelow(x, domain.Field.Value) == 0u ||
        ComputeEcElementBelow(y, domain.Field.Value) == 0u)
        return false;

    EcElement montgomeryX = ConvertEcElementToMontgomery(x, ref domain.Field);
    EcElement montgomeryY = ConvertEcElementToMontgomery(y, ref domain.Field);
    EcElement left = MultiplyEcElements(montgomeryY, montgomeryY, ref domain.Field);
    EcElement right = ComputeEcCurveRightSide(montgomeryX, ref domain);
    return ComputeEcElementEqualMask(left, right) != 0u;
}

/// A point decoded from its SEC 1 §2.3.4 form — `04 X Y` or `02 X` / `03 X` —
/// and checked: on the curve, and not the point at infinity, whose one-byte
/// encoding is refused. Public keys only, so variable time.
Result<bool, CryptoError> DecodeEcPointVariableTime(ReadOnlySpan<byte> encoded,
                                                    ref EcDomain domain, out EcElement x,
                                                    out EcElement y)
{
    EcElement none;
    x = none;
    y = none;
    nuint size = domain.Size;
    if (encoded.Length == 0u)
        return Fail(CryptoError.InvalidPoint);

    byte form = encoded[0u];
    if (form == 0x04 && encoded.Length == 1u + 2u * size)
    {
        x = ReadEcElement(encoded[1u:1u + size]);
        y = ReadEcElement(encoded[1u + size:]);
    }
    else if ((form == 0x02 || form == 0x03) && encoded.Length == 1u + size)
    {
        x = ReadEcElement(encoded[1u:]);
        if (ComputeEcElementBelow(x, domain.Field.Value) == 0u)
            return Fail(CryptoError.InvalidPoint);

        // p = 3 mod 4 for both curves, so a square root is a power.
        EcElement montgomeryX = ConvertEcElementToMontgomery(x, ref domain.Field);
        EcElement square = ComputeEcCurveRightSide(montgomeryX, ref domain);
        EcElement one;
        one.Limbs[0u] = 1u;
        EcElement exponent = AddEcElementsUnreduced(domain.Field.Value, one, domain.Field.Count);
        exponent = ShiftEcElementRight(exponent, 2u);
        EcElement root = RaiseEcElementToPublicPower(square, exponent, ref domain.Field);
        if (ComputeEcElementEqualMask(MultiplyEcElements(root, root, ref domain.Field),
                                      square) == 0u)
            return Fail(CryptoError.InvalidPoint);

        y = ConvertEcElementFromMontgomery(root, ref domain.Field);
        if ((y.Limbs[0u] & 1u) != (ulong)(form & 1))
        {
            EcElement zero;
            y = SubtractEcElements(zero, y, ref domain.Field);
        }
        if ((y.Limbs[0u] & 1u) != (ulong)(form & 1))
            return Fail(CryptoError.InvalidPoint);
    }
    else
    {
        return Fail(CryptoError.InvalidPoint);
    }

    if (!IsOnEcCurveVariableTime(x, y, ref domain))
        return Fail(CryptoError.InvalidPoint);
    return Ok(true);
}

/// `(x, y)` as `04 X Y`, SEC 1's uncompressed form.
byte[] EncodeEcPoint(EcElement x, EcElement y, nuint size)
{
    byte[] encoded = new byte[1u + 2u * size];
    encoded[0u] = 0x04;
    WriteEcElement(x, size, encoded, 1u);
    WriteEcElement(y, size, encoded, 1u + size);
    return encoded;
}

/// `left + right` with no reduction; the caller MUST know it does not carry
/// out of `count` limbs.
EcElement AddEcElementsUnreduced(EcElement left, EcElement right, nuint count)
{
    EcElement sum;
    ulong carry = 0u;
    for (nuint i = 0u; i < count; i++)
    {
        ulong a = left.Limbs[i];
        ulong b = right.Limbs[i];
        ulong total = a + b + carry;
        carry = ComputeEcCarry(a, b, total);
        sum.Limbs[i] = total;
    }
    return sum;
}

/// `value >> bits`, for `bits` below 64.
EcElement ShiftEcElementRight(EcElement value, nuint bits)
{
    EcElement shifted;
    for (nuint i = 0u; i < 6u; i++)
    {
        ulong high = i + 1u < 6u ? value.Limbs[i + 1u] : 0u;
        shifted.Limbs[i] = (value.Limbs[i] >> (uint)bits) | (high << (uint)(64u - bits));
    }
    return shifted;
}
