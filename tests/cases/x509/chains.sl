// SPDX-License-Identifier: 0BSD
module X509Case;

import Standard.Console;
import Standard.Security.Cryptography;
import Standard.Security.Cryptography.X509Certificates;

/// Builds a chain for `leaf` against `anchors` alone, through `extra`, for a
/// TLS server at the fixed verification time, and prints what it found.
void CheckChain(String label, byte[] leaf, byte[][] anchors, byte[][] extra,
                X509ChainStatusFlags want, nuint length)
{
    var chain = new X509Chain();
    chain.ChainPolicy.TrustMode = X509ChainTrustMode.CustomRootTrust;
    chain.ChainPolicy.VerificationTime = VerificationTime;
    chain.ChainPolicy.ApplicationPolicy.Add(X509EnhancedKeyUsageExtension.ServerAuthenticationOid);
    foreach (byte[] anchor in anchors)
        chain.ChainPolicy.CustomTrustStore.Add(LoadFixture(label, anchor));
    foreach (byte[] one in extra)
        chain.ChainPolicy.ExtraStore.Add(LoadFixture(label, one));

    bool built = chain.Build(LoadFixture(label, leaf));
    bool passed = built == (want == X509ChainStatusFlags.NoError) && chain.StatusFlags == want &&
                  chain.ChainElements.Length == length;
    if (passed)
    {
        Console.WriteLine($"chain {label} ok: {chain.StatusFlags}");
    }
    else
    {
        Console.WriteLine($"chain {label} FAIL: {built} {chain.StatusFlags} " +
                          $"length {chain.ChainElements.Length}");
    }
}

void BuildChains()
{
    byte[][] root = [RootPem];
    byte[][] inter = [InterPem];
    byte[][] none = [];

    CheckChain("good", GoodPem, root, inter, X509ChainStatusFlags.NoError, 3u);
    CheckChain("expired", ExpiredPem, root, inter, X509ChainStatusFlags.NotTimeValid, 3u);
    CheckChain("not yet valid", NotYetPem, root, inter, X509ChainStatusFlags.NotTimeValid, 3u);
    CheckChain("wrong extended key usage", WrongEkuPem, root, inter,
               X509ChainStatusFlags.NotValidForUsage, 3u);
    CheckChain("key usage without a signature", BadKuPem, root, inter,
               X509ChainStatusFlags.NotValidForUsage, 3u);
    CheckChain("wildcard", WildcardPem, root, inter, X509ChainStatusFlags.NoError, 3u);
    CheckChain("ip", IpPem, root, inter, X509ChainStatusFlags.NoError, 3u);
    CheckChain("unknown critical extension", CriticalPem, root, inter,
               X509ChainStatusFlags.InvalidExtension |
               X509ChainStatusFlags.HasNotSupportedCriticalExtension, 3u);

    byte[][] noCa = [NoCaPem];
    CheckChain("issuer that is not a CA", UnderNoCaPem, root, noCa,
               X509ChainStatusFlags.InvalidBasicConstraints, 3u);
    byte[][] deep = [InterPem, SubPem];
    CheckChain("path length exceeded", UnderSubPem, root, deep,
               X509ChainStatusFlags.InvalidBasicConstraints, 4u);
    byte[][] noKu = [NoKuPem];
    CheckChain("issuer without certificate signing", UnderNoKuPem, root, noKu,
               X509ChainStatusFlags.NotValidForUsage, 3u);

    // Permitted DNS:example.com and IP:192.0.2.0/24; excluded bad.example.com
    // and 2001:db8::/32.
    byte[][] nc = [NcPem];
    CheckChain("name constraints met", NcOkPem, root, nc, X509ChainStatusFlags.NoError, 3u);
    CheckChain("name not permitted", NcOtherPem, root, nc,
               X509ChainStatusFlags.HasNotPermittedNameConstraint, 3u);
    CheckChain("name excluded", NcExcludedPem, root, nc,
               X509ChainStatusFlags.HasExcludedNameConstraint, 3u);
    CheckChain("address not permitted", NcIpPem, root, nc,
               X509ChainStatusFlags.HasNotPermittedNameConstraint, 3u);
    // *.example.com could stand for bad.example.com, so it is refused, as
    // Chromium refuses it. OpenSSL accepts this one.
    CheckChain("wildcard over an excluded name", NcWildcardPem, root, nc,
               X509ChainStatusFlags.HasExcludedNameConstraint, 3u);

    // Trust only the other root: the path goes through the cross-signed copy
    // of the intermediate rather than the one the leaf's issuer first finds.
    byte[][] rootB = [RootBPem];
    byte[][] both = [InterPem, InterCrossPem];
    CheckChain("cross-signed", GoodPem, rootB, both, X509ChainStatusFlags.NoError, 3u);
    CheckChain("no intermediate", GoodPem, root, none, X509ChainStatusFlags.PartialChain, 1u);
    CheckChain("untrusted root", GoodPem, rootB, [InterPem, RootPem],
               X509ChainStatusFlags.UntrustedRoot, 3u);
    CheckChain("anchor is the leaf", RootPem, root, none, X509ChainStatusFlags.NoError, 1u);
    CheckChain("intermediate as anchor", GoodPem, inter, none, X509ChainStatusFlags.NoError, 2u);

    // Cycle A and Cycle B issue each other, and neither is trusted.
    byte[][] cycle = [CycleAPem, CycleBPem];
    CheckChain("cyclic", CyclicPem, root, cycle,
               X509ChainStatusFlags.Cyclic | X509ChainStatusFlags.PartialChain, 3u);

    CheckTamperedSignature();

    // RSA PKCS #1 v1.5, RSA-PSS, ECDSA P-256, and Let's Encrypt's own.
    CheckChain("rsa", RsaLeafPem, [RsaRootPem], none, X509ChainStatusFlags.NoError, 2u);
    CheckChain("rsa-pss", RsaPssPem, [RsaRootPem], none, X509ChainStatusFlags.NoError, 2u);
    CheckChain("p-256", P256LeafPem, [P256RootPem], none, X509ChainStatusFlags.NoError, 2u);
    CheckChain("isrg x1 to r10", R10Pem, [IsrgX1Pem], none, X509ChainStatusFlags.NoError, 2u);
    CheckChain("isrg x2 to e6", E6Pem, [IsrgX2Pem], none, X509ChainStatusFlags.NoError, 2u);

    CheckElements();
    CheckPolicyChoices();
}

/// The last byte of the leaf's signature changed: everything else is as it was.
void CheckTamperedSignature()
{
    byte[] tampered = GoodDer[:].ToArray();
    tampered[tampered.Length - 1u] = (byte)(tampered[tampered.Length - 1u] ^ 0x01);
    var leaf = X509Certificate2.FromDer(tampered);
    if (!leaf.Ok)
    {
        Check("chain tampered signature parses", false);
        return;
    }

    var chain = new X509Chain();
    chain.ChainPolicy.TrustMode = X509ChainTrustMode.CustomRootTrust;
    chain.ChainPolicy.VerificationTime = VerificationTime;
    chain.ChainPolicy.CustomTrustStore.Add(LoadFixture("root", RootPem));
    chain.ChainPolicy.ExtraStore.Add(LoadFixture("inter", InterPem));
    Check("chain tampered signature",
          !chain.Build(leaf.Value) && chain.StatusFlags == X509ChainStatusFlags.NotSignatureValid &&
          chain.ChainElements[0u].StatusFlags == X509ChainStatusFlags.NotSignatureValid);
}

void CheckElements()
{
    var chain = new X509Chain();
    chain.ChainPolicy.TrustMode = X509ChainTrustMode.CustomRootTrust;
    chain.ChainPolicy.VerificationTime = VerificationTime;
    chain.ChainPolicy.CustomTrustStore.Add(LoadFixture("root", RootPem));
    chain.ChainPolicy.ExtraStore.Add(LoadFixture("inter", InterPem));
    chain.Build(LoadFixture("expired", ExpiredPem));

    X509ChainElement[] elements = chain.ChainElements;
    Check("elements run leaf to root",
          elements.Length == 3u &&
          elements[0u].Certificate.Subject == "CN=expired.example.com" &&
          elements[2u].Certificate.Subject == "CN=Stainless Test Root, O=\"Stainless, Test\", C=US");
    Check("only the leaf is out of time",
          elements[0u].StatusFlags == X509ChainStatusFlags.NotTimeValid &&
          elements[1u].StatusFlags == X509ChainStatusFlags.NoError);
    X509ChainStatus[] status = chain.ChainStatus;
    Check("chain status names the flag",
          status.Length == 1u && status[0u].Status == X509ChainStatusFlags.NotTimeValid &&
          !status[0u].StatusInformation.IsEmpty);
}

void CheckPolicyChoices()
{
    // No application policy: the client-only leaf is fine.
    var chain = new X509Chain();
    chain.ChainPolicy.TrustMode = X509ChainTrustMode.CustomRootTrust;
    chain.ChainPolicy.VerificationTime = VerificationTime;
    chain.ChainPolicy.CustomTrustStore.Add(LoadFixture("root", RootPem));
    chain.ChainPolicy.ExtraStore.Add(LoadFixture("inter", InterPem));
    Check("client leaf with no policy", chain.Build(LoadFixture("wrongeku", WrongEkuPem)));

    chain.ChainPolicy.ApplicationPolicy.Add(X509EnhancedKeyUsageExtension.ClientAuthenticationOid);
    Check("client leaf for a client", chain.Build(LoadFixture("wrongeku", WrongEkuPem)));

    // Revocation cannot be checked, and asking says so.
    chain.ChainPolicy.RevocationMode = X509RevocationMode.Online;
    Check("revocation asked for",
          !chain.Build(LoadFixture("good", GoodPem)) &&
          chain.StatusFlags == (X509ChainStatusFlags.RevocationStatusUnknown |
                                X509ChainStatusFlags.OfflineRevocation));

    // The time moved past the intermediate's end.
    chain.ChainPolicy.RevocationMode = X509RevocationMode.NoCheck;
    chain.ChainPolicy.VerificationTime = 2100000000;
    Check("everything expired",
          !chain.Build(LoadFixture("good", GoodPem)) &&
          chain.StatusFlags == X509ChainStatusFlags.NotTimeValid &&
          chain.ChainElements[2u].StatusFlags == X509ChainStatusFlags.NoError);
}

/// A self-signed certificate is its own root, untrusted when it is no anchor,
/// and is not chained to an anchor that only shares its name. A developer's
/// `CN=localhost` in the system store is that anchor on some machines.
Result<bool, CryptoError> CheckTwinRoots()
{
    var trustedKey = try X509SignatureGenerator.CreateForEd25519(CreateFilledBytes(32u, 0x33));
    var strangerKey = try X509SignatureGenerator.CreateForEd25519(CreateFilledBytes(32u, 0x44));
    var trusted = try MintAuthority(trustedKey, "Twin", HashAlgorithmName.Sha256);
    var stranger = try MintAuthority(strangerKey, "Twin", HashAlgorithmName.Sha256);

    var chain = new X509Chain();
    chain.ChainPolicy.TrustMode = X509ChainTrustMode.CustomRootTrust;
    chain.ChainPolicy.CustomTrustStore.Add(trusted);
    bool built = chain.Build(stranger);
    Check("a twin of an anchor is an untrusted root",
          !built && chain.StatusFlags == X509ChainStatusFlags.UntrustedRoot);
    return Ok(true);
}
