# Standard.Security.Cryptography.X509Certificates

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

X.509 certificates: reading them, checking a host name against one,
building and validating a chain to a trusted root, the platform's root
store, and making new ones.

```csharp
var leaf = try X509Certificate2.FromPem(pem);
bool named = leaf.MatchesHostname("www.example.com");

var chain = new X509Chain();
chain.ChainPolicy.ApplicationPolicy.Add(X509EnhancedKeyUsageExtension.ServerAuthenticationOid);
chain.ChainPolicy.ExtraStore.AddRange(intermediates);
if (!chain.Build(leaf))
    Console.WriteLine(chain.StatusFlags);
```

**The shape is `System.Security.Cryptography.X509Certificates`'s**, with
the house casing and a `Result` where .NET throws. Every failure is a
`CryptoError`, the module underneath's own vocabulary, rather than an
enum of this module's: a certificate that does not parse is
`CryptoError.Encoding` whatever part of it was wrong, a key this does not
sign with is `CryptoError.Unsupported`, and a signing failure passes
through unchanged. A chain that does not validate is not a failure of the
call; `X509Chain.Build` answers `false` and says why in its status flags.

**Times are seconds since 1970-01-01 UTC, in a `long`**, as in
`Standard.Formats.Asn1`: a certificate can name 9999 and a
`DateTimeOffset` ends in 2262. The `DateTimeOffset` accessors cross over
where they can.

**Parsing is RFC 5280's, strictly, with the leniencies browsers have.**
The DER is held to the letter: minimal lengths and integers, a signature
algorithm outside the signed part identical to the one inside it, a
version of 1, 2 or 3, extensions only in version 3 and none twice. What
is tolerated is what real certificates do: a serial number of up to 20
octets that is zero or negative, a `GeneralizedTime` before 2050, an
explicit `critical FALSE`, and a `PrintableString` holding `*` or `@`.
Every extension this module knows is decoded as the certificate is read,
so a malformed one is a certificate that does not parse.

**Signatures** are Ed25519, ECDSA over P-256 and P-384 with SHA-256, -384
or -512, RSA PKCS #1 v1.5 with SHA-1, -256, -384 or -512, and RSASSA-PSS
whose mask hash is its message hash. A chain refuses SHA-1 as
`HasWeakSignature` though the signature is checked.

**Host names are matched as RFC 6125 and the CA/Browser Forum say**:
against the DNS names in the subject alternative name and never the
common name, whatever else the certificate holds; case-insensitively in
ASCII; with a wildcard only as the whole of the left-most label, matching
exactly one label, and only over at least two labels; an address only
against the address entries, as bytes.

**There is no revocation.** Nothing here fetches or reads a CRL or asks an
OCSP responder, so `X509RevocationMode.NoCheck` is the default and the
only mode that can succeed; asking for another is answered with
`RevocationStatusUnknown` on every element rather than silently ignored.

## Contents

**Types** &nbsp; [CertificateRequest](#certificaterequest-class) &middot; [PublicKey](#publickey-class) &middot; [StoreLocation](#storelocation-enum) &middot; [StoreName](#storename-enum) &middot; [SubjectAlternativeNameBuilder](#subjectalternativenamebuilder-class) &middot; [X500DistinguishedName](#x500distinguishedname-class) &middot; [X500DistinguishedNameBuilder](#x500distinguishednamebuilder-class) &middot; [X500RelativeDistinguishedName](#x500relativedistinguishedname-class) &middot; [X509AuthorityKeyIdentifierExtension](#x509authoritykeyidentifierextension-class) &middot; [X509BasicConstraintsExtension](#x509basicconstraintsextension-class) &middot; [X509Certificate2](#x509certificate2-class) &middot; [X509Certificate2Collection](#x509certificate2collection-class) &middot; [X509Chain](#x509chain-class) &middot; [X509ChainElement](#x509chainelement-class) &middot; [X509ChainPolicy](#x509chainpolicy-class) &middot; [X509ChainStatus](#x509chainstatus-struct) &middot; [X509ChainStatusFlags](#x509chainstatusflags-enum) &middot; [X509ChainTrustMode](#x509chaintrustmode-enum) &middot; [X509EnhancedKeyUsageExtension](#x509enhancedkeyusageextension-class) &middot; [X509Extension](#x509extension-class) &middot; [X509ExtensionCollection](#x509extensioncollection-class) &middot; [X509KeyUsageExtension](#x509keyusageextension-class) &middot; [X509KeyUsageFlags](#x509keyusageflags-enum) &middot; [X509NameConstraintsExtension](#x509nameconstraintsextension-class) &middot; [X509RevocationMode](#x509revocationmode-enum) &middot; [X509SignatureGenerator](#x509signaturegenerator-class) &middot; [X509Store](#x509store-class) &middot; [X509SubjectAlternativeNameExtension](#x509subjectalternativenameextension-class) &middot; [X509SubjectKeyIdentifierExtension](#x509subjectkeyidentifierextension-class)

## Types

### CertificateRequest *class*

```
sealed class CertificateRequest
```

Makes a certificate: .NET's `CertificateRequest`.

```csharp
var rootKey = try X509SignatureGenerator.CreateForEd25519(Ed25519.GeneratePrivateKey());
var rootRequest = new CertificateRequest(rootName, rootKey, HashAlgorithmName.Sha256);
rootRequest.CertificateExtensions.Add(new X509BasicConstraintsExtension(true, false, 0, true));
var root = try rootRequest.CreateSelfSigned(notBefore, notAfter);

var leafRequest = new CertificateRequest(leafName, leafKey.PublicKey, HashAlgorithmName.Sha256);
var leaf = try leafRequest.Create(root, rootKey, notBefore, notAfter, serial);
```

The certificate is version 3, its validity a `UTCTime` through 2049 and a
`GeneralizedTime` after, and its extensions exactly those added, in that
order: nothing is added on the caller's behalf, as .NET adds nothing.
What comes back is read back through `X509Certificate2.FromDer`, so it is
what any reader of it will see.

<sub>[stdlib/Security/Cryptography/X509Certificates/CertificateRequest.sl:45](../../stdlib/Security/Cryptography/X509Certificates/CertificateRequest.sl#L45)</sub>

#### SubjectName *property*

```
X500DistinguishedName SubjectName { get; }
```

Who the certificate is for.

<sub>[stdlib/Security/Cryptography/X509Certificates/CertificateRequest.sl:86](../../stdlib/Security/Cryptography/X509Certificates/CertificateRequest.sl#L86)</sub>

#### PublicKey *property*

```
PublicKey PublicKey { get; }
```

The subject's key.

<sub>[stdlib/Security/Cryptography/X509Certificates/CertificateRequest.sl:89](../../stdlib/Security/Cryptography/X509Certificates/CertificateRequest.sl#L89)</sub>

#### HashAlgorithm *property*

```
HashAlgorithmName HashAlgorithm { get; }
```

The hash a signature is made over.

<sub>[stdlib/Security/Cryptography/X509Certificates/CertificateRequest.sl:92](../../stdlib/Security/Cryptography/X509Certificates/CertificateRequest.sl#L92)</sub>

#### CertificateExtensions *property*

```
List<X509Extension> CertificateExtensions { get; }
```

The extensions the certificate will carry, in order. No two MAY have
the same identifier.

<sub>[stdlib/Security/Cryptography/X509Certificates/CertificateRequest.sl:96](../../stdlib/Security/Cryptography/X509Certificates/CertificateRequest.sl#L96)</sub>

#### CreateSelfSigned *method*

```
Result<X509Certificate2, CryptoError> CreateSelfSigned(long notBefore, long notAfter)
```

The certificate signed by its own key, with a random positive serial
number of sixteen bytes.

**Parameters**

- `notBefore` -- the first moment it is valid, in seconds since the epoch
- `notAfter` -- the last, no earlier than `notBefore`

**Fails with**

- [CryptoError.InvalidKey](Standard-Security-Cryptography.md#invalidkey-case) -- the request was made with a public key only
- [CryptoError.Parameter](Standard-Security-Cryptography.md#parameter-case) -- `notAfter` is before `notBefore`, or either is outside the years 0 to 9999
- [CryptoError.NoEntropy](Standard-Security-Cryptography.md#noentropy-case) -- the platform would not supply a serial number

<sub>[stdlib/Security/Cryptography/X509Certificates/CertificateRequest.sl:107](../../stdlib/Security/Cryptography/X509Certificates/CertificateRequest.sl#L107)</sub>

#### Create *method*

```
Result<X509Certificate2, CryptoError> Create(X509Certificate2 issuerCertificate, X509SignatureGenerator issuerKey, long notBefore, long notAfter, ReadOnlySpan<byte> serialNumber)
```

The certificate issued by `issuerCertificate`, signed with its key.

As .NET requires, the issuer MUST be a CA by its basic constraints,
`issuerKey` MUST be the key its certificate names, and the new
certificate's validity MUST lie within the issuer's.

**Parameters**

- `issuerCertificate` -- the CA
- `issuerKey` -- its private key
- `notBefore` -- the first moment it is valid
- `notAfter` -- the last
- `serialNumber` -- big-endian and unsigned, 1 to 20 bytes once leading zeros are gone, and not zero

**Fails with**

- [CryptoError.InvalidKey](Standard-Security-Cryptography.md#invalidkey-case) -- `issuerKey` is not the issuer's key
- [CryptoError.Parameter](Standard-Security-Cryptography.md#parameter-case) -- the issuer is not a CA, the validity is not within its, or the serial number is not one RFC 5280 allows

<sub>[stdlib/Security/Cryptography/X509Certificates/CertificateRequest.sl:135](../../stdlib/Security/Cryptography/X509Certificates/CertificateRequest.sl#L135)</sub>

#### Create *method*

```
Result<X509Certificate2, CryptoError> Create(X500DistinguishedName issuerName, X509SignatureGenerator generator, long notBefore, long notAfter, ReadOnlySpan<byte> serialNumber)
```

The certificate issued in `issuerName`, signed by `generator`, with no
check that the two belong together.

**Parameters**

- `issuerName` -- the issuer's name, exactly as its own certificate has it
- `generator` -- the issuer's private key
- `notBefore` -- the first moment it is valid
- `notAfter` -- the last
- `serialNumber` -- big-endian and unsigned, 1 to 20 bytes once leading zeros are gone, and not zero

**Fails with**

- [CryptoError.Parameter](Standard-Security-Cryptography.md#parameter-case) -- the validity or the serial number is not one RFC 5280 allows

<sub>[stdlib/Security/Cryptography/X509Certificates/CertificateRequest.sl:160](../../stdlib/Security/Cryptography/X509Certificates/CertificateRequest.sl#L160)</sub>

### PublicKey *class*

```
sealed class PublicKey
```

A certificate's public key: the algorithm, its parameters and the key,
as a `SubjectPublicKeyInfo` holds them.

```csharp
PublicKey key = certificate.PublicKey;
ECDsa verifier = try key.GetECDsaPublicKey();
```

.NET's `PublicKey`, with the algorithm a dotted identifier and a reader
for each kind of key this module signs with: `GetEd25519PublicKey`,
`GetRsaPublicKey` and the modulus and exponent, `GetECDsaPublicKey` and
the curve and point. Each answers `CryptoError.Unsupported` for a key of
another algorithm, and `CryptoError.Encoding` for one whose bytes are not
what that algorithm's key is.

<sub>[stdlib/Security/Cryptography/X509Certificates/PublicKey.sl:41](../../stdlib/Security/Cryptography/X509Certificates/PublicKey.sl#L41)</sub>

#### Ed25519Oid *property*

```
static String Ed25519Oid { get; }
```

`id-Ed25519`, RFC 8410's.

<sub>[stdlib/Security/Cryptography/X509Certificates/PublicKey.sl:57](../../stdlib/Security/Cryptography/X509Certificates/PublicKey.sl#L57)</sub>

#### RsaOid *property*

```
static String RsaOid { get; }
```

`rsaEncryption`, PKCS #1's.

<sub>[stdlib/Security/Cryptography/X509Certificates/PublicKey.sl:60](../../stdlib/Security/Cryptography/X509Certificates/PublicKey.sl#L60)</sub>

#### RsaPssOid *property*

```
static String RsaPssOid { get; }
```

`id-RSASSA-PSS`, for a key restricted to PSS signatures.

<sub>[stdlib/Security/Cryptography/X509Certificates/PublicKey.sl:63](../../stdlib/Security/Cryptography/X509Certificates/PublicKey.sl#L63)</sub>

#### ECOid *property*

```
static String ECOid { get; }
```

`id-ecPublicKey`, RFC 5480's.

<sub>[stdlib/Security/Cryptography/X509Certificates/PublicKey.sl:66](../../stdlib/Security/Cryptography/X509Certificates/PublicKey.sl#L66)</sub>

#### CreateFromSubjectPublicKeyInfo *method*

```
static Result<PublicKey, CryptoError> CreateFromSubjectPublicKeyInfo(ReadOnlySpan<byte> source, out nuint bytesRead)
```

The key a `SubjectPublicKeyInfo` holds.

**Parameters**

- `source` -- the DER, perhaps with more after it
- `bytesRead` -- how many bytes of `source` the structure took; zero on failure

**Fails with**

- [CryptoError.Encoding](Standard-Security-Cryptography.md#encoding-case) -- it is not a `SubjectPublicKeyInfo`

<sub>[stdlib/Security/Cryptography/X509Certificates/PublicKey.sl:75](../../stdlib/Security/Cryptography/X509Certificates/PublicKey.sl#L75)</sub>

#### CreateFromEd25519PublicKey *method*

```
static Result<PublicKey, CryptoError> CreateFromEd25519PublicKey(ReadOnlySpan<byte> publicKey)
```

An Ed25519 key.

**Parameters**

- `publicKey` -- the 32 bytes RFC 8032 encodes a point as

**Fails with**

- [CryptoError.KeyLength](Standard-Security-Cryptography.md#keylength-case) -- `publicKey` is not 32 bytes

<sub>[stdlib/Security/Cryptography/X509Certificates/PublicKey.sl:90](../../stdlib/Security/Cryptography/X509Certificates/PublicKey.sl#L90)</sub>

#### CreateFromECDsa *method*

```
static Result<PublicKey, CryptoError> CreateFromECDsa(ECDsa key)
```

`key`'s public half.

**Fails with**

- [CryptoError.Encoding](Standard-Security-Cryptography.md#encoding-case) -- never, in practice: the key writes its own

<sub>[stdlib/Security/Cryptography/X509Certificates/PublicKey.sl:108](../../stdlib/Security/Cryptography/X509Certificates/PublicKey.sl#L108)</sub>

#### CreateFromRsa *method*

```
static Result<PublicKey, CryptoError> CreateFromRsa(Rsa key)
```

`key`'s public half.

**Fails with**

- [CryptoError.Encoding](Standard-Security-Cryptography.md#encoding-case) -- never, in practice: the key writes its own

<sub>[stdlib/Security/Cryptography/X509Certificates/PublicKey.sl:114](../../stdlib/Security/Cryptography/X509Certificates/PublicKey.sl#L114)</sub>

#### Oid *property*

```
String Oid { get; }
```

The algorithm, dotted: `Ed25519Oid`, `RsaOid`, `RsaPssOid` or `ECOid`
for the keys this module reads, and anything at all otherwise.

<sub>[stdlib/Security/Cryptography/X509Certificates/PublicKey.sl:145](../../stdlib/Security/Cryptography/X509Certificates/PublicKey.sl#L145)</sub>

#### EncodedParameters *property*

```
byte[] EncodedParameters { get; }
```

The algorithm's parameters as DER, or empty when there are none.

<sub>[stdlib/Security/Cryptography/X509Certificates/PublicKey.sl:148](../../stdlib/Security/Cryptography/X509Certificates/PublicKey.sl#L148)</sub>

#### EncodedKeyValue *property*

```
byte[] EncodedKeyValue { get; }
```

The key itself: the contents of the `BIT STRING`.

<sub>[stdlib/Security/Cryptography/X509Certificates/PublicKey.sl:151](../../stdlib/Security/Cryptography/X509Certificates/PublicKey.sl#L151)</sub>

#### ExportSubjectPublicKeyInfo *method*

```
byte[] ExportSubjectPublicKeyInfo()
```

The whole `SubjectPublicKeyInfo`, as DER.

<sub>[stdlib/Security/Cryptography/X509Certificates/PublicKey.sl:154](../../stdlib/Security/Cryptography/X509Certificates/PublicKey.sl#L154)</sub>

#### Equals *method*

```
bool Equals(PublicKey other)
```

Whether `other` is the same key under the same algorithm.

<sub>[stdlib/Security/Cryptography/X509Certificates/PublicKey.sl:157](../../stdlib/Security/Cryptography/X509Certificates/PublicKey.sl#L157)</sub>

#### GetEd25519PublicKey *method*

```
Result<byte[], CryptoError> GetEd25519PublicKey()
```

The 32 bytes of an Ed25519 key.

**Fails with**

- [CryptoError.Unsupported](Standard-Security-Cryptography.md#unsupported-case) -- the key is not Ed25519
- [CryptoError.Encoding](Standard-Security-Cryptography.md#encoding-case) -- it has parameters, which RFC 8410 forbids, or is not 32 bytes

<sub>[stdlib/Security/Cryptography/X509Certificates/PublicKey.sl:164](../../stdlib/Security/Cryptography/X509Certificates/PublicKey.sl#L164)</sub>

#### GetRsaPublicKey *method*

```
Result<Rsa, CryptoError> GetRsaPublicKey()
```

The RSA key, for verifying or encrypting.

**Fails with**

- [CryptoError.Unsupported](Standard-Security-Cryptography.md#unsupported-case) -- the key is not RSA
- [CryptoError.Encoding](Standard-Security-Cryptography.md#encoding-case) -- it is not a PKCS #1 `RSAPublicKey`
- [CryptoError.InvalidKey](Standard-Security-Cryptography.md#invalidkey-case) -- the modulus or exponent is not usable

<sub>[stdlib/Security/Cryptography/X509Certificates/PublicKey.sl:178](../../stdlib/Security/Cryptography/X509Certificates/PublicKey.sl#L178)</sub>

#### GetRsaModulus *method*

```
Result<byte[], CryptoError> GetRsaModulus()
```

The RSA modulus, big-endian and without a sign octet.

**Fails with**

- [CryptoError.Unsupported](Standard-Security-Cryptography.md#unsupported-case) -- the key is not RSA
- [CryptoError.Encoding](Standard-Security-Cryptography.md#encoding-case) -- it is not a PKCS #1 `RSAPublicKey`

<sub>[stdlib/Security/Cryptography/X509Certificates/PublicKey.sl:189](../../stdlib/Security/Cryptography/X509Certificates/PublicKey.sl#L189)</sub>

#### GetRsaExponent *method*

```
Result<byte[], CryptoError> GetRsaExponent()
```

The RSA public exponent, big-endian and without a sign octet.

**Fails with**

- [CryptoError.Unsupported](Standard-Security-Cryptography.md#unsupported-case) -- the key is not RSA
- [CryptoError.Encoding](Standard-Security-Cryptography.md#encoding-case) -- it is not a PKCS #1 `RSAPublicKey`

<sub>[stdlib/Security/Cryptography/X509Certificates/PublicKey.sl:195](../../stdlib/Security/Cryptography/X509Certificates/PublicKey.sl#L195)</sub>

#### GetECCurve *method*

```
Result<ECCurve, CryptoError> GetECCurve()
```

The curve an elliptic-curve key is on.

**Fails with**

- [CryptoError.Unsupported](Standard-Security-Cryptography.md#unsupported-case) -- the key is not an elliptic-curve key, or its curve is given by explicit parameters
- [CryptoError.Encoding](Standard-Security-Cryptography.md#encoding-case) -- the parameters are not a curve's identifier

<sub>[stdlib/Security/Cryptography/X509Certificates/PublicKey.sl:225](../../stdlib/Security/Cryptography/X509Certificates/PublicKey.sl#L225)</sub>

#### GetECPoint *method*

```
Result<byte[], CryptoError> GetECPoint()
```

The point of an elliptic-curve key as SEC 1 encodes it: `04`, then
`X` and `Y`, for the uncompressed form every certificate uses.

**Fails with**

- [CryptoError.Unsupported](Standard-Security-Cryptography.md#unsupported-case) -- the key is not an elliptic-curve key

<sub>[stdlib/Security/Cryptography/X509Certificates/PublicKey.sl:243](../../stdlib/Security/Cryptography/X509Certificates/PublicKey.sl#L243)</sub>

#### GetECDsaPublicKey *method*

```
Result<ECDsa, CryptoError> GetECDsaPublicKey()
```

The elliptic-curve key, for verifying.

**Fails with**

- [CryptoError.Unsupported](Standard-Security-Cryptography.md#unsupported-case) -- the key is not on P-256 or P-384, or its point is compressed
- [CryptoError.Encoding](Standard-Security-Cryptography.md#encoding-case) -- the point is not the curve's size
- [CryptoError.InvalidPoint](Standard-Security-Cryptography.md#invalidpoint-case) -- the point is not on the curve

<sub>[stdlib/Security/Cryptography/X509Certificates/PublicKey.sl:256](../../stdlib/Security/Cryptography/X509Certificates/PublicKey.sl#L256)</sub>

### StoreLocation *enum*

```
enum StoreLocation
```

Whose certificate store to open: .NET's `StoreLocation`. Only Windows
tells the two apart; elsewhere both are the system bundle.

<sub>[stdlib/Security/Cryptography/X509Certificates/StoreLocation.sl:26](../../stdlib/Security/Cryptography/X509Certificates/StoreLocation.sl#L26)</sub>

#### CurrentUser *case*

```
CurrentUser
```

The user's, which on Windows also shows the machine's.

<sub>[stdlib/Security/Cryptography/X509Certificates/StoreLocation.sl:29](../../stdlib/Security/Cryptography/X509Certificates/StoreLocation.sl#L29)</sub>

#### LocalMachine *case*

```
LocalMachine
```

The machine's.

<sub>[stdlib/Security/Cryptography/X509Certificates/StoreLocation.sl:32](../../stdlib/Security/Cryptography/X509Certificates/StoreLocation.sl#L32)</sub>

### StoreName *enum*

```
enum StoreName
```

Which certificate store to open: .NET's `StoreName`, the two a chain uses.

<sub>[stdlib/Security/Cryptography/X509Certificates/StoreName.sl:25](../../stdlib/Security/Cryptography/X509Certificates/StoreName.sl#L25)</sub>

#### Root *case*

```
Root
```

Trusted roots.

<sub>[stdlib/Security/Cryptography/X509Certificates/StoreName.sl:28](../../stdlib/Security/Cryptography/X509Certificates/StoreName.sl#L28)</sub>

#### CertificateAuthority *case*

```
CertificateAuthority
```

Intermediate CAs, which Windows keeps apart from the roots. Empty
elsewhere, where a bundle holds roots alone.

<sub>[stdlib/Security/Cryptography/X509Certificates/StoreName.sl:32](../../stdlib/Security/Cryptography/X509Certificates/StoreName.sl#L32)</sub>

### SubjectAlternativeNameBuilder *class*

```
sealed class SubjectAlternativeNameBuilder
```

Makes a subject alternative name extension: .NET's
`SubjectAlternativeNameBuilder`.

```csharp
var names = new SubjectAlternativeNameBuilder();
names.AddDnsName("www.example.com");
names.AddIPAddress([192, 0, 2, 1]);
request.CertificateExtensions.Add(names.Build());
```

The names are written in the order they were added. Each MUST be ASCII,
which is what the `IA5String` they are written as holds: an
internationalized domain name is added as its `xn--` form. Anything else
aborts, as a mistake in the program rather than in its data.

<sub>[stdlib/Security/Cryptography/X509Certificates/SubjectAlternativeNameBuilder.sl:42](../../stdlib/Security/Cryptography/X509Certificates/SubjectAlternativeNameBuilder.sl#L42)</sub>

#### AddDnsName *method*

```
void AddDnsName(String dnsName)
```

A DNS name, `www.example.com` or `*.example.com`.

<sub>[stdlib/Security/Cryptography/X509Certificates/SubjectAlternativeNameBuilder.sl:61](../../stdlib/Security/Cryptography/X509Certificates/SubjectAlternativeNameBuilder.sl#L61)</sub>

#### AddEmailAddress *method*

```
void AddEmailAddress(String emailAddress)
```

An e-mail address.

<sub>[stdlib/Security/Cryptography/X509Certificates/SubjectAlternativeNameBuilder.sl:68](../../stdlib/Security/Cryptography/X509Certificates/SubjectAlternativeNameBuilder.sl#L68)</sub>

#### AddUri *method*

```
void AddUri(String uri)
```

A URI.

<sub>[stdlib/Security/Cryptography/X509Certificates/SubjectAlternativeNameBuilder.sl:75](../../stdlib/Security/Cryptography/X509Certificates/SubjectAlternativeNameBuilder.sl#L75)</sub>

#### AddIPAddress *method*

```
void AddIPAddress(ReadOnlySpan<byte> address)
```

An IP address: four bytes for IPv4, sixteen for IPv6; any other length
aborts.

<sub>[stdlib/Security/Cryptography/X509Certificates/SubjectAlternativeNameBuilder.sl:83](../../stdlib/Security/Cryptography/X509Certificates/SubjectAlternativeNameBuilder.sl#L83)</sub>

#### Build *method*

```
X509SubjectAlternativeNameExtension Build(bool critical)
```

The extension, holding every name added so far. At least one MUST
have been; this aborts otherwise.

**Parameters**

- `critical` -- whether it is critical, which RFC 5280 requires only when the subject name is empty

<sub>[stdlib/Security/Cryptography/X509Certificates/SubjectAlternativeNameBuilder.sl:98](../../stdlib/Security/Cryptography/X509Certificates/SubjectAlternativeNameBuilder.sl#L98)</sub>

### X500DistinguishedName *class*

```
sealed class X500DistinguishedName
```

An X.500 name, as a certificate's issuer and subject are: a sequence of
relative distinguished names from the most general to the most specific.

```csharp
Console.WriteLine(certificate.SubjectName.Name);   // CN=www.example.com, O=Example, C=US
var common = certificate.SubjectName.GetFirstValue("2.5.4.3");
```

**`Name` is written as .NET writes it**: most specific first, separated by
`, `, with the short names `CN`, `O`, `OU`, `L`, `S`, `C`, `E`, `DC`,
`STREET`, `T`, `G`, `I`, `SN` and `SERIALNUMBER`, and `OID.` and the
dotted identifier for any other type. A value holding `,`, `+`, `=`, `"`,
`<`, `>`, `#`, `;`, a newline, or a space at either end is quoted, with a
`"` inside doubled. The attributes of a multi-valued step are joined by
` + `.

**Two names are equal as RFC 5280 §7.1 compares them**: the same types in
the same order, and each string value equal once runs of spaces are one
space, spaces at either end are gone, and ASCII letters are one case. The
string type does not matter; a value that is not a string is compared as
DER. This is what finds an issuer whose CA wrote its name differently.

<sub>[stdlib/Security/Cryptography/X509Certificates/X500DistinguishedName.sl:49](../../stdlib/Security/Cryptography/X509Certificates/X500DistinguishedName.sl#L49)</sub>

#### FromDer *method*

```
static Result<X500DistinguishedName, CryptoError> FromDer(ReadOnlySpan<byte> encoded)
```

The name one `Name` value in DER encodes.

**Parameters**

- `encoded` -- exactly one `SEQUENCE` of relative distinguished names

**Fails with**

- [CryptoError.Encoding](Standard-Security-Cryptography.md#encoding-case) -- it is not one, or a string value is not valid for its type

<sub>[stdlib/Security/Cryptography/X509Certificates/X500DistinguishedName.sl:69](../../stdlib/Security/Cryptography/X509Certificates/X500DistinguishedName.sl#L69)</sub>

#### RawData *property*

```
byte[] RawData { get; }
```

The name as DER.

<sub>[stdlib/Security/Cryptography/X509Certificates/X500DistinguishedName.sl:106](../../stdlib/Security/Cryptography/X509Certificates/X500DistinguishedName.sl#L106)</sub>

#### Name *property*

```
String Name { get; }
```

The name as .NET writes it: `CN=www.example.com, O=Example, C=US`.

<sub>[stdlib/Security/Cryptography/X509Certificates/X500DistinguishedName.sl:109](../../stdlib/Security/Cryptography/X509Certificates/X500DistinguishedName.sl#L109)</sub>

#### IsEmpty *property*

```
bool IsEmpty { get; }
```

Whether the name has no relative distinguished names at all.

<sub>[stdlib/Security/Cryptography/X509Certificates/X500DistinguishedName.sl:112](../../stdlib/Security/Cryptography/X509Certificates/X500DistinguishedName.sl#L112)</sub>

#### EnumerateRelativeDistinguishedNames *method*

```
List<X500RelativeDistinguishedName> EnumerateRelativeDistinguishedNames(bool reversed)
```

Each relative distinguished name.

**Parameters**

- `reversed` -- most specific first, as `Name` writes them, which is .NET's default; otherwise in the order they are encoded

<sub>[stdlib/Security/Cryptography/X509Certificates/X500DistinguishedName.sl:118](../../stdlib/Security/Cryptography/X509Certificates/X500DistinguishedName.sl#L118)</sub>

#### GetFirstValue *method*

```
Optional<String> GetFirstValue(String typeOid)
```

The text of the first attribute of type `typeOid`, most specific
first, or `None` when there is none or it is not a character string.

**Parameters**

- `typeOid` -- the attribute type, as `2.5.4.3` for a common name

<sub>[stdlib/Security/Cryptography/X509Certificates/X500DistinguishedName.sl:131](../../stdlib/Security/Cryptography/X509Certificates/X500DistinguishedName.sl#L131)</sub>

#### Equals *method*

```
bool Equals(X500DistinguishedName other)
```

Whether `other` names the same thing, as RFC 5280 compares names.

<sub>[stdlib/Security/Cryptography/X509Certificates/X500DistinguishedName.sl:149](../../stdlib/Security/Cryptography/X509Certificates/X500DistinguishedName.sl#L149)</sub>

### X500DistinguishedNameBuilder *class*

```
sealed class X500DistinguishedNameBuilder
```

Makes an `X500DistinguishedName` one attribute at a time: .NET's
`X500DistinguishedNameBuilder`.

```csharp
var builder = new X500DistinguishedNameBuilder();
builder.AddCountryOrRegion("US");
builder.AddOrganizationName("Example");
builder.AddCommonName("www.example.com");
var name = try builder.Build();              // CN=www.example.com, O=Example, C=US
```

**Each call adds one relative distinguished name, most general first**, so
the order of the calls is the order of the encoding and the reverse of
`Name`. Values are `UTF8String` except a country, which is a two-letter
`PrintableString`, and an e-mail address and a domain component, which
are `IA5String`.

<sub>[stdlib/Security/Cryptography/X509Certificates/X500DistinguishedNameBuilder.sl:44](../../stdlib/Security/Cryptography/X509Certificates/X500DistinguishedNameBuilder.sl#L44)</sub>

#### Add *method*

```
void Add(String typeOid, String value, UniversalTagNumber encodingType)
```

An attribute of any type.

A value its string type cannot hold, or a type that is not a dotted
identifier, is reported by `Build` rather than here.

**Parameters**

- `typeOid` -- the attribute type, dotted
- `value` -- its text
- `encodingType` -- the string type to write it as

<sub>[stdlib/Security/Cryptography/X509Certificates/X500DistinguishedNameBuilder.sl:64](../../stdlib/Security/Cryptography/X509Certificates/X500DistinguishedNameBuilder.sl#L64)</sub>

#### AddCommonName *method*

```
void AddCommonName(String commonName)
```

A common name, `CN`.

<sub>[stdlib/Security/Cryptography/X509Certificates/X500DistinguishedNameBuilder.sl:80](../../stdlib/Security/Cryptography/X509Certificates/X500DistinguishedNameBuilder.sl#L80)</sub>

#### AddOrganizationName *method*

```
void AddOrganizationName(String organizationName)
```

An organization, `O`.

<sub>[stdlib/Security/Cryptography/X509Certificates/X500DistinguishedNameBuilder.sl:83](../../stdlib/Security/Cryptography/X509Certificates/X500DistinguishedNameBuilder.sl#L83)</sub>

#### AddOrganizationalUnitName *method*

```
void AddOrganizationalUnitName(String organizationalUnitName)
```

An organizational unit, `OU`.

<sub>[stdlib/Security/Cryptography/X509Certificates/X500DistinguishedNameBuilder.sl:86](../../stdlib/Security/Cryptography/X509Certificates/X500DistinguishedNameBuilder.sl#L86)</sub>

#### AddLocalityName *method*

```
void AddLocalityName(String localityName)
```

A locality, `L`.

<sub>[stdlib/Security/Cryptography/X509Certificates/X500DistinguishedNameBuilder.sl:90](../../stdlib/Security/Cryptography/X509Certificates/X500DistinguishedNameBuilder.sl#L90)</sub>

#### AddStateOrProvinceName *method*

```
void AddStateOrProvinceName(String stateOrProvinceName)
```

A state or province, `S`.

<sub>[stdlib/Security/Cryptography/X509Certificates/X500DistinguishedNameBuilder.sl:93](../../stdlib/Security/Cryptography/X509Certificates/X500DistinguishedNameBuilder.sl#L93)</sub>

#### AddCountryOrRegion *method*

```
void AddCountryOrRegion(String twoLetterCode)
```

A country, `C`: two letters, as ISO 3166 writes it. Anything else is
reported by `Build`.

<sub>[stdlib/Security/Cryptography/X509Certificates/X500DistinguishedNameBuilder.sl:98](../../stdlib/Security/Cryptography/X509Certificates/X500DistinguishedNameBuilder.sl#L98)</sub>

#### AddEmailAddress *method*

```
void AddEmailAddress(String emailAddress)
```

An e-mail address, `E`, as PKCS #9 names one.

<sub>[stdlib/Security/Cryptography/X509Certificates/X500DistinguishedNameBuilder.sl:106](../../stdlib/Security/Cryptography/X509Certificates/X500DistinguishedNameBuilder.sl#L106)</sub>

#### AddDomainComponent *method*

```
void AddDomainComponent(String domainComponent)
```

A domain component, `DC`.

<sub>[stdlib/Security/Cryptography/X509Certificates/X500DistinguishedNameBuilder.sl:110](../../stdlib/Security/Cryptography/X509Certificates/X500DistinguishedNameBuilder.sl#L110)</sub>

#### Build *method*

```
Result<X500DistinguishedName, CryptoError> Build()
```

The name, in the order the attributes were added.

**Fails with**

- [CryptoError.Encoding](Standard-Security-Cryptography.md#encoding-case) -- an attribute type was not an identifier, or a value was not valid for its string type

<sub>[stdlib/Security/Cryptography/X509Certificates/X500DistinguishedNameBuilder.sl:117](../../stdlib/Security/Cryptography/X509Certificates/X500DistinguishedNameBuilder.sl#L117)</sub>

### X500RelativeDistinguishedName *class*

```
sealed class X500RelativeDistinguishedName
```

One step of a distinguished name: a `SET` of attribute types and values,
almost always of one, such as `CN=www.example.com`.

.NET's `X500RelativeDistinguishedName`, with each type a dotted object
identifier. A value that is a character string is its text; any other is
`#` and the hexadecimal of its DER, as RFC 4514 writes one.

**See also** &nbsp; [X500DistinguishedName.EnumerateRelativeDistinguishedNames](#enumeraterelativedistinguishednames-method)

<sub>[stdlib/Security/Cryptography/X509Certificates/X500RelativeDistinguishedName.sl:32](../../stdlib/Security/Cryptography/X509Certificates/X500RelativeDistinguishedName.sl#L32)</sub>

#### RawData *property*

```
byte[] RawData { get; }
```

The `SET`, as DER.

<sub>[stdlib/Security/Cryptography/X509Certificates/X500RelativeDistinguishedName.sl:49](../../stdlib/Security/Cryptography/X509Certificates/X500RelativeDistinguishedName.sl#L49)</sub>

#### Count *property*

```
nuint Count { get; }
```

How many attributes it holds; one or more.

<sub>[stdlib/Security/Cryptography/X509Certificates/X500RelativeDistinguishedName.sl:52](../../stdlib/Security/Cryptography/X509Certificates/X500RelativeDistinguishedName.sl#L52)</sub>

#### HasMultipleElements *property*

```
bool HasMultipleElements { get; }
```

Whether it holds more than one attribute.

<sub>[stdlib/Security/Cryptography/X509Certificates/X500RelativeDistinguishedName.sl:55](../../stdlib/Security/Cryptography/X509Certificates/X500RelativeDistinguishedName.sl#L55)</sub>

#### GetElementType *method*

```
String GetElementType(nuint index)
```

The type of attribute `index`: `2.5.4.3` for a common name.

**Parameters**

- `index` -- below `Count`; aborts otherwise

<sub>[stdlib/Security/Cryptography/X509Certificates/X500RelativeDistinguishedName.sl:60](../../stdlib/Security/Cryptography/X509Certificates/X500RelativeDistinguishedName.sl#L60)</sub>

#### GetElementValue *method*

```
String GetElementValue(nuint index)
```

The value of attribute `index`, as text or as `#` and hexadecimal.

**Parameters**

- `index` -- below `Count`; aborts otherwise

<sub>[stdlib/Security/Cryptography/X509Certificates/X500RelativeDistinguishedName.sl:65](../../stdlib/Security/Cryptography/X509Certificates/X500RelativeDistinguishedName.sl#L65)</sub>

#### IsElementText *method*

```
bool IsElementText(nuint index)
```

Whether the value of attribute `index` is a character string.

**Parameters**

- `index` -- below `Count`; aborts otherwise

<sub>[stdlib/Security/Cryptography/X509Certificates/X500RelativeDistinguishedName.sl:70](../../stdlib/Security/Cryptography/X509Certificates/X500RelativeDistinguishedName.sl#L70)</sub>

#### GetSingleElementType *method*

```
String GetSingleElementType()
```

The type of the one attribute. A caller MUST ask
`HasMultipleElements` first; this aborts when there are several.

<sub>[stdlib/Security/Cryptography/X509Certificates/X500RelativeDistinguishedName.sl:74](../../stdlib/Security/Cryptography/X509Certificates/X500RelativeDistinguishedName.sl#L74)</sub>

#### GetSingleElementValue *method*

```
Optional<String> GetSingleElementValue()
```

The text of the one attribute, or `None` when it is not a character
string. Aborts when there are several, as `GetSingleElementType` does.

<sub>[stdlib/Security/Cryptography/X509Certificates/X500RelativeDistinguishedName.sl:83](../../stdlib/Security/Cryptography/X509Certificates/X500RelativeDistinguishedName.sl#L83)</sub>

### X509AuthorityKeyIdentifierExtension *class*

```
sealed class X509AuthorityKeyIdentifierExtension : X509Extension
```

Which key signed the certificate: RFC 5280 §4.2.1.1, `2.5.29.35`.

A chain building from a certificate with a key identifier here passes
over any issuer whose subject key identifier is different, which is what
picks the right one of two CAs with the same name.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509AuthorityKeyIdentifierExtension.sl:32](../../stdlib/Security/Cryptography/X509Certificates/X509AuthorityKeyIdentifierExtension.sl#L32)</sub>

#### KeyIdentifier *property*

```
Optional<byte[]> KeyIdentifier { get; }
```

The signing key's identifier, when there is one.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509AuthorityKeyIdentifierExtension.sl:50](../../stdlib/Security/Cryptography/X509Certificates/X509AuthorityKeyIdentifierExtension.sl#L50)</sub>

#### RawIssuer *property*

```
Optional<byte[]> RawIssuer { get; }
```

The issuer's issuer as `GeneralNames` in DER, when there is one.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509AuthorityKeyIdentifierExtension.sl:53](../../stdlib/Security/Cryptography/X509Certificates/X509AuthorityKeyIdentifierExtension.sl#L53)</sub>

#### SerialNumber *property*

```
Optional<byte[]> SerialNumber { get; }
```

The issuer's serial number, big-endian, when there is one.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509AuthorityKeyIdentifierExtension.sl:56](../../stdlib/Security/Cryptography/X509Certificates/X509AuthorityKeyIdentifierExtension.sl#L56)</sub>

#### CreateFromSubjectKeyIdentifier *method*

```
static X509AuthorityKeyIdentifierExtension CreateFromSubjectKeyIdentifier(ReadOnlySpan<byte> subjectKeyIdentifier)
```

The extension naming the key `subjectKeyIdentifier`, and nothing else:
what a CA puts in what it issues.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509AuthorityKeyIdentifierExtension.sl:60](../../stdlib/Security/Cryptography/X509Certificates/X509AuthorityKeyIdentifierExtension.sl#L60)</sub>

#### CreateFromCertificate *method*

```
static X509AuthorityKeyIdentifierExtension CreateFromCertificate(X509Certificate2 certificateAuthority, bool includeKeyIdentifier, bool includeIssuerAndSerial)
```

The extension a certificate issued by `certificateAuthority` carries.

**Parameters**

- `certificateAuthority` -- the issuer
- `includeKeyIdentifier` -- whether to name its key: its subject key identifier, or one made from its key when it has none
- `includeIssuerAndSerial` -- whether to name it by its own issuer and serial number as well

<sub>[stdlib/Security/Cryptography/X509Certificates/X509AuthorityKeyIdentifierExtension.sl:79](../../stdlib/Security/Cryptography/X509Certificates/X509AuthorityKeyIdentifierExtension.sl#L79)</sub>

### X509BasicConstraintsExtension *class*

```
sealed class X509BasicConstraintsExtension : X509Extension
```

Whether the subject is a CA, and how many CAs may follow it: RFC 5280
§4.2.1.9, `2.5.29.19`.

A CA's certificate MUST have this with `CertificateAuthority` set for a
chain to pass through it. The path length counts the intermediate CAs
that may stand between this one and a leaf.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509BasicConstraintsExtension.sl:33](../../stdlib/Security/Cryptography/X509Certificates/X509BasicConstraintsExtension.sl#L33)</sub>

#### CertificateAuthority *property*

```
bool CertificateAuthority { get; }
```

Whether the subject is a CA.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509BasicConstraintsExtension.sl:65](../../stdlib/Security/Cryptography/X509Certificates/X509BasicConstraintsExtension.sl#L65)</sub>

#### HasPathLengthConstraint *property*

```
bool HasPathLengthConstraint { get; }
```

Whether the path length is limited.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509BasicConstraintsExtension.sl:68](../../stdlib/Security/Cryptography/X509Certificates/X509BasicConstraintsExtension.sl#L68)</sub>

#### PathLengthConstraint *property*

```
int PathLengthConstraint { get; }
```

How many intermediate CAs may follow this one; zero when there is no
limit.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509BasicConstraintsExtension.sl:72](../../stdlib/Security/Cryptography/X509Certificates/X509BasicConstraintsExtension.sl#L72)</sub>

### X509Certificate2 *class*

```
sealed class X509Certificate2
```

An X.509 certificate, read from DER or PEM: .NET's `X509Certificate2`,
without a private key.

```csharp
var certificate = try X509Certificate2.FromPem(File.ReadAllText("server.pem"));
Console.WriteLine(certificate.Subject);        // CN=www.example.com, O=Example, C=US
Console.WriteLine(certificate.Thumbprint);     // the SHA-1, as .NET and Windows show it
bool mine = certificate.MatchesHostname("www.example.com");
```

**Everything is read when the certificate is**, and checked then: the DER,
the names, the key's `SubjectPublicKeyInfo`, and every extension this
module knows. What comes back is immutable, so one MAY be shared between
threads. The signature is not checked here; that is `X509Chain`'s job,
since it needs the issuer.

**See also** &nbsp; [X509Chain](#x509chain-class)

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl:45](../../stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl#L45)</sub>

#### FromDer *method*

```
static Result<X509Certificate2, CryptoError> FromDer(ReadOnlySpan<byte> data)
```

The certificate `data` holds, as DER.

**Parameters**

- `data` -- exactly one `Certificate`, with nothing after it

**Fails with**

- [CryptoError.Encoding](Standard-Security-Cryptography.md#encoding-case) -- it is not one, as the module's summary reads RFC 5280

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl:133](../../stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl#L133)</sub>

#### FromPem *method*

```
static Result<X509Certificate2, CryptoError> FromPem(String text)
```

The first `CERTIFICATE` block in `text`, as .NET's `CreateFromPem`
finds it. Blocks with other labels are passed over.

**Parameters**

- `text` -- PEM, perhaps among other text

**Fails with**

- [CryptoError.Encoding](Standard-Security-Cryptography.md#encoding-case) -- there is no `CERTIFICATE` block, or the first one does not hold a certificate

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl:227](../../stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl#L227)</sub>

#### RawData *property*

```
byte[] RawData { get; }
```

The whole certificate, as DER: a copy, so that changing it changes
nothing here.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl:243](../../stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl#L243)</sub>

#### Version *property*

```
int Version { get; }
```

1, 2 or 3.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl:246](../../stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl#L246)</sub>

#### SerialNumber *property*

```
String SerialNumber { get; }
```

The serial number in upper-case hexadecimal, as its DER contents are
written: `00FF` for a positive number whose top bit is set.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl:250](../../stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl#L250)</sub>

#### SerialNumberBytes *property*

```
byte[] SerialNumberBytes { get; }
```

The serial number's DER contents, big-endian and two's complement.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl:253](../../stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl#L253)</sub>

#### SignatureAlgorithm *property*

```
String SignatureAlgorithm { get; }
```

The signature algorithm, dotted: `1.3.101.112` for Ed25519,
`1.2.840.10045.4.3.2` for ECDSA with SHA-256.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl:257](../../stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl#L257)</sub>

#### IssuerName *property*

```
X500DistinguishedName IssuerName { get; }
```

Who issued it.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl:260](../../stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl#L260)</sub>

#### SubjectName *property*

```
X500DistinguishedName SubjectName { get; }
```

Who it is for.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl:263](../../stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl#L263)</sub>

#### Issuer *property*

```
String Issuer { get; }
```

`IssuerName.Name`.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl:266](../../stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl#L266)</sub>

#### Subject *property*

```
String Subject { get; }
```

`SubjectName.Name`.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl:269](../../stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl#L269)</sub>

#### NotBefore *property*

```
long NotBefore { get; }
```

The first moment it is valid, in seconds since the epoch.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl:272](../../stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl#L272)</sub>

#### NotAfter *property*

```
long NotAfter { get; }
```

The last moment it is valid, in seconds since the epoch.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl:275](../../stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl#L275)</sub>

#### PublicKey *property*

```
PublicKey PublicKey { get; }
```

The subject's key.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl:278](../../stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl#L278)</sub>

#### Extensions *property*

```
X509ExtensionCollection Extensions { get; }
```

Every extension.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl:281](../../stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl#L281)</sub>

#### Thumbprint *property*

```
String Thumbprint { get; }
```

The SHA-1 of the DER in upper-case hexadecimal: what .NET, Windows and
`openssl x509 -fingerprint` show.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl:285](../../stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl#L285)</sub>

#### Sha256Thumbprint *property*

```
String Sha256Thumbprint { get; }
```

The SHA-256 of the DER in upper-case hexadecimal.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl:288](../../stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl#L288)</sub>

#### IsSelfIssued *property*

```
bool IsSelfIssued { get; }
```

Whether the issuer and the subject are the same name, which a root's
are and a leaf's usually are not.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl:292](../../stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl#L292)</sub>

#### BasicConstraints *property*

```
X509BasicConstraintsExtension? BasicConstraints { get; }
```

The basic constraints extension, or null.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl:295](../../stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl#L295)</sub>

#### KeyUsage *property*

```
X509KeyUsageExtension? KeyUsage { get; }
```

The key usage extension, or null.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl:298](../../stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl#L298)</sub>

#### EnhancedKeyUsage *property*

```
X509EnhancedKeyUsageExtension? EnhancedKeyUsage { get; }
```

The extended key usage extension, or null.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl:301](../../stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl#L301)</sub>

#### SubjectAlternativeName *property*

```
X509SubjectAlternativeNameExtension? SubjectAlternativeName { get; }
```

The subject alternative name extension, or null.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl:304](../../stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl#L304)</sub>

#### SubjectKeyIdentifier *property*

```
X509SubjectKeyIdentifierExtension? SubjectKeyIdentifier { get; }
```

The subject key identifier extension, or null.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl:307](../../stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl#L307)</sub>

#### AuthorityKeyIdentifier *property*

```
X509AuthorityKeyIdentifierExtension? AuthorityKeyIdentifier { get; }
```

The authority key identifier extension, or null.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl:310](../../stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl#L310)</sub>

#### NameConstraints *property*

```
X509NameConstraintsExtension? NameConstraints { get; }
```

The name constraints extension, or null.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl:313](../../stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl#L313)</sub>

#### GetNotBeforeDateTimeOffset *method*

```
Result<DateTimeOffset, CryptoError> GetNotBeforeDateTimeOffset()
```

`NotBefore` as a `DateTimeOffset`.

**Fails with**

- [CryptoError.Parameter](Standard-Security-Cryptography.md#parameter-case) -- the moment is outside 1677 to 2262, which is what a `DateTimeOffset` holds

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl:333](../../stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl#L333)</sub>

#### GetNotAfterDateTimeOffset *method*

```
Result<DateTimeOffset, CryptoError> GetNotAfterDateTimeOffset()
```

`NotAfter` as a `DateTimeOffset`.

**Fails with**

- [CryptoError.Parameter](Standard-Security-Cryptography.md#parameter-case) -- the moment is outside 1677 to 2262, which is what a `DateTimeOffset` holds

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl:340](../../stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl#L340)</sub>

#### GetCertHash *method*

```
Result<byte[], CryptoError> GetCertHash(HashAlgorithmName hashAlgorithm)
```

The hash of the DER under `hashAlgorithm`.

**Fails with**

- [CryptoError.Unsupported](Standard-Security-Cryptography.md#unsupported-case) -- `hashAlgorithm` is not one this library has

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl:354](../../stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl#L354)</sub>

#### GetCertHashString *method*

```
Result<String, CryptoError> GetCertHashString(HashAlgorithmName hashAlgorithm)
```

The same, in upper-case hexadecimal.

**Fails with**

- [CryptoError.Unsupported](Standard-Security-Cryptography.md#unsupported-case) -- `hashAlgorithm` is not one this library has

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl:364](../../stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl#L364)</sub>

#### ExportCertificatePem *method*

```
String ExportCertificatePem()
```

The certificate as PEM, with a `CERTIFICATE` label and no newline after
the last line.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl:369](../../stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl#L369)</sub>

#### Equals *method*

```
bool Equals(X509Certificate2 other)
```

Whether `other` is this certificate, byte for byte.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl:372](../../stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl#L372)</sub>

#### MatchesHostname *method*

```
bool MatchesHostname(String hostname, bool allowWildcards)
```

Whether the certificate names `hostname`, by RFC 6125 and the CA/Browser
Forum's rules.

- **Only the subject alternative name is consulted.** A certificate
  with no DNS name there matches no host name, whatever its common name
  says; no current browser falls back, and neither does this.
- A DNS name compares case-insensitively in ASCII, with one trailing
  dot on either side ignored. A name that is not ASCII letters, digits,
  `-`, `_` and dots matches nothing; an internationalized name MUST be
  given as its `xn--` form.
- A wildcard is only the whole left-most label, `*.example.com`; it
  stands for exactly one non-empty label, and is honoured only with at
  least two labels after it, so `*.com` matches nothing.
- An address — dotted IPv4, or IPv6 with or without brackets —
  matches only an `iPAddress` entry, compared as bytes, and never a DNS
  name that spells it.

**Parameters**

- `hostname` -- what the client asked to connect to
- `allowWildcards` -- whether a wildcard entry may match

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl:393](../../stdlib/Security/Cryptography/X509Certificates/X509Certificate2.sl#L393)</sub>

### X509Certificate2Collection *class*

```
sealed class X509Certificate2Collection
```

An ordered set of certificates: .NET's `X509Certificate2Collection`.

```csharp
var bundle = new X509Certificate2Collection();
nuint added = try bundle.ImportFromPem(File.ReadAllText("chain.pem"));
foreach (X509Certificate2 certificate in bundle)
    Console.WriteLine(certificate.Subject);
```

A certificate already present, byte for byte, is not added a second time.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Certificate2Collection.sl:37](../../stdlib/Security/Cryptography/X509Certificates/X509Certificate2Collection.sl#L37)</sub>

#### Count *property*

```
nuint Count { get; }
```

How many certificates there are.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Certificate2Collection.sl:48](../../stdlib/Security/Cryptography/X509Certificates/X509Certificate2Collection.sl#L48)</sub>

#### this[] *indexer*

```
X509Certificate2 this[nuint index] { get; }
```

Certificate `index`, in the order they were added; aborts past `Count`.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Certificate2Collection.sl:51](../../stdlib/Security/Cryptography/X509Certificates/X509Certificate2Collection.sl#L51)</sub>

#### GetEnumerator *method*

```
IEnumerator<X509Certificate2> GetEnumerator()
```

Each certificate in turn.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Certificate2Collection.sl:54](../../stdlib/Security/Cryptography/X509Certificates/X509Certificate2Collection.sl#L54)</sub>

#### Add *method*

```
bool Add(X509Certificate2 certificate)
```

Adds `certificate` unless it is already here.

**Returns** &nbsp; whether it was added

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Certificate2Collection.sl:59](../../stdlib/Security/Cryptography/X509Certificates/X509Certificate2Collection.sl#L59)</sub>

#### AddRange *method*

```
void AddRange(X509Certificate2Collection certificates)
```

Adds each of `certificates` that is not already here.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Certificate2Collection.sl:68](../../stdlib/Security/Cryptography/X509Certificates/X509Certificate2Collection.sl#L68)</sub>

#### Contains *method*

```
bool Contains(X509Certificate2 certificate)
```

Whether `certificate` is here, byte for byte.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Certificate2Collection.sl:75](../../stdlib/Security/Cryptography/X509Certificates/X509Certificate2Collection.sl#L75)</sub>

#### Remove *method*

```
bool Remove(X509Certificate2 certificate)
```

Removes `certificate`, when it is here.

**Returns** &nbsp; whether it was

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Certificate2Collection.sl:88](../../stdlib/Security/Cryptography/X509Certificates/X509Certificate2Collection.sl#L88)</sub>

#### ImportFromPem *method*

```
Result<nuint, CryptoError> ImportFromPem(String text)
```

Every certificate in the `CERTIFICATE` blocks of `text`, as a PEM
bundle holds them. Blocks with other labels are passed over.

**All or nothing**: when one block does not hold a certificate,
nothing is added.

**Parameters**

- `text` -- PEM, perhaps among other text

**Returns** &nbsp; how many were added, not counting any already here

**Fails with**

- [CryptoError.Encoding](Standard-Security-Cryptography.md#encoding-case) -- a `CERTIFICATE` block does not hold a certificate

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Certificate2Collection.sl:110](../../stdlib/Security/Cryptography/X509Certificates/X509Certificate2Collection.sl#L110)</sub>

#### ExportCertificatePems *method*

```
String ExportCertificatePems()
```

Every certificate as PEM, one block after another, each followed by a
newline: a bundle `ImportFromPem` reads back.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Certificate2Collection.sl:150](../../stdlib/Security/Cryptography/X509Certificates/X509Certificate2Collection.sl#L150)</sub>

### X509Chain *class*

```
sealed class X509Chain
```

Builds a path from a certificate to a trust anchor and validates it:
.NET's `X509Chain`, doing its own work rather than asking the platform.

```csharp
var chain = new X509Chain();
chain.ChainPolicy.ExtraStore.AddRange(sentByTheServer);
chain.ChainPolicy.ApplicationPolicy.Add(X509EnhancedKeyUsageExtension.ServerAuthenticationOid);
if (!chain.Build(leaf) || !leaf.MatchesHostname(host))
    return Fail(...);
```

**Building.** From the certificate, an issuer is any certificate among
the anchors or the extra store whose subject is its issuer's name, as RFC
5280 compares names, and whose subject key identifier, when both sides
have one, is its authority key identifier. Anchors are tried first, then
intermediates valid at the verification time, then the rest; every
alternative is tried in turn, so a cross-signed intermediate or a second
CA of the same name is found when the first does not lead anywhere. A
path stops at any anchor, self-signed or not. A path holds at most eight
certificates, and at most 128 candidates are tried in all.

**Validating** each path, the first that passes everything is kept, and
otherwise the first that reached an anchor, and otherwise the longest:

- every certificate valid at `VerificationTime`, the anchor included;
- every signature verified, the anchor's own excepted, and none over
  SHA-1;
- every issuer a CA with basic constraints — an anchor may have none, as
  a version 1 root does — and not more non-self-issued intermediates
  below it than its path length allows;
- every issuer's key usage, when it has one, allowing `KeyCertSign`;
- the application policy allowed by the leaf's extended key usage and by
  that of every intermediate that has one; and for a TLS purpose the
  leaf's key usage, when it has one, allowing a signature, key
  encipherment or key agreement;
- the leaf's DNS and IP subject alternative names inside the name
  constraints of every issuer above it;
- no critical extension this module does not understand.

No revocation is checked; see `X509RevocationMode`.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Chain.sl:67](../../stdlib/Security/Cryptography/X509Certificates/X509Chain.sl#L67)</sub>

#### ChainPolicy *property*

```
X509ChainPolicy ChainPolicy { get; set; }
```

What the next `Build` is held to.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Chain.sl:96](../../stdlib/Security/Cryptography/X509Certificates/X509Chain.sl#L96)</sub>

#### ChainElements *property*

```
X509ChainElement[] ChainElements { get; }
```

The path the last `Build` chose, from the certificate to the anchor, or
as far as it got.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Chain.sl:104](../../stdlib/Security/Cryptography/X509Certificates/X509Chain.sl#L104)</sub>

#### ChainStatus *property*

```
X509ChainStatus[] ChainStatus { get; }
```

Everything wrong with the last `Build`, one flag each; empty when it
passed.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Chain.sl:108](../../stdlib/Security/Cryptography/X509Certificates/X509Chain.sl#L108)</sub>

#### StatusFlags *property*

```
X509ChainStatusFlags StatusFlags { get; }
```

Everything wrong with the last `Build`, as one set of flags.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Chain.sl:111](../../stdlib/Security/Cryptography/X509Certificates/X509Chain.sl#L111)</sub>

#### Reset *method*

```
void Reset()
```

Forgets the last `Build`; the policy stays.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Chain.sl:114](../../stdlib/Security/Cryptography/X509Certificates/X509Chain.sl#L114)</sub>

#### Build *method*

```
bool Build(X509Certificate2 certificate)
```

Builds and validates a path from `certificate`.

**Parameters**

- `certificate` -- the leaf, usually a server's

**Returns** &nbsp; whether a path reached an anchor and passed every check; `ChainElements` and `ChainStatus` say what was found either way

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Chain.sl:125](../../stdlib/Security/Cryptography/X509Certificates/X509Chain.sl#L125)</sub>

### X509ChainElement *class*

```
sealed class X509ChainElement
```

One certificate of a built chain and what is wrong with it: .NET's
`X509ChainElement`.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509ChainElement.sl:26](../../stdlib/Security/Cryptography/X509Certificates/X509ChainElement.sl#L26)</sub>

#### Certificate *property*

```
X509Certificate2 Certificate { get; }
```

The certificate.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509ChainElement.sl:38](../../stdlib/Security/Cryptography/X509Certificates/X509ChainElement.sl#L38)</sub>

#### ChainElementStatus *property*

```
X509ChainStatus[] ChainElementStatus { get; }
```

Everything wrong with it, one flag each.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509ChainElement.sl:41](../../stdlib/Security/Cryptography/X509Certificates/X509ChainElement.sl#L41)</sub>

#### StatusFlags *property*

```
X509ChainStatusFlags StatusFlags { get; }
```

Everything wrong with it, as one set of flags; `NoError` when nothing is.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509ChainElement.sl:44](../../stdlib/Security/Cryptography/X509Certificates/X509ChainElement.sl#L44)</sub>

### X509ChainPolicy *class*

```
sealed class X509ChainPolicy
```

What a chain is built from and held to: .NET's `X509ChainPolicy`.

```csharp
var policy = chain.ChainPolicy;
policy.TrustMode = X509ChainTrustMode.CustomRootTrust;
policy.CustomTrustStore.Add(root);
policy.ExtraStore.Add(intermediate);
policy.ApplicationPolicy.Add(X509EnhancedKeyUsageExtension.ServerAuthenticationOid);
policy.VerificationTime = 1790812800;
```

<sub>[stdlib/Security/Cryptography/X509Certificates/X509ChainPolicy.sl:37](../../stdlib/Security/Cryptography/X509Certificates/X509ChainPolicy.sl#L37)</sub>

#### ApplicationPolicy *property*

```
List<String> ApplicationPolicy { get; }
```

Purposes the leaf MUST serve, as dotted extended key usages; an
intermediate that lists extended key usages MUST allow them too.
Empty asks nothing.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509ChainPolicy.sl:58](../../stdlib/Security/Cryptography/X509Certificates/X509ChainPolicy.sl#L58)</sub>

#### ExtraStore *property*

```
X509Certificate2Collection ExtraStore { get; }
```

Intermediates to build through, as a server sends them. Nothing here
is trusted for being here.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509ChainPolicy.sl:62](../../stdlib/Security/Cryptography/X509Certificates/X509ChainPolicy.sl#L62)</sub>

#### CustomTrustStore *property*

```
X509Certificate2Collection CustomTrustStore { get; }
```

The trust anchors when `TrustMode` is `CustomRootTrust`. Any
certificate here is an anchor, self-signed or not.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509ChainPolicy.sl:66](../../stdlib/Security/Cryptography/X509Certificates/X509ChainPolicy.sl#L66)</sub>

#### TrustMode *property*

```
X509ChainTrustMode TrustMode { get; set; }
```

Where the anchors come from.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509ChainPolicy.sl:69](../../stdlib/Security/Cryptography/X509Certificates/X509ChainPolicy.sl#L69)</sub>

#### RevocationMode *property*

```
X509RevocationMode RevocationMode { get; set; }
```

Whether revocation is asked about; see `X509RevocationMode`.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509ChainPolicy.sl:72](../../stdlib/Security/Cryptography/X509Certificates/X509ChainPolicy.sl#L72)</sub>

#### VerificationTime *property*

```
long VerificationTime { get; set; }
```

The moment every certificate MUST be valid at, in seconds since the
epoch.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509ChainPolicy.sl:76](../../stdlib/Security/Cryptography/X509Certificates/X509ChainPolicy.sl#L76)</sub>

#### Reset *method*

```
void Reset()
```

Back to the defaults, with the time now.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509ChainPolicy.sl:79](../../stdlib/Security/Cryptography/X509Certificates/X509ChainPolicy.sl#L79)</sub>

### X509ChainStatus *struct*

```
struct X509ChainStatus
```

One thing wrong with a chain or an element of it: .NET's
`X509ChainStatus`.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509ChainStatus.sl:26](../../stdlib/Security/Cryptography/X509Certificates/X509ChainStatus.sl#L26)</sub>

#### Status *field*

```
X509ChainStatusFlags Status
```

The flag, one bit of `X509ChainStatusFlags`.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509ChainStatus.sl:29](../../stdlib/Security/Cryptography/X509Certificates/X509ChainStatus.sl#L29)</sub>

#### StatusInformation *field*

```
String StatusInformation
```

A sentence saying what it means.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509ChainStatus.sl:32](../../stdlib/Security/Cryptography/X509Certificates/X509ChainStatus.sl#L32)</sub>

### X509ChainStatusFlags *enum*

```
enum X509ChainStatusFlags
```

What is wrong with a chain or one certificate in it: .NET's
`X509ChainStatusFlags`, with .NET's values, and set in the same
circumstances wherever this module checks the same thing.

Flags .NET has and nothing here sets — the certificate trust list ones,
`NotTimeNested`, `Revoked`, the policy ones — are kept, so that a program
written against .NET's names compiles.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl:31](../../stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl#L31)</sub>

#### NoError *case*

```
NoError = 0
```

Nothing is wrong.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl:35](../../stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl#L35)</sub>

#### NotTimeValid *case*

```
NotTimeValid = 1
```

The verification time is before `NotBefore` or after `NotAfter`.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl:38](../../stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl#L38)</sub>

#### NotTimeNested *case*

```
NotTimeNested = 2
```

Never set; RFC 5280 does not require nesting.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl:41](../../stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl#L41)</sub>

#### Revoked *case*

```
Revoked = 4
```

Never set; there is no revocation checking.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl:44](../../stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl#L44)</sub>

#### NotSignatureValid *case*

```
NotSignatureValid = 8
```

The signature does not verify under the issuer's key, or its algorithm
is one this module does not verify.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl:48](../../stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl#L48)</sub>

#### NotValidForUsage *case*

```
NotValidForUsage = 16
```

A key usage or extended key usage forbids what the chain was built for:
an issuer without `KeyCertSign`, or a leaf or intermediate without the
application policy asked for.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl:53](../../stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl#L53)</sub>

#### UntrustedRoot *case*

```
UntrustedRoot = 32
```

The chain ends in a self-signed certificate that is not trusted.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl:56](../../stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl#L56)</sub>

#### RevocationStatusUnknown *case*

```
RevocationStatusUnknown = 64
```

Revocation was asked for, and there is none to give.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl:59](../../stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl#L59)</sub>

#### Cyclic *case*

```
Cyclic = 128
```

Every path from the certificate loops back on itself.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl:62](../../stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl#L62)</sub>

#### InvalidExtension *case*

```
InvalidExtension = 256
```

A critical extension is one this module does not understand.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl:65](../../stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl#L65)</sub>

#### InvalidPolicyConstraints *case*

```
InvalidPolicyConstraints = 512
```

Never set; no policy is enforced.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl:68](../../stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl#L68)</sub>

#### InvalidBasicConstraints *case*

```
InvalidBasicConstraints = 1024
```

An issuer is not a CA, or more CAs stand below it than its path length
allows.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl:72](../../stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl#L72)</sub>

#### InvalidNameConstraints *case*

```
InvalidNameConstraints = 2048
```

Never set; a malformed name constraint does not parse at all.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl:75](../../stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl#L75)</sub>

#### HasNotSupportedNameConstraint *case*

```
HasNotSupportedNameConstraint = 4096
```

Never set; a constraint of an unenforced kind is passed over.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl:78](../../stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl#L78)</sub>

#### HasNotDefinedNameConstraint *case*

```
HasNotDefinedNameConstraint = 8192
```

Never set.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl:81](../../stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl#L81)</sub>

#### HasNotPermittedNameConstraint *case*

```
HasNotPermittedNameConstraint = 16384
```

A name of the leaf is outside every permitted subtree of its kind.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl:84](../../stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl#L84)</sub>

#### HasExcludedNameConstraint *case*

```
HasExcludedNameConstraint = 32768
```

A name of the leaf is inside an excluded subtree.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl:87](../../stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl#L87)</sub>

#### PartialChain *case*

```
PartialChain = 65536
```

No path reaches a trusted certificate.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl:90](../../stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl#L90)</sub>

#### CtlNotTimeValid *case*

```
CtlNotTimeValid = 131072
```

Never set.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl:93](../../stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl#L93)</sub>

#### CtlNotSignatureValid *case*

```
CtlNotSignatureValid = 262144
```

Never set.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl:96](../../stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl#L96)</sub>

#### CtlNotValidForUsage *case*

```
CtlNotValidForUsage = 524288
```

Never set.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl:99](../../stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl#L99)</sub>

#### HasWeakSignature *case*

```
HasWeakSignature = 1048576
```

A signature is made over SHA-1, which no longer resists collision.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl:102](../../stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl#L102)</sub>

#### OfflineRevocation *case*

```
OfflineRevocation = 16777216
```

Revocation was asked for, and nothing could be reached to answer it.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl:105](../../stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl#L105)</sub>

#### NoIssuanceChainPolicy *case*

```
NoIssuanceChainPolicy = 33554432
```

Never set.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl:108](../../stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl#L108)</sub>

#### ExplicitDistrust *case*

```
ExplicitDistrust = 67108864
```

Never set.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl:111](../../stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl#L111)</sub>

#### HasNotSupportedCriticalExtension *case*

```
HasNotSupportedCriticalExtension = 134217728
```

A critical extension is one this module does not understand; set with
`InvalidExtension`.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl:115](../../stdlib/Security/Cryptography/X509Certificates/X509ChainStatusFlags.sl#L115)</sub>

### X509ChainTrustMode *enum*

```
enum X509ChainTrustMode
```

Where a chain's trust anchors come from: .NET's `X509ChainTrustMode`.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509ChainTrustMode.sl:25](../../stdlib/Security/Cryptography/X509Certificates/X509ChainTrustMode.sl#L25)</sub>

#### System *case*

```
System
```

The platform's root store, as `X509Store` opens it.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509ChainTrustMode.sl:28](../../stdlib/Security/Cryptography/X509Certificates/X509ChainTrustMode.sl#L28)</sub>

#### CustomRootTrust *case*

```
CustomRootTrust
```

`X509ChainPolicy.CustomTrustStore` and nothing else.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509ChainTrustMode.sl:31](../../stdlib/Security/Cryptography/X509Certificates/X509ChainTrustMode.sl#L31)</sub>

### X509EnhancedKeyUsageExtension *class*

```
sealed class X509EnhancedKeyUsageExtension : X509Extension
```

The purposes the key may serve: RFC 5280 §4.2.1.12's extended key usage,
`2.5.29.37`.

```csharp
var usage = new X509EnhancedKeyUsageExtension(
    [X509EnhancedKeyUsageExtension.ServerAuthenticationOid], false);
```

A chain asked for an application policy requires the leaf, and any
intermediate that has this, to list that purpose or
`AnyExtendedKeyUsageOid`. A certificate without it is not restricted.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509EnhancedKeyUsageExtension.sl:39](../../stdlib/Security/Cryptography/X509Certificates/X509EnhancedKeyUsageExtension.sl#L39)</sub>

#### ServerAuthenticationOid *property*

```
static String ServerAuthenticationOid { get; }
```

`id-kp-serverAuth`: a TLS server.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509EnhancedKeyUsageExtension.sl:61](../../stdlib/Security/Cryptography/X509Certificates/X509EnhancedKeyUsageExtension.sl#L61)</sub>

#### ClientAuthenticationOid *property*

```
static String ClientAuthenticationOid { get; }
```

`id-kp-clientAuth`: a TLS client.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509EnhancedKeyUsageExtension.sl:64](../../stdlib/Security/Cryptography/X509Certificates/X509EnhancedKeyUsageExtension.sl#L64)</sub>

#### CodeSigningOid *property*

```
static String CodeSigningOid { get; }
```

`id-kp-codeSigning`.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509EnhancedKeyUsageExtension.sl:67](../../stdlib/Security/Cryptography/X509Certificates/X509EnhancedKeyUsageExtension.sl#L67)</sub>

#### EmailProtectionOid *property*

```
static String EmailProtectionOid { get; }
```

`id-kp-emailProtection`.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509EnhancedKeyUsageExtension.sl:70](../../stdlib/Security/Cryptography/X509Certificates/X509EnhancedKeyUsageExtension.sl#L70)</sub>

#### TimeStampingOid *property*

```
static String TimeStampingOid { get; }
```

`id-kp-timeStamping`.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509EnhancedKeyUsageExtension.sl:73](../../stdlib/Security/Cryptography/X509Certificates/X509EnhancedKeyUsageExtension.sl#L73)</sub>

#### OcspSigningOid *property*

```
static String OcspSigningOid { get; }
```

`id-kp-OCSPSigning`.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509EnhancedKeyUsageExtension.sl:76](../../stdlib/Security/Cryptography/X509Certificates/X509EnhancedKeyUsageExtension.sl#L76)</sub>

#### AnyExtendedKeyUsageOid *property*

```
static String AnyExtendedKeyUsageOid { get; }
```

`anyExtendedKeyUsage`, which allows every purpose.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509EnhancedKeyUsageExtension.sl:79](../../stdlib/Security/Cryptography/X509Certificates/X509EnhancedKeyUsageExtension.sl#L79)</sub>

#### EnhancedKeyUsages *property*

```
String[] EnhancedKeyUsages { get; }
```

The purposes, dotted, in the order they are listed.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509EnhancedKeyUsageExtension.sl:82](../../stdlib/Security/Cryptography/X509Certificates/X509EnhancedKeyUsageExtension.sl#L82)</sub>

#### AllowsUsage *method*

```
bool AllowsUsage(String usage)
```

Whether `usage` is listed, or `AnyExtendedKeyUsageOid` is.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509EnhancedKeyUsageExtension.sl:85](../../stdlib/Security/Cryptography/X509Certificates/X509EnhancedKeyUsageExtension.sl#L85)</sub>

### X509Extension *class*

```
class X509Extension
```

One certificate extension: its identifier, whether it is critical, and
its value as DER.

An extension this module knows is one of the classes derived from this,
already decoded: `X509BasicConstraintsExtension`,
`X509KeyUsageExtension`, `X509EnhancedKeyUsageExtension`,
`X509SubjectAlternativeNameExtension`,
`X509SubjectKeyIdentifierExtension`,
`X509AuthorityKeyIdentifierExtension` and
`X509NameConstraintsExtension`. Any other is this class, as it was read.

**A critical extension this module does not understand makes a chain
fail** with `HasNotSupportedCriticalExtension`, as RFC 5280 requires.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Extension.sl:37](../../stdlib/Security/Cryptography/X509Certificates/X509Extension.sl#L37)</sub>

#### Oid *property*

```
String Oid { get; }
```

The identifier, dotted: `2.5.29.19` for basic constraints.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Extension.sl:57](../../stdlib/Security/Cryptography/X509Certificates/X509Extension.sl#L57)</sub>

#### Critical *property*

```
bool Critical { get; }
```

Whether it is marked critical.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Extension.sl:60](../../stdlib/Security/Cryptography/X509Certificates/X509Extension.sl#L60)</sub>

#### RawData *property*

```
byte[] RawData { get; }
```

The value, as DER.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Extension.sl:63](../../stdlib/Security/Cryptography/X509Certificates/X509Extension.sl#L63)</sub>

### X509ExtensionCollection *class*

```
sealed class X509ExtensionCollection
```

A certificate's extensions, in the order they are encoded.

```csharp
foreach (X509Extension extension in certificate.Extensions)
    Console.WriteLine($"{extension.Oid} {extension.Critical}");
X509Extension? constraints = certificate.Extensions["2.5.29.19"];
```

Read-only: a certificate is signed as it is, so there is nothing to add
to. `CertificateRequest.CertificateExtensions` is where extensions are
gathered for a new one.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509ExtensionCollection.sl:39](../../stdlib/Security/Cryptography/X509Certificates/X509ExtensionCollection.sl#L39)</sub>

#### Count *property*

```
nuint Count { get; }
```

How many there are.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509ExtensionCollection.sl:53](../../stdlib/Security/Cryptography/X509Certificates/X509ExtensionCollection.sl#L53)</sub>

#### this[] *indexer*

```
X509Extension this[nuint index] { get; }
```

Extension `index`, in encoded order; aborts past `Count`.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509ExtensionCollection.sl:56](../../stdlib/Security/Cryptography/X509Certificates/X509ExtensionCollection.sl#L56)</sub>

#### this[] *indexer*

```
X509Extension? this[String oid] { get; }
```

The extension whose identifier is `oid`, or null. No identifier
appears twice.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509ExtensionCollection.sl:60](../../stdlib/Security/Cryptography/X509Certificates/X509ExtensionCollection.sl#L60)</sub>

#### GetEnumerator *method*

```
IEnumerator<X509Extension> GetEnumerator()
```

Each extension in turn.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509ExtensionCollection.sl:74](../../stdlib/Security/Cryptography/X509Certificates/X509ExtensionCollection.sl#L74)</sub>

### X509KeyUsageExtension *class*

```
sealed class X509KeyUsageExtension : X509Extension
```

What the key may be used for: RFC 5280 §4.2.1.3, `2.5.29.15`.

A CA's key MUST allow `KeyCertSign` for a chain to pass through it when
this is present; with none, the key is not restricted.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509KeyUsageExtension.sl:31](../../stdlib/Security/Cryptography/X509Certificates/X509KeyUsageExtension.sl#L31)</sub>

#### KeyUsages *property*

```
X509KeyUsageFlags KeyUsages { get; }
```

What the key may do.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509KeyUsageExtension.sl:53](../../stdlib/Security/Cryptography/X509Certificates/X509KeyUsageExtension.sl#L53)</sub>

### X509KeyUsageFlags *enum*

```
enum X509KeyUsageFlags
```

What a certificate's key may be used for, as its key usage extension
says: .NET's `X509KeyUsageFlags`, with .NET's values.

The low byte is the first octet of the `BIT STRING` as it is encoded, so
`DigitalSignature`, bit 0 of RFC 5280's list, is `0x80`.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509KeyUsageFlags.sl:29](../../stdlib/Security/Cryptography/X509Certificates/X509KeyUsageFlags.sl#L29)</sub>

#### None *case*

```
None = 0
```

No usage at all.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509KeyUsageFlags.sl:33](../../stdlib/Security/Cryptography/X509Certificates/X509KeyUsageFlags.sl#L33)</sub>

#### EncipherOnly *case*

```
EncipherOnly = 1
```

With `KeyAgreement`, the key may only encipher in agreement.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509KeyUsageFlags.sl:36](../../stdlib/Security/Cryptography/X509Certificates/X509KeyUsageFlags.sl#L36)</sub>

#### CrlSign *case*

```
CrlSign = 2
```

The key may sign revocation lists.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509KeyUsageFlags.sl:39](../../stdlib/Security/Cryptography/X509Certificates/X509KeyUsageFlags.sl#L39)</sub>

#### KeyCertSign *case*

```
KeyCertSign = 4
```

The key may sign certificates, which a CA's MUST allow.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509KeyUsageFlags.sl:42](../../stdlib/Security/Cryptography/X509Certificates/X509KeyUsageFlags.sl#L42)</sub>

#### KeyAgreement *case*

```
KeyAgreement = 8
```

The key may agree keys, as an ECDH key does.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509KeyUsageFlags.sl:45](../../stdlib/Security/Cryptography/X509Certificates/X509KeyUsageFlags.sl#L45)</sub>

#### DataEncipherment *case*

```
DataEncipherment = 16
```

The key may encipher data directly.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509KeyUsageFlags.sl:48](../../stdlib/Security/Cryptography/X509Certificates/X509KeyUsageFlags.sl#L48)</sub>

#### KeyEncipherment *case*

```
KeyEncipherment = 32
```

The key may encipher other keys, as RSA key transport does.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509KeyUsageFlags.sl:51](../../stdlib/Security/Cryptography/X509Certificates/X509KeyUsageFlags.sl#L51)</sub>

#### NonRepudiation *case*

```
NonRepudiation = 64
```

Signatures made with the key are meant not to be repudiated.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509KeyUsageFlags.sl:54](../../stdlib/Security/Cryptography/X509Certificates/X509KeyUsageFlags.sl#L54)</sub>

#### DigitalSignature *case*

```
DigitalSignature = 128
```

The key may make signatures other than on certificates and lists.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509KeyUsageFlags.sl:57](../../stdlib/Security/Cryptography/X509Certificates/X509KeyUsageFlags.sl#L57)</sub>

#### DecipherOnly *case*

```
DecipherOnly = 32768
```

With `KeyAgreement`, the key may only decipher in agreement.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509KeyUsageFlags.sl:60](../../stdlib/Security/Cryptography/X509Certificates/X509KeyUsageFlags.sl#L60)</sub>

### X509NameConstraintsExtension *class*

```
sealed class X509NameConstraintsExtension : X509Extension
```

Which names a CA may issue for: RFC 5280 §4.2.1.10, `2.5.29.30`. Not in
.NET, which reads the extension only through the platform's chain.

DNS names and IP address ranges are read out and enforced by
`X509Chain` over the leaf's subject alternative names: a name is
refused when it is inside an excluded subtree, or when there are
permitted subtrees of its kind and it is inside none of them. Subtrees
of the other kinds — directory names, e-mail addresses, URIs — are
checked to be well-formed and are not enforced.

A range is an address followed by a mask of the same length: eight bytes
for IPv4, thirty-two for IPv6.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509NameConstraintsExtension.sl:40](../../stdlib/Security/Cryptography/X509Certificates/X509NameConstraintsExtension.sl#L40)</sub>

#### PermittedDnsNames *property*

```
String[] PermittedDnsNames { get; }
```

The permitted DNS subtrees.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509NameConstraintsExtension.sl:78](../../stdlib/Security/Cryptography/X509Certificates/X509NameConstraintsExtension.sl#L78)</sub>

#### PermittedIPRanges *property*

```
byte[][] PermittedIPRanges { get; }
```

The permitted address ranges.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509NameConstraintsExtension.sl:81](../../stdlib/Security/Cryptography/X509Certificates/X509NameConstraintsExtension.sl#L81)</sub>

#### ExcludedDnsNames *property*

```
String[] ExcludedDnsNames { get; }
```

The excluded DNS subtrees.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509NameConstraintsExtension.sl:84](../../stdlib/Security/Cryptography/X509Certificates/X509NameConstraintsExtension.sl#L84)</sub>

#### ExcludedIPRanges *property*

```
byte[][] ExcludedIPRanges { get; }
```

The excluded address ranges.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509NameConstraintsExtension.sl:87](../../stdlib/Security/Cryptography/X509Certificates/X509NameConstraintsExtension.sl#L87)</sub>

### X509RevocationMode *enum*

```
enum X509RevocationMode
```

Whether a chain asks if a certificate is revoked: .NET's
`X509RevocationMode`.

**Only `NoCheck` can succeed.** There is no CRL and no OCSP here, so
either of the others marks every element `RevocationStatusUnknown` and
`OfflineRevocation`, which fails the chain, rather than pretending to
have looked.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509RevocationMode.sl:31](../../stdlib/Security/Cryptography/X509Certificates/X509RevocationMode.sl#L31)</sub>

#### NoCheck *case*

```
NoCheck
```

Revocation is not asked about. The default.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509RevocationMode.sl:34](../../stdlib/Security/Cryptography/X509Certificates/X509RevocationMode.sl#L34)</sub>

#### Online *case*

```
Online
```

Ask the network; not possible here.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509RevocationMode.sl:37](../../stdlib/Security/Cryptography/X509Certificates/X509RevocationMode.sl#L37)</sub>

#### Offline *case*

```
Offline
```

Ask what is cached; not possible here.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509RevocationMode.sl:40](../../stdlib/Security/Cryptography/X509Certificates/X509RevocationMode.sl#L40)</sub>

### X509SignatureGenerator *class*

```
sealed class X509SignatureGenerator
```

A private key that signs certificates: .NET's `X509SignatureGenerator`.

```csharp
var issuerKey = try X509SignatureGenerator.CreateForEd25519(privateKey);
var signer = X509SignatureGenerator.CreateForECDsa(ecdsa);
var rsaSigner = X509SignatureGenerator.CreateForRsa(rsa, RsaSignaturePadding.Pss);
```

Ed25519 signs the certificate itself and ignores the hash it is given;
ECDSA signs with the hash, as `ecdsa-with-SHA256` and its siblings; RSA
signs with PKCS #1 v1.5 or PSS as its padding says, PSS with MGF1 over
the same hash and the salt length written into the parameters.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509SignatureGenerator.sl:47](../../stdlib/Security/Cryptography/X509Certificates/X509SignatureGenerator.sl#L47)</sub>

#### CreateForEd25519 *method*

```
static Result<X509SignatureGenerator, CryptoError> CreateForEd25519(ReadOnlySpan<byte> privateKey)
```

A generator signing with the Ed25519 key `privateKey`.

**Parameters**

- `privateKey` -- the 32-byte seed RFC 8032 calls the private key

**Fails with**

- [CryptoError.KeyLength](Standard-Security-Cryptography.md#keylength-case) -- it is not 32 bytes

<sub>[stdlib/Security/Cryptography/X509Certificates/X509SignatureGenerator.sl:71](../../stdlib/Security/Cryptography/X509Certificates/X509SignatureGenerator.sl#L71)</sub>

#### CreateForECDsa *method*

```
static Result<X509SignatureGenerator, CryptoError> CreateForECDsa(ECDsa key)
```

A generator signing with `key`, which MUST hold its private half for
signing to succeed.

**Fails with**

- [CryptoError.Encoding](Standard-Security-Cryptography.md#encoding-case) -- never, in practice: the key writes its own

<sub>[stdlib/Security/Cryptography/X509Certificates/X509SignatureGenerator.sl:84](../../stdlib/Security/Cryptography/X509Certificates/X509SignatureGenerator.sl#L84)</sub>

#### CreateForRsa *method*

```
static Result<X509SignatureGenerator, CryptoError> CreateForRsa(Rsa key, RsaSignaturePadding padding)
```

A generator signing with `key` under `padding`, which MUST hold its
private half for signing to succeed.

**Fails with**

- [CryptoError.Encoding](Standard-Security-Cryptography.md#encoding-case) -- never, in practice: the key writes its own

<sub>[stdlib/Security/Cryptography/X509Certificates/X509SignatureGenerator.sl:95](../../stdlib/Security/Cryptography/X509Certificates/X509SignatureGenerator.sl#L95)</sub>

#### PublicKey *property*

```
PublicKey PublicKey { get; }
```

The public half, for a self-signed certificate's subject key.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509SignatureGenerator.sl:104](../../stdlib/Security/Cryptography/X509Certificates/X509SignatureGenerator.sl#L104)</sub>

#### GetSignatureAlgorithmIdentifier *method*

```
Result<byte[], CryptoError> GetSignatureAlgorithmIdentifier(HashAlgorithmName hashAlgorithm)
```

The `AlgorithmIdentifier` a certificate signed with `hashAlgorithm`
names, as DER.

**Fails with**

- [CryptoError.Unsupported](Standard-Security-Cryptography.md#unsupported-case) -- the hash is not SHA-256, -384 or -512 for ECDSA, or SHA-1, -256, -384 or -512 for RSA

<sub>[stdlib/Security/Cryptography/X509Certificates/X509SignatureGenerator.sl:111](../../stdlib/Security/Cryptography/X509Certificates/X509SignatureGenerator.sl#L111)</sub>

#### SignData *method*

```
Result<byte[], CryptoError> SignData(ReadOnlySpan<byte> data, HashAlgorithmName hashAlgorithm)
```

The signature of `data`, in the form a certificate carries it.

**Fails with**

- [CryptoError.InvalidKey](Standard-Security-Cryptography.md#invalidkey-case) -- the key has no private half
- [CryptoError.Unsupported](Standard-Security-Cryptography.md#unsupported-case) -- the hash is not one the key signs with

<sub>[stdlib/Security/Cryptography/X509Certificates/X509SignatureGenerator.sl:148](../../stdlib/Security/Cryptography/X509Certificates/X509SignatureGenerator.sl#L148)</sub>

### X509Store *class*

```
sealed class X509Store
```

The platform's certificates: .NET's `X509Store`, read-only.

```csharp
var roots = X509Store.Open(StoreName.Root);
Console.WriteLine($"{roots.Certificates.Count} trusted roots");
```

**On Windows** the system stores are read through crypt32 — `ROOT` for
`Root` and `CA` for `CertificateAuthority` — which is loaded by name the
first time a store is opened, so a program that never opens one does not
link it. **Elsewhere** `Root` is the PEM bundle `SSL_CERT_FILE` names,
or else the first of the usual places that exists —
`/etc/ssl/certs/ca-certificates.crt`, `/etc/pki/tls/certs/ca-bundle.crt`,
`/etc/ssl/ca-bundle.pem`, `/etc/pki/tls/cacert.pem`, `/etc/ssl/cert.pem`
— together with every file in the directories `SSL_CERT_DIR` lists; and
`CertificateAuthority` is empty.

**Each store is read once per process**, the first time it is opened from
any thread, and shared after that. A certificate that does not parse is
passed over, and one found twice is kept once. A store that cannot be read
at all is empty, which a chain reports as `UntrustedRoot` or
`PartialChain` rather than as a failure of its own.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Store.sl:51](../../stdlib/Security/Cryptography/X509Certificates/X509Store.sl#L51)</sub>

#### Open *method*

```
static X509Store Open(StoreName name, StoreLocation location)
```

The store `name` at `location`, read the first time it is asked for.

**Parameters**

- `name` -- which store
- `location` -- whose; only Windows tells the two apart

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Store.sl:83](../../stdlib/Security/Cryptography/X509Certificates/X509Store.sl#L83)</sub>

#### Name *property*

```
StoreName Name { get; }
```

Which store this is.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Store.sl:102](../../stdlib/Security/Cryptography/X509Certificates/X509Store.sl#L102)</sub>

#### Location *property*

```
StoreLocation Location { get; }
```

Whose store this is.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Store.sl:105](../../stdlib/Security/Cryptography/X509Certificates/X509Store.sl#L105)</sub>

#### Certificates *property*

```
X509Certificate2Collection Certificates { get; }
```

Its certificates: a copy, which the caller MAY change.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509Store.sl:108](../../stdlib/Security/Cryptography/X509Certificates/X509Store.sl#L108)</sub>

### X509SubjectAlternativeNameExtension *class*

```
sealed class X509SubjectAlternativeNameExtension : X509Extension
```

The names the certificate is for: RFC 5280 §4.2.1.6, `2.5.29.17`.

Four kinds of name are read out: DNS names, IP addresses as their four or
sixteen bytes, URIs and e-mail addresses. The other kinds — a directory
name, an `otherName`, a registered identifier — are checked to be
well-formed and are otherwise left in `RawData`.

**See also** &nbsp; [SubjectAlternativeNameBuilder](#subjectalternativenamebuilder-class) &middot; [X509Certificate2.MatchesHostname](#matcheshostname-method)

<sub>[stdlib/Security/Cryptography/X509Certificates/X509SubjectAlternativeNameExtension.sl:37](../../stdlib/Security/Cryptography/X509Certificates/X509SubjectAlternativeNameExtension.sl#L37)</sub>

#### DnsNames *property*

```
String[] DnsNames { get; }
```

The `dNSName` entries, as written.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509SubjectAlternativeNameExtension.sl:56](../../stdlib/Security/Cryptography/X509Certificates/X509SubjectAlternativeNameExtension.sl#L56)</sub>

#### IPAddresses *property*

```
byte[][] IPAddresses { get; }
```

The `iPAddress` entries: four bytes for IPv4, sixteen for IPv6.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509SubjectAlternativeNameExtension.sl:59](../../stdlib/Security/Cryptography/X509Certificates/X509SubjectAlternativeNameExtension.sl#L59)</sub>

#### Uris *property*

```
String[] Uris { get; }
```

The `uniformResourceIdentifier` entries.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509SubjectAlternativeNameExtension.sl:62](../../stdlib/Security/Cryptography/X509Certificates/X509SubjectAlternativeNameExtension.sl#L62)</sub>

#### EmailAddresses *property*

```
String[] EmailAddresses { get; }
```

The `rfc822Name` entries.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509SubjectAlternativeNameExtension.sl:65](../../stdlib/Security/Cryptography/X509Certificates/X509SubjectAlternativeNameExtension.sl#L65)</sub>

### X509SubjectKeyIdentifierExtension *class*

```
sealed class X509SubjectKeyIdentifierExtension : X509Extension
```

A short name for the subject's key: RFC 5280 §4.2.1.2, `2.5.29.14`.

A chain uses it to tell apart two issuers with the same name, matching it
against the authority key identifier of what they issued.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509SubjectKeyIdentifierExtension.sl:31](../../stdlib/Security/Cryptography/X509Certificates/X509SubjectKeyIdentifierExtension.sl#L31)</sub>

#### SubjectKeyIdentifier *property*

```
String SubjectKeyIdentifier { get; }
```

The identifier in upper-case hexadecimal, as .NET gives it.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509SubjectKeyIdentifierExtension.sl:64](../../stdlib/Security/Cryptography/X509Certificates/X509SubjectKeyIdentifierExtension.sl#L64)</sub>

#### SubjectKeyIdentifierBytes *property*

```
byte[] SubjectKeyIdentifierBytes { get; }
```

The identifier's bytes.

<sub>[stdlib/Security/Cryptography/X509Certificates/X509SubjectKeyIdentifierExtension.sl:67](../../stdlib/Security/Cryptography/X509Certificates/X509SubjectKeyIdentifierExtension.sl#L67)</sub>

