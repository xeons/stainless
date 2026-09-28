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

module Standard.Net.Security;

/// What an alert says, with the numbers RFC 8446 §6 gives them.
///
/// In TLS 1.3 every alert but `CloseNotify` and `UserCanceled` ends the
/// connection, whatever level it was sent at.
public enum TlsAlertDescription : byte
{
    /// The sender will send nothing more. The orderly end of a connection.
    CloseNotify = 0,

    /// A message arrived where the protocol allows none.
    UnexpectedMessage = 10,

    /// A record failed authentication.
    BadRecordMac = 20,

    /// A record was longer than the protocol allows.
    RecordOverflow = 22,

    /// No acceptable set of parameters could be agreed.
    HandshakeFailure = 40,

    /// A certificate was corrupt or failed verification.
    BadCertificate = 42,

    /// A certificate was of a type the sender cannot use.
    UnsupportedCertificate = 43,

    /// A certificate was revoked by its signer.
    CertificateRevoked = 44,

    /// A certificate was outside its validity period.
    CertificateExpired = 45,

    /// A certificate was refused for a reason with no alert of its own.
    CertificateUnknown = 46,

    /// A field held a value the protocol forbids there.
    IllegalParameter = 47,

    /// A certificate chain led to no authority the sender trusts.
    UnknownCa = 48,

    /// Valid credentials that the sender's policy refuses.
    AccessDenied = 49,

    /// A message could not be parsed.
    DecodeError = 50,

    /// A signature or a `Finished` did not verify.
    DecryptError = 51,

    /// No protocol version was acceptable.
    ProtocolVersion = 70,

    /// The parameters on offer were all too weak for the sender.
    InsufficientSecurity = 71,

    /// The sender failed for a reason of its own.
    InternalError = 80,

    /// A retried connection offered less than the first one.
    InappropriateFallback = 86,

    /// The sender is abandoning the handshake, and will follow this with
    /// `CloseNotify`. Not fatal.
    UserCanceled = 90,

    /// A message lacked an extension that is required in it.
    MissingExtension = 109,

    /// An extension arrived that the receiver never offered.
    UnsupportedExtension = 110,

    /// No certificate is configured for the name the client asked for.
    UnrecognizedName = 112,

    /// An OCSP response was invalid.
    BadCertificateStatusResponse = 113,

    /// No key matches the offered pre-shared key identity.
    UnknownPskIdentity = 115,

    /// A server that requires a client certificate was sent none.
    CertificateRequired = 116,

    /// No application protocol offered by the client is supported.
    NoApplicationProtocol = 120,
}
