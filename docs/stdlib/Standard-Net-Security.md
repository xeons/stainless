# Standard.Net.Security

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

TLS 1.3, client and server, in Stainless and over any stream.

```csharp
var options = new TlsClientOptions();
options.CertificateValidator = PinnedLeaf;
options.ApplicationProtocols.Add("http/1.1");
var tls = try TlsSocket.Connect("example.com", 443u, options);
tls.Write(request, 0u, request.Length);

var server = new TlsServerOptions();
server.CertificateChain.Add(leafDer);
server.PrivateKey = try TlsSigningKey.ImportFromPem(keyPem);
var accepted = try TlsSocket.Accept(listener, server);
```

**The shape is `System.Net.Security`'s.** `TlsStream` is `SslStream`: an
`IStream` over another `IStream`, so it runs over a `TcpClient`, a proxy's
tunnel or anything else that carries bytes in order. It is made by
`AuthenticateAsClient` or `AuthenticateAsServer`, which return a `Result`
where .NET throws. `TlsSocket` owns its TCP connection as well, for the
common case.

**What is implemented** is RFC 8446 whole, less resumption: the three
AEAD suites; key exchange over X25519, P-256 and P-384, with a
HelloRetryRequest when the client guessed the wrong group; certificates
signed with Ed25519, ECDSA on P-256 or P-384, or RSA-PSS, on either side;
ALPN, server_name, KeyUpdate in both directions, the exporter, and the
middlebox compatibility mode. Session tickets are read and handed to
`TlsClientOptions.SessionTicketReceived`, and nothing yet offers one back.

**What is not:** TLS 1.2, which `TlsProtocolVersion.Tls12` names so that
options can already ask for it; resumption; a server that issues tickets;
and 0-RTT data, which is never coming, since it is replayable by design.

**Certificates are judged by a `TlsCertificateValidator`**, a closure the
options carry. The default refuses every chain, because X.509 path
validation is not in the library yet and a default that trusted anything
would be worse than none; a program pins the certificate it expects, or
supplies its own policy. The validator decides whom to trust; the
CertificateVerify signature against the leaf's key is always checked here.

**The record layer is constant time where a secret is involved.** The
AEADs check their tags in constant time, and the padding of a TLS 1.3
record is stripped by a scan over the whole record that selects by mask,
so how much of a record was padding does not show in how long it took.
Finished values are compared with `FixedTimeEquals`.

**Blocking, one reader and one writer.** A read blocks until a record of
application data arrives, and one thread MAY read while another writes;
every record written goes under one lock, because a read can write too:
the alert that ends a connection it found at fault. The KeyUpdate a peer
asks for is sent before the next application data written, as RFC 8446
§4.6.3 allows, so a reader that never writes never answers one.

## Contents

**Types** &nbsp; [TlsAlertDescription](#tlsalertdescription-enum) &middot; [TlsCertificateValidator](#tlscertificatevalidator-closure) &middot; [TlsCipherSuite](#tlsciphersuite-enum) &middot; [TlsClientOptions](#tlsclientoptions-class) &middot; [TlsError](#tlserror-enum) &middot; [TlsNamedGroup](#tlsnamedgroup-enum) &middot; [TlsProtocolVersion](#tlsprotocolversion-enum) &middot; [TlsServerOptions](#tlsserveroptions-class) &middot; [TlsSessionTicket](#tlssessionticket-class) &middot; [TlsSessionTicketHandler](#tlssessiontickethandler-closure) &middot; [TlsSignatureScheme](#tlssignaturescheme-enum) &middot; [TlsSigningKey](#tlssigningkey-class) &middot; [TlsSocket](#tlssocket-class) &middot; [TlsStream](#tlsstream-class)

**Functions** &nbsp; [DescribeTlsError](#describetlserror-function) &middot; [DiscardTlsSessionTicket](#discardtlssessionticket-function) &middot; [ValidateTlsCertificateChainByDefault](#validatetlscertificatechainbydefault-function)

## Types

### TlsAlertDescription *enum*

```
enum TlsAlertDescription : byte
```

What an alert says, with the numbers RFC 8446 §6 gives them.

In TLS 1.3 every alert but `CloseNotify` and `UserCanceled` ends the
connection, whatever level it was sent at.

<sub>[stdlib/Net/Security/TlsAlertDescription.sl:28](../../stdlib/Net/Security/TlsAlertDescription.sl#L28)</sub>

#### CloseNotify *case*

```
CloseNotify = 0
```

The sender will send nothing more. The orderly end of a connection.

<sub>[stdlib/Net/Security/TlsAlertDescription.sl:31](../../stdlib/Net/Security/TlsAlertDescription.sl#L31)</sub>

#### UnexpectedMessage *case*

```
UnexpectedMessage = 10
```

A message arrived where the protocol allows none.

<sub>[stdlib/Net/Security/TlsAlertDescription.sl:34](../../stdlib/Net/Security/TlsAlertDescription.sl#L34)</sub>

#### BadRecordMac *case*

```
BadRecordMac = 20
```

A record failed authentication.

<sub>[stdlib/Net/Security/TlsAlertDescription.sl:37](../../stdlib/Net/Security/TlsAlertDescription.sl#L37)</sub>

#### RecordOverflow *case*

```
RecordOverflow = 22
```

A record was longer than the protocol allows.

<sub>[stdlib/Net/Security/TlsAlertDescription.sl:40](../../stdlib/Net/Security/TlsAlertDescription.sl#L40)</sub>

#### HandshakeFailure *case*

```
HandshakeFailure = 40
```

No acceptable set of parameters could be agreed.

<sub>[stdlib/Net/Security/TlsAlertDescription.sl:43](../../stdlib/Net/Security/TlsAlertDescription.sl#L43)</sub>

#### BadCertificate *case*

```
BadCertificate = 42
```

A certificate was corrupt or failed verification.

<sub>[stdlib/Net/Security/TlsAlertDescription.sl:46](../../stdlib/Net/Security/TlsAlertDescription.sl#L46)</sub>

#### UnsupportedCertificate *case*

```
UnsupportedCertificate = 43
```

A certificate was of a type the sender cannot use.

<sub>[stdlib/Net/Security/TlsAlertDescription.sl:49](../../stdlib/Net/Security/TlsAlertDescription.sl#L49)</sub>

#### CertificateRevoked *case*

```
CertificateRevoked = 44
```

A certificate was revoked by its signer.

<sub>[stdlib/Net/Security/TlsAlertDescription.sl:52](../../stdlib/Net/Security/TlsAlertDescription.sl#L52)</sub>

#### CertificateExpired *case*

```
CertificateExpired = 45
```

A certificate was outside its validity period.

<sub>[stdlib/Net/Security/TlsAlertDescription.sl:55](../../stdlib/Net/Security/TlsAlertDescription.sl#L55)</sub>

#### CertificateUnknown *case*

```
CertificateUnknown = 46
```

A certificate was refused for a reason with no alert of its own.

<sub>[stdlib/Net/Security/TlsAlertDescription.sl:58](../../stdlib/Net/Security/TlsAlertDescription.sl#L58)</sub>

#### IllegalParameter *case*

```
IllegalParameter = 47
```

A field held a value the protocol forbids there.

<sub>[stdlib/Net/Security/TlsAlertDescription.sl:61](../../stdlib/Net/Security/TlsAlertDescription.sl#L61)</sub>

#### UnknownCa *case*

```
UnknownCa = 48
```

A certificate chain led to no authority the sender trusts.

<sub>[stdlib/Net/Security/TlsAlertDescription.sl:64](../../stdlib/Net/Security/TlsAlertDescription.sl#L64)</sub>

#### AccessDenied *case*

```
AccessDenied = 49
```

Valid credentials that the sender's policy refuses.

<sub>[stdlib/Net/Security/TlsAlertDescription.sl:67](../../stdlib/Net/Security/TlsAlertDescription.sl#L67)</sub>

#### DecodeError *case*

```
DecodeError = 50
```

A message could not be parsed.

<sub>[stdlib/Net/Security/TlsAlertDescription.sl:70](../../stdlib/Net/Security/TlsAlertDescription.sl#L70)</sub>

#### DecryptError *case*

```
DecryptError = 51
```

A signature or a `Finished` did not verify.

<sub>[stdlib/Net/Security/TlsAlertDescription.sl:73](../../stdlib/Net/Security/TlsAlertDescription.sl#L73)</sub>

#### ProtocolVersion *case*

```
ProtocolVersion = 70
```

No protocol version was acceptable.

<sub>[stdlib/Net/Security/TlsAlertDescription.sl:76](../../stdlib/Net/Security/TlsAlertDescription.sl#L76)</sub>

#### InsufficientSecurity *case*

```
InsufficientSecurity = 71
```

The parameters on offer were all too weak for the sender.

<sub>[stdlib/Net/Security/TlsAlertDescription.sl:79](../../stdlib/Net/Security/TlsAlertDescription.sl#L79)</sub>

#### InternalError *case*

```
InternalError = 80
```

The sender failed for a reason of its own.

<sub>[stdlib/Net/Security/TlsAlertDescription.sl:82](../../stdlib/Net/Security/TlsAlertDescription.sl#L82)</sub>

#### InappropriateFallback *case*

```
InappropriateFallback = 86
```

A retried connection offered less than the first one.

<sub>[stdlib/Net/Security/TlsAlertDescription.sl:85](../../stdlib/Net/Security/TlsAlertDescription.sl#L85)</sub>

#### UserCanceled *case*

```
UserCanceled = 90
```

The sender is abandoning the handshake, and will follow this with
`CloseNotify`. Not fatal.

<sub>[stdlib/Net/Security/TlsAlertDescription.sl:89](../../stdlib/Net/Security/TlsAlertDescription.sl#L89)</sub>

#### MissingExtension *case*

```
MissingExtension = 109
```

A message lacked an extension that is required in it.

<sub>[stdlib/Net/Security/TlsAlertDescription.sl:92](../../stdlib/Net/Security/TlsAlertDescription.sl#L92)</sub>

#### UnsupportedExtension *case*

```
UnsupportedExtension = 110
```

An extension arrived that the receiver never offered.

<sub>[stdlib/Net/Security/TlsAlertDescription.sl:95](../../stdlib/Net/Security/TlsAlertDescription.sl#L95)</sub>

#### UnrecognizedName *case*

```
UnrecognizedName = 112
```

No certificate is configured for the name the client asked for.

<sub>[stdlib/Net/Security/TlsAlertDescription.sl:98](../../stdlib/Net/Security/TlsAlertDescription.sl#L98)</sub>

#### BadCertificateStatusResponse *case*

```
BadCertificateStatusResponse = 113
```

An OCSP response was invalid.

<sub>[stdlib/Net/Security/TlsAlertDescription.sl:101](../../stdlib/Net/Security/TlsAlertDescription.sl#L101)</sub>

#### UnknownPskIdentity *case*

```
UnknownPskIdentity = 115
```

No key matches the offered pre-shared key identity.

<sub>[stdlib/Net/Security/TlsAlertDescription.sl:104](../../stdlib/Net/Security/TlsAlertDescription.sl#L104)</sub>

#### CertificateRequired *case*

```
CertificateRequired = 116
```

A server that requires a client certificate was sent none.

<sub>[stdlib/Net/Security/TlsAlertDescription.sl:107](../../stdlib/Net/Security/TlsAlertDescription.sl#L107)</sub>

#### NoApplicationProtocol *case*

```
NoApplicationProtocol = 120
```

No application protocol offered by the client is supported.

<sub>[stdlib/Net/Security/TlsAlertDescription.sl:110](../../stdlib/Net/Security/TlsAlertDescription.sl#L110)</sub>

### TlsCertificateValidator *closure*

```
closure TlsError TlsCertificateValidator(List<byte[]> chain, String targetHost)
```

Decides whether the peer's certificate chain is to be trusted.

`chain` is the certificates as the peer sent them, each in DER, the leaf
first. `targetHost` is the name the client asked for: what a server
certificate MUST be valid for, and empty when a server is judging a client.
The answer is `TlsError.None` to go on; anything else ends the handshake
and is sent to the peer as that error's alert, so `CertificateExpired`
and `UnknownCertificateAuthority` are the precise refusals and
`CertificateRefused` the general one.

The validator is asked before the CertificateVerify signature is checked,
and the signature is then checked against the leaf whatever it answered.

<sub>[stdlib/Net/Security/TlsCertificateValidator.sl:38](../../stdlib/Net/Security/TlsCertificateValidator.sl#L38)</sub>

### TlsCipherSuite *enum*

```
enum TlsCipherSuite : ushort
```

A cipher suite, with the number IANA gives it.

The names are IANA's in this library's casing: `TLS_AES_128_GCM_SHA256`
is `TlsAes128GcmSha256`. A TLS 1.3 suite names the record protection and
the hash of the key schedule, and nothing else.

<sub>[stdlib/Net/Security/TlsCipherSuite.sl:29](../../stdlib/Net/Security/TlsCipherSuite.sl#L29)</sub>

#### TlsAes128GcmSha256 *case*

```
TlsAes128GcmSha256 = 4865
```

AES-128 in GCM, with SHA-256. The suite every TLS 1.3 peer MUST
implement.

<sub>[stdlib/Net/Security/TlsCipherSuite.sl:33](../../stdlib/Net/Security/TlsCipherSuite.sl#L33)</sub>

#### TlsAes256GcmSha384 *case*

```
TlsAes256GcmSha384 = 4866
```

AES-256 in GCM, with SHA-384.

<sub>[stdlib/Net/Security/TlsCipherSuite.sl:36](../../stdlib/Net/Security/TlsCipherSuite.sl#L36)</sub>

#### TlsChaCha20Poly1305Sha256 *case*

```
TlsChaCha20Poly1305Sha256 = 4867
```

ChaCha20 and Poly1305, with SHA-256. About three times as fast as the
AES suites here, since AES runs in software.

<sub>[stdlib/Net/Security/TlsCipherSuite.sl:40](../../stdlib/Net/Security/TlsCipherSuite.sl#L40)</sub>

### TlsClientOptions *class*

```
sealed class TlsClientOptions
```

How a client connects: the name it wants, what it offers, and how it
decides to trust the answer.

    var options = new TlsClientOptions();
    options.TargetHost = "example.com";
    options.ApplicationProtocols.Add("http/1.1");
    options.CertificateValidator = PinnedLeaf;

.NET's `SslClientAuthenticationOptions`, with the lists this library can
negotiate spelled out rather than left to the platform.

<sub>[stdlib/Net/Security/TlsClientOptions.sl:36](../../stdlib/Net/Security/TlsClientOptions.sl#L36)</sub>

#### TargetHost *property*

```
String TargetHost { get; set; }
```

The server's name: sent as server_name unless it is a literal
address, and handed to the validator as the name the certificate MUST
be valid for.

<sub>[stdlib/Net/Security/TlsClientOptions.sl:41](../../stdlib/Net/Security/TlsClientOptions.sl#L41)</sub>

#### ApplicationProtocols *property*

```
List<String> ApplicationProtocols { get; set; }
```

ALPN protocol names to offer, most preferred first. Empty offers none.

<sub>[stdlib/Net/Security/TlsClientOptions.sl:44](../../stdlib/Net/Security/TlsClientOptions.sl#L44)</sub>

#### EnabledProtocols *property*

```
TlsProtocolVersion EnabledProtocols { get; set; }
```

Which versions may be negotiated. TLS 1.2 is accepted here and not yet
implemented, so only a TLS 1.3 server is reached.

<sub>[stdlib/Net/Security/TlsClientOptions.sl:48](../../stdlib/Net/Security/TlsClientOptions.sl#L48)</sub>

#### CipherSuites *property*

```
List<TlsCipherSuite> CipherSuites { get; set; }
```

Suites to offer, most preferred first.

<sub>[stdlib/Net/Security/TlsClientOptions.sl:52](../../stdlib/Net/Security/TlsClientOptions.sl#L52)</sub>

#### KeyExchangeGroups *property*

```
List<TlsNamedGroup> KeyExchangeGroups { get; set; }
```

Groups to offer for the key exchange, most preferred first.

<sub>[stdlib/Net/Security/TlsClientOptions.sl:55](../../stdlib/Net/Security/TlsClientOptions.sl#L55)</sub>

#### KeyShareGroups *property*

```
List<TlsNamedGroup> KeyShareGroups { get; set; }
```

Groups to send a key share for in the first ClientHello. Each MUST be
in `KeyExchangeGroups`. A server that wants another group asks for it
with a HelloRetryRequest, which costs a round trip.

<sub>[stdlib/Net/Security/TlsClientOptions.sl:60](../../stdlib/Net/Security/TlsClientOptions.sl#L60)</sub>

#### CertificateValidator *property*

```
TlsCertificateValidator CertificateValidator { get; set; }
```

Decides whether to trust the server's chain. The default refuses every
chain until X.509 validation is in this library.

**See also** &nbsp; [ValidateTlsCertificateChainByDefault](#validatetlscertificatechainbydefault-function)

<sub>[stdlib/Net/Security/TlsClientOptions.sl:66](../../stdlib/Net/Security/TlsClientOptions.sl#L66)</sub>

#### ClientCertificateChain *property*

```
List<byte[]> ClientCertificateChain { get; set; }
```

The client's certificates, DER, leaf first, sent when a server asks.
Empty sends an empty Certificate, which a server MAY refuse.

<sub>[stdlib/Net/Security/TlsClientOptions.sl:71](../../stdlib/Net/Security/TlsClientOptions.sl#L71)</sub>

#### ClientPrivateKey *property*

```
TlsSigningKey? ClientPrivateKey { get; set; }
```

The key of the client's leaf certificate.

<sub>[stdlib/Net/Security/TlsClientOptions.sl:74](../../stdlib/Net/Security/TlsClientOptions.sl#L74)</sub>

#### SessionTicketReceived *property*

```
TlsSessionTicketHandler SessionTicketReceived { get; set; }
```

Given each session ticket the server sends. Resumption is not
implemented yet; this is where a cache would collect them.

<sub>[stdlib/Net/Security/TlsClientOptions.sl:78](../../stdlib/Net/Security/TlsClientOptions.sl#L78)</sub>

#### LeaveInnerStreamOpen *property*

```
bool LeaveInnerStreamOpen { get; set; }
```

Whether `Close` leaves the stream underneath open.

<sub>[stdlib/Net/Security/TlsClientOptions.sl:81](../../stdlib/Net/Security/TlsClientOptions.sl#L81)</sub>

### TlsError *enum*

```
enum TlsError
```

Why a TLS connection failed. `None` is success.

Each failure found here is also an alert sent to the peer, and the case
says which: `Decode` is `decode_error`, `BadRecordMac` is
`bad_record_mac`. A failure the peer found arrives as `AlertReceived`,
and the stream's `AlertDescription` says what it was.

<sub>[stdlib/Net/Security/TlsError.sl:30](../../stdlib/Net/Security/TlsError.sl#L30)</sub>

#### None *case*

```
None = 0
```

Nothing went wrong.

<sub>[stdlib/Net/Security/TlsError.sl:33](../../stdlib/Net/Security/TlsError.sl#L33)</sub>

#### HandshakeFailed *case*

```
HandshakeFailed
```

The two ends could not agree on anything this enum has a better name
for. Sent as `handshake_failure`.

<sub>[stdlib/Net/Security/TlsError.sl:37](../../stdlib/Net/Security/TlsError.sl#L37)</sub>

#### ProtocolVersion *case*

```
ProtocolVersion
```

The peer speaks no version this end has enabled. Sent as
`protocol_version`.

<sub>[stdlib/Net/Security/TlsError.sl:41](../../stdlib/Net/Security/TlsError.sl#L41)</sub>

#### UnexpectedMessage *case*

```
UnexpectedMessage
```

A message or record arrived where the protocol does not allow one.
Sent as `unexpected_message`.

<sub>[stdlib/Net/Security/TlsError.sl:45](../../stdlib/Net/Security/TlsError.sl#L45)</sub>

#### Decode *case*

```
Decode
```

A message is malformed: a length that disagrees with its contents, a
field out of its range. Sent as `decode_error`.

<sub>[stdlib/Net/Security/TlsError.sl:49](../../stdlib/Net/Security/TlsError.sl#L49)</sub>

#### BadRecordMac *case*

```
BadRecordMac
```

A record failed authentication. Sent as `bad_record_mac`.

<sub>[stdlib/Net/Security/TlsError.sl:52](../../stdlib/Net/Security/TlsError.sl#L52)</sub>

#### RecordOverflow *case*

```
RecordOverflow
```

A record is longer than the protocol allows. Sent as `record_overflow`.

<sub>[stdlib/Net/Security/TlsError.sl:55](../../stdlib/Net/Security/TlsError.sl#L55)</sub>

#### IllegalParameter *case*

```
IllegalParameter
```

A field is well formed and holds a value the protocol forbids there.
Sent as `illegal_parameter`.

<sub>[stdlib/Net/Security/TlsError.sl:59](../../stdlib/Net/Security/TlsError.sl#L59)</sub>

#### CertificateRefused *case*

```
CertificateRefused
```

The certificate validator refused the peer's certificate, or it could
not be read. Sent as `bad_certificate`.

<sub>[stdlib/Net/Security/TlsError.sl:63](../../stdlib/Net/Security/TlsError.sl#L63)</sub>

#### UnsupportedCertificate *case*

```
UnsupportedCertificate
```

The certificate holds a key of a type this end cannot use. Sent as
`unsupported_certificate`.

<sub>[stdlib/Net/Security/TlsError.sl:67](../../stdlib/Net/Security/TlsError.sl#L67)</sub>

#### CertificateExpired *case*

```
CertificateExpired
```

The certificate validator found a certificate outside its validity
period. Sent as `certificate_expired`.

<sub>[stdlib/Net/Security/TlsError.sl:71](../../stdlib/Net/Security/TlsError.sl#L71)</sub>

#### UnknownCertificateAuthority *case*

```
UnknownCertificateAuthority
```

The certificate validator could not chain the certificate to an
authority it trusts. Sent as `unknown_ca`.

<sub>[stdlib/Net/Security/TlsError.sl:75](../../stdlib/Net/Security/TlsError.sl#L75)</sub>

#### CertificateRequired *case*

```
CertificateRequired
```

The server asked for a client certificate and required one, and the
client sent none. Sent as `certificate_required`.

<sub>[stdlib/Net/Security/TlsError.sl:79](../../stdlib/Net/Security/TlsError.sl#L79)</sub>

#### NoCommonCipherSuite *case*

```
NoCommonCipherSuite
```

No cipher suite is offered by one end and accepted by the other. Sent
as `handshake_failure`.

<sub>[stdlib/Net/Security/TlsError.sl:83](../../stdlib/Net/Security/TlsError.sl#L83)</sub>

#### NoCommonGroup *case*

```
NoCommonGroup
```

No key-exchange group is offered by one end and accepted by the other.
Sent as `handshake_failure`.

<sub>[stdlib/Net/Security/TlsError.sl:87](../../stdlib/Net/Security/TlsError.sl#L87)</sub>

#### NoApplicationProtocol *case*

```
NoApplicationProtocol
```

Both ends named application protocols and no name is on both lists.
Sent as `no_application_protocol`.

<sub>[stdlib/Net/Security/TlsError.sl:91](../../stdlib/Net/Security/TlsError.sl#L91)</sub>

#### DecryptError *case*

```
DecryptError
```

A signature or a `Finished` did not verify. Sent as `decrypt_error`.

<sub>[stdlib/Net/Security/TlsError.sl:94](../../stdlib/Net/Security/TlsError.sl#L94)</sub>

#### MissingExtension *case*

```
MissingExtension
```

A message lacks an extension the protocol requires in it. Sent as
`missing_extension`.

<sub>[stdlib/Net/Security/TlsError.sl:98](../../stdlib/Net/Security/TlsError.sl#L98)</sub>

#### UnsupportedExtension *case*

```
UnsupportedExtension
```

The peer answered with an extension this end never offered. Sent as
`unsupported_extension`.

<sub>[stdlib/Net/Security/TlsError.sl:102](../../stdlib/Net/Security/TlsError.sl#L102)</sub>

#### InternalError *case*

```
InternalError
```

Something failed here that the peer had no part in: no entropy, a key
that would not load. Sent as `internal_error`.

<sub>[stdlib/Net/Security/TlsError.sl:106](../../stdlib/Net/Security/TlsError.sl#L106)</sub>

#### Closed *case*

```
Closed
```

The transport ended without a `close_notify`, or the stream was used
after `Close`. Nothing is sent.

<sub>[stdlib/Net/Security/TlsError.sl:110](../../stdlib/Net/Security/TlsError.sl#L110)</sub>

#### AlertReceived *case*

```
AlertReceived
```

The peer sent a fatal alert. Nothing is sent back.

<sub>[stdlib/Net/Security/TlsError.sl:113](../../stdlib/Net/Security/TlsError.sl#L113)</sub>

#### Io *case*

```
Io
```

The stream underneath failed; its own `Error` says how. Nothing is
sent, since there is nowhere to send it.

<sub>[stdlib/Net/Security/TlsError.sl:117](../../stdlib/Net/Security/TlsError.sl#L117)</sub>

### TlsNamedGroup *enum*

```
enum TlsNamedGroup : ushort
```

A group for the ephemeral key exchange, with the number IANA gives it.

<sub>[stdlib/Net/Security/TlsNamedGroup.sl:25](../../stdlib/Net/Security/TlsNamedGroup.sl#L25)</sub>

#### Secp256r1 *case*

```
Secp256r1 = 23
```

NIST P-256, as `secp256r1`.

<sub>[stdlib/Net/Security/TlsNamedGroup.sl:28](../../stdlib/Net/Security/TlsNamedGroup.sl#L28)</sub>

#### Secp384r1 *case*

```
Secp384r1 = 24
```

NIST P-384, as `secp384r1`.

<sub>[stdlib/Net/Security/TlsNamedGroup.sl:31](../../stdlib/Net/Security/TlsNamedGroup.sl#L31)</sub>

#### X25519 *case*

```
X25519 = 29
```

Curve25519 in Montgomery form, RFC 7748.

<sub>[stdlib/Net/Security/TlsNamedGroup.sl:34](../../stdlib/Net/Security/TlsNamedGroup.sl#L34)</sub>

### TlsProtocolVersion *enum*

```
enum TlsProtocolVersion
```

Versions of TLS, as bits so that a set of them can be enabled at once.

**See also** &nbsp; [TlsClientOptions.EnabledProtocols](#enabledprotocols-property)

<sub>[stdlib/Net/Security/TlsProtocolVersion.sl:27](../../stdlib/Net/Security/TlsProtocolVersion.sl#L27)</sub>

#### None *case*

```
None = 0
```

No version: what a set with nothing in it holds.

<sub>[stdlib/Net/Security/TlsProtocolVersion.sl:31](../../stdlib/Net/Security/TlsProtocolVersion.sl#L31)</sub>

#### Tls12 *case*

```
Tls12 = 1
```

TLS 1.2, RFC 5246. Named so that a set can hold it; no connection is
made in it yet, and a peer that offers nothing newer is refused.

<sub>[stdlib/Net/Security/TlsProtocolVersion.sl:35](../../stdlib/Net/Security/TlsProtocolVersion.sl#L35)</sub>

#### Tls13 *case*

```
Tls13 = 2
```

TLS 1.3, RFC 8446.

<sub>[stdlib/Net/Security/TlsProtocolVersion.sl:38](../../stdlib/Net/Security/TlsProtocolVersion.sl#L38)</sub>

### TlsServerOptions *class*

```
sealed class TlsServerOptions
```

How a server answers: its certificate and key, what it accepts, and
whether it asks the client to authenticate.

    var options = new TlsServerOptions();
    options.CertificateChain.Add(leafDer);
    options.PrivateKey = try TlsSigningKey.ImportFromPem(keyPem);

The lists are in the server's order of preference, and the server's
preference decides: the first suite, group and protocol on its list that
the client also offered.

<sub>[stdlib/Net/Security/TlsServerOptions.sl:36](../../stdlib/Net/Security/TlsServerOptions.sl#L36)</sub>

#### CertificateChain *property*

```
List<byte[]> CertificateChain { get; set; }
```

The server's certificates, DER, leaf first. It MUST NOT be empty.

<sub>[stdlib/Net/Security/TlsServerOptions.sl:39](../../stdlib/Net/Security/TlsServerOptions.sl#L39)</sub>

#### PrivateKey *property*

```
TlsSigningKey? PrivateKey { get; set; }
```

The key of the leaf certificate.

<sub>[stdlib/Net/Security/TlsServerOptions.sl:42](../../stdlib/Net/Security/TlsServerOptions.sl#L42)</sub>

#### ApplicationProtocols *property*

```
List<String> ApplicationProtocols { get; set; }
```

ALPN protocol names this server speaks, most preferred first. When
both ends name protocols and none is shared, the handshake fails with
`NoApplicationProtocol`.

<sub>[stdlib/Net/Security/TlsServerOptions.sl:47](../../stdlib/Net/Security/TlsServerOptions.sl#L47)</sub>

#### EnabledProtocols *property*

```
TlsProtocolVersion EnabledProtocols { get; set; }
```

Which versions may be negotiated. TLS 1.2 is accepted here and not yet
implemented, so a client that offers only TLS 1.2 is refused.

<sub>[stdlib/Net/Security/TlsServerOptions.sl:51](../../stdlib/Net/Security/TlsServerOptions.sl#L51)</sub>

#### CipherSuites *property*

```
List<TlsCipherSuite> CipherSuites { get; set; }
```

Suites to accept, most preferred first.

<sub>[stdlib/Net/Security/TlsServerOptions.sl:55](../../stdlib/Net/Security/TlsServerOptions.sl#L55)</sub>

#### KeyExchangeGroups *property*

```
List<TlsNamedGroup> KeyExchangeGroups { get; set; }
```

Groups to accept, most preferred first. A client that sent no share
in any of them is asked for one with a HelloRetryRequest.

<sub>[stdlib/Net/Security/TlsServerOptions.sl:59](../../stdlib/Net/Security/TlsServerOptions.sl#L59)</sub>

#### ClientCertificateRequested *property*

```
bool ClientCertificateRequested { get; set; }
```

Whether to ask the client for a certificate. It MAY send none.

<sub>[stdlib/Net/Security/TlsServerOptions.sl:62](../../stdlib/Net/Security/TlsServerOptions.sl#L62)</sub>

#### ClientCertificateRequired *property*

```
bool ClientCertificateRequired { get; set; }
```

Whether to ask for a client certificate and refuse a client that sends
none, with `CertificateRequired`. Implies `ClientCertificateRequested`.

<sub>[stdlib/Net/Security/TlsServerOptions.sl:66](../../stdlib/Net/Security/TlsServerOptions.sl#L66)</sub>

#### ClientCertificateValidator *property*

```
TlsCertificateValidator ClientCertificateValidator { get; set; }
```

Decides whether to trust a client's chain. The target host it is given
is empty. The default refuses every chain.

<sub>[stdlib/Net/Security/TlsServerOptions.sl:70](../../stdlib/Net/Security/TlsServerOptions.sl#L70)</sub>

#### LeaveInnerStreamOpen *property*

```
bool LeaveInnerStreamOpen { get; set; }
```

Whether `Close` leaves the stream underneath open.

<sub>[stdlib/Net/Security/TlsServerOptions.sl:74](../../stdlib/Net/Security/TlsServerOptions.sl#L74)</sub>

### TlsSessionTicket *class*

```
sealed class TlsSessionTicket
```

A session ticket (RFC 8446 §4.6.1), and the pre-shared key it stands for.

Nothing here resumes a session yet. A cache can keep these now, and
resumption will offer them back.

<sub>[stdlib/Net/Security/TlsSessionTicket.sl:31](../../stdlib/Net/Security/TlsSessionTicket.sl#L31)</sub>

#### CipherSuite *property*

```
TlsCipherSuite CipherSuite { get; }
```

The suite of the connection that issued it, whose hash a resumption
MUST use.

<sub>[stdlib/Net/Security/TlsSessionTicket.sl:58](../../stdlib/Net/Security/TlsSessionTicket.sl#L58)</sub>

#### TargetHost *property*

```
String TargetHost { get; }
```

The name the connection was made to.

<sub>[stdlib/Net/Security/TlsSessionTicket.sl:61](../../stdlib/Net/Security/TlsSessionTicket.sl#L61)</sub>

#### Lifetime *property*

```
uint Lifetime { get; }
```

How many seconds the server will honour it for, at most a week.

<sub>[stdlib/Net/Security/TlsSessionTicket.sl:64](../../stdlib/Net/Security/TlsSessionTicket.sl#L64)</sub>

#### AgeAdd *property*

```
uint AgeAdd { get; }
```

What obscures the ticket's age when it is offered back.

<sub>[stdlib/Net/Security/TlsSessionTicket.sl:67](../../stdlib/Net/Security/TlsSessionTicket.sl#L67)</sub>

#### Nonce *property*

```
byte[] Nonce { get; }
```

The per-ticket value the key is derived with.

<sub>[stdlib/Net/Security/TlsSessionTicket.sl:70](../../stdlib/Net/Security/TlsSessionTicket.sl#L70)</sub>

#### Ticket *property*

```
byte[] Ticket { get; }
```

The server's opaque label for the session.

<sub>[stdlib/Net/Security/TlsSessionTicket.sl:73](../../stdlib/Net/Security/TlsSessionTicket.sl#L73)</sub>

#### ResumptionKey *property*

```
byte[] ResumptionKey { get; }
```

The pre-shared key: HKDF-Expand-Label of the resumption master secret
over the nonce. **A secret**, and to be kept as one.

<sub>[stdlib/Net/Security/TlsSessionTicket.sl:77](../../stdlib/Net/Security/TlsSessionTicket.sl#L77)</sub>

#### MaxEarlyDataSize *property*

```
uint MaxEarlyDataSize { get; }
```

How much 0-RTT data the server would take, or zero. 0-RTT is never
sent by this library.

<sub>[stdlib/Net/Security/TlsSessionTicket.sl:81](../../stdlib/Net/Security/TlsSessionTicket.sl#L81)</sub>

### TlsSessionTicketHandler *closure*

```
closure void TlsSessionTicketHandler(TlsSessionTicket ticket)
```

Receives each session ticket a server sends after the handshake.

<sub>[stdlib/Net/Security/TlsSessionTicket.sl:25](../../stdlib/Net/Security/TlsSessionTicket.sl#L25)</sub>

### TlsSignatureScheme *enum*

```
enum TlsSignatureScheme : ushort
```

A signature algorithm and its hash, with the number IANA gives it.

Each of the ECDSA schemes names its curve as well as its hash, and the
RSA-PSS schemes are split by the kind of key: `RsaPssRsae` for a key
published as `rsaEncryption` and `RsaPssPss` for one published as
`RSASSA-PSS`. PKCS #1 v1.5 is accepted in certificates and never in a
handshake signature.

<sub>[stdlib/Net/Security/TlsSignatureScheme.sl:31](../../stdlib/Net/Security/TlsSignatureScheme.sl#L31)</sub>

#### RsaPkcs1Sha256 *case*

```
RsaPkcs1Sha256 = 1025
```

RSA with PKCS #1 v1.5 padding and SHA-256. Certificates only.

<sub>[stdlib/Net/Security/TlsSignatureScheme.sl:34](../../stdlib/Net/Security/TlsSignatureScheme.sl#L34)</sub>

#### RsaPkcs1Sha384 *case*

```
RsaPkcs1Sha384 = 1281
```

RSA with PKCS #1 v1.5 padding and SHA-384. Certificates only.

<sub>[stdlib/Net/Security/TlsSignatureScheme.sl:37](../../stdlib/Net/Security/TlsSignatureScheme.sl#L37)</sub>

#### RsaPkcs1Sha512 *case*

```
RsaPkcs1Sha512 = 1537
```

RSA with PKCS #1 v1.5 padding and SHA-512. Certificates only.

<sub>[stdlib/Net/Security/TlsSignatureScheme.sl:40](../../stdlib/Net/Security/TlsSignatureScheme.sl#L40)</sub>

#### EcdsaSecp256r1Sha256 *case*

```
EcdsaSecp256r1Sha256 = 1027
```

ECDSA on P-256 with SHA-256.

<sub>[stdlib/Net/Security/TlsSignatureScheme.sl:43](../../stdlib/Net/Security/TlsSignatureScheme.sl#L43)</sub>

#### EcdsaSecp384r1Sha384 *case*

```
EcdsaSecp384r1Sha384 = 1283
```

ECDSA on P-384 with SHA-384.

<sub>[stdlib/Net/Security/TlsSignatureScheme.sl:46](../../stdlib/Net/Security/TlsSignatureScheme.sl#L46)</sub>

#### EcdsaSecp521r1Sha512 *case*

```
EcdsaSecp521r1Sha512 = 1539
```

ECDSA on P-521 with SHA-512. Named and never offered: there is no
P-521 here.

<sub>[stdlib/Net/Security/TlsSignatureScheme.sl:50](../../stdlib/Net/Security/TlsSignatureScheme.sl#L50)</sub>

#### RsaPssRsaeSha256 *case*

```
RsaPssRsaeSha256 = 2052
```

RSA-PSS with SHA-256, for an `rsaEncryption` key.

<sub>[stdlib/Net/Security/TlsSignatureScheme.sl:53](../../stdlib/Net/Security/TlsSignatureScheme.sl#L53)</sub>

#### RsaPssRsaeSha384 *case*

```
RsaPssRsaeSha384 = 2053
```

RSA-PSS with SHA-384, for an `rsaEncryption` key.

<sub>[stdlib/Net/Security/TlsSignatureScheme.sl:56](../../stdlib/Net/Security/TlsSignatureScheme.sl#L56)</sub>

#### RsaPssRsaeSha512 *case*

```
RsaPssRsaeSha512 = 2054
```

RSA-PSS with SHA-512, for an `rsaEncryption` key.

<sub>[stdlib/Net/Security/TlsSignatureScheme.sl:59](../../stdlib/Net/Security/TlsSignatureScheme.sl#L59)</sub>

#### Ed25519 *case*

```
Ed25519 = 2055
```

Ed25519, RFC 8032.

<sub>[stdlib/Net/Security/TlsSignatureScheme.sl:62](../../stdlib/Net/Security/TlsSignatureScheme.sl#L62)</sub>

#### Ed448 *case*

```
Ed448 = 2056
```

Ed448. Named and never offered.

<sub>[stdlib/Net/Security/TlsSignatureScheme.sl:65](../../stdlib/Net/Security/TlsSignatureScheme.sl#L65)</sub>

#### RsaPssPssSha256 *case*

```
RsaPssPssSha256 = 2057
```

RSA-PSS with SHA-256, for an `RSASSA-PSS` key.

<sub>[stdlib/Net/Security/TlsSignatureScheme.sl:68](../../stdlib/Net/Security/TlsSignatureScheme.sl#L68)</sub>

#### RsaPssPssSha384 *case*

```
RsaPssPssSha384 = 2058
```

RSA-PSS with SHA-384, for an `RSASSA-PSS` key.

<sub>[stdlib/Net/Security/TlsSignatureScheme.sl:71](../../stdlib/Net/Security/TlsSignatureScheme.sl#L71)</sub>

#### RsaPssPssSha512 *case*

```
RsaPssPssSha512 = 2059
```

RSA-PSS with SHA-512, for an `RSASSA-PSS` key.

<sub>[stdlib/Net/Security/TlsSignatureScheme.sl:74](../../stdlib/Net/Security/TlsSignatureScheme.sl#L74)</sub>

### TlsSigningKey *class*

```
sealed class TlsSigningKey
```

The private key that signs a CertificateVerify: Ed25519, ECDSA on P-256
or P-384, or RSA with PSS.

    var key = try TlsSigningKey.ImportFromPem(File.ReadAllText("server.key"));
    options.PrivateKey = key;

It MUST be the key of the leaf certificate it is configured beside; a
mismatch is found by the peer, as a signature that does not verify.

<sub>[stdlib/Net/Security/TlsSigningKey.sl:36](../../stdlib/Net/Security/TlsSigningKey.sl#L36)</sub>

#### FromEd25519PrivateKey *method*

```
static Result<TlsSigningKey, CryptoError> FromEd25519PrivateKey(ReadOnlySpan<byte> privateKey)
```

An Ed25519 key from its 32-byte seed, RFC 8032's private key.

**Fails with**

- [CryptoError.KeyLength](Standard-Security-Cryptography.md#keylength-case) — `privateKey` is not 32 bytes

<sub>[stdlib/Net/Security/TlsSigningKey.sl:54](../../stdlib/Net/Security/TlsSigningKey.sl#L54)</sub>

#### FromECDsa *method*

```
static Result<TlsSigningKey, CryptoError> FromECDsa(ECDsa key)
```

An ECDSA key, which MUST hold its private half and be on P-256 or
P-384.

**Fails with**

- [CryptoError.InvalidKey](Standard-Security-Cryptography.md#invalidkey-case) — `key` is a public key

<sub>[stdlib/Net/Security/TlsSigningKey.sl:66](../../stdlib/Net/Security/TlsSigningKey.sl#L66)</sub>

#### FromRsa *method*

```
static Result<TlsSigningKey, CryptoError> FromRsa(Rsa key)
```

An RSA key published as `rsaEncryption`, which signs with the
`RsaPssRsae` schemes.

**Fails with**

- [CryptoError.InvalidKey](Standard-Security-Cryptography.md#invalidkey-case) — `key` is a public key

<sub>[stdlib/Net/Security/TlsSigningKey.sl:79](../../stdlib/Net/Security/TlsSigningKey.sl#L79)</sub>

#### FromRsaPss *method*

```
static Result<TlsSigningKey, CryptoError> FromRsaPss(Rsa key)
```

An RSA key published as `RSASSA-PSS`, which signs with the
`RsaPssPss` schemes.

**Fails with**

- [CryptoError.InvalidKey](Standard-Security-Cryptography.md#invalidkey-case) — `key` is a public key

<sub>[stdlib/Net/Security/TlsSigningKey.sl:90](../../stdlib/Net/Security/TlsSigningKey.sl#L90)</sub>

#### ImportFromPem *method*

```
static Result<TlsSigningKey, CryptoError> ImportFromPem(String input)
```

The key in a PEM block: `PRIVATE KEY` (PKCS #8, for any of the four
kinds), `EC PRIVATE KEY` or `RSA PRIVATE KEY`. The first such block is
used; certificates beside it are passed over.

**Fails with**

- [CryptoError.Encoding](Standard-Security-Cryptography.md#encoding-case) — no key block, or one that does not parse
- [CryptoError.Unsupported](Standard-Security-Cryptography.md#unsupported-case) — a key of another algorithm, or an encrypted one
- [CryptoError.InvalidKey](Standard-Security-Cryptography.md#invalidkey-case) — the numbers are not a consistent key

<sub>[stdlib/Net/Security/TlsSigningKey.sl:105](../../stdlib/Net/Security/TlsSigningKey.sl#L105)</sub>

#### ImportPkcs8PrivateKey *method*

```
static Result<TlsSigningKey, CryptoError> ImportPkcs8PrivateKey(ReadOnlySpan<byte> source)
```

The key in an unencrypted PKCS #8 `PrivateKeyInfo`, DER.

**Fails with**

- [CryptoError.Encoding](Standard-Security-Cryptography.md#encoding-case) — not a `PrivateKeyInfo`
- [CryptoError.Unsupported](Standard-Security-Cryptography.md#unsupported-case) — a key of another algorithm
- [CryptoError.InvalidKey](Standard-Security-Cryptography.md#invalidkey-case) — the numbers are not a consistent key

<sub>[stdlib/Net/Security/TlsSigningKey.sl:139](../../stdlib/Net/Security/TlsSigningKey.sl#L139)</sub>

### TlsSocket *class*

```
sealed class TlsSocket : IStream
```

A TLS connection that owns its TCP connection: `TcpClient` and
`TlsStream` as one thing, and an `IStream`.

    var options = new TlsClientOptions();
    options.CertificateValidator = PinnedLeaf;
    var socket = try TlsSocket.Connect("example.com", 443u, options);

`Client` is the TCP connection, for its timeouts and its end points.
Everything else is the `TlsStream`'s, and `Stream` is that.

<sub>[stdlib/Net/Security/TlsSocket.sl:37](../../stdlib/Net/Security/TlsSocket.sl#L37)</sub>

#### Connect *method*

```
static Result<TlsSocket, TlsError> Connect(String host, ushort port, TlsClientOptions options)
```

Connects to `host` and runs the client's handshake. An empty
`TargetHost` in `options` means `host`.

**Parameters**

- `host` — the name or address to reach
- `port` — the port to reach it on
- `options` — what to offer, and how to judge the certificate

**Fails with**

- [TlsError.Io](#io-case) — the TCP connection could not be made
- [TlsError.CertificateRefused](#certificaterefused-case) — the validator refused the chain
- [TlsError.AlertReceived](#alertreceived-case) — the server refused

<sub>[stdlib/Net/Security/TlsSocket.sl:59](../../stdlib/Net/Security/TlsSocket.sl#L59)</sub>

#### Connect *method*

```
static Result<TlsSocket, TlsError> Connect(String host, ushort port, TlsClientOptions options, out TlsAlertDescription alertReceived)
```

Connects and runs the client's handshake, and reports the alert the
server sent when it refused.

**Parameters**

- `host` — the name or address to reach
- `port` — the port to reach it on
- `options` — what to offer, and how to judge the certificate
- `alertReceived` — the server's alert when the failure is `AlertReceived`, and `CloseNotify` otherwise

**Fails with**

- [TlsError.AlertReceived](#alertreceived-case) — the server refused, and `alertReceived` says why

<sub>[stdlib/Net/Security/TlsSocket.sl:73](../../stdlib/Net/Security/TlsSocket.sl#L73)</sub>

#### Accept *method*

```
static Result<TlsSocket, TlsError> Accept(TcpListener listener, TlsServerOptions options)
```

Accepts a connection from `listener` and runs the server's handshake.

**Parameters**

- `listener` — where connections arrive
- `options` — the certificate, the key, and what to accept

**Fails with**

- [TlsError.Io](#io-case) — the accept failed
- [TlsError.NoCommonCipherSuite](#nocommonciphersuite-case) — no suite on both lists
- [TlsError.NoApplicationProtocol](#noapplicationprotocol-case) — no ALPN name on both lists

<sub>[stdlib/Net/Security/TlsSocket.sl:102](../../stdlib/Net/Security/TlsSocket.sl#L102)</sub>

#### Accept *method*

```
static Result<TlsSocket, TlsError> Accept(TcpListener listener, TlsServerOptions options, out TlsAlertDescription alertReceived)
```

Accepts a connection and runs the server's handshake, and reports the
alert the client sent when it refused.

**Parameters**

- `listener` — where connections arrive
- `options` — the certificate, the key, and what to accept
- `alertReceived` — the client's alert when the failure is `AlertReceived`, and `CloseNotify` otherwise

**Fails with**

- [TlsError.AlertReceived](#alertreceived-case) — the client refused, and `alertReceived` says why

<sub>[stdlib/Net/Security/TlsSocket.sl:115](../../stdlib/Net/Security/TlsSocket.sl#L115)</sub>

#### Client *property*

```
TcpClient Client { get; }
```

The TCP connection underneath, for timeouts and end points. Reading
or writing it directly corrupts the TLS stream.

<sub>[stdlib/Net/Security/TlsSocket.sl:136](../../stdlib/Net/Security/TlsSocket.sl#L136)</sub>

#### Stream *property*

```
TlsStream Stream { get; }
```

The TLS stream.

<sub>[stdlib/Net/Security/TlsSocket.sl:139](../../stdlib/Net/Security/TlsSocket.sl#L139)</sub>

#### IsServer *property*

```
bool IsServer { get; }
```

*No documentation.*

<sub>[stdlib/Net/Security/TlsSocket.sl:141](../../stdlib/Net/Security/TlsSocket.sl#L141)</sub>

#### NegotiatedProtocol *property*

```
TlsProtocolVersion NegotiatedProtocol { get; }
```

*No documentation.*

<sub>[stdlib/Net/Security/TlsSocket.sl:143](../../stdlib/Net/Security/TlsSocket.sl#L143)</sub>

#### CipherSuite *property*

```
TlsCipherSuite CipherSuite { get; }
```

*No documentation.*

<sub>[stdlib/Net/Security/TlsSocket.sl:145](../../stdlib/Net/Security/TlsSocket.sl#L145)</sub>

#### KeyExchangeGroup *property*

```
TlsNamedGroup KeyExchangeGroup { get; }
```

*No documentation.*

<sub>[stdlib/Net/Security/TlsSocket.sl:147](../../stdlib/Net/Security/TlsSocket.sl#L147)</sub>

#### SignatureScheme *property*

```
TlsSignatureScheme SignatureScheme { get; }
```

*No documentation.*

<sub>[stdlib/Net/Security/TlsSocket.sl:149](../../stdlib/Net/Security/TlsSocket.sl#L149)</sub>

#### NegotiatedApplicationProtocol *property*

```
String? NegotiatedApplicationProtocol { get; }
```

*No documentation.*

<sub>[stdlib/Net/Security/TlsSocket.sl:151](../../stdlib/Net/Security/TlsSocket.sl#L151)</sub>

#### TargetHostName *property*

```
String TargetHostName { get; }
```

*No documentation.*

<sub>[stdlib/Net/Security/TlsSocket.sl:153](../../stdlib/Net/Security/TlsSocket.sl#L153)</sub>

#### RemoteCertificate *property*

```
byte[] RemoteCertificate { get; }
```

*No documentation.*

<sub>[stdlib/Net/Security/TlsSocket.sl:155](../../stdlib/Net/Security/TlsSocket.sl#L155)</sub>

#### RemoteCertificateChain *property*

```
List<byte[]> RemoteCertificateChain { get; }
```

*No documentation.*

<sub>[stdlib/Net/Security/TlsSocket.sl:157](../../stdlib/Net/Security/TlsSocket.sl#L157)</sub>

#### TlsErrorCode *property*

```
TlsError TlsErrorCode { get; }
```

*No documentation.*

<sub>[stdlib/Net/Security/TlsSocket.sl:159](../../stdlib/Net/Security/TlsSocket.sl#L159)</sub>

#### AlertDescription *property*

```
TlsAlertDescription AlertDescription { get; }
```

*No documentation.*

<sub>[stdlib/Net/Security/TlsSocket.sl:161](../../stdlib/Net/Security/TlsSocket.sl#L161)</sub>

#### CanRead *property*

```
bool CanRead { get; }
```

*No documentation.*

<sub>[stdlib/Net/Security/TlsSocket.sl:163](../../stdlib/Net/Security/TlsSocket.sl#L163)</sub>

#### CanWrite *property*

```
bool CanWrite { get; }
```

*No documentation.*

<sub>[stdlib/Net/Security/TlsSocket.sl:165](../../stdlib/Net/Security/TlsSocket.sl#L165)</sub>

#### CanSeek *property*

```
bool CanSeek { get; }
```

*No documentation.*

<sub>[stdlib/Net/Security/TlsSocket.sl:167](../../stdlib/Net/Security/TlsSocket.sl#L167)</sub>

#### Read *method*

```
nuint Read(byte[] buffer, nuint offset, nuint count)
```

*No documentation.*

<sub>[stdlib/Net/Security/TlsSocket.sl:169](../../stdlib/Net/Security/TlsSocket.sl#L169)</sub>

#### Write *method*

```
nuint Write(byte[] buffer, nuint offset, nuint count)
```

*No documentation.*

<sub>[stdlib/Net/Security/TlsSocket.sl:172](../../stdlib/Net/Security/TlsSocket.sl#L172)</sub>

#### Position *property*

```
long Position { get; }
```

*No documentation.*

<sub>[stdlib/Net/Security/TlsSocket.sl:175](../../stdlib/Net/Security/TlsSocket.sl#L175)</sub>

#### Length *property*

```
long Length { get; }
```

*No documentation.*

<sub>[stdlib/Net/Security/TlsSocket.sl:177](../../stdlib/Net/Security/TlsSocket.sl#L177)</sub>

#### Seek *method*

```
bool Seek(long offset, SeekOrigin origin)
```

*No documentation.*

<sub>[stdlib/Net/Security/TlsSocket.sl:179](../../stdlib/Net/Security/TlsSocket.sl#L179)</sub>

#### Flush *method*

```
void Flush()
```

*No documentation.*

<sub>[stdlib/Net/Security/TlsSocket.sl:181](../../stdlib/Net/Security/TlsSocket.sl#L181)</sub>

#### Close *method*

```
void Close()
```

Sends close_notify and closes the TCP connection. Idempotent.

<sub>[stdlib/Net/Security/TlsSocket.sl:184](../../stdlib/Net/Security/TlsSocket.sl#L184)</sub>

#### Error *property*

```
IOError Error { get; }
```

*No documentation.*

<sub>[stdlib/Net/Security/TlsSocket.sl:186](../../stdlib/Net/Security/TlsSocket.sl#L186)</sub>

### TlsStream *class*

```
sealed class TlsStream : IStream
```

A TLS connection over another stream, and an `IStream` itself.

    var tcp = try TcpClient.Connect("example.com", 443u);
    var options = new TlsClientOptions();
    options.TargetHost = "example.com";
    options.CertificateValidator = PinnedLeaf;
    var tls = try TlsStream.AuthenticateAsClient(tcp, options);
    tls.Write(request, 0u, request.Length);

.NET's `SslStream`, made by a static method that returns a `Result`
rather than by a constructor and a method that throws. The stream
underneath can be anything — a `TcpClient`, a proxy's tunnel, a pipe — as
long as it delivers bytes in order.

`Read` blocks until a record of application data arrives, and returns
part of it if `count` is smaller; `Write` sends everything it is given,
in records of at most 16 KiB. One thread MAY read while another writes.

The IO error a failure rounds off to is `Closed` for a transport that
ended, the stream's own for one that failed, and `InvalidData` for
everything the protocol refused; `TlsErrorCode` has the exact reason.

<sub>[stdlib/Net/Security/TlsStream.sl:48](../../stdlib/Net/Security/TlsStream.sl#L48)</sub>

#### AuthenticateAsClient *method*

```
static Result<TlsStream, TlsError> AuthenticateAsClient(IStream inner, TlsClientOptions options)
```

Runs the client's handshake over `inner`.

On failure the alert has been sent and `inner` closed, unless
`LeaveInnerStreamOpen`.

**Parameters**

- `inner` — the connection to the server
- `options` — what to offer, and how to judge the certificate

**Fails with**

- [TlsError.CertificateRefused](#certificaterefused-case) — the validator refused the chain
- [TlsError.ProtocolVersion](#protocolversion-case) — the server does not speak TLS 1.3
- [TlsError.AlertReceived](#alertreceived-case) — the server refused, and said why in an alert
- [TlsError.Io](#io-case) — the stream underneath failed

<sub>[stdlib/Net/Security/TlsStream.sl:74](../../stdlib/Net/Security/TlsStream.sl#L74)</sub>

#### AuthenticateAsClient *method*

```
static Result<TlsStream, TlsError> AuthenticateAsClient(IStream inner, TlsClientOptions options, out TlsAlertDescription alertReceived)
```

Runs the client's handshake, and reports the alert the server sent
when it refused.

**Parameters**

- `inner` — the connection to the server
- `options` — what to offer, and how to judge the certificate
- `alertReceived` — the server's alert when the failure is `AlertReceived`, and `CloseNotify` otherwise

**Fails with**

- [TlsError.AlertReceived](#alertreceived-case) — the server refused, and `alertReceived` says why

<sub>[stdlib/Net/Security/TlsStream.sl:89](../../stdlib/Net/Security/TlsStream.sl#L89)</sub>

#### AuthenticateAsServer *method*

```
static Result<TlsStream, TlsError> AuthenticateAsServer(IStream inner, TlsServerOptions options)
```

Runs the server's handshake over `inner`.

On failure the alert has been sent and `inner` closed, unless
`LeaveInnerStreamOpen`.

**Parameters**

- `inner` — the connection from the client
- `options` — the certificate, the key, and what to accept

**Fails with**

- [TlsError.NoCommonCipherSuite](#nocommonciphersuite-case) — no suite on both lists
- [TlsError.NoCommonGroup](#nocommongroup-case) — no group on both lists
- [TlsError.NoApplicationProtocol](#noapplicationprotocol-case) — no ALPN name on both lists
- [TlsError.CertificateRequired](#certificaterequired-case) — a client certificate was required and none came
- [TlsError.InternalError](#internalerror-case) — no certificate or no key is configured

<sub>[stdlib/Net/Security/TlsStream.sl:118](../../stdlib/Net/Security/TlsStream.sl#L118)</sub>

#### AuthenticateAsServer *method*

```
static Result<TlsStream, TlsError> AuthenticateAsServer(IStream inner, TlsServerOptions options, out TlsAlertDescription alertReceived)
```

Runs the server's handshake, and reports the alert the client sent
when it refused.

**Parameters**

- `inner` — the connection from the client
- `options` — the certificate, the key, and what to accept
- `alertReceived` — the client's alert when the failure is `AlertReceived`, and `CloseNotify` otherwise

**Fails with**

- [TlsError.AlertReceived](#alertreceived-case) — the client refused, and `alertReceived` says why

<sub>[stdlib/Net/Security/TlsStream.sl:133](../../stdlib/Net/Security/TlsStream.sl#L133)</sub>

#### IsServer *property*

```
bool IsServer { get; }
```

Whether this end is the server.

<sub>[stdlib/Net/Security/TlsStream.sl:151](../../stdlib/Net/Security/TlsStream.sl#L151)</sub>

#### NegotiatedProtocol *property*

```
TlsProtocolVersion NegotiatedProtocol { get; }
```

The version negotiated. Always TLS 1.3 for now.

<sub>[stdlib/Net/Security/TlsStream.sl:154](../../stdlib/Net/Security/TlsStream.sl#L154)</sub>

#### CipherSuite *property*

```
TlsCipherSuite CipherSuite { get; }
```

The suite negotiated.

<sub>[stdlib/Net/Security/TlsStream.sl:157](../../stdlib/Net/Security/TlsStream.sl#L157)</sub>

#### KeyExchangeGroup *property*

```
TlsNamedGroup KeyExchangeGroup { get; }
```

The group the key exchange was made in.

<sub>[stdlib/Net/Security/TlsStream.sl:160](../../stdlib/Net/Security/TlsStream.sl#L160)</sub>

#### SignatureScheme *property*

```
TlsSignatureScheme SignatureScheme { get; }
```

The scheme the server signed its CertificateVerify with.

<sub>[stdlib/Net/Security/TlsStream.sl:163](../../stdlib/Net/Security/TlsStream.sl#L163)</sub>

#### NegotiatedApplicationProtocol *property*

```
String? NegotiatedApplicationProtocol { get; }
```

The ALPN protocol agreed, or null when there was none.

<sub>[stdlib/Net/Security/TlsStream.sl:166](../../stdlib/Net/Security/TlsStream.sl#L166)</sub>

#### TargetHostName *property*

```
String TargetHostName { get; }
```

On a client, the name it asked for; on a server, the name in the
client's server_name, or empty.

<sub>[stdlib/Net/Security/TlsStream.sl:170](../../stdlib/Net/Security/TlsStream.sl#L170)</sub>

#### RemoteCertificate *property*

```
byte[] RemoteCertificate { get; }
```

The peer's leaf certificate, DER, or empty when it sent none — which
only a client can do.

<sub>[stdlib/Net/Security/TlsStream.sl:174](../../stdlib/Net/Security/TlsStream.sl#L174)</sub>

#### RemoteCertificateChain *property*

```
List<byte[]> RemoteCertificateChain { get; }
```

The peer's certificates as it sent them, DER, leaf first.

<sub>[stdlib/Net/Security/TlsStream.sl:185](../../stdlib/Net/Security/TlsStream.sl#L185)</sub>

#### IsMutuallyAuthenticated *property*

```
bool IsMutuallyAuthenticated { get; }
```

Whether the client presented a certificate that was accepted.

<sub>[stdlib/Net/Security/TlsStream.sl:188](../../stdlib/Net/Security/TlsStream.sl#L188)</sub>

#### TlsErrorCode *property*

```
TlsError TlsErrorCode { get; }
```

The exact failure, or `None`.

<sub>[stdlib/Net/Security/TlsStream.sl:191](../../stdlib/Net/Security/TlsStream.sl#L191)</sub>

#### AlertDescription *property*

```
TlsAlertDescription AlertDescription { get; }
```

The alert the peer ended the connection with, when `TlsErrorCode` is
`AlertReceived`.

<sub>[stdlib/Net/Security/TlsStream.sl:195](../../stdlib/Net/Security/TlsStream.sl#L195)</sub>

#### InnerStream *property*

```
IStream InnerStream { get; }
```

The stream underneath.

<sub>[stdlib/Net/Security/TlsStream.sl:198](../../stdlib/Net/Security/TlsStream.sl#L198)</sub>

#### ExportKeyingMaterial *method*

```
Result<byte[], TlsError> ExportKeyingMaterial(String label, ReadOnlySpan<byte> context, nuint length)
```

Keying material for a protocol above this one (RFC 8446 §7.5): the
same bytes at both ends for the same label and context, and no use to
anyone else.

**Parameters**

- `label` — names the use, as the protocol that wants it defines
- `context` — bound into the result; empty when the protocol has none
- `length` — how many bytes, at most 255 digests' worth

**Fails with**

- [TlsError.Closed](#closed-case) — the stream is closed

<sub>[stdlib/Net/Security/TlsStream.sl:210](../../stdlib/Net/Security/TlsStream.sl#L210)</sub>

#### UpdateTrafficKeys *method*

```
TlsError UpdateTrafficKeys(bool requestPeerUpdate)
```

Moves this end to its next write key with a KeyUpdate, and asks the
peer to do the same when `requestPeerUpdate`. Keys are also updated
without being asked, before one has protected 2^24 records.

**Fails with**

- [TlsError.Closed](#closed-case) — the stream is closed or failed
- [TlsError.Io](#io-case) — the stream underneath failed

<sub>[stdlib/Net/Security/TlsStream.sl:225](../../stdlib/Net/Security/TlsStream.sl#L225)</sub>

#### CanRead *property*

```
bool CanRead { get; }
```

*No documentation.*

<sub>[stdlib/Net/Security/TlsStream.sl:230](../../stdlib/Net/Security/TlsStream.sl#L230)</sub>

#### CanWrite *property*

```
bool CanWrite { get; }
```

*No documentation.*

<sub>[stdlib/Net/Security/TlsStream.sl:232](../../stdlib/Net/Security/TlsStream.sl#L232)</sub>

#### CanSeek *property*

```
bool CanSeek { get; }
```

A connection has no position.

<sub>[stdlib/Net/Security/TlsStream.sl:235](../../stdlib/Net/Security/TlsStream.sl#L235)</sub>

#### Read *method*

```
nuint Read(byte[] buffer, nuint offset, nuint count)
```

Reads up to `count` bytes of application data. Zero means the peer
sent close_notify, or a failure, which `Error` tells apart.

<sub>[stdlib/Net/Security/TlsStream.sl:239](../../stdlib/Net/Security/TlsStream.sl#L239)</sub>

#### Write *method*

```
nuint Write(byte[] buffer, nuint offset, nuint count)
```

Writes all `count` bytes as application data, and answers `count`, or
zero on a failure.

<sub>[stdlib/Net/Security/TlsStream.sl:248](../../stdlib/Net/Security/TlsStream.sl#L248)</sub>

#### Position *property*

```
long Position { get; }
```

*No documentation.*

<sub>[stdlib/Net/Security/TlsStream.sl:255](../../stdlib/Net/Security/TlsStream.sl#L255)</sub>

#### Length *property*

```
long Length { get; }
```

*No documentation.*

<sub>[stdlib/Net/Security/TlsStream.sl:257](../../stdlib/Net/Security/TlsStream.sl#L257)</sub>

#### Seek *method*

```
bool Seek(long offset, SeekOrigin origin)
```

*No documentation.*

<sub>[stdlib/Net/Security/TlsStream.sl:259](../../stdlib/Net/Security/TlsStream.sl#L259)</sub>

#### Flush *method*

```
void Flush()
```

Flushes the stream underneath. Every `Write` has already sent its
records.

<sub>[stdlib/Net/Security/TlsStream.sl:263](../../stdlib/Net/Security/TlsStream.sl#L263)</sub>

#### Close *method*

```
void Close()
```

Sends close_notify and closes the stream underneath, unless
`LeaveInnerStreamOpen`. Idempotent, and the destructor calls it.

<sub>[stdlib/Net/Security/TlsStream.sl:267](../../stdlib/Net/Security/TlsStream.sl#L267)</sub>

#### Error *property*

```
IOError Error { get; }
```

*No documentation.*

<sub>[stdlib/Net/Security/TlsStream.sl:269](../../stdlib/Net/Security/TlsStream.sl#L269)</sub>

## Functions

### DescribeTlsError *function*

```
String DescribeTlsError(TlsError error)
```

A sentence describing a TLS error, for a message a person will read.

**See also** &nbsp; [TlsError](#tlserror-enum)

<sub>[stdlib/Net/Security/Security.sl:173](../../stdlib/Net/Security/Security.sl#L173)</sub>

### DiscardTlsSessionTicket *function*

```
void DiscardTlsSessionTicket(TlsSessionTicket ticket)
```

What a client does with a ticket when no handler is configured: nothing.

<sub>[stdlib/Net/Security/TlsSessionTicket.sl:85](../../stdlib/Net/Security/TlsSessionTicket.sl#L85)</sub>

### ValidateTlsCertificateChainByDefault *function*

```
TlsError ValidateTlsCertificateChainByDefault(List<byte[]> chain, String targetHost)
```

The validator used when none is configured. **It refuses every chain.**

X.509 path validation is not in this library yet, and a default that
trusted anything would be an invitation to a machine in the middle. A
program that has pinned its peer's certificate, or accepts any for a
test, supplies its own.

**Parameters**

- `chain` — the peer's certificates, DER, leaf first
- `targetHost` — the name the certificate must be valid for

<sub>[stdlib/Net/Security/TlsCertificateValidator.sl:49](../../stdlib/Net/Security/TlsCertificateValidator.sl#L49)</sub>

