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

/// The private half of an RSA key, held as the Chinese remainder theorem
/// uses it. Checked for consistency before it is made, and not changed after.
class RsaPrivateKey
{
    private ulong[] _exponent;
    private MontgomeryModulus _primeP;
    private MontgomeryModulus _primeQ;
    private ulong[] _exponentP;
    private ulong[] _exponentQ;
    private ulong[] _coefficient;
    private ulong[] _fermatP;
    private ulong[] _fermatQ;

    /// `exponent` has the modulus's limbs; `exponentP` and `coefficient`
    /// have `p`'s, `exponentQ` has `q`'s. All are kept rather than copied.
    RsaPrivateKey(ulong[] exponent, ulong[] p, ulong[] q, ulong[] exponentP, ulong[] exponentQ,
                  ulong[] coefficient)
    {
        _exponent = exponent;
        _primeP = new MontgomeryModulus(p);
        _primeQ = new MontgomeryModulus(q);
        _exponentP = exponentP;
        _exponentQ = exponentQ;
        _coefficient = coefficient;

        // p - 2 and q - 2, the exponents that invert by Fermat's little theorem.
        _fermatP = CopyLimbs(p);
        _fermatQ = CopyLimbs(q);
        Limbs.SubtractLimb(&_fermatP[0u], 2ul, _fermatP.Length);
        Limbs.SubtractLimb(&_fermatQ[0u], 2ul, _fermatQ.Length);
    }

    ~RsaPrivateKey()
    {
        Limbs.ZeroMemory(_exponent);
        _primeP.EraseLimbs();
        _primeQ.EraseLimbs();
        Limbs.ZeroMemory(_exponentP);
        Limbs.ZeroMemory(_exponentQ);
        Limbs.ZeroMemory(_coefficient);
        Limbs.ZeroMemory(_fermatP);
        Limbs.ZeroMemory(_fermatQ);
    }

    /// `d`.
    ulong[] Exponent => _exponent;

    /// `p`, prepared.
    MontgomeryModulus PrimeP => _primeP;

    /// `q`, prepared.
    MontgomeryModulus PrimeQ => _primeQ;

    /// `d mod (p - 1)`.
    ulong[] ExponentP => _exponentP;

    /// `d mod (q - 1)`.
    ulong[] ExponentQ => _exponentQ;

    /// `q^-1 mod p`.
    ulong[] Coefficient => _coefficient;

    /// `blinded^d mod n`, unblinded by `blinding^-1`, where `blinded` is
    /// `input * blinding^e`: RFC 8017 §5.1.2 by the Chinese remainder theorem,
    /// with the inverse of the blinding factor taken modulo each prime.
    ///
    /// @param modulus   `n`
    /// @param blinded   below `n`
    /// @param blinding  the factor `blinded` was made with, below `n` and
    ///                  prime to it
    ulong[] ComputeUnblindedPower(MontgomeryModulus modulus, ulong[] blinded, ulong[] blinding)
    {
        MontgomeryModulus p = _primeP;
        MontgomeryModulus q = _primeQ;

        ulong[] fromP = p.Power(p.Reduce(blinded), _exponentP);
        ulong[] fromQ = q.Power(q.Reduce(blinded), _exponentQ);

        // Each half times the blinding factor's inverse modulo its prime.
        ulong[] inverseP = p.Power(p.Reduce(blinding), _fermatP);
        ulong[] inverseQ = q.Power(q.Reduce(blinding), _fermatQ);
        fromP = p.MultiplyModular(fromP, inverseP);
        fromQ = q.MultiplyModular(fromQ, inverseQ);

        // Garner: m = fromQ + q * (qInv * (fromP - fromQ) mod p).
        ulong[] difference = p.SubtractModular(fromP, p.Reduce(fromQ));
        ulong[] h = p.MultiplyModular(difference, _coefficient);

        nuint pCount = p.LimbCount;
        nuint qCount = q.LimbCount;
        ulong[] product = new ulong[pCount + qCount];
        Limbs.Multiply(&product[0u], &q.Modulus[0u], qCount, &h[0u], pCount);
        ulong carry = Limbs.Add(&product[0u], &product[0u], &fromQ[0u], qCount);
        Limbs.AddLimb(&product[qCount], carry, pCount);

        ulong[] result = modulus.CreateNumber();
        nuint count = result.Length < product.Length ? result.Length : product.Length;
        Limbs.Copy(&result[0u], &product[0u], count);

        Limbs.ZeroMemory(fromP);
        Limbs.ZeroMemory(fromQ);
        Limbs.ZeroMemory(difference);
        Limbs.ZeroMemory(h);
        Limbs.ZeroMemory(product);
        return result;
    }

    static ulong[] CopyLimbs(ulong[] value) => value[:].ToArray();
}
