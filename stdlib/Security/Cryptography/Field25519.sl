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

// ============================================================ GF(2^255 - 19)

/// An element of GF(2^255 − 19), the field under both X25519 and Ed25519.
///
/// Five limbs of 51 bits, least significant first. **Every operation answers
/// a weakly reduced value**: each limb below 2^52, and the value itself any
/// representative of its class below 2^255 + 2^18. That bound is what keeps a
/// product's column sums inside 128 bits. Only `Reduce` makes a value
/// canonical, and only encoding needs it to be.
///
/// **Constant time.** Nothing here branches on a limb, indexes by one, or
/// loops a number of times one decides. A choice between two values is a
/// mask, passed through `OpaqueCopy` so the optimiser cannot make a branch of
/// it. The one exception is `TrySquareRootOfRatio`, whose answer says whether
/// a root exists and is only ever asked of public data.
struct Field25519
{
    const ulong LimbMask = 0x7FFFFFFFFFFFFu;

    private ulong _limb0;
    private ulong _limb1;
    private ulong _limb2;
    private ulong _limb3;
    private ulong _limb4;

    Field25519(ulong limb0, ulong limb1, ulong limb2, ulong limb3, ulong limb4)
    {
        _limb0 = limb0;
        _limb1 = limb1;
        _limb2 = limb2;
        _limb3 = limb3;
        _limb4 = limb4;
    }

    // ------------------------------------------------------------ constants

    static Field25519 Zero => new Field25519(0u, 0u, 0u, 0u, 0u);

    static Field25519 One => new Field25519(1u, 0u, 0u, 0u, 0u);

    /// The Edwards curve's d, which is −121665/121666.
    static Field25519 EdwardsD => new Field25519(0x34DCA135978A3u, 0x1A8283B156EBDu,
                                                 0x5E7A26001C029u, 0x739C663A03CBBu,
                                                 0x52036CEE2B6FFu);

    /// 2d, which the addition formula wants rather than d.
    static Field25519 EdwardsDoubleD => new Field25519(0x69B9426B2F159u, 0x35050762ADD7Au,
                                                       0x3CF44C0038052u, 0x6738CC7407977u,
                                                       0x2406D9DC56DFFu);

    /// 2^((p − 1)/4), a square root of −1.
    static Field25519 SquareRootOfMinusOne => new Field25519(0x61B274A0EA0B0u, 0x0D5A5FC8F189Du,
                                                             0x7EF5E9CBD0C60u, 0x78595A6804C9Eu,
                                                             0x2B8324804FC1Du);

    // ------------------------------------------------------------ arithmetic

    public static Field25519 operator +(Field25519 left, Field25519 right) =>
        CarryLimbs(left._limb0 + right._limb0, left._limb1 + right._limb1,
                   left._limb2 + right._limb2, left._limb3 + right._limb3,
                   left._limb4 + right._limb4);

    /// `left − right`, computed as `left + 2p − right` so no limb goes below
    /// zero. That needs every limb of `right` below 2p's, which a weakly
    /// reduced value always is.
    public static Field25519 operator -(Field25519 left, Field25519 right) =>
        CarryLimbs(left._limb0 + 0xFFFFFFFFFFFDAu - right._limb0,
                   left._limb1 + 0xFFFFFFFFFFFFEu - right._limb1,
                   left._limb2 + 0xFFFFFFFFFFFFEu - right._limb2,
                   left._limb3 + 0xFFFFFFFFFFFFEu - right._limb3,
                   left._limb4 + 0xFFFFFFFFFFFFEu - right._limb4);

    public static Field25519 operator -(Field25519 value) => Zero - value;

    /// The product, schoolbook, with a limb that passes 2^255 folded back in
    /// times 19.
    ///
    /// Each 102-to-108-bit partial product is split at bit 51 as it is made:
    /// the low part goes into its own column and the high part into the next.
    /// Five low parts stay below 2^54 and five high parts below 2^58, so both
    /// sums fit a `ulong` and no carry between them is ever needed.
    public static Field25519 operator *(Field25519 left, Field25519 right)
    {
        ulong f0 = left._limb0;
        ulong f1 = left._limb1;
        ulong f2 = left._limb2;
        ulong f3 = left._limb3;
        ulong f4 = left._limb4;

        ulong g0 = right._limb0;
        ulong g1 = right._limb1;
        ulong g2 = right._limb2;
        ulong g3 = right._limb3;
        ulong g4 = right._limb4;

        ulong g1Folded = 19u * g1;
        ulong g2Folded = 19u * g2;
        ulong g3Folded = 19u * g3;
        ulong g4Folded = 19u * g4;

        ulong low0 = 0u;
        ulong high0 = 0u;
        AccumulateProduct(f0, g0, ref low0, ref high0);
        AccumulateProduct(f1, g4Folded, ref low0, ref high0);
        AccumulateProduct(f2, g3Folded, ref low0, ref high0);
        AccumulateProduct(f3, g2Folded, ref low0, ref high0);
        AccumulateProduct(f4, g1Folded, ref low0, ref high0);

        ulong low1 = 0u;
        ulong high1 = 0u;
        AccumulateProduct(f0, g1, ref low1, ref high1);
        AccumulateProduct(f1, g0, ref low1, ref high1);
        AccumulateProduct(f2, g4Folded, ref low1, ref high1);
        AccumulateProduct(f3, g3Folded, ref low1, ref high1);
        AccumulateProduct(f4, g2Folded, ref low1, ref high1);

        ulong low2 = 0u;
        ulong high2 = 0u;
        AccumulateProduct(f0, g2, ref low2, ref high2);
        AccumulateProduct(f1, g1, ref low2, ref high2);
        AccumulateProduct(f2, g0, ref low2, ref high2);
        AccumulateProduct(f3, g4Folded, ref low2, ref high2);
        AccumulateProduct(f4, g3Folded, ref low2, ref high2);

        ulong low3 = 0u;
        ulong high3 = 0u;
        AccumulateProduct(f0, g3, ref low3, ref high3);
        AccumulateProduct(f1, g2, ref low3, ref high3);
        AccumulateProduct(f2, g1, ref low3, ref high3);
        AccumulateProduct(f3, g0, ref low3, ref high3);
        AccumulateProduct(f4, g4Folded, ref low3, ref high3);

        ulong low4 = 0u;
        ulong high4 = 0u;
        AccumulateProduct(f0, g4, ref low4, ref high4);
        AccumulateProduct(f1, g3, ref low4, ref high4);
        AccumulateProduct(f2, g2, ref low4, ref high4);
        AccumulateProduct(f3, g1, ref low4, ref high4);
        AccumulateProduct(f4, g0, ref low4, ref high4);

        return CarryLimbs(low0 + 19u * high4, low1 + high0, low2 + high1, low3 + high2,
                          low4 + high3);
    }

    /// The value times itself: the product with its symmetric terms paired,
    /// fifteen partial products rather than twenty-five.
    public Field25519 Square()
    {
        ulong f0 = _limb0;
        ulong f1 = _limb1;
        ulong f2 = _limb2;
        ulong f3 = _limb3;
        ulong f4 = _limb4;

        ulong f0Doubled = 2u * f0;
        ulong f1Doubled = 2u * f1;
        ulong f2Doubled = 2u * f2;
        ulong f3Doubled = 2u * f3;
        ulong f3Folded = 19u * f3;
        ulong f4Folded = 19u * f4;

        ulong low0 = 0u;
        ulong high0 = 0u;
        AccumulateProduct(f0, f0, ref low0, ref high0);
        AccumulateProduct(f1Doubled, f4Folded, ref low0, ref high0);
        AccumulateProduct(f2Doubled, f3Folded, ref low0, ref high0);

        ulong low1 = 0u;
        ulong high1 = 0u;
        AccumulateProduct(f0Doubled, f1, ref low1, ref high1);
        AccumulateProduct(f2Doubled, f4Folded, ref low1, ref high1);
        AccumulateProduct(f3, f3Folded, ref low1, ref high1);

        ulong low2 = 0u;
        ulong high2 = 0u;
        AccumulateProduct(f0Doubled, f2, ref low2, ref high2);
        AccumulateProduct(f1, f1, ref low2, ref high2);
        AccumulateProduct(f3Doubled, f4Folded, ref low2, ref high2);

        ulong low3 = 0u;
        ulong high3 = 0u;
        AccumulateProduct(f0Doubled, f3, ref low3, ref high3);
        AccumulateProduct(f1Doubled, f2, ref low3, ref high3);
        AccumulateProduct(f4, f4Folded, ref low3, ref high3);

        ulong low4 = 0u;
        ulong high4 = 0u;
        AccumulateProduct(f0Doubled, f4, ref low4, ref high4);
        AccumulateProduct(f1Doubled, f3, ref low4, ref high4);
        AccumulateProduct(f2, f2, ref low4, ref high4);

        return CarryLimbs(low0 + 19u * high4, low1 + high0, low2 + high1, low3 + high2,
                          low4 + high3);
    }

    /// The value squared `count` times over, which is raising it to 2^count.
    public Field25519 SquareRepeatedly(int count)
    {
        Field25519 result = this;
        for (int i = 0; i < count; i++)
            result = result.Square();
        return result;
    }

    /// The value times a small constant, which `factor` MUST be: below 2^20.
    public Field25519 MultiplySmall(ulong factor)
    {
        ulong low0 = 0u;
        ulong high0 = 0u;
        AccumulateProduct(_limb0, factor, ref low0, ref high0);
        ulong low1 = 0u;
        ulong high1 = 0u;
        AccumulateProduct(_limb1, factor, ref low1, ref high1);
        ulong low2 = 0u;
        ulong high2 = 0u;
        AccumulateProduct(_limb2, factor, ref low2, ref high2);
        ulong low3 = 0u;
        ulong high3 = 0u;
        AccumulateProduct(_limb3, factor, ref low3, ref high3);
        ulong low4 = 0u;
        ulong high4 = 0u;
        AccumulateProduct(_limb4, factor, ref low4, ref high4);

        return CarryLimbs(low0 + 19u * high4, low1 + high0, low2 + high1, low3 + high2,
                          low4 + high3);
    }

    /// The inverse, as the value to the power p − 2, by the fixed chain of
    /// 254 squarings and 11 multiplications every implementation uses. Zero
    /// answers zero.
    public Field25519 Invert()
    {
        Field25519 power250 = RaiseToTwoPower250MinusOne(out Field25519 power11);
        return power250.SquareRepeatedly(5) * power11;
    }

    /// The value to the power (p − 5)/8 = 2^252 − 3, which is the exponent a
    /// square root in this field is computed with.
    Field25519 RaiseToTwoPower252MinusThree()
    {
        Field25519 power250 = RaiseToTwoPower250MinusOne(out Field25519 power11);
        return power250.SquareRepeatedly(2) * this;
    }

    /// The value to the power 2^250 − 1, with its eleventh power on the side
    /// for `Invert`.
    Field25519 RaiseToTwoPower250MinusOne(out Field25519 power11)
    {
        Field25519 power2 = Square();
        Field25519 power9 = power2.SquareRepeatedly(2) * this;
        power11 = power9 * power2;
        Field25519 power2To5 = power11.Square() * power9;
        Field25519 power2To10 = power2To5.SquareRepeatedly(5) * power2To5;
        Field25519 power2To20 = power2To10.SquareRepeatedly(10) * power2To10;
        Field25519 power2To40 = power2To20.SquareRepeatedly(20) * power2To20;
        Field25519 power2To50 = power2To40.SquareRepeatedly(10) * power2To10;
        Field25519 power2To100 = power2To50.SquareRepeatedly(50) * power2To50;
        Field25519 power2To200 = power2To100.SquareRepeatedly(100) * power2To100;
        return power2To200.SquareRepeatedly(50) * power2To50;
    }

    /// A square root of `numerator / denominator` into `root`, and whether
    /// there is one; the root chosen is the one whose canonical form is even.
    ///
    /// **Not constant time in its answer**, which says whether a root exists.
    /// It is for decoding a point, and a point is public.
    static bool TrySquareRootOfRatio(Field25519 numerator, Field25519 denominator,
                                     out Field25519 root)
    {
        // RFC 8032 §5.1.3: x = u v^3 (u v^7)^((p − 5)/8), then fix the sign
        // by sqrt(−1) if v x^2 came out as −u.
        Field25519 denominator3 = denominator.Square() * denominator;
        Field25519 denominator7 = denominator3.Square() * denominator;
        Field25519 candidate = numerator * denominator3 *
                               (numerator * denominator7).RaiseToTwoPower252MinusThree();

        Field25519 check = denominator * candidate.Square();
        if ((check - numerator).IsZero)
        {
            root = candidate;
        }
        else if ((check + numerator).IsZero)
        {
            root = candidate * SquareRootOfMinusOne;
        }
        else
        {
            root = Field25519.Zero;
            return false;
        }

        root = ConditionalSelect(root, -root, root.SignBit);
        return true;
    }

    // ------------------------------------------------------------ selection

    /// `whenZero` when `choice` is 0 and `whenOne` when it is 1. `choice`
    /// MUST be 0 or 1.
    static Field25519 ConditionalSelect(Field25519 whenZero, Field25519 whenOne, ulong choice)
    {
        ulong mask = OpaqueCopy(0u - choice);
        return new Field25519((whenZero._limb0 & ~mask) | (whenOne._limb0 & mask),
                              (whenZero._limb1 & ~mask) | (whenOne._limb1 & mask),
                              (whenZero._limb2 & ~mask) | (whenOne._limb2 & mask),
                              (whenZero._limb3 & ~mask) | (whenOne._limb3 & mask),
                              (whenZero._limb4 & ~mask) | (whenOne._limb4 & mask));
    }

    /// Exchanges `left` and `right` when `choice` is 1 and leaves them when it
    /// is 0. `choice` MUST be 0 or 1.
    static void ConditionalSwap(ref Field25519 left, ref Field25519 right, ulong choice)
    {
        ulong mask = OpaqueCopy(0u - choice);
        ulong exchange = mask & (left._limb0 ^ right._limb0);
        left._limb0 ^= exchange;
        right._limb0 ^= exchange;
        exchange = mask & (left._limb1 ^ right._limb1);
        left._limb1 ^= exchange;
        right._limb1 ^= exchange;
        exchange = mask & (left._limb2 ^ right._limb2);
        left._limb2 ^= exchange;
        right._limb2 ^= exchange;
        exchange = mask & (left._limb3 ^ right._limb3);
        left._limb3 ^= exchange;
        right._limb3 ^= exchange;
        exchange = mask & (left._limb4 ^ right._limb4);
        left._limb4 ^= exchange;
        right._limb4 ^= exchange;
    }

    // ------------------------------------------------------------- encoding

    /// Thirty-two little-endian bytes as an element, with the top bit
    /// ignored as RFC 7748 requires. A value from p to 2^255 − 1 is accepted
    /// and stands for itself minus p.
    static Field25519 FromBytes(ReadOnlySpan<byte> bytes, nuint at)
    {
        ulong word0 = ReadLittleDoubleWord(bytes, at);
        ulong word1 = ReadLittleDoubleWord(bytes, at + 8u);
        ulong word2 = ReadLittleDoubleWord(bytes, at + 16u);
        ulong word3 = ReadLittleDoubleWord(bytes, at + 24u);

        return new Field25519(word0 & LimbMask,
                              ((word0 >> 51) | (word1 << 13)) & LimbMask,
                              ((word1 >> 38) | (word2 << 26)) & LimbMask,
                              ((word2 >> 25) | (word3 << 39)) & LimbMask,
                              (word3 >> 12) & LimbMask);
    }

    /// The canonical encoding: thirty-two little-endian bytes of the one
    /// representative below p, top bit clear.
    public byte[] ToBytes()
    {
        Field25519 reduced = Reduce();
        byte[] bytes = new byte[32u];
        WriteLittleDoubleWord(bytes, 0u, reduced._limb0 | (reduced._limb1 << 51));
        WriteLittleDoubleWord(bytes, 8u, (reduced._limb1 >> 13) | (reduced._limb2 << 38));
        WriteLittleDoubleWord(bytes, 16u, (reduced._limb2 >> 26) | (reduced._limb3 << 25));
        WriteLittleDoubleWord(bytes, 24u, (reduced._limb3 >> 39) | (reduced._limb4 << 12));
        return bytes;
    }

    /// The same value with every limb below 2^51 and the whole below p.
    Field25519 Reduce()
    {
        Field25519 value = CarryLimbs(_limb0, _limb1, _limb2, _limb3, _limb4);

        // The value is now below 2^255 + 2^18 < 2p, so it is at most one p too
        // large, and it is exactly when adding 19 carries out of bit 255.
        ulong excess = (value._limb0 + 19u) >> 51;
        excess = (value._limb1 + excess) >> 51;
        excess = (value._limb2 + excess) >> 51;
        excess = (value._limb3 + excess) >> 51;
        excess = (value._limb4 + excess) >> 51;

        // Adding 19 and dropping bit 255 is subtracting p.
        ulong limb0 = value._limb0 + 19u * excess;
        ulong limb1 = value._limb1 + (limb0 >> 51);
        ulong limb2 = value._limb2 + (limb1 >> 51);
        ulong limb3 = value._limb3 + (limb2 >> 51);
        ulong limb4 = value._limb4 + (limb3 >> 51);
        return new Field25519(limb0 & LimbMask, limb1 & LimbMask, limb2 & LimbMask,
                              limb3 & LimbMask, limb4 & LimbMask);
    }

    /// Whether the value is zero, as an element rather than as limbs.
    bool IsZero
    {
        get
        {
            Field25519 reduced = Reduce();
            return (reduced._limb0 | reduced._limb1 | reduced._limb2 | reduced._limb3 |
                    reduced._limb4) == 0u;
        }
    }

    /// The low bit of the canonical form, which RFC 8032 calls the sign and
    /// stores in the top bit of a point's encoding. A number rather than a
    /// `bool`, for code that MUST NOT branch on it.
    ulong SignBit => Reduce()._limb0 & 1u;

    // ------------------------------------------------------------- internals

    /// One partial product, split at bit 51 into the column it belongs to
    /// and the one above. Both factors MUST be small enough that the product
    /// is below 2^115, which every caller's bounds ensure.
    static void AccumulateProduct(ulong left, ulong right, ref ulong low, ref ulong high)
    {
        ulong product = left * right;
        low += product & LimbMask;
        high += (product >> 51) | (MultiplyHigh(left, right) << 13);
    }

    /// Limbs below 2^63 carried into a weakly reduced value, with what passes
    /// bit 255 folded back to the bottom times 19.
    static Field25519 CarryLimbs(ulong limb0, ulong limb1, ulong limb2, ulong limb3,
                                 ulong limb4)
    {
        limb1 += limb0 >> 51;
        limb0 &= LimbMask;
        limb2 += limb1 >> 51;
        limb1 &= LimbMask;
        limb3 += limb2 >> 51;
        limb2 &= LimbMask;
        limb4 += limb3 >> 51;
        limb3 &= LimbMask;
        limb0 += 19u * (limb4 >> 51);
        limb4 &= LimbMask;
        return new Field25519(limb0, limb1, limb2, limb3, limb4);
    }
}
