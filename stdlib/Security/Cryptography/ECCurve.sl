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

/// An elliptic curve, named by its object identifier: .NET's `ECCurve`,
/// for named curves.
///
/// ```csharp
/// var key = try ECDsa.Create(ECCurve.NamedCurves.NistP256);
/// ```
///
/// **Any identifier can be held, and two can be used**: P-256 and P-384,
/// which are what TLS, X.509 and FIPS 186-5 use. A key on any other curve —
/// `secp256k1`, P-521, a curve given by explicit parameters — is refused
/// with `CryptoError.Unsupported` when a key is made or imported, so a
/// certificate naming one reads cleanly and fails where it is used.
///
/// The zero value names no curve.
public struct ECCurve
{
    private String _oid;
    private bool _isNamed;

    ECCurve(String oid)
    {
        _oid = oid;
        _isNamed = true;
    }

    /// The curves this module has arithmetic for.
    public static class NamedCurves
    {
        /// NIST P-256, also called `secp256r1` and `prime256v1`: OID
        /// 1.2.840.10045.3.1.7.
        public static ECCurve NistP256 => ECCurve.CreateFromValue("1.2.840.10045.3.1.7");

        /// NIST P-384, also called `secp384r1`: OID 1.3.132.0.34.
        public static ECCurve NistP384 => ECCurve.CreateFromValue("1.3.132.0.34");
    }

    /// Whether this names a curve, which every curve but the zero value does.
    public bool IsNamed => _isNamed;

    /// The curve's object identifier, dotted, or empty for the zero value.
    public String OidValue => _isNamed ? _oid : "";

    /// .NET's name for the curve — `nistP256`, `nistP384` — or empty for a
    /// curve this module has no arithmetic for.
    public String FriendlyName
    {
        get
        {
            if (!_isNamed)
                return "";
            switch (_oid)
            {
                case "1.2.840.10045.3.1.7": return "nistP256";
                case "1.3.132.0.34": return "nistP384";
            }
            return "";
        }
    }

    /// The curve named by `oidValue`, supported or not.
    ///
    /// @param oidValue  a dotted object identifier, as a certificate carries it
    /// @see ECCurve.CreateFromFriendlyName
    public static ECCurve CreateFromValue(String oidValue) => new ECCurve(oidValue);

    /// The curve a name means: `nistP256`, `secp256r1`, `prime256v1` or
    /// `P-256`, and `nistP384`, `secp384r1` or `P-384`. Any other name gives
    /// the zero value, which names no curve.
    ///
    /// @param friendlyName  what the curve is called, with its case as written here
    /// @see ECCurve.CreateFromValue
    public static ECCurve CreateFromFriendlyName(String friendlyName)
    {
        switch (friendlyName)
        {
            case "nistP256":
            case "secp256r1":
            case "prime256v1":
            case "P-256":
                return new ECCurve("1.2.840.10045.3.1.7");

            case "nistP384":
            case "secp384r1":
            case "P-384":
                return new ECCurve("1.3.132.0.34");
        }

        ECCurve none = new ECCurve("");
        none._isNamed = false;
        return none;
    }

    /// Whether both name the same curve.
    public bool Equals(ECCurve other) =>
        _isNamed == other._isNamed && (!_isNamed || _oid == other._oid);
}

/// The arithmetic for `curve`, or `CryptoError.Unsupported`.
Result<EcDomain, CryptoError> CreateEcDomainForCurve(ECCurve curve)
{
    switch (curve.OidValue)
    {
        case "1.2.840.10045.3.1.7": return Ok(CreateP256Domain());
        case "1.3.132.0.34": return Ok(CreateP384Domain());
    }
    return Fail(CryptoError.Unsupported);
}
