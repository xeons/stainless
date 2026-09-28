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

/// What is wrong with a chain or one certificate in it: .NET's
/// `X509ChainStatusFlags`, with .NET's values, and set in the same
/// circumstances wherever this module checks the same thing.
///
/// Flags .NET has and nothing here sets — the certificate trust list ones,
/// `NotTimeNested`, `Revoked`, the policy ones — are kept, so that a program
/// written against .NET's names compiles.
[Flags]
public enum X509ChainStatusFlags
{
    /// Nothing is wrong.
    NoError = 0,

    /// The verification time is before `NotBefore` or after `NotAfter`.
    NotTimeValid = 0x1,

    /// Never set; RFC 5280 does not require nesting.
    NotTimeNested = 0x2,

    /// Never set; there is no revocation checking.
    Revoked = 0x4,

    /// The signature does not verify under the issuer's key, or its algorithm
    /// is one this module does not verify.
    NotSignatureValid = 0x8,

    /// A key usage or extended key usage forbids what the chain was built for:
    /// an issuer without `KeyCertSign`, or a leaf or intermediate without the
    /// application policy asked for.
    NotValidForUsage = 0x10,

    /// The chain ends in a self-signed certificate that is not trusted.
    UntrustedRoot = 0x20,

    /// Revocation was asked for, and there is none to give.
    RevocationStatusUnknown = 0x40,

    /// Every path from the certificate loops back on itself.
    Cyclic = 0x80,

    /// A critical extension is one this module does not understand.
    InvalidExtension = 0x100,

    /// Never set; no policy is enforced.
    InvalidPolicyConstraints = 0x200,

    /// An issuer is not a CA, or more CAs stand below it than its path length
    /// allows.
    InvalidBasicConstraints = 0x400,

    /// Never set; a malformed name constraint does not parse at all.
    InvalidNameConstraints = 0x800,

    /// Never set; a constraint of an unenforced kind is passed over.
    HasNotSupportedNameConstraint = 0x1000,

    /// Never set.
    HasNotDefinedNameConstraint = 0x2000,

    /// A name of the leaf is outside every permitted subtree of its kind.
    HasNotPermittedNameConstraint = 0x4000,

    /// A name of the leaf is inside an excluded subtree.
    HasExcludedNameConstraint = 0x8000,

    /// No path reaches a trusted certificate.
    PartialChain = 0x10000,

    /// Never set.
    CtlNotTimeValid = 0x20000,

    /// Never set.
    CtlNotSignatureValid = 0x40000,

    /// Never set.
    CtlNotValidForUsage = 0x80000,

    /// A signature is made over SHA-1, which no longer resists collision.
    HasWeakSignature = 0x100000,

    /// Revocation was asked for, and nothing could be reached to answer it.
    OfflineRevocation = 0x1000000,

    /// Never set.
    NoIssuanceChainPolicy = 0x2000000,

    /// Never set.
    ExplicitDistrust = 0x4000000,

    /// A critical extension is one this module does not understand; set with
    /// `InvalidExtension`.
    HasNotSupportedCriticalExtension = 0x8000000,
}
