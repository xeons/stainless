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

/// Why a TLS connection failed. `None` is success.
///
/// Each failure found here is also an alert sent to the peer, and the case
/// says which: `Decode` is `decode_error`, `BadRecordMac` is
/// `bad_record_mac`. A failure the peer found arrives as `AlertReceived`,
/// and the stream's `AlertDescription` says what it was.
public enum TlsError
{
    /// Nothing went wrong.
    None = 0,

    /// The two ends could not agree on anything this enum has a better name
    /// for. Sent as `handshake_failure`.
    HandshakeFailed,

    /// The peer speaks no version this end has enabled. Sent as
    /// `protocol_version`.
    ProtocolVersion,

    /// A message or record arrived where the protocol does not allow one.
    /// Sent as `unexpected_message`.
    UnexpectedMessage,

    /// A message is malformed: a length that disagrees with its contents, a
    /// field out of its range. Sent as `decode_error`.
    Decode,

    /// A record failed authentication. Sent as `bad_record_mac`.
    BadRecordMac,

    /// A record is longer than the protocol allows. Sent as `record_overflow`.
    RecordOverflow,

    /// A field is well formed and holds a value the protocol forbids there.
    /// Sent as `illegal_parameter`.
    IllegalParameter,

    /// The certificate validator refused the peer's certificate, or it could
    /// not be read. Sent as `bad_certificate`.
    CertificateRefused,

    /// The certificate holds a key of a type this end cannot use. Sent as
    /// `unsupported_certificate`.
    UnsupportedCertificate,

    /// The certificate validator found a certificate outside its validity
    /// period. Sent as `certificate_expired`.
    CertificateExpired,

    /// The certificate validator could not chain the certificate to an
    /// authority it trusts. Sent as `unknown_ca`.
    UnknownCertificateAuthority,

    /// The server asked for a client certificate and required one, and the
    /// client sent none. Sent as `certificate_required`.
    CertificateRequired,

    /// No cipher suite is offered by one end and accepted by the other. Sent
    /// as `handshake_failure`.
    NoCommonCipherSuite,

    /// No key-exchange group is offered by one end and accepted by the other.
    /// Sent as `handshake_failure`.
    NoCommonGroup,

    /// Both ends named application protocols and no name is on both lists.
    /// Sent as `no_application_protocol`.
    NoApplicationProtocol,

    /// A signature or a `Finished` did not verify. Sent as `decrypt_error`.
    DecryptError,

    /// A message lacks an extension the protocol requires in it. Sent as
    /// `missing_extension`.
    MissingExtension,

    /// The peer answered with an extension this end never offered. Sent as
    /// `unsupported_extension`.
    UnsupportedExtension,

    /// Something failed here that the peer had no part in: no entropy, a key
    /// that would not load. Sent as `internal_error`.
    InternalError,

    /// The transport ended without a `close_notify`, or the stream was used
    /// after `Close`. Nothing is sent.
    Closed,

    /// The peer sent a fatal alert. Nothing is sent back.
    AlertReceived,

    /// The stream underneath failed; its own `Error` says how. Nothing is
    /// sent, since there is nowhere to send it.
    Io,
}
