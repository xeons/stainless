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
import Standard.Time;

/// What a chain is built from and held to: .NET's `X509ChainPolicy`.
///
/// ```csharp
/// var policy = chain.ChainPolicy;
/// policy.TrustMode = X509ChainTrustMode.CustomRootTrust;
/// policy.CustomTrustStore.Add(root);
/// policy.ExtraStore.Add(intermediate);
/// policy.ApplicationPolicy.Add(X509EnhancedKeyUsageExtension.ServerAuthenticationOid);
/// policy.VerificationTime = 1790812800;
/// ```
public sealed class X509ChainPolicy
{
    private List<String> _applicationPolicy;
    private X509Certificate2Collection _extraStore;
    private X509Certificate2Collection _customTrustStore;
    private long _verificationTime;
    private bool _verificationTimeIgnored;

    /// The defaults: the system's roots, no extra certificates, no purpose
    /// required, no revocation, and the time of each `Build`.
    public X509ChainPolicy()
    {
        _applicationPolicy = new List<String>();
        _extraStore = new X509Certificate2Collection();
        _customTrustStore = new X509Certificate2Collection();
        TrustMode = X509ChainTrustMode.System;
        RevocationMode = X509RevocationMode.NoCheck;
        _verificationTime = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        _verificationTimeIgnored = true;
    }

    /// Purposes the leaf MUST serve, as dotted extended key usages; an
    /// intermediate that lists extended key usages MUST allow them too.
    /// Empty asks nothing.
    public List<String> ApplicationPolicy => _applicationPolicy;

    /// Intermediates to build through, as a server sends them. Nothing here
    /// is trusted for being here, and only the first 64 are read.
    public X509Certificate2Collection ExtraStore => _extraStore;

    /// The trust anchors when `TrustMode` is `CustomRootTrust`. Any
    /// certificate here is an anchor, self-signed or not.
    public X509Certificate2Collection CustomTrustStore => _customTrustStore;

    /// Where the anchors come from.
    public X509ChainTrustMode TrustMode { get; set; }

    /// Whether revocation is asked about; see `X509RevocationMode`.
    public X509RevocationMode RevocationMode { get; set; }

    /// The moment every certificate MUST be valid at, in seconds since the
    /// epoch, when `VerificationTimeIgnored` is false. Setting it clears
    /// `VerificationTimeIgnored`, as in .NET.
    public long VerificationTime
    {
        get => _verificationTime;
        set
        {
            _verificationTime = value;
            _verificationTimeIgnored = false;
        }
    }

    /// Whether each `Build` validates at the moment it runs rather than at
    /// `VerificationTime`. True until `VerificationTime` is set.
    public bool VerificationTimeIgnored
    {
        get => _verificationTimeIgnored;
        set => _verificationTimeIgnored = value;
    }

    /// Back to the defaults, with the time of each `Build`.
    public void Reset()
    {
        _applicationPolicy.Clear();
        _extraStore = new X509Certificate2Collection();
        _customTrustStore = new X509Certificate2Collection();
        TrustMode = X509ChainTrustMode.System;
        RevocationMode = X509RevocationMode.NoCheck;
        _verificationTime = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        _verificationTimeIgnored = true;
    }

    /// The moment a `Build` starting now validates at.
    internal long FindEffectiveVerificationTime() =>
        _verificationTimeIgnored ? DateTimeOffset.UtcNow.ToUnixTimeSeconds() : _verificationTime;
}
