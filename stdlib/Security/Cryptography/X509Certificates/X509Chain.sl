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
import Standard.Security.Cryptography;

/// Builds a path from a certificate to a trust anchor and validates it:
/// .NET's `X509Chain`, doing its own work rather than asking the platform.
///
/// ```csharp
/// var chain = new X509Chain();
/// chain.ChainPolicy.ExtraStore.AddRange(sentByTheServer);
/// chain.ChainPolicy.ApplicationPolicy.Add(X509EnhancedKeyUsageExtension.ServerAuthenticationOid);
/// if (!chain.Build(leaf) || !leaf.MatchesHostname(host))
///     return Fail(...);
/// ```
///
/// **Building.** From the certificate, an issuer is any certificate among
/// the anchors or the extra store whose subject is its issuer's name, as RFC
/// 5280 compares names, and whose subject key identifier, when both sides
/// have one, is its authority key identifier. Anchors are tried first, then
/// intermediates valid at the verification time, then the rest; every
/// alternative is tried in turn, so a cross-signed intermediate or a second
/// CA of the same name is found when the first does not lead anywhere. A
/// path stops at any anchor, self-signed or not. A path holds at most eight
/// certificates, and at most 128 candidates are tried in all.
///
/// **Validating** each path, the first that passes everything is kept, and
/// otherwise the first that reached an anchor, and otherwise the longest:
///
/// - every certificate valid at `VerificationTime`, the anchor included;
/// - every signature verified, the anchor's own excepted, and none over
///   SHA-1;
/// - every issuer a CA with basic constraints — an anchor may have none, as
///   a version 1 root does — and not more non-self-issued intermediates
///   below it than its path length allows;
/// - every issuer's key usage, when it has one, allowing `KeyCertSign`;
/// - the application policy allowed by the leaf's extended key usage and by
///   that of every intermediate that has one; and for a TLS purpose the
///   leaf's key usage, when it has one, allowing a signature, key
///   encipherment or key agreement;
/// - the leaf's DNS and IP subject alternative names inside the name
///   constraints of every issuer above it;
/// - no critical extension this module does not understand.
///
/// No revocation is checked; see `X509RevocationMode`.
public sealed class X509Chain
{
    private const nuint MaximumLength = 8u;
    private const nuint MaximumCandidates = 128u;

    private X509ChainPolicy _policy;
    private X509ChainElement[] _elements;
    private X509ChainStatusFlags _status;

    private X509Certificate2Collection _anchors;
    private X509Certificate2Collection _intermediates;
    private nuint _candidatesTried;
    private bool _cyclic;
    private List<X509Certificate2> _bestPath;
    private X509ChainStatusFlags[] _bestFlags;
    private bool _bestAnchored;

    /// A chain with the default policy and nothing built.
    public X509Chain()
    {
        _policy = new X509ChainPolicy();
        _elements = new X509ChainElement[0u];
        _anchors = new X509Certificate2Collection();
        _intermediates = new X509Certificate2Collection();
        _bestPath = new List<X509Certificate2>();
        _bestFlags = new X509ChainStatusFlags[0u];
    }

    /// What the next `Build` is held to.
    public X509ChainPolicy ChainPolicy
    {
        get => _policy;
        set => _policy = value;
    }

    /// The path the last `Build` chose, from the certificate to the anchor, or
    /// as far as it got.
    public X509ChainElement[] ChainElements => _elements;

    /// Everything wrong with the last `Build`, one flag each; empty when it
    /// passed.
    public X509ChainStatus[] ChainStatus => DescribeStatusFlags(_status);

    /// Everything wrong with the last `Build`, as one set of flags.
    public X509ChainStatusFlags StatusFlags => _status;

    /// Forgets the last `Build`; the policy stays.
    public void Reset()
    {
        _elements = new X509ChainElement[0u];
        _status = X509ChainStatusFlags.NoError;
    }

    /// Builds and validates a path from `certificate`.
    ///
    /// @param certificate  the leaf, usually a server's
    /// @returns whether a path reached an anchor and passed every check;
    ///          `ChainElements` and `ChainStatus` say what was found either way
    public bool Build(X509Certificate2 certificate)
    {
        _anchors = new X509Certificate2Collection();
        _intermediates = new X509Certificate2Collection();
        if (_policy.TrustMode == X509ChainTrustMode.CustomRootTrust)
        {
            _anchors.AddRange(_policy.CustomTrustStore);
        }
        else
        {
            _anchors.AddRange(X509Store.Open(StoreName.Root).Certificates);
            _intermediates.AddRange(X509Store.Open(StoreName.CertificateAuthority).Certificates);
        }
        _intermediates.AddRange(_policy.ExtraStore);

        _candidatesTried = 0u;
        _cyclic = false;
        _bestPath = new List<X509Certificate2>();
        _bestFlags = new X509ChainStatusFlags[0u];
        _bestAnchored = false;

        var path = new List<X509Certificate2>();
        path.Add(certificate);
        ExtendPath(path);

        _status = X509ChainStatusFlags.NoError;
        _elements = new X509ChainElement[_bestPath.Count];
        for (nuint i = 0u; i < _bestPath.Count; i++)
        {
            _elements[i] = new X509ChainElement(_bestPath[i], _bestFlags[i]);
            _status = _status | _bestFlags[i];
        }
        if (_cyclic && !_bestAnchored)
            _status = _status | X509ChainStatusFlags.Cyclic;

        _anchors = new X509Certificate2Collection();
        _intermediates = new X509Certificate2Collection();
        _bestPath = new List<X509Certificate2>();
        return _status == X509ChainStatusFlags.NoError;
    }

    // ------------------------------------------------------------ building

    /// Tries every way on from the last certificate of `path`. True once a
    /// path has passed everything, which ends the search.
    private bool ExtendPath(List<X509Certificate2> path)
    {
        X509Certificate2 last = path[path.Count - 1u];
        if (_anchors.Contains(last))
            return ConsiderPath(path, true);

        bool extended = false;
        if (path.Count < MaximumLength)
        {
            foreach (X509Certificate2 candidate in FindIssuers(last))
            {
                if (_candidatesTried >= MaximumCandidates)
                    break;
                _candidatesTried++;
                if (ContainsCertificate(path, candidate))
                {
                    if (!candidate.Equals(last))
                        _cyclic = true;
                    continue;
                }

                extended = true;
                path.Add(candidate);
                bool passed = ExtendPath(path);
                path.RemoveAt(path.Count - 1u);
                if (passed)
                    return true;
            }
        }

        if (!extended)
            ConsiderPath(path, false);
        return false;
    }

    /// Every certificate that could have issued `certificate`, in the order
    /// they are worth trying.
    private List<X509Certificate2> FindIssuers(X509Certificate2 certificate)
    {
        var found = new List<X509Certificate2>();
        foreach (X509Certificate2 anchor in _anchors)
        {
            if (CouldHaveIssued(anchor, certificate))
                found.Add(anchor);
        }

        long now = _policy.VerificationTime;
        for (int pass = 0; pass < 2; pass++)
        {
            foreach (X509Certificate2 intermediate in _intermediates)
            {
                bool current = now >= intermediate.NotBefore && now <= intermediate.NotAfter;
                if (current != (pass == 0) || _anchors.Contains(intermediate))
                    continue;
                if (CouldHaveIssued(intermediate, certificate))
                    found.Add(intermediate);
            }
        }
        return found;
    }

    private static bool CouldHaveIssued(X509Certificate2 issuer, X509Certificate2 certificate)
    {
        if (!issuer.SubjectName.Equals(certificate.IssuerName))
            return false;

        X509AuthorityKeyIdentifierExtension? authority = certificate.AuthorityKeyIdentifier;
        X509SubjectKeyIdentifierExtension? subject = issuer.SubjectKeyIdentifier;
        if (authority == null || subject == null)
            return true;
        if (authority.KeyIdentifier is Some wanted)
            return AreBytesEqual(wanted.Value, subject.SubjectKeyIdentifierBytes);
        return true;
    }

    private static bool ContainsCertificate(List<X509Certificate2> path,
                                            X509Certificate2 certificate)
    {
        foreach (X509Certificate2 held in path)
        {
            if (held.Equals(certificate))
                return true;
        }
        return false;
    }

    /// Validates `path` and keeps it when it is the best so far. True when it
    /// passed everything.
    private bool ConsiderPath(List<X509Certificate2> path, bool anchored)
    {
        X509ChainStatusFlags[] flags = ValidatePath(path, anchored);
        bool passed = anchored;
        foreach (X509ChainStatusFlags one in flags)
        {
            if (one != X509ChainStatusFlags.NoError)
                passed = false;
        }

        bool better = _bestPath.Count == 0u || passed ||
                      (anchored && !_bestAnchored) ||
                      (!anchored && !_bestAnchored && path.Count > _bestPath.Count);
        if (better)
        {
            _bestPath = new List<X509Certificate2>();
            foreach (X509Certificate2 certificate in path)
                _bestPath.Add(certificate);
            _bestFlags = flags;
            _bestAnchored = anchored;
        }
        return passed;
    }

    // ---------------------------------------------------------- validating

    private X509ChainStatusFlags[] ValidatePath(List<X509Certificate2> path, bool anchored)
    {
        nuint count = path.Count;
        var flags = new X509ChainStatusFlags[count];
        long now = _policy.VerificationTime;

        for (nuint i = 0u; i < count; i++)
        {
            X509Certificate2 certificate = path[i];
            bool isAnchor = anchored && i == count - 1u;
            X509ChainStatusFlags found = X509ChainStatusFlags.NoError;

            if (now < certificate.NotBefore || now > certificate.NotAfter)
                found = found | X509ChainStatusFlags.NotTimeValid;
            if (certificate.Extensions.ContainsUnsupportedCriticalExtension())
            {
                found = found | X509ChainStatusFlags.InvalidExtension |
                        X509ChainStatusFlags.HasNotSupportedCriticalExtension;
            }
            if (_policy.RevocationMode != X509RevocationMode.NoCheck)
            {
                found = found | X509ChainStatusFlags.RevocationStatusUnknown |
                        X509ChainStatusFlags.OfflineRevocation;
            }

            if (i + 1u < count)
            {
                X509Certificate2 issuer = path[i + 1u];
                if (!SignatureVerifier.Verify(certificate.SignatureAlgorithm,
                                              certificate.SignatureParameters, issuer.PublicKey,
                                              certificate.SignedPart, certificate.Signature))
                {
                    found = found | X509ChainStatusFlags.NotSignatureValid;
                }
                else if (SignatureVerifier.IsWeakAlgorithm(certificate.SignatureAlgorithm))
                {
                    found = found | X509ChainStatusFlags.HasWeakSignature;
                }
            }
            else if (!anchored)
            {
                found = found | (certificate.IsSelfIssued ? X509ChainStatusFlags.UntrustedRoot
                                                          : X509ChainStatusFlags.PartialChain);
            }

            if (i > 0u)
            {
                found = found | ValidateIssuer(path, i, isAnchor);
                X509NameConstraintsExtension? constraints = certificate.NameConstraints;
                if (constraints != null)
                    flags[0u] = flags[0u] | CheckNameConstraints(path[0u], constraints);
            }
            else if (!isAnchor)
            {
                found = found | ValidateLeafUsage(certificate);
            }

            flags[i] = flags[i] | found;
        }
        return flags;
    }

    /// What is wrong with `path[index]` as the issuer of what is below it.
    private X509ChainStatusFlags ValidateIssuer(List<X509Certificate2> path, nuint index,
                                                bool isAnchor)
    {
        X509Certificate2 issuer = path[index];
        X509ChainStatusFlags found = X509ChainStatusFlags.NoError;

        X509BasicConstraintsExtension? basic = issuer.BasicConstraints;
        if (basic == null)
        {
            if (!isAnchor)
                found = found | X509ChainStatusFlags.InvalidBasicConstraints;
        }
        else if (!basic.CertificateAuthority)
        {
            found = found | X509ChainStatusFlags.InvalidBasicConstraints;
        }
        else if (basic.HasPathLengthConstraint)
        {
            nuint below = 0u;
            for (nuint j = 1u; j < index; j++)
            {
                if (!path[j].IsSelfIssued)
                    below++;
            }
            if (below > (nuint)basic.PathLengthConstraint)
                found = found | X509ChainStatusFlags.InvalidBasicConstraints;
        }

        X509KeyUsageExtension? usage = issuer.KeyUsage;
        if (usage != null && !usage.KeyUsages.HasFlag(X509KeyUsageFlags.KeyCertSign))
            found = found | X509ChainStatusFlags.NotValidForUsage;

        X509EnhancedKeyUsageExtension? enhanced = issuer.EnhancedKeyUsage;
        if (!isAnchor && enhanced != null && !AllowsApplicationPolicy(enhanced))
            found = found | X509ChainStatusFlags.NotValidForUsage;
        return found;
    }

    private X509ChainStatusFlags ValidateLeafUsage(X509Certificate2 leaf)
    {
        X509EnhancedKeyUsageExtension? enhanced = leaf.EnhancedKeyUsage;
        if (enhanced != null && !AllowsApplicationPolicy(enhanced))
            return X509ChainStatusFlags.NotValidForUsage;

        bool forTls = false;
        foreach (String purpose in _policy.ApplicationPolicy)
        {
            if (purpose == X509EnhancedKeyUsageExtension.ServerAuthenticationOid ||
                purpose == X509EnhancedKeyUsageExtension.ClientAuthenticationOid)
            {
                forTls = true;
            }
        }

        X509KeyUsageExtension? usage = leaf.KeyUsage;
        X509KeyUsageFlags handshake = X509KeyUsageFlags.DigitalSignature |
                                      X509KeyUsageFlags.KeyEncipherment |
                                      X509KeyUsageFlags.KeyAgreement;
        if (forTls && usage != null && (usage.KeyUsages & handshake) == X509KeyUsageFlags.None)
            return X509ChainStatusFlags.NotValidForUsage;
        return X509ChainStatusFlags.NoError;
    }

    private bool AllowsApplicationPolicy(X509EnhancedKeyUsageExtension enhanced)
    {
        foreach (String purpose in _policy.ApplicationPolicy)
        {
            if (!enhanced.AllowsUsage(purpose))
                return false;
        }
        return true;
    }

    private static X509ChainStatusFlags CheckNameConstraints(
        X509Certificate2 leaf, X509NameConstraintsExtension constraints)
    {
        X509SubjectAlternativeNameExtension? names = leaf.SubjectAlternativeName;
        if (names == null)
            return X509ChainStatusFlags.NoError;

        X509ChainStatusFlags found = X509ChainStatusFlags.NoError;
        foreach (String name in names.DnsNames)
        {
            var normalized = NormalizeDnsName(name, true);
            if (normalized.Some)
            {
                found = found | constraints.CheckDnsName(normalized.Value);
            }
            else
            {
                found = found | X509ChainStatusFlags.HasNotPermittedNameConstraint;
            }
        }
        foreach (byte[] address in names.IPAddresses)
            found = found | constraints.CheckIPAddress(address);
        return found;
    }

    // ------------------------------------------------------------ describing

    /// One status for each flag set in `flags`, in the order of their values.
    internal static X509ChainStatus[] DescribeStatusFlags(X509ChainStatusFlags flags)
    {
        var described = new List<X509ChainStatus>();
        uint bits = (uint)(int)flags;
        for (int bit = 0; bit < 32; bit++)
        {
            uint one = 1u << bit;
            if ((bits & one) == 0u)
                continue;
            var flag = (X509ChainStatusFlags)(int)one;
            described.Add(new X509ChainStatus(flag, DescribeStatusFlag(flag)));
        }
        return described.ToArray();
    }

    private static String DescribeStatusFlag(X509ChainStatusFlags flag)
    {
        switch (flag)
        {
            case X509ChainStatusFlags.NotTimeValid:
                return "a certificate is not valid at the verification time";
            case X509ChainStatusFlags.NotSignatureValid:
                return "a signature does not verify";
            case X509ChainStatusFlags.NotValidForUsage:
                return "a key usage does not allow what the chain is for";
            case X509ChainStatusFlags.UntrustedRoot:
                return "the chain ends in a root that is not trusted";
            case X509ChainStatusFlags.RevocationStatusUnknown:
                return "revocation was asked about, and is not checked";
            case X509ChainStatusFlags.Cyclic:
                return "every path loops back on itself";
            case X509ChainStatusFlags.InvalidExtension:
                return "an extension is not valid here";
            case X509ChainStatusFlags.InvalidBasicConstraints:
                return "an issuer is not a CA, or its path length is exceeded";
            case X509ChainStatusFlags.HasNotPermittedNameConstraint:
                return "a name is outside what an issuer permits";
            case X509ChainStatusFlags.HasExcludedNameConstraint:
                return "a name is inside what an issuer excludes";
            case X509ChainStatusFlags.PartialChain:
                return "no path reaches a trusted certificate";
            case X509ChainStatusFlags.HasWeakSignature:
                return "a signature is made over SHA-1";
            case X509ChainStatusFlags.OfflineRevocation:
                return "nothing could be asked about revocation";
            case X509ChainStatusFlags.HasNotSupportedCriticalExtension:
                return "a critical extension is not understood";
        }
        return "a status this module does not set";
    }
}
