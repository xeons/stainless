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

import Standard.Formats.Asn1;
import Standard.Security.Cryptography;

/// The one place a certificate's signature algorithm becomes a call into
/// `Standard.Security.Cryptography`, for checking and for making.
///
/// Every algorithm a certificate can name is a case of `Verify`; one that is
/// not is a signature that does not verify.
internal static class SignatureVerifier
{
    /// Whether `signature` is `key`'s signature of `signedData` under the
    /// algorithm `algorithmOid` with the DER `parameters`, empty when absent.
    internal static bool Verify(String algorithmOid, ReadOnlySpan<byte> parameters,
                                PublicKey key, ReadOnlySpan<byte> signedData,
                                ReadOnlySpan<byte> signature)
    {
        switch (algorithmOid)
        {
            case "1.3.101.112":                                     // id-Ed25519
            {
                if (parameters.Length != 0u)
                    return false;
                var ed25519 = key.GetEd25519PublicKey();
                if (!ed25519.Ok)
                    return false;
                return Ed25519.Verify(ed25519.Value, signedData, signature);
            }

            case "1.2.840.10045.4.3.2":                             // ecdsa-with-SHA256
                return VerifyECDsa(parameters, key, signedData, signature,
                                   HashAlgorithmName.Sha256);
            case "1.2.840.10045.4.3.3":                             // ecdsa-with-SHA384
                return VerifyECDsa(parameters, key, signedData, signature,
                                   HashAlgorithmName.Sha384);
            case "1.2.840.10045.4.3.4":                             // ecdsa-with-SHA512
                return VerifyECDsa(parameters, key, signedData, signature,
                                   HashAlgorithmName.Sha512);

            case "1.2.840.113549.1.1.5":                            // sha1WithRSAEncryption
                return VerifyRsaPkcs1(parameters, key, signedData, signature,
                                      HashAlgorithmName.Sha1);
            case "1.2.840.113549.1.1.11":                           // sha256WithRSAEncryption
                return VerifyRsaPkcs1(parameters, key, signedData, signature,
                                      HashAlgorithmName.Sha256);
            case "1.2.840.113549.1.1.12":                           // sha384WithRSAEncryption
                return VerifyRsaPkcs1(parameters, key, signedData, signature,
                                      HashAlgorithmName.Sha384);
            case "1.2.840.113549.1.1.13":                           // sha512WithRSAEncryption
                return VerifyRsaPkcs1(parameters, key, signedData, signature,
                                      HashAlgorithmName.Sha512);

            case "1.2.840.113549.1.1.10":                           // id-RSASSA-PSS
                return VerifyRsaPss(parameters, key, signedData, signature);
        }
        return false;
    }

    /// Whether the algorithm, with its DER `parameters`, is a signature over
    /// SHA-1, which a chain refuses as weak. RSASSA-PSS is weak when its
    /// hash is SHA-1, which is also what absent fields default to, or when
    /// its parameters do not parse.
    internal static bool IsWeakAlgorithm(String algorithmOid, ReadOnlySpan<byte> parameters)
    {
        switch (algorithmOid)
        {
            case "1.2.840.113549.1.1.5":                            // sha1WithRSAEncryption
            case "1.2.840.10045.4.1":                               // ecdsa-with-SHA1
                return true;
            case "1.2.840.113549.1.1.10":                           // id-RSASSA-PSS
            {
                var hash = DecodePssParameters(parameters, out int saltLength);
                return !hash.Some || hash.Value == HashAlgorithmName.Sha1;
            }
        }
        return false;
    }

    /// Whether `key` is an RSA key of fewer than 2048 bits, which a chain
    /// refuses as weak.
    internal static bool IsWeakKey(PublicKey key)
    {
        if (key.Oid != PublicKey.RsaOid && key.Oid != PublicKey.RsaPssOid)
            return false;
        var modulus = key.GetRsaModulus();
        if (!modulus.Ok)
            return false;
        return CountBigEndianBits(modulus.Value) < 2048u;
    }

    private static nuint CountBigEndianBits(ReadOnlySpan<byte> number)
    {
        for (nuint i = 0u; i < number.Length; i++)
        {
            byte top = number[i];
            if (top == 0)
                continue;
            nuint bits = (number.Length - i) * 8u;
            while ((top & 0x80) == 0)
            {
                top = (byte)(top << 1);
                bits--;
            }
            return bits;
        }
        return 0u;
    }

    /// RFC 5758: the parameters are absent.
    private static bool VerifyECDsa(ReadOnlySpan<byte> parameters, PublicKey key,
                                    ReadOnlySpan<byte> signedData, ReadOnlySpan<byte> signature,
                                    HashAlgorithmName hash)
    {
        if (parameters.Length != 0u)
            return false;
        var verifier = key.GetECDsaPublicKey();
        if (!verifier.Ok)
            return false;
        return verifier.Value.VerifyData(signedData, signature, hash,
                                         DsaSignatureFormat.Rfc3279DerSequence);
    }

    /// RFC 4055: the parameters are `NULL`, and absent is accepted as every
    /// browser does. The key MUST be `rsaEncryption`, not one restricted to PSS.
    private static bool VerifyRsaPkcs1(ReadOnlySpan<byte> parameters, PublicKey key,
                                       ReadOnlySpan<byte> signedData,
                                       ReadOnlySpan<byte> signature, HashAlgorithmName hash)
    {
        if (!IsNullOrAbsent(parameters) || key.Oid != PublicKey.RsaOid)
            return false;
        var verifier = key.GetRsaPublicKey();
        if (!verifier.Ok)
            return false;
        return verifier.Value.VerifyData(signedData, signature, hash, RsaSignaturePadding.Pkcs1);
    }

    /// RFC 4055 section 3.1: a key restricted to PSS by parameters of its
    /// own MUST be used with the same hash and mask, and a salt at least as
    /// long as the one it names.
    private static bool VerifyRsaPss(ReadOnlySpan<byte> parameters, PublicKey key,
                                     ReadOnlySpan<byte> signedData, ReadOnlySpan<byte> signature)
    {
        var decoded = DecodePssParameters(parameters, out int saltLength);
        if (!decoded.Some)
            return false;
        if (key.Oid == PublicKey.RsaPssOid && key.EncodedParameters.Length != 0u)
        {
            var restricted = DecodePssParameters(key.EncodedParameters, out int minimumSalt);
            if (!restricted.Some || restricted.Value != decoded.Value || saltLength < minimumSalt)
                return false;
        }
        var padding = RsaSignaturePadding.CreatePss(saltLength);
        var verifier = key.GetRsaPublicKey();
        if (!padding.Ok || !verifier.Ok)
            return false;
        return verifier.Value.VerifyData(signedData, signature, decoded.Value, padding.Value);
    }

    private static bool IsNullOrAbsent(ReadOnlySpan<byte> parameters) =>
        parameters.Length == 0u ||
        (parameters.Length == 2u && parameters[0u] == 0x05 && parameters[1u] == 0x00);

    /// RFC 4055's `RSASSA-PSS-params`: the hash, and in `saltLength` the
    /// salt's length. `None` for parameters that do not parse, a hash this
    /// does not have, a mask other than MGF1 over the same hash, or a trailer
    /// other than `0xBC`.
    internal static Optional<HashAlgorithmName> DecodePssParameters(ReadOnlySpan<byte> parameters,
                                                                    out int saltLength)
    {
        saltLength = 20;
        var document = new AsnReader(parameters, AsnEncodingRules.Der);
        var sequence = document.ReadSequence();
        if (!sequence.Ok || document.VerifyEndOfData() != AsnError.None)
            return None;
        AsnReader fields = sequence.Value;

        String hashOid = "1.3.14.3.2.26";
        String maskHashOid = "1.3.14.3.2.26";
        if (IsNextTag(fields, 0))
        {
            var hash = ReadExplicitHashIdentifier(fields, 0);
            if (!hash.Some)
                return None;
            hashOid = hash.Value;
        }
        if (IsNextTag(fields, 1))
        {
            var wrapper = fields.ReadSequence(CreateContextTag(1, true));
            if (!wrapper.Ok)
                return None;
            AsnReader explicitMask = wrapper.Value;
            var mask = explicitMask.ReadSequence();
            if (!mask.Ok || explicitMask.VerifyEndOfData() != AsnError.None)
                return None;
            AsnReader maskFields = mask.Value;
            var mgf = maskFields.ReadObjectIdentifier();
            if (!mgf.Ok || mgf.Value != "1.2.840.113549.1.1.8")        // id-mgf1
                return None;
            var maskHash = ReadHashIdentifier(maskFields);
            if (!maskHash.Some || maskFields.VerifyEndOfData() != AsnError.None)
                return None;
            maskHashOid = maskHash.Value;
        }
        if (IsNextTag(fields, 2))
        {
            var wrapper = fields.ReadSequence(CreateContextTag(2, true));
            if (!wrapper.Ok)
                return None;
            AsnReader explicitSalt = wrapper.Value;
            var salt = explicitSalt.ReadInt64();
            if (!salt.Ok || salt.Value < 0 || salt.Value > 65535 ||
                explicitSalt.VerifyEndOfData() != AsnError.None)
            {
                return None;
            }
            saltLength = (int)salt.Value;
        }
        if (IsNextTag(fields, 3))
        {
            var wrapper = fields.ReadSequence(CreateContextTag(3, true));
            if (!wrapper.Ok)
                return None;
            AsnReader explicitTrailer = wrapper.Value;
            var trailer = explicitTrailer.ReadInt64();
            if (!trailer.Ok || trailer.Value != 1 ||
                explicitTrailer.VerifyEndOfData() != AsnError.None)
            {
                return None;
            }
        }
        if (fields.VerifyEndOfData() != AsnError.None || hashOid != maskHashOid)
            return None;
        return FindHashAlgorithmByOid(hashOid);
    }

    /// The parameters `DecodePssParameters` reads, for signing: every field
    /// written, the trailer left at its default.
    internal static byte[] EncodePssParameters(HashAlgorithmName hash, int saltLength)
    {
        String hashOid = FindOidOfHashAlgorithm(hash).GetValueOrDefault("2.16.840.1.101.3.4.2.1");
        var writer = new AsnWriter();
        writer.PushSequence();
        writer.PushSequence(CreateContextTag(0, true));
        WriteHashIdentifier(writer, hashOid);
        writer.PopSequence();
        writer.PushSequence(CreateContextTag(1, true));
        writer.PushSequence();
        writer.WriteObjectIdentifier("1.2.840.113549.1.1.8");
        WriteHashIdentifier(writer, hashOid);
        writer.PopSequence();
        writer.PopSequence();
        writer.PushSequence(CreateContextTag(2, true));
        writer.WriteInteger((long)saltLength);
        writer.PopSequence();
        writer.PopSequence();
        return writer.Encode();
    }

    private static void WriteHashIdentifier(AsnWriter writer, String hashOid)
    {
        writer.PushSequence();
        writer.WriteObjectIdentifier(hashOid);
        writer.WriteNull();
        writer.PopSequence();
    }

    private static bool IsNextTag(AsnReader fields, int number)
    {
        if (!fields.HasData)
            return false;
        var tag = fields.PeekTag();
        return tag.Ok && tag.Value == CreateContextTag(number, true);
    }

    private static Optional<String> ReadExplicitHashIdentifier(AsnReader fields, int number)
    {
        var wrapper = fields.ReadSequence(CreateContextTag(number, true));
        if (!wrapper.Ok)
            return None;
        AsnReader inside = wrapper.Value;
        var hash = ReadHashIdentifier(inside);
        if (!hash.Some || inside.VerifyEndOfData() != AsnError.None)
            return None;
        return hash;
    }

    /// A hash's `AlgorithmIdentifier`, with `NULL` or absent parameters.
    private static Optional<String> ReadHashIdentifier(AsnReader reader)
    {
        var sequence = reader.ReadSequence();
        if (!sequence.Ok)
            return None;
        AsnReader identifier = sequence.Value;
        var oid = identifier.ReadObjectIdentifier();
        if (!oid.Ok)
            return None;
        if (identifier.HasData && identifier.ReadNull() != AsnError.None)
            return None;
        if (identifier.VerifyEndOfData() != AsnError.None)
            return None;
        return Some(oid.Value);
    }
}
