# Standard.Security.Cryptography

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

Hashes, message authentication codes, key derivation, block and stream
ciphers, key agreement and signatures.

```csharp
var digest = Sha256.HashData(Encoding.CreateUtf8().GetBytes("hello"));
Console.WriteLine(Convert.ToHexString(digest));

var cipher = try Aes.FromKey(key);
var encrypted = try cipher.EncryptCbc(plaintext, iv, PaddingMode.Pkcs7);

var shared = try X25519.DeriveSharedSecret(myPrivateKey, theirPublicKey);
var signature = try Ed25519.Sign(signingKey, message);

var signer = try Rsa.ImportFromPem(pem);
var rsaSignature = try signer.SignData(data, HashAlgorithmName.Sha256,
                                       RsaSignaturePadding.Pss);
```

**The shape is `System.Security.Cryptography`'s**, so a program being
ported finds the names where it left them: `Sha256`, `Hmac`, `Aes`,
`AesGcm`, `ChaCha20Poly1305`, `Rfc2898DeriveBytes.Pbkdf2`, `ECDsa`,
`ECDiffieHellman`, `Rsa`, `RandomNumberGenerator.Fill`,
`CryptographicOperations.FixedTimeEquals`.
`Blake2b`, `Scrypt` and `Argon2id` are not in .NET and follow the same
shape. Three things about it differ, and each is a rule this language
already has rather than a choice made here:

- **The casing is the house rule's**, not .NET's. `SHA256` is `Sha256` and
  `HMACSHA256` is `HmacSha256`, because an acronym longer than two letters
  is `PascalCase` here (style §1.3). Nothing else about a name moves.
- **What can fail returns a `Result`.** .NET throws
  `CryptographicException` for a wrong key length, a bad padding and a
  failed authentication tag; there is no unwinding here, so each of those
  is a `CryptoError` the caller cannot read past (§2.6). That is the
  difference that matters most: an authentication failure *must* be
  checked, and a `Result` is what makes it impossible not to.
- **`Create()` is `new`.** `SHA256.Create()` exists because .NET's is an
  abstract class over a CryptoAPI implementation chosen at run time. There
  is one implementation here, so `new Sha256()` is the whole of it.
  `ECDsa.Create` and `ECDiffieHellman.Create` keep the name, because they
  make a key and can fail.

**The ciphers and MACs are constant time in software.** AES is bitsliced
and its S-box is a logic circuit, GHASH multiplies with integer multiplies
rather than a table, and ChaCha20, Poly1305, the SHA-2 family and BLAKE2b
are arithmetic on words. None indexes memory by a key or by data, and none
branches on either, so the time and the cache lines touched depend only on
lengths. `FixedTimeEquals` is the comparison to use on anything secret.

Three things that claim does not cover. **It is timing and cache only**:
nothing here resists power analysis, electromagnetic emanation or fault
injection, which want masking and hardware this library does not have.
**It rests on the multiply**: GHASH, Poly1305 and every curve assume a
multiply whose time does not depend on its operands, which is true of every
x64 and ARMv8 core and not of some older and embedded ones. **The
memory-hard password hashes index memory by the password**, which is what
makes them memory hard: all of scrypt's second half, and Argon2id's after
its first half.

Nothing uses AES-NI, which the language cannot spell, so AES runs at a
small fraction of what the hardware could give. `ChaCha20Poly1305` is
about three times as fast as `AesGcm` here, and is the one to choose
where a format leaves the choice open.

**Public-key is RSA, Curve25519, P-256 and P-384.** `X25519` and
`ECDiffieHellman` agree keys; `Ed25519` and `ECDsa` sign. The NIST curves
are fixed-width Montgomery multiplication in 64-bit limbs held inline, with
the complete formulas of Renes, Costello and Batina so that no point is a
special case, and keys travel as `ECParameters`, SEC 1 points, SEC 1 and
PKCS #8 private keys, `SubjectPublicKeyInfo` and PEM.

**Every operation on a private scalar or a nonce is constant time**: key
generation, agreement and signing on every curve. A scalar multiplication
reads the whole of its table and keeps one entry with a mask, an inversion
is an exponentiation by a public exponent, and every conditional subtraction
is a mask passed through `OpaqueCopy`, so the optimiser cannot turn it back
into a branch. A random or RFC 6979 candidate outside `[1, n - 1]` is drawn
again, which shows only that a number nobody uses was out of range.
Verification and the checking of a public point read nothing secret and are
written for speed.

**`Rsa` is the public-key half**, over a constant-time bignum of 64-bit
limbs: signatures in PKCS #1 v1.5 and PSS, encryption in OAEP and PKCS #1
v1.5, key generation, and keys in PKCS #1, PKCS #8, X.509 and PEM.

**What is constant time there, exactly.** Every operation that touches a
private key runs in time, and reads memory at addresses, fixed by the
key's size: the Montgomery exponentiation reads all sixteen entries of its
window table for every window, a reduction or an inverse runs a fixed count
of steps, and a selection is a mask rather than a branch. The private
operation is blinded by a fresh random factor and its result is checked
against the public key before it is released. OAEP decoding and PKCS #1
v1.5 decoding run under masks with one verdict at the end, and the latter
uses implicit rejection, so a bad padding is not even a failure. Three
things are not constant time, and none handles a secret an attacker can
choose: verifying and encrypting, which use only the public key; key
generation's search, which throws away candidates as soon as they fail and
so reveals only things about numbers it does not keep; and exporting a
private key, since DER writes each number in the fewest bytes it takes.

X.509 is `Standard.Formats.Asn1` and a signature check, which is
enough to verify a certificate and not yet a path validator.

## Contents

**Types** &nbsp; [Aes](#aes-class) &middot; [AesGcm](#aesgcm-class) &middot; [Argon2id](#argon2id-class) &middot; [Blake2b](#blake2b-class) &middot; [ChaCha20](#chacha20-class) &middot; [ChaCha20Poly1305](#chacha20poly1305-class) &middot; [CipherMode](#ciphermode-enum) &middot; [CryptoError](#cryptoerror-enum) &middot; [CryptographicOperations](#cryptographicoperations-class) &middot; [DsaSignatureFormat](#dsasignatureformat-enum) &middot; [ECCurve](#eccurve-struct) &middot; [ECCurve.NamedCurves](#eccurvenamedcurves-class) &middot; [ECDiffieHellman](#ecdiffiehellman-class) &middot; [ECDsa](#ecdsa-class) &middot; [ECParameters](#ecparameters-struct) &middot; [ECPoint](#ecpoint-struct) &middot; [Ed25519](#ed25519-class) &middot; [HashAlgorithm](#hashalgorithm-class) &middot; [HashAlgorithmName](#hashalgorithmname-struct) &middot; [Hkdf](#hkdf-class) &middot; [Hmac](#hmac-class) &middot; [HmacMd5](#hmacmd5-class) &middot; [HmacSha1](#hmacsha1-class) &middot; [HmacSha256](#hmacsha256-class) &middot; [HmacSha384](#hmacsha384-class) &middot; [HmacSha512](#hmacsha512-class) &middot; [IHashAlgorithm](#ihashalgorithm-interface) &middot; [Md5](#md5-class) &middot; [PaddingMode](#paddingmode-enum) &middot; [PemEncoding](#pemencoding-class) &middot; [PemFields](#pemfields-struct) &middot; [Poly1305](#poly1305-class) &middot; [RandomNumberGenerator](#randomnumbergenerator-class) &middot; [Rfc2898DeriveBytes](#rfc2898derivebytes-class) &middot; [Rsa](#rsa-class) &middot; [RsaEncryptionPadding](#rsaencryptionpadding-struct) &middot; [RsaEncryptionPaddingMode](#rsaencryptionpaddingmode-enum) &middot; [RsaParameters](#rsaparameters-class) &middot; [RsaSignaturePadding](#rsasignaturepadding-struct) &middot; [RsaSignaturePaddingMode](#rsasignaturepaddingmode-enum) &middot; [Scrypt](#scrypt-class) &middot; [Sha1](#sha1-class) &middot; [Sha256](#sha256-class) &middot; [Sha2Wide](#sha2wide-class) &middot; [Sha384](#sha384-class) &middot; [Sha512](#sha512-class) &middot; [X25519](#x25519-class)

## Types

### Aes *class*

```
sealed class Aes
```

AES, in ECB, CBC, CFB and CTR.

```csharp
var cipher = try Aes.FromKey(key);          // 16, 24 or 32 bytes
var sealed = try cipher.EncryptCbc(plaintext, iv, PaddingMode.Pkcs7);
var opened = try cipher.DecryptCbc(sealed, iv, PaddingMode.Pkcs7);
```

**None of these modes authenticates anything.** A ciphertext an attacker
can modify is a plaintext they can modify, and CBC in particular hands them
a bit-flipping attack on the block after the one they touched. Reach for
`AesGcm` unless a format forces one of these; where one is forced, put an
HMAC over the ciphertext and check it with `FixedTimeEquals` before
decrypting anything.

**It is constant time.** The cipher is bitsliced, as BearSSL's `aes_ct64`
is: four blocks are spread across eight 64-bit words, one word for each bit
position of every byte, and the S-box is the Boyar–Peralta logic circuit
rather than a table. Nothing is indexed by, and nothing branches on, the
key or the data. ECB, CTR and the decrypting half of CBC and CFB run four
blocks in each pass. CBC and CFB encryption chain each block into the next,
so they run one block per pass at the cost of four.

The one-shot methods are .NET 6's `EncryptCbc` and friends rather than its
older `CreateEncryptor`/`ICryptoTransform` pair. A transform object exists
to stream a message larger than memory; `CryptoStream` is the piece that
would want one and is not written, so the object with no stream to feed
would be a shape with no user.

**See also** &nbsp; [AesGcm](#aesgcm-class)

<sub>[stdlib/Security/Cryptography/Aes.sl:57](../../stdlib/Security/Cryptography/Aes.sl#L57)</sub>

#### BlockSize *constant*

```
const nuint BlockSize = 16
```

One block, for every key length. AES is a 128-bit block cipher; it is
Rijndael that had others, and no standard uses them.

<sub>[stdlib/Security/Cryptography/Aes.sl:61](../../stdlib/Security/Cryptography/Aes.sl#L61)</sub>

#### FromKey *method*

```
static Result<Aes, CryptoError> FromKey(ReadOnlySpan<byte> key)
```

A cipher under `key`, which must be 16, 24 or 32 bytes -- AES-128,
AES-192 or AES-256.

**Fails with**

- [CryptoError.KeyLength](#keylength-case) — `key` is not 16, 24 or 32 bytes

<sub>[stdlib/Security/Cryptography/Aes.sl:89](../../stdlib/Security/Cryptography/Aes.sl#L89)</sub>

#### Create *method*

```
static Aes Create()
```

A cipher under a fresh 256-bit key from the platform, which is what
.NET's `Aes.Create()` gives. Aborts if the machine will supply no
entropy, which is a broken machine rather than an outcome to plan for.

<sub>[stdlib/Security/Cryptography/Aes.sl:99](../../stdlib/Security/Cryptography/Aes.sl#L99)</sub>

#### Rounds *property*

```
nuint Rounds { get; }
```

How many rounds this key length runs: 10, 12 or 14.

<sub>[stdlib/Security/Cryptography/Aes.sl:110](../../stdlib/Security/Cryptography/Aes.sl#L110)</sub>

#### EncryptBlock *method*

```
void EncryptBlock(byte[] block, nuint offset)
```

One block enciphered in place, at `offset` in `block`.

Public because AES-GCM and a CTR keystream are built on it and a caller
implementing a mode this class does not have needs the same door.
**Not a way to encrypt a message**: a bare block cipher applied twice
to the same input gives the same output, which is what a mode exists to
fix. One block costs a pass that could have carried four.

<sub>[stdlib/Security/Cryptography/Aes.sl:121](../../stdlib/Security/Cryptography/Aes.sl#L121)</sub>

#### DecryptBlock *method*

```
void DecryptBlock(byte[] block, nuint offset)
```

One block deciphered in place, at `offset` in `block`.

<sub>[stdlib/Security/Cryptography/Aes.sl:124](../../stdlib/Security/Cryptography/Aes.sl#L124)</sub>

#### EncryptEcb *method*

```
Result<byte[], CryptoError> EncryptEcb(ReadOnlySpan<byte> plaintext, PaddingMode padding)
```

Every block on its own. See `CipherMode.Ecb` for why this is almost
always the wrong answer.

**Fails with**

- [CryptoError.BlockLength](#blocklength-case) — `padding` is `None` and the input is not a whole number of blocks

**See also** &nbsp; [CipherMode.Ecb](#ecb-case) &middot; [Aes.DecryptEcb](#decryptecb-method)

<sub>[stdlib/Security/Cryptography/Aes.sl:135](../../stdlib/Security/Cryptography/Aes.sl#L135)</sub>

#### DecryptEcb *method*

```
Result<byte[], CryptoError> DecryptEcb(ReadOnlySpan<byte> ciphertext, PaddingMode padding)
```

The inverse of `EncryptEcb`.

**Fails with**

- [CryptoError.BlockLength](#blocklength-case) — the input is empty or not a whole number of blocks
- [CryptoError.Padding](#padding-case) — the padding does not describe itself, which is usually the wrong key

**See also** &nbsp; [Aes.EncryptEcb](#encryptecb-method)

<sub>[stdlib/Security/Cryptography/Aes.sl:152](../../stdlib/Security/Cryptography/Aes.sl#L152)</sub>

#### EncryptCbc *method*

```
Result<byte[], CryptoError> EncryptCbc(ReadOnlySpan<byte> plaintext, ReadOnlySpan<byte> iv, PaddingMode padding)
```

Chained blocks. `iv` must be one block and must never be reused with
this key; `RandomNumberGenerator.GetBytes(16u)` is how to make one, and
it is not secret -- send it alongside the ciphertext.

**Fails with**

- [CryptoError.IvLength](#ivlength-case) — `iv` is not one block
- [CryptoError.BlockLength](#blocklength-case) — `padding` is `None` and the input is not a whole number of blocks

**See also** &nbsp; [Aes.DecryptCbc](#decryptcbc-method) &middot; [RandomNumberGenerator.GetBytes](#getbytes-method)

<sub>[stdlib/Security/Cryptography/Aes.sl:175](../../stdlib/Security/Cryptography/Aes.sl#L175)</sub>

#### DecryptCbc *method*

```
Result<byte[], CryptoError> DecryptCbc(ReadOnlySpan<byte> ciphertext, ReadOnlySpan<byte> iv, PaddingMode padding)
```

The inverse of `EncryptCbc`.

A wrong key shows up as `CryptoError.Padding` about 255 times in 256,
and as a plausible-looking wrong plaintext the rest of the time. That
is the whole reason to authenticate a ciphertext before decrypting it.

**Fails with**

- [CryptoError.IvLength](#ivlength-case) — `iv` is not one block
- [CryptoError.BlockLength](#blocklength-case) — the input is empty or not a whole number of blocks
- [CryptoError.Padding](#padding-case) — the padding does not describe itself

**See also** &nbsp; [Aes.EncryptCbc](#encryptcbc-method)

<sub>[stdlib/Security/Cryptography/Aes.sl:210](../../stdlib/Security/Cryptography/Aes.sl#L210)</sub>

#### EncryptCfb *method*

```
Result<byte[], CryptoError> EncryptCfb(ReadOnlySpan<byte> plaintext, ReadOnlySpan<byte> iv)
```

Cipher feedback over whole blocks, which is .NET's `CipherMode.CFB`
with a feedback size of 128 bits. No padding: the mode is a stream.

**Fails with**

- [CryptoError.IvLength](#ivlength-case) — `iv` is not one block

**See also** &nbsp; [Aes.DecryptCfb](#decryptcfb-method)

<sub>[stdlib/Security/Cryptography/Aes.sl:239](../../stdlib/Security/Cryptography/Aes.sl#L239)</sub>

#### DecryptCfb *method*

```
Result<byte[], CryptoError> DecryptCfb(ReadOnlySpan<byte> ciphertext, ReadOnlySpan<byte> iv)
```

The inverse of `EncryptCfb`.

**Fails with**

- [CryptoError.IvLength](#ivlength-case) — `iv` is not one block

**See also** &nbsp; [Aes.EncryptCfb](#encryptcfb-method)

<sub>[stdlib/Security/Cryptography/Aes.sl:270](../../stdlib/Security/Cryptography/Aes.sl#L270)</sub>

#### ApplyCtr *method*

```
Result<byte[], CryptoError> ApplyCtr(ReadOnlySpan<byte> data, ReadOnlySpan<byte> counter)
```

Counter mode, which is its own inverse: the same call decrypts.

`counter` is sixteen bytes and is incremented as one big-endian number
per block, which is what NIST SP 800-38A and every protocol built on it
do. **A counter value used twice under one key is fatal** -- the two
messages XOR to the XOR of their plaintexts -- so the usual arrangement
is a random nonce in the high bytes and a block counter in the low.

**Fails with**

- [CryptoError.IvLength](#ivlength-case) — `counter` is not one block

<sub>[stdlib/Security/Cryptography/Aes.sl:303](../../stdlib/Security/Cryptography/Aes.sl#L303)</sub>

### AesGcm *class*

```
sealed class AesGcm
```

AES-GCM: encryption and authentication in one pass, as .NET's `AesGcm`.

```csharp
var box = try AesGcm.FromKey(key);
byte[] tag = new byte[16u];
var sealed = try box.Encrypt(nonce, plaintext, associated, tag);
var opened = try box.Decrypt(nonce, sealed, associated, tag);
```

**The nonce must never repeat under one key.** GCM is CTR mode with a MAC
over the result, and a repeated nonce gives an attacker the XOR of two
plaintexts *and*, worse, the authentication key itself -- after which they
can forge. Twelve random bytes per message is fine up to about 2^32
messages; a counter is better where one can be kept.

`Decrypt` returns `CryptoError.AuthenticationFailed` and no plaintext when
the tag does not match. That is not a convenience: releasing unauthenticated
plaintext is the single most common way AEAD is misused, and a `Result` is
what makes it impossible here.

<sub>[stdlib/Security/Cryptography/AesGcm.sl:48](../../stdlib/Security/Cryptography/AesGcm.sl#L48)</sub>

#### TagSize *constant*

```
const nuint TagSize = 16
```

What the tag is, and the only length this produces. .NET allows 12 to
16; a shorter tag weakens forgery resistance by exactly the bits it
drops, and no format here asks for one.

**Value** &nbsp; sixteen bytes.

<sub>[stdlib/Security/Cryptography/AesGcm.sl:55](../../stdlib/Security/Cryptography/AesGcm.sl#L55)</sub>

#### NonceSize *constant*

```
const nuint NonceSize = 12
```

What every protocol built on GCM uses, and the only length for which
the nonce is used directly rather than hashed.

**Value** &nbsp; twelve bytes.

<sub>[stdlib/Security/Cryptography/AesGcm.sl:61](../../stdlib/Security/Cryptography/AesGcm.sl#L61)</sub>

#### FromKey *method*

```
static Result<AesGcm, CryptoError> FromKey(ReadOnlySpan<byte> key)
```

A GCM box under `key`, which must be 16, 24 or 32 bytes.

**Fails with**

- [CryptoError.KeyLength](#keylength-case) — `key` is not 16, 24 or 32 bytes

<sub>[stdlib/Security/Cryptography/AesGcm.sl:83](../../stdlib/Security/Cryptography/AesGcm.sl#L83)</sub>

#### Encrypt *method*

```
Result<byte[], CryptoError> Encrypt(ReadOnlySpan<byte> nonce, ReadOnlySpan<byte> plaintext, ReadOnlySpan<byte> associatedData, byte[] tag)
```

The ciphertext, with the tag written into `tag`.

`associatedData` is authenticated and not encrypted -- a message header,
a record number, anything the recipient must be sure of and that is not
secret. Pass an empty array when there is none.

**Parameters**

- `nonce` — never to repeat under this key; twelve bytes is what every protocol uses
- `plaintext` — the message to encipher
- `associatedData` — authenticated and not encrypted; empty when there is none
- `tag` — a `TagSize` array the tag is written into

**Fails with**

- [CryptoError.NonceLength](#noncelength-case) — `nonce` is empty
- [CryptoError.TagLength](#taglength-case) — `tag` is not `TagSize` long

**See also** &nbsp; [AesGcm.Decrypt](#decrypt-method)

<sub>[stdlib/Security/Cryptography/AesGcm.sl:105](../../stdlib/Security/Cryptography/AesGcm.sl#L105)</sub>

#### Decrypt *method*

```
Result<byte[], CryptoError> Decrypt(ReadOnlySpan<byte> nonce, ReadOnlySpan<byte> ciphertext, ReadOnlySpan<byte> associatedData, ReadOnlySpan<byte> tag)
```

The plaintext, or `AuthenticationFailed` and nothing.

**Parameters**

- `nonce` — the one the message was enciphered under
- `ciphertext` — the message to open
- `associatedData` — the same bytes the sender authenticated
- `tag` — the tag the sender sent

**Fails with**

- [CryptoError.NonceLength](#noncelength-case) — `nonce` is empty
- [CryptoError.TagLength](#taglength-case) — `tag` is not `TagSize` long
- [CryptoError.AuthenticationFailed](#authenticationfailed-case) — the tag does not match, and no plaintext is returned

**See also** &nbsp; [AesGcm.Encrypt](#encrypt-method)

<sub>[stdlib/Security/Cryptography/AesGcm.sl:142](../../stdlib/Security/Cryptography/AesGcm.sl#L142)</sub>

### Argon2id *class*

```
class Argon2id
```

Argon2id (RFC 9106), version 0x13: the password hash RFC 9106 recommends,
and the one to choose where no format decides.

```csharp
var key = try Argon2id.DeriveKey(password, salt, 3u, 65536u, 4u, 32u);
```

**Memory and passes are the cost.** `memoryKiB` is what each guess has to
hold, `iterations` how many times it is walked. RFC 9106 §4 gives two
starting points: 2 GiB and one pass where the memory can be spared, and
64 MiB and three passes where it cannot. Raise memory before passes.

**Half of it is data-independent and half is not, and that is the design.**
The first half of the first pass chooses which blocks to mix from a counter,
as Argon2i does, so a cache-timing attacker watching it learns nothing
about the password. Everything after chooses them from the data, as Argon2d
does, which is what makes a trade of memory for time expensive and is also
a timing channel in principle. That second half is inherent in Argon2id.

**The lanes are computed one after another.** `parallelism` is part of the
function, so it changes the answer and has to match whatever else computes
it, but here it buys no speed.

**See also** &nbsp; [Blake2b](#blake2b-class) &middot; [Scrypt](#scrypt-class)

<sub>[stdlib/Security/Cryptography/Argon2id.sl:54](../../stdlib/Security/Cryptography/Argon2id.sl#L54)</sub>

#### MaxMemoryKiB *constant*

```
const nuint MaxMemoryKiB = 4194304
```

The most memory a derivation may ask for: 4 GiB. Parameters read from
a stored hash are input like any other, and this bounds what one can
make a call allocate.

**Value** &nbsp; 2^22 KiB.

<sub>[stdlib/Security/Cryptography/Argon2id.sl:61](../../stdlib/Security/Cryptography/Argon2id.sl#L61)</sub>

#### MinSaltSize *constant*

```
const nuint MinSaltSize = 8
```

The shortest salt. RFC 9106 recommends sixteen random bytes.

**Value** &nbsp; eight bytes.

<sub>[stdlib/Security/Cryptography/Argon2id.sl:66](../../stdlib/Security/Cryptography/Argon2id.sl#L66)</sub>

#### DeriveKey *method*

```
static Result<byte[], CryptoError> DeriveKey(ReadOnlySpan<byte> password, ReadOnlySpan<byte> salt, nuint iterations, nuint memoryKiB, nuint parallelism, nuint length)
```

`length` bytes derived from `password` and `salt`.

**Parameters**

- `password` — the secret to stretch
- `salt` — at least `MinSaltSize` random bytes, sixteen recommended, stored beside the result
- `iterations` — t, how many passes over the memory
- `memoryKiB` — m, how many kibibytes to fill; at least eight per lane
- `parallelism` — p, how many lanes, computed one after another here
- `length` — how many bytes to derive, at least four

**Fails with**

- [CryptoError.Parameter](#parameter-case) — a parameter is outside RFC 9106 §3.1, `salt` is shorter than `MinSaltSize`, or `memoryKiB` is past `MaxMemoryKiB`

<sub>[stdlib/Security/Cryptography/Argon2id.sl:80](../../stdlib/Security/Cryptography/Argon2id.sl#L80)</sub>

#### DeriveKey *method*

```
static Result<byte[], CryptoError> DeriveKey(ReadOnlySpan<byte> password, ReadOnlySpan<byte> salt, nuint iterations, nuint memoryKiB, nuint parallelism, nuint length, ReadOnlySpan<byte> secret, ReadOnlySpan<byte> associatedData)
```

`length` bytes derived from `password` and `salt`, bound to a secret
kept apart from the stored hashes and to associated data.

`secret` is a pepper: a key the server holds outside the database, so
that a stolen table of hashes cannot be attacked without it as well.

**Parameters**

- `password` — the secret to stretch
- `salt` — at least `MinSaltSize` random bytes, stored beside the result
- `iterations` — t, how many passes over the memory
- `memoryKiB` — m, how many kibibytes to fill; at least eight per lane
- `parallelism` — p, how many lanes, computed one after another here
- `length` — how many bytes to derive, at least four
- `secret` — K, a key held apart from the hashes; empty for none
- `associatedData` — X, bound into the result and not secret; empty for none

**Fails with**

- [CryptoError.Parameter](#parameter-case) — a parameter is outside RFC 9106 §3.1, `salt` is shorter than `MinSaltSize`, or `memoryKiB` is past `MaxMemoryKiB`

<sub>[stdlib/Security/Cryptography/Argon2id.sl:104](../../stdlib/Security/Cryptography/Argon2id.sl#L104)</sub>

### Blake2b *class*

```
sealed class Blake2b : IHashAlgorithm
```

BLAKE2b (RFC 7693): a hash as strong as SHA-3 and faster than SHA-256, with
a key and a digest length of its own.

```csharp
var digest = Blake2b.HashData(data);
var mac = try Blake2b.FromKey(key, 32u);
mac.AppendData(message);
var tag = mac.GetHashAndReset();
```

**A keyed BLAKE2b is a MAC on its own.** It is not a Merkle-Damgård hash,
so it cannot be extended the way `Sha256.HashData(key + message)` can, and
HMAC's two passes buy nothing. The key goes in its own first block.

**The digest length is a parameter, not a truncation.** BLAKE2b-256 is not
the first half of BLAKE2b-512: the length is mixed into the initial state,
so every length is its own function.

Not in .NET. It is here because Argon2 is built on it, and it fits
`IHashAlgorithm` as it is, so `Hmac` takes it like any other.

**See also** &nbsp; [Argon2id](#argon2id-class)

<sub>[stdlib/Security/Cryptography/Blake2b.sl:51](../../stdlib/Security/Cryptography/Blake2b.sl#L51)</sub>

#### MaxHashSize *constant*

```
const nuint MaxHashSize = 64
```

The longest digest, and the one `new Blake2b()` gives.

**Value** &nbsp; sixty-four bytes.

<sub>[stdlib/Security/Cryptography/Blake2b.sl:56](../../stdlib/Security/Cryptography/Blake2b.sl#L56)</sub>

#### MaxKeySize *constant*

```
const nuint MaxKeySize = 64
```

The longest key.

**Value** &nbsp; sixty-four bytes.

<sub>[stdlib/Security/Cryptography/Blake2b.sl:61](../../stdlib/Security/Cryptography/Blake2b.sl#L61)</sub>

#### FromKey *method*

```
static Result<Blake2b, CryptoError> FromKey(ReadOnlySpan<byte> key, nuint hashSize)
```

A BLAKE2b under `key` giving `hashSize` bytes. An empty key is the
unkeyed hash of that length.

**Parameters**

- `key` — at most `MaxKeySize` bytes; empty for none
- `hashSize` — one to `MaxHashSize` bytes of digest

**Fails with**

- [CryptoError.KeyLength](#keylength-case) — `key` is longer than `MaxKeySize`
- [CryptoError.Parameter](#parameter-case) — `hashSize` is zero or past `MaxHashSize`

<sub>[stdlib/Security/Cryptography/Blake2b.sl:112](../../stdlib/Security/Cryptography/Blake2b.sl#L112)</sub>

#### HashData *method*

```
static byte[] HashData(ReadOnlySpan<byte> data)
```

The BLAKE2b-512 digest of `data`, with no object to keep.

<sub>[stdlib/Security/Cryptography/Blake2b.sl:122](../../stdlib/Security/Cryptography/Blake2b.sl#L122)</sub>

#### Name *property*

```
String Name { get; }
```

`BLAKE2b-512`, or the length this one was made with, in bits.

<sub>[stdlib/Security/Cryptography/Blake2b.sl:125](../../stdlib/Security/Cryptography/Blake2b.sl#L125)</sub>

#### HashSizeInBytes *property*

```
nuint HashSizeInBytes { get; }
```

*No documentation.*

<sub>[stdlib/Security/Cryptography/Blake2b.sl:127](../../stdlib/Security/Cryptography/Blake2b.sl#L127)</sub>

#### BlockSizeInBytes *property*

```
nuint BlockSizeInBytes { get; }
```

*No documentation.*

<sub>[stdlib/Security/Cryptography/Blake2b.sl:129](../../stdlib/Security/Cryptography/Blake2b.sl#L129)</sub>

#### AppendData *method*

```
void AppendData(ReadOnlySpan<byte> data)
```

*No documentation.*

<sub>[stdlib/Security/Cryptography/Blake2b.sl:131](../../stdlib/Security/Cryptography/Blake2b.sl#L131)</sub>

#### GetHashAndReset *method*

```
byte[] GetHashAndReset()
```

*No documentation.*

<sub>[stdlib/Security/Cryptography/Blake2b.sl:157](../../stdlib/Security/Cryptography/Blake2b.sl#L157)</sub>

#### Reset *method*

```
void Reset()
```

*No documentation.*

<sub>[stdlib/Security/Cryptography/Blake2b.sl:177](../../stdlib/Security/Cryptography/Blake2b.sl#L177)</sub>

#### ComputeHash *method*

```
byte[] ComputeHash(ReadOnlySpan<byte> data)
```

The digest of `data` on its own. Resets first, so an object that has
been appended to is still safe to ask.

<sub>[stdlib/Security/Cryptography/Blake2b.sl:201](../../stdlib/Security/Cryptography/Blake2b.sl#L201)</sub>

### ChaCha20 *class*

```
sealed class ChaCha20
```

ChaCha20, the stream cipher of RFC 8439: a 256-bit key, a 96-bit nonce and
a 32-bit block counter.

```csharp
var cipher = try ChaCha20.FromKey(key);
var sealed = try cipher.ApplyKeystream(nonce, 1u, plaintext);
var opened = try cipher.ApplyKeystream(nonce, 1u, sealed);
```

**This is encryption without authentication.** Anyone can flip a bit of
the ciphertext and the same bit of the plaintext flips. `ChaCha20Poly1305`
is the construction to use; this is here for a protocol that specifies the
bare cipher, and for the block vectors that pin it.

**It is constant time by construction.** The whole cipher is additions,
rotations and exclusive-ors on 32-bit words, with no table and no branch on
the key, which is also what makes it fast without hardware support.

The nonce MUST NOT repeat under one key. A repeated nonce gives the same
keystream twice, and the XOR of two ciphertexts is then the XOR of the two
plaintexts.

**See also** &nbsp; [ChaCha20Poly1305](#chacha20poly1305-class)

<sub>[stdlib/Security/Cryptography/ChaCha20.sl:52](../../stdlib/Security/Cryptography/ChaCha20.sl#L52)</sub>

#### KeySize *constant*

```
const nuint KeySize = 32
```

**Value** &nbsp; thirty-two bytes.

<sub>[stdlib/Security/Cryptography/ChaCha20.sl:55](../../stdlib/Security/Cryptography/ChaCha20.sl#L55)</sub>

#### NonceSize *constant*

```
const nuint NonceSize = 12
```

**Value** &nbsp; twelve bytes.

<sub>[stdlib/Security/Cryptography/ChaCha20.sl:58](../../stdlib/Security/Cryptography/ChaCha20.sl#L58)</sub>

#### BlockSize *constant*

```
const nuint BlockSize = 64
```

What one counter value covers.

**Value** &nbsp; sixty-four bytes.

<sub>[stdlib/Security/Cryptography/ChaCha20.sl:63](../../stdlib/Security/Cryptography/ChaCha20.sl#L63)</sub>

#### FromKey *method*

```
static Result<ChaCha20, CryptoError> FromKey(ReadOnlySpan<byte> key)
```

A cipher under `key`, which must be 32 bytes.

**Fails with**

- [CryptoError.KeyLength](#keylength-case) — `key` is not 32 bytes

<sub>[stdlib/Security/Cryptography/ChaCha20.sl:79](../../stdlib/Security/Cryptography/ChaCha20.sl#L79)</sub>

#### ApplyKeystream *method*

```
Result<byte[], CryptoError> ApplyKeystream(ReadOnlySpan<byte> nonce, uint counter, ReadOnlySpan<byte> input)
```

`input` exclusive-ored with the keystream that begins at block
`counter`. The same call encrypts and decrypts.

RFC 8439 starts at one when block zero has another use, as it has in
the AEAD construction, and at zero otherwise.

**Parameters**

- `nonce` — twelve bytes, never to repeat under this key
- `counter` — the block the keystream starts at
- `input` — the plaintext or the ciphertext

**Fails with**

- [CryptoError.NonceLength](#noncelength-case) — `nonce` is not twelve bytes
- [CryptoError.Parameter](#parameter-case) — `input` runs past block 2^32 - 1, where the counter would wrap

<sub>[stdlib/Security/Cryptography/ChaCha20.sl:98](../../stdlib/Security/Cryptography/ChaCha20.sl#L98)</sub>

### ChaCha20Poly1305 *class*

```
sealed class ChaCha20Poly1305
```

ChaCha20-Poly1305: the AEAD of RFC 8439 §2.8, as .NET's
`ChaCha20Poly1305`, and with exactly `AesGcm`'s shape.

```csharp
var box = try ChaCha20Poly1305.FromKey(key);
byte[] tag = new byte[16u];
var sealed = try box.Encrypt(nonce, plaintext, associated, tag);
var opened = try box.Decrypt(nonce, sealed, associated, tag);
```

**It is AES-GCM's alternative where there is no AES in hardware.** Every
step is additions, rotations and exclusive-ors on words, with no table and
no branch on a secret, so it is constant time and fast in software; here it
runs about three times as fast as `AesGcm`. TLS 1.3, WireGuard and SSH all
offer it for that reason.

**The nonce MUST NOT repeat under one key.** A repeat reuses the keystream
and the one-time Poly1305 key both, which gives away the XOR of the two
plaintexts and lets an attacker forge. Twelve random bytes per message is
safe to about 2^32 messages; a counter is better where one can be kept.

`Decrypt` returns `CryptoError.AuthenticationFailed` and no plaintext when
the tag does not match. The tag is checked before anything is deciphered.

**See also** &nbsp; [AesGcm](#aesgcm-class)

<sub>[stdlib/Security/Cryptography/ChaCha20Poly1305.sl:54](../../stdlib/Security/Cryptography/ChaCha20Poly1305.sl#L54)</sub>

#### TagSize *constant*

```
const nuint TagSize = 16
```

**Value** &nbsp; sixteen bytes.

<sub>[stdlib/Security/Cryptography/ChaCha20Poly1305.sl:57](../../stdlib/Security/Cryptography/ChaCha20Poly1305.sl#L57)</sub>

#### NonceSize *constant*

```
const nuint NonceSize = 12
```

The only length RFC 8439 defines.

**Value** &nbsp; twelve bytes.

<sub>[stdlib/Security/Cryptography/ChaCha20Poly1305.sl:62](../../stdlib/Security/Cryptography/ChaCha20Poly1305.sl#L62)</sub>

#### FromKey *method*

```
static Result<ChaCha20Poly1305, CryptoError> FromKey(ReadOnlySpan<byte> key)
```

A box under `key`, which must be 32 bytes.

**Fails with**

- [CryptoError.KeyLength](#keylength-case) — `key` is not 32 bytes

<sub>[stdlib/Security/Cryptography/ChaCha20Poly1305.sl:74](../../stdlib/Security/Cryptography/ChaCha20Poly1305.sl#L74)</sub>

#### Encrypt *method*

```
Result<byte[], CryptoError> Encrypt(ReadOnlySpan<byte> nonce, ReadOnlySpan<byte> plaintext, ReadOnlySpan<byte> associatedData, byte[] tag)
```

The ciphertext, with the tag written into `tag`.

`associatedData` is authenticated and not encrypted — a message header,
a record number, anything the recipient must be sure of and that is not
secret. Pass an empty array when there is none.

**Parameters**

- `nonce` — twelve bytes, never to repeat under this key
- `plaintext` — the message to encipher
- `associatedData` — authenticated and not encrypted; empty when there is none
- `tag` — a `TagSize` array the tag is written into

**Fails with**

- [CryptoError.NonceLength](#noncelength-case) — `nonce` is not twelve bytes
- [CryptoError.TagLength](#taglength-case) — `tag` is not `TagSize` long
- [CryptoError.Parameter](#parameter-case) — `plaintext` is longer than the 256 GiB the counter covers

**See also** &nbsp; [ChaCha20Poly1305.Decrypt](#decrypt-method)

<sub>[stdlib/Security/Cryptography/ChaCha20Poly1305.sl:97](../../stdlib/Security/Cryptography/ChaCha20Poly1305.sl#L97)</sub>

#### Decrypt *method*

```
Result<byte[], CryptoError> Decrypt(ReadOnlySpan<byte> nonce, ReadOnlySpan<byte> ciphertext, ReadOnlySpan<byte> associatedData, ReadOnlySpan<byte> tag)
```

The plaintext, or `AuthenticationFailed` and nothing.

**Parameters**

- `nonce` — the one the message was enciphered under
- `ciphertext` — the message to open
- `associatedData` — the same bytes the sender authenticated
- `tag` — the tag the sender sent

**Fails with**

- [CryptoError.NonceLength](#noncelength-case) — `nonce` is not twelve bytes
- [CryptoError.TagLength](#taglength-case) — `tag` is not `TagSize` long
- [CryptoError.Parameter](#parameter-case) — `ciphertext` is longer than the counter covers
- [CryptoError.AuthenticationFailed](#authenticationfailed-case) — the tag does not match, and no plaintext is returned

**See also** &nbsp; [ChaCha20Poly1305.Encrypt](#encrypt-method)

<sub>[stdlib/Security/Cryptography/ChaCha20Poly1305.sl:129](../../stdlib/Security/Cryptography/ChaCha20Poly1305.sl#L129)</sub>

### CipherMode *enum*

```
enum CipherMode
```

How the blocks of a message are chained together.

.NET's `CipherMode`, minus the two nobody should pick: `Ofb` and `Cts` are
not implemented by .NET's own AES either, and a mode that exists only to be
rejected is worse than a name that is not there.

<sub>[stdlib/Security/Cryptography/CipherMode.sl:34](../../stdlib/Security/Cryptography/CipherMode.sl#L34)</sub>

#### Cbc *case*

```
Cbc
```

Cipher block chaining: each block is XORed with the one before it, and
the first with the IV. Needs a unique, unpredictable IV per message,
and provides no authentication at all.

<sub>[stdlib/Security/Cryptography/CipherMode.sl:39](../../stdlib/Security/Cryptography/CipherMode.sl#L39)</sub>

#### Ecb *case*

```
Ecb
```

Electronic codebook: each block alone. **Equal plaintext blocks give
equal ciphertext blocks**, which is why the penguin picture is famous.
Right for exactly one thing -- enciphering a single block that is
already a key.

<sub>[stdlib/Security/Cryptography/CipherMode.sl:45](../../stdlib/Security/Cryptography/CipherMode.sl#L45)</sub>

#### Cfb *case*

```
Cfb
```

Cipher feedback, as a full-block stream. Needs a unique IV and, like
CBC, authenticates nothing.

<sub>[stdlib/Security/Cryptography/CipherMode.sl:49](../../stdlib/Security/Cryptography/CipherMode.sl#L49)</sub>

#### Ctr *case*

```
Ctr
```

Counter mode: the cipher makes a keystream, and the message is XORed
with it. Not in .NET's enum, and here because it is what AES-GCM is
built on and what most modern protocols specify. **Reusing a counter
value with the same key destroys the message pair completely.**

<sub>[stdlib/Security/Cryptography/CipherMode.sl:55](../../stdlib/Security/Cryptography/CipherMode.sl#L55)</sub>

### CryptoError *enum*

```
enum CryptoError
```

Why an operation did not happen.

One enum for the module, as `IOError` is for `Standard.IO`: a caller
switching on the failure of a decrypt wants the same vocabulary as one
checking a key length.

<sub>[stdlib/Security/Cryptography/CryptoError.sl:34](../../stdlib/Security/Cryptography/CryptoError.sl#L34)</sub>

#### KeyLength *case*

```
KeyLength
```

The key is not a length this algorithm takes. AES takes 16, 24 or 32
bytes; an HMAC key may be any length at all, so this never comes from
one.

<sub>[stdlib/Security/Cryptography/CryptoError.sl:39](../../stdlib/Security/Cryptography/CryptoError.sl#L39)</sub>

#### IvLength *case*

```
IvLength
```

The initialization vector is not one block long.

<sub>[stdlib/Security/Cryptography/CryptoError.sl:42](../../stdlib/Security/Cryptography/CryptoError.sl#L42)</sub>

#### NonceLength *case*

```
NonceLength
```

The nonce is not a length this mode takes. AES-GCM takes any non-empty
nonce and wants twelve bytes; ChaCha20 takes twelve and nothing else.

<sub>[stdlib/Security/Cryptography/CryptoError.sl:46](../../stdlib/Security/Cryptography/CryptoError.sl#L46)</sub>

#### TagLength *case*

```
TagLength
```

The authentication tag is not a length this mode produces.

<sub>[stdlib/Security/Cryptography/CryptoError.sl:49](../../stdlib/Security/Cryptography/CryptoError.sl#L49)</sub>

#### BlockLength *case*

```
BlockLength
```

The input is not a whole number of blocks, and the padding mode in
force does not add any.

<sub>[stdlib/Security/Cryptography/CryptoError.sl:53](../../stdlib/Security/Cryptography/CryptoError.sl#L53)</sub>

#### Padding *case*

```
Padding
```

The padding on a decrypted block does not describe itself. Usually the
wrong key, and deliberately says no more than that.

<sub>[stdlib/Security/Cryptography/CryptoError.sl:57](../../stdlib/Security/Cryptography/CryptoError.sl#L57)</sub>

#### AuthenticationFailed *case*

```
AuthenticationFailed
```

The tag did not match. **The plaintext is not returned**, because a
plaintext that failed authentication is attacker-controlled and
handling it at all is the mistake AEAD exists to prevent.

<sub>[stdlib/Security/Cryptography/CryptoError.sl:62](../../stdlib/Security/Cryptography/CryptoError.sl#L62)</sub>

#### Parameter *case*

```
Parameter
```

A parameter outside the range the algorithm defines: an iteration count
or an output length of zero, a salt too short, a cost that is not a
power of two or asks for more memory than is allowed, or more data than
a stream cipher's counter covers.

<sub>[stdlib/Security/Cryptography/CryptoError.sl:68](../../stdlib/Security/Cryptography/CryptoError.sl#L68)</sub>

#### NoEntropy *case*

```
NoEntropy
```

The platform would not supply entropy.

<sub>[stdlib/Security/Cryptography/CryptoError.sl:71](../../stdlib/Security/Cryptography/CryptoError.sl#L71)</sub>

#### InvalidKey *case*

```
InvalidKey
```

A key that is the right length and still not a key: an RSA modulus
that is even or too small, a private key whose parts disagree, a
scalar of zero or not below the group order, or a Diffie-Hellman
result that is the identity.

<sub>[stdlib/Security/Cryptography/CryptoError.sl:77](../../stdlib/Security/Cryptography/CryptoError.sl#L77)</sub>

#### InvalidSignature *case*

```
InvalidSignature
```

A signature that does not verify, or is not a well-formed signature
at all. The two are deliberately not told apart.

<sub>[stdlib/Security/Cryptography/CryptoError.sl:81](../../stdlib/Security/Cryptography/CryptoError.sl#L81)</sub>

#### InvalidPoint *case*

```
InvalidPoint
```

A point that is not on the curve, is the point at infinity where one
is not allowed, or is encoded in a form this does not read.

<sub>[stdlib/Security/Cryptography/CryptoError.sl:85](../../stdlib/Security/Cryptography/CryptoError.sl#L85)</sub>

#### Encoding *case*

```
Encoding
```

A key or signature whose DER, PEM or other encoding does not parse,
or parses as something other than what was asked for.

<sub>[stdlib/Security/Cryptography/CryptoError.sl:89](../../stdlib/Security/Cryptography/CryptoError.sl#L89)</sub>

#### MessageLength *case*

```
MessageLength
```

A message too long for the key: more than an RSA modulus can carry
under the padding asked for.

<sub>[stdlib/Security/Cryptography/CryptoError.sl:93](../../stdlib/Security/Cryptography/CryptoError.sl#L93)</sub>

#### Unsupported *case*

```
Unsupported
```

A well-formed request this does not implement: a curve, a hash or a
padding mode it has no code for.

<sub>[stdlib/Security/Cryptography/CryptoError.sl:97](../../stdlib/Security/Cryptography/CryptoError.sl#L97)</sub>

### CryptographicOperations *class*

```
class CryptographicOperations
```

The two operations on a secret that are easy to write wrongly.

<sub>[stdlib/Security/Cryptography/CryptographicOperations.sl:30](../../stdlib/Security/Cryptography/CryptographicOperations.sl#L30)</sub>

#### FixedTimeEquals *method*

```
static bool FixedTimeEquals(ReadOnlySpan<byte> left, ReadOnlySpan<byte> right)
```

Whether two byte strings are equal, in time that does not depend on
where they first differ.

**Use this for every comparison of a MAC, a tag, a token or a password
hash.** An ordinary loop returns as soon as it finds a difference, and
an attacker who can time it recovers the expected value one byte at a
time -- a few thousand requests for a MAC that would take for ever to
guess.

Unequal lengths answer false immediately, which leaks the length and
nothing else; .NET does the same, and a length is not the secret.

<sub>[stdlib/Security/Cryptography/CryptographicOperations.sl:43](../../stdlib/Security/Cryptography/CryptographicOperations.sl#L43)</sub>

#### ZeroMemory *method*

```
static void ZeroMemory(byte[] buffer)
```

Overwrites `buffer` with zeros, in a way the optimiser may not remove
however little is read afterwards.

A key that is overwritten is not in the next core dump. It may still be
in a register, a copy made along the way, or memory the allocator has
moved; this clears the one buffer it is given and nothing else.

<sub>[stdlib/Security/Cryptography/CryptographicOperations.sl:63](../../stdlib/Security/Cryptography/CryptographicOperations.sl#L63)</sub>

### DsaSignatureFormat *enum*

```
enum DsaSignatureFormat
```

How the two numbers of a DSA or ECDSA signature, `r` and `s`, are laid out
as bytes: .NET's `DSASignatureFormat`.

<sub>[stdlib/Security/Cryptography/DsaSignatureFormat.sl:26](../../stdlib/Security/Cryptography/DsaSignatureFormat.sl#L26)</sub>

#### IeeeP1363FixedFieldConcatenation *case*

```
IeeeP1363FixedFieldConcatenation
```

`r` then `s`, each big-endian and as wide as the group order: 64 bytes
for P-256 and 96 for P-384. What JOSE, WebAuthn and .NET's default use.

<sub>[stdlib/Security/Cryptography/DsaSignatureFormat.sl:30](../../stdlib/Security/Cryptography/DsaSignatureFormat.sl#L30)</sub>

#### Rfc3279DerSequence *case*

```
Rfc3279DerSequence
```

A DER `SEQUENCE` of two `INTEGER`s, as RFC 3279 defines it. What X.509,
TLS and OpenSSL use; its length varies by a few bytes.

<sub>[stdlib/Security/Cryptography/DsaSignatureFormat.sl:34](../../stdlib/Security/Cryptography/DsaSignatureFormat.sl#L34)</sub>

### ECCurve *struct*

```
struct ECCurve
```

An elliptic curve, named by its object identifier: .NET's `ECCurve`,
for named curves.

```csharp
var key = try ECDsa.Create(ECCurve.NamedCurves.NistP256);
```

**Any identifier can be held, and two can be used**: P-256 and P-384,
which are what TLS, X.509 and FIPS 186-5 use. A key on any other curve —
`secp256k1`, P-521, a curve given by explicit parameters — is refused
with `CryptoError.Unsupported` when a key is made or imported, so a
certificate naming one reads cleanly and fails where it is used.

The zero value names no curve.

<sub>[stdlib/Security/Cryptography/ECCurve.sl:38](../../stdlib/Security/Cryptography/ECCurve.sl#L38)</sub>

#### IsNamed *property*

```
bool IsNamed { get; }
```

Whether this names a curve, which every curve but the zero value does.

<sub>[stdlib/Security/Cryptography/ECCurve.sl:61](../../stdlib/Security/Cryptography/ECCurve.sl#L61)</sub>

#### OidValue *property*

```
String OidValue { get; }
```

The curve's object identifier, dotted, or empty for the zero value.

<sub>[stdlib/Security/Cryptography/ECCurve.sl:64](../../stdlib/Security/Cryptography/ECCurve.sl#L64)</sub>

#### FriendlyName *property*

```
String FriendlyName { get; }
```

.NET's name for the curve — `nistP256`, `nistP384` — or empty for a
curve this module has no arithmetic for.

<sub>[stdlib/Security/Cryptography/ECCurve.sl:68](../../stdlib/Security/Cryptography/ECCurve.sl#L68)</sub>

#### CreateFromValue *method*

```
static ECCurve CreateFromValue(String oidValue)
```

The curve named by `oidValue`, supported or not.

**Parameters**

- `oidValue` — a dotted object identifier, as a certificate carries it

**See also** &nbsp; [ECCurve.CreateFromFriendlyName](#createfromfriendlyname-method)

<sub>[stdlib/Security/Cryptography/ECCurve.sl:87](../../stdlib/Security/Cryptography/ECCurve.sl#L87)</sub>

#### CreateFromFriendlyName *method*

```
static ECCurve CreateFromFriendlyName(String friendlyName)
```

The curve a name means: `nistP256`, `secp256r1`, `prime256v1` or
`P-256`, and `nistP384`, `secp384r1` or `P-384`. Any other name gives
the zero value, which names no curve.

**Parameters**

- `friendlyName` — what the curve is called, with its case as written here

**See also** &nbsp; [ECCurve.CreateFromValue](#createfromvalue-method)

<sub>[stdlib/Security/Cryptography/ECCurve.sl:95](../../stdlib/Security/Cryptography/ECCurve.sl#L95)</sub>

#### Equals *method*

```
bool Equals(ECCurve other)
```

Whether both name the same curve.

<sub>[stdlib/Security/Cryptography/ECCurve.sl:116](../../stdlib/Security/Cryptography/ECCurve.sl#L116)</sub>

### ECCurve.NamedCurves *class*

```
class ECCurve.NamedCurves
```

The curves this module has arithmetic for.

<sub>[stdlib/Security/Cryptography/ECCurve.sl:50](../../stdlib/Security/Cryptography/ECCurve.sl#L50)</sub>

#### NistP256 *property*

```
static ECCurve NistP256 { get; }
```

NIST P-256, also called `secp256r1` and `prime256v1`: OID
1.2.840.10045.3.1.7.

<sub>[stdlib/Security/Cryptography/ECCurve.sl:54](../../stdlib/Security/Cryptography/ECCurve.sl#L54)</sub>

#### NistP384 *property*

```
static ECCurve NistP384 { get; }
```

NIST P-384, also called `secp384r1`: OID 1.3.132.0.34.

<sub>[stdlib/Security/Cryptography/ECCurve.sl:57](../../stdlib/Security/Cryptography/ECCurve.sl#L57)</sub>

### ECDiffieHellman *class*

```
sealed class ECDiffieHellman
```

Elliptic-curve Diffie-Hellman over P-256 or P-384: SP 800-56A's ECC CDH
primitive, in .NET's `ECDiffieHellman` shape.

```csharp
var mine = try ECDiffieHellman.Create(ECCurve.NamedCurves.NistP256);
send(mine.PublicKey);
byte[] shared = try mine.DeriveRawSecretAgreement(received);
```

**Points travel in SEC 1 form**, the one TLS key shares and X9.63 use:
`PublicKey` is `04 X Y`, and a point from the other party may be that or
compressed. Every such point is checked before it is used — on the curve,
not at infinity, each coordinate below `p` — so an invalid-curve attack
has nothing to work with.

**The secret is the shared point's x coordinate, raw.** It is not a key:
run it through a KDF, as TLS 1.3 does with HKDF, or ask for one of the
`DeriveKeyFrom*` forms. The scalar multiplication behind it is constant
time.

**See also** &nbsp; [ECDsa](#ecdsa-class)

<sub>[stdlib/Security/Cryptography/ECDiffieHellman.sl:45](../../stdlib/Security/Cryptography/ECDiffieHellman.sl#L45)</sub>

#### Create *method*

```
static Result<ECDiffieHellman, CryptoError> Create()
```

A new key on P-256.

**Fails with**

- [CryptoError.NoEntropy](#noentropy-case) — the platform supplied no random bytes

<sub>[stdlib/Security/Cryptography/ECDiffieHellman.sl:57](../../stdlib/Security/Cryptography/ECDiffieHellman.sl#L57)</sub>

#### Create *method*

```
static Result<ECDiffieHellman, CryptoError> Create(ECCurve curve)
```

A new key on `curve`.

**Parameters**

- `curve` — P-256 or P-384

**Fails with**

- [CryptoError.Unsupported](#unsupported-case) — `curve` is another curve
- [CryptoError.NoEntropy](#noentropy-case) — the platform supplied no random bytes

<sub>[stdlib/Security/Cryptography/ECDiffieHellman.sl:65](../../stdlib/Security/Cryptography/ECDiffieHellman.sl#L65)</sub>

#### Create *method*

```
static Result<ECDiffieHellman, CryptoError> Create(ECParameters parameters)
```

The key `parameters` describe: private when `D` is set, and public
otherwise.

**Parameters**

- `parameters` — the curve, the point and perhaps the scalar

**Fails with**

- [CryptoError.Unsupported](#unsupported-case) — the curve is not P-256 or P-384
- [CryptoError.InvalidPoint](#invalidpoint-case) — the point is not on the curve
- [CryptoError.InvalidKey](#invalidkey-case) — the scalar is not in `[1, n - 1]` or does not give the point

<sub>[stdlib/Security/Cryptography/ECDiffieHellman.sl:81](../../stdlib/Security/Cryptography/ECDiffieHellman.sl#L81)</sub>

#### KeySize *property*

```
nuint KeySize { get; }
```

The size of the key in bits: 256 or 384.

<sub>[stdlib/Security/Cryptography/ECDiffieHellman.sl:90](../../stdlib/Security/Cryptography/ECDiffieHellman.sl#L90)</sub>

#### PublicKey *property*

```
byte[] PublicKey { get; }
```

The public point in SEC 1's uncompressed form, `04 X Y`: 65 bytes for
P-256 and 97 for P-384. What a TLS key share carries.

<sub>[stdlib/Security/Cryptography/ECDiffieHellman.sl:94](../../stdlib/Security/Cryptography/ECDiffieHellman.sl#L94)</sub>

#### ImportParameters *method*

```
Result<bool, CryptoError> ImportParameters(ECParameters parameters)
```

Replaces the key with the one `parameters` describe. On failure the
key is unchanged.

**Parameters**

- `parameters` — the curve, the point and perhaps the scalar

**Fails with**

- [CryptoError.Unsupported](#unsupported-case) — the curve is not P-256 or P-384
- [CryptoError.InvalidPoint](#invalidpoint-case) — the point is not on the curve
- [CryptoError.InvalidKey](#invalidkey-case) — the scalar is not in `[1, n - 1]` or does not give the point

<sub>[stdlib/Security/Cryptography/ECDiffieHellman.sl:104](../../stdlib/Security/Cryptography/ECDiffieHellman.sl#L104)</sub>

#### ExportParameters *method*

```
Result<ECParameters, CryptoError> ExportParameters(bool includePrivateParameters)
```

The key's numbers.

**Parameters**

- `includePrivateParameters` — whether to include `D`

**Fails with**

- [CryptoError.InvalidKey](#invalidkey-case) — `D` was asked for and this is a public key

<sub>[stdlib/Security/Cryptography/ECDiffieHellman.sl:117](../../stdlib/Security/Cryptography/ECDiffieHellman.sl#L117)</sub>

#### DeriveRawSecretAgreement *method*

```
Result<byte[], CryptoError> DeriveRawSecretAgreement(ReadOnlySpan<byte> otherPartyPublicKey)
```

The shared secret with the holder of `otherPartyPublicKey`: the x
coordinate of `d * Q`, as wide as the field.

**Parameters**

- `otherPartyPublicKey` — the other party's point in SEC 1 form, on this key's curve

**Fails with**

- [CryptoError.InvalidPoint](#invalidpoint-case) — the point is malformed, on another curve, or not on the curve at all
- [CryptoError.InvalidKey](#invalidkey-case) — this is a public key, or the result is the point at infinity

**See also** &nbsp; [ECDiffieHellman.PublicKey](#publickey-property)

<sub>[stdlib/Security/Cryptography/ECDiffieHellman.sl:132](../../stdlib/Security/Cryptography/ECDiffieHellman.sl#L132)</sub>

#### DeriveKeyFromHash *method*

```
Result<byte[], CryptoError> DeriveKeyFromHash(ReadOnlySpan<byte> otherPartyPublicKey, HashAlgorithmName hashAlgorithm)
```

`hashAlgorithm` over the shared secret: .NET's `DeriveKeyFromHash` with
nothing before or after it.

**Parameters**

- `otherPartyPublicKey` — the other party's point in SEC 1 form
- `hashAlgorithm` — the hash

**Fails with**

- [CryptoError.InvalidPoint](#invalidpoint-case) — the point does not check
- [CryptoError.InvalidKey](#invalidkey-case) — this is a public key, or the result is infinity
- [CryptoError.Unsupported](#unsupported-case) — `hashAlgorithm` is the zero value

<sub>[stdlib/Security/Cryptography/ECDiffieHellman.sl:143](../../stdlib/Security/Cryptography/ECDiffieHellman.sl#L143)</sub>

#### DeriveKeyFromHash *method*

```
Result<byte[], CryptoError> DeriveKeyFromHash(ReadOnlySpan<byte> otherPartyPublicKey, HashAlgorithmName hashAlgorithm, ReadOnlySpan<byte> secretPrepend, ReadOnlySpan<byte> secretAppend)
```

`hashAlgorithm` over `secretPrepend`, the shared secret and
`secretAppend`.

**Parameters**

- `otherPartyPublicKey` — the other party's point in SEC 1 form
- `hashAlgorithm` — the hash
- `secretPrepend` — what to hash before the secret
- `secretAppend` — what to hash after it

**Fails with**

- [CryptoError.InvalidPoint](#invalidpoint-case) — the point does not check
- [CryptoError.InvalidKey](#invalidkey-case) — this is a public key, or the result is infinity
- [CryptoError.Unsupported](#unsupported-case) — `hashAlgorithm` is the zero value

<sub>[stdlib/Security/Cryptography/ECDiffieHellman.sl:157](../../stdlib/Security/Cryptography/ECDiffieHellman.sl#L157)</sub>

#### DeriveKeyFromHmac *method*

```
Result<byte[], CryptoError> DeriveKeyFromHmac(ReadOnlySpan<byte> otherPartyPublicKey, HashAlgorithmName hashAlgorithm, ReadOnlySpan<byte> hmacKey)
```

HMAC under `hmacKey` over the shared secret.

**Parameters**

- `otherPartyPublicKey` — the other party's point in SEC 1 form
- `hashAlgorithm` — the hash under the HMAC
- `hmacKey` — the HMAC key

**Fails with**

- [CryptoError.InvalidPoint](#invalidpoint-case) — the point does not check
- [CryptoError.InvalidKey](#invalidkey-case) — this is a public key, or the result is infinity
- [CryptoError.Unsupported](#unsupported-case) — `hashAlgorithm` is the zero value

<sub>[stdlib/Security/Cryptography/ECDiffieHellman.sl:184](../../stdlib/Security/Cryptography/ECDiffieHellman.sl#L184)</sub>

#### DeriveKeyFromHmac *method*

```
Result<byte[], CryptoError> DeriveKeyFromHmac(ReadOnlySpan<byte> otherPartyPublicKey, HashAlgorithmName hashAlgorithm, ReadOnlySpan<byte> hmacKey, ReadOnlySpan<byte> secretPrepend, ReadOnlySpan<byte> secretAppend)
```

HMAC under `hmacKey` over `secretPrepend`, the shared secret and
`secretAppend`.

**Parameters**

- `otherPartyPublicKey` — the other party's point in SEC 1 form
- `hashAlgorithm` — the hash under the HMAC
- `hmacKey` — the HMAC key
- `secretPrepend` — what to authenticate before the secret
- `secretAppend` — what to authenticate after it

**Fails with**

- [CryptoError.InvalidPoint](#invalidpoint-case) — the point does not check
- [CryptoError.InvalidKey](#invalidkey-case) — this is a public key, or the result is infinity
- [CryptoError.Unsupported](#unsupported-case) — `hashAlgorithm` is the zero value

<sub>[stdlib/Security/Cryptography/ECDiffieHellman.sl:200](../../stdlib/Security/Cryptography/ECDiffieHellman.sl#L200)</sub>

#### ImportSubjectPublicKeyInfo *method*

```
Result<nuint, CryptoError> ImportSubjectPublicKeyInfo(ReadOnlySpan<byte> source)
```

Replaces the key with the public key in an RFC 5480
`SubjectPublicKeyInfo`. On failure the key is unchanged.

**Parameters**

- `source` — the DER, perhaps with more after it

**Returns** &nbsp; how many bytes of `source` the structure took

**Fails with**

- [CryptoError.Encoding](#encoding-case) — not a `SubjectPublicKeyInfo` for an EC key
- [CryptoError.Unsupported](#unsupported-case) — a curve other than P-256 and P-384
- [CryptoError.InvalidPoint](#invalidpoint-case) — the point is not on the curve

<sub>[stdlib/Security/Cryptography/ECDiffieHellman.sl:231](../../stdlib/Security/Cryptography/ECDiffieHellman.sl#L231)</sub>

#### ExportSubjectPublicKeyInfo *method*

```
byte[] ExportSubjectPublicKeyInfo()
```

The public key as an RFC 5480 `SubjectPublicKeyInfo`, in DER.

<sub>[stdlib/Security/Cryptography/ECDiffieHellman.sl:241](../../stdlib/Security/Cryptography/ECDiffieHellman.sl#L241)</sub>

#### ExportSubjectPublicKeyInfoPem *method*

```
String ExportSubjectPublicKeyInfoPem()
```

The public key as a `PUBLIC KEY` PEM block.

<sub>[stdlib/Security/Cryptography/ECDiffieHellman.sl:244](../../stdlib/Security/Cryptography/ECDiffieHellman.sl#L244)</sub>

#### ImportECPrivateKey *method*

```
Result<nuint, CryptoError> ImportECPrivateKey(ReadOnlySpan<byte> source)
```

Replaces the key with the private key in an RFC 5915 `ECPrivateKey`,
which MUST name its curve. On failure the key is unchanged.

**Parameters**

- `source` — the DER, perhaps with more after it

**Returns** &nbsp; how many bytes of `source` the structure took

**Fails with**

- [CryptoError.Encoding](#encoding-case) — not an `ECPrivateKey`, or one with no curve
- [CryptoError.Unsupported](#unsupported-case) — a curve other than P-256 and P-384
- [CryptoError.InvalidKey](#invalidkey-case) — the scalar is not in `[1, n - 1]`, or does not give the public point beside it
- [CryptoError.InvalidPoint](#invalidpoint-case) — the public point is not on the curve

<sub>[stdlib/Security/Cryptography/ECDiffieHellman.sl:257](../../stdlib/Security/Cryptography/ECDiffieHellman.sl#L257)</sub>

#### ExportECPrivateKey *method*

```
Result<byte[], CryptoError> ExportECPrivateKey()
```

The private key as an RFC 5915 `ECPrivateKey`, in DER.

**Fails with**

- [CryptoError.InvalidKey](#invalidkey-case) — this is a public key

<sub>[stdlib/Security/Cryptography/ECDiffieHellman.sl:269](../../stdlib/Security/Cryptography/ECDiffieHellman.sl#L269)</sub>

#### ExportECPrivateKeyPem *method*

```
Result<String, CryptoError> ExportECPrivateKeyPem()
```

The private key as an `EC PRIVATE KEY` PEM block.

**Fails with**

- [CryptoError.InvalidKey](#invalidkey-case) — this is a public key

<sub>[stdlib/Security/Cryptography/ECDiffieHellman.sl:274](../../stdlib/Security/Cryptography/ECDiffieHellman.sl#L274)</sub>

#### ImportPkcs8PrivateKey *method*

```
Result<nuint, CryptoError> ImportPkcs8PrivateKey(ReadOnlySpan<byte> source)
```

Replaces the key with the private key in an unencrypted PKCS #8
`PrivateKeyInfo`. On failure the key is unchanged.

**Parameters**

- `source` — the DER, perhaps with more after it

**Returns** &nbsp; how many bytes of `source` the structure took

**Fails with**

- [CryptoError.Encoding](#encoding-case) — not a `PrivateKeyInfo` for an EC key
- [CryptoError.Unsupported](#unsupported-case) — a curve other than P-256 and P-384
- [CryptoError.InvalidKey](#invalidkey-case) — the scalar is not in `[1, n - 1]`, or does not give the public point beside it
- [CryptoError.InvalidPoint](#invalidpoint-case) — the public point is not on the curve

<sub>[stdlib/Security/Cryptography/ECDiffieHellman.sl:292](../../stdlib/Security/Cryptography/ECDiffieHellman.sl#L292)</sub>

#### ExportPkcs8PrivateKey *method*

```
Result<byte[], CryptoError> ExportPkcs8PrivateKey()
```

The private key as an unencrypted PKCS #8 `PrivateKeyInfo`, in DER.

**Fails with**

- [CryptoError.InvalidKey](#invalidkey-case) — this is a public key

<sub>[stdlib/Security/Cryptography/ECDiffieHellman.sl:304](../../stdlib/Security/Cryptography/ECDiffieHellman.sl#L304)</sub>

#### ExportPkcs8PrivateKeyPem *method*

```
Result<String, CryptoError> ExportPkcs8PrivateKeyPem()
```

The private key as a `PRIVATE KEY` PEM block.

**Fails with**

- [CryptoError.InvalidKey](#invalidkey-case) — this is a public key

<sub>[stdlib/Security/Cryptography/ECDiffieHellman.sl:309](../../stdlib/Security/Cryptography/ECDiffieHellman.sl#L309)</sub>

#### ImportFromPem *method*

```
Result<bool, CryptoError> ImportFromPem(String input)
```

Replaces the key with the first `PUBLIC KEY`, `EC PRIVATE KEY` or
`PRIVATE KEY` block in `input`. Blocks with other labels are passed
over. On failure the key is unchanged.

**Parameters**

- `input` — PEM text

**Fails with**

- [CryptoError.Encoding](#encoding-case) — no such block, or one whose contents are not what its label says
- [CryptoError.Unsupported](#unsupported-case) — an encrypted key, or a curve other than P-256 and P-384
- [CryptoError.InvalidKey](#invalidkey-case) — the key does not check

<sub>[stdlib/Security/Cryptography/ECDiffieHellman.sl:327](../../stdlib/Security/Cryptography/ECDiffieHellman.sl#L327)</sub>

### ECDsa *class*

```
sealed class ECDsa
```

ECDSA over P-256 or P-384: FIPS 186-5's signature, in .NET's `ECDsa`
shape.

```csharp
var key = try ECDsa.Create(ECCurve.NamedCurves.NistP256);
byte[] signature = try key.SignData(message, HashAlgorithmName.Sha256);
bool genuine = key.VerifyData(message, signature, HashAlgorithmName.Sha256);

var verifier = try ECDsa.Create(ECCurve.NamedCurves.NistP256);
try verifier.ImportSubjectPublicKeyInfo(publicKeyDer);
```

**Signing is deterministic**: the nonce is RFC 6979's, derived by HMAC
from the key and the hash, so the same key and message always give the
same signature and no weak random number can leak the key. Signing is
constant time: the scalar multiplication, the inversion and the nonce
derivation run the same operations and touch the same addresses whatever
the key and nonce are.

**Verifying is variable time**, which is safe because everything it reads
is public, and it never fails: a signature that is malformed, out of
range or simply wrong is `false`.

A key made by `Create` is checked, and so is every key imported: a public
point on the curve and not at infinity, a private scalar in `[1, n - 1]`
that gives the public point beside it.

**See also** &nbsp; [ECDiffieHellman](#ecdiffiehellman-class)

<sub>[stdlib/Security/Cryptography/ECDsa.sl:54](../../stdlib/Security/Cryptography/ECDsa.sl#L54)</sub>

#### Create *method*

```
static Result<ECDsa, CryptoError> Create()
```

A new key on P-256.

**Fails with**

- [CryptoError.NoEntropy](#noentropy-case) — the platform supplied no random bytes

<sub>[stdlib/Security/Cryptography/ECDsa.sl:66](../../stdlib/Security/Cryptography/ECDsa.sl#L66)</sub>

#### Create *method*

```
static Result<ECDsa, CryptoError> Create(ECCurve curve)
```

A new key on `curve`.

**Parameters**

- `curve` — P-256 or P-384

**Fails with**

- [CryptoError.Unsupported](#unsupported-case) — `curve` is another curve
- [CryptoError.NoEntropy](#noentropy-case) — the platform supplied no random bytes

<sub>[stdlib/Security/Cryptography/ECDsa.sl:73](../../stdlib/Security/Cryptography/ECDsa.sl#L73)</sub>

#### Create *method*

```
static Result<ECDsa, CryptoError> Create(ECParameters parameters)
```

The key `parameters` describe: private when `D` is set, and public
otherwise.

**Parameters**

- `parameters` — the curve, the point and perhaps the scalar

**Fails with**

- [CryptoError.Unsupported](#unsupported-case) — the curve is not P-256 or P-384
- [CryptoError.InvalidPoint](#invalidpoint-case) — the point is not on the curve
- [CryptoError.InvalidKey](#invalidkey-case) — the scalar is not in `[1, n - 1]` or does not give the point

<sub>[stdlib/Security/Cryptography/ECDsa.sl:89](../../stdlib/Security/Cryptography/ECDsa.sl#L89)</sub>

#### KeySize *property*

```
nuint KeySize { get; }
```

The size of the key in bits: 256 or 384.

<sub>[stdlib/Security/Cryptography/ECDsa.sl:98](../../stdlib/Security/Cryptography/ECDsa.sl#L98)</sub>

#### ImportParameters *method*

```
Result<bool, CryptoError> ImportParameters(ECParameters parameters)
```

Replaces the key with the one `parameters` describe. On failure the
key is unchanged.

**Parameters**

- `parameters` — the curve, the point and perhaps the scalar

**Fails with**

- [CryptoError.Unsupported](#unsupported-case) — the curve is not P-256 or P-384
- [CryptoError.InvalidPoint](#invalidpoint-case) — the point is not on the curve
- [CryptoError.InvalidKey](#invalidkey-case) — the scalar is not in `[1, n - 1]` or does not give the point

<sub>[stdlib/Security/Cryptography/ECDsa.sl:108](../../stdlib/Security/Cryptography/ECDsa.sl#L108)</sub>

#### ExportParameters *method*

```
Result<ECParameters, CryptoError> ExportParameters(bool includePrivateParameters)
```

The key's numbers.

**Parameters**

- `includePrivateParameters` — whether to include `D`

**Fails with**

- [CryptoError.InvalidKey](#invalidkey-case) — `D` was asked for and this is a public key

<sub>[stdlib/Security/Cryptography/ECDsa.sl:121](../../stdlib/Security/Cryptography/ECDsa.sl#L121)</sub>

#### SignHash *method*

```
Result<byte[], CryptoError> SignHash(ReadOnlySpan<byte> hash)
```

The signature of a hash already computed, as `r` then `s`.

The nonce's HMAC uses the hash whose length `hash` has — SHA-1,
SHA-256, SHA-384 or SHA-512 — and the curve's own for any other length.

**Parameters**

- `hash` — the digest of the message

**Fails with**

- [CryptoError.InvalidKey](#invalidkey-case) — this is a public key

**See also** &nbsp; [ECDsa.VerifyHash](#verifyhash-method)

<sub>[stdlib/Security/Cryptography/ECDsa.sl:134](../../stdlib/Security/Cryptography/ECDsa.sl#L134)</sub>

#### SignHash *method*

```
Result<byte[], CryptoError> SignHash(ReadOnlySpan<byte> hash, DsaSignatureFormat signatureFormat)
```

The signature of a hash already computed, in `signatureFormat`.

**Parameters**

- `hash` — the digest of the message
- `signatureFormat` — how to lay out `r` and `s`

**Fails with**

- [CryptoError.InvalidKey](#invalidkey-case) — this is a public key

<sub>[stdlib/Security/Cryptography/ECDsa.sl:142](../../stdlib/Security/Cryptography/ECDsa.sl#L142)</sub>

#### SignData *method*

```
Result<byte[], CryptoError> SignData(ReadOnlySpan<byte> data, HashAlgorithmName hashAlgorithm)
```

The signature of `data` hashed with `hashAlgorithm`, as `r` then `s`.

**Parameters**

- `data` — the message
- `hashAlgorithm` — the hash, which the nonce's HMAC uses too

**Fails with**

- [CryptoError.InvalidKey](#invalidkey-case) — this is a public key
- [CryptoError.Unsupported](#unsupported-case) — `hashAlgorithm` is the zero value

**See also** &nbsp; [ECDsa.VerifyData](#verifydata-method)

<sub>[stdlib/Security/Cryptography/ECDsa.sl:174](../../stdlib/Security/Cryptography/ECDsa.sl#L174)</sub>

#### SignData *method*

```
Result<byte[], CryptoError> SignData(ReadOnlySpan<byte> data, HashAlgorithmName hashAlgorithm, DsaSignatureFormat signatureFormat)
```

The signature of `data` hashed with `hashAlgorithm`, in
`signatureFormat`.

**Parameters**

- `data` — the message
- `hashAlgorithm` — the hash, which the nonce's HMAC uses too
- `signatureFormat` — how to lay out `r` and `s`

**Fails with**

- [CryptoError.InvalidKey](#invalidkey-case) — this is a public key
- [CryptoError.Unsupported](#unsupported-case) — `hashAlgorithm` is the zero value

<sub>[stdlib/Security/Cryptography/ECDsa.sl:186](../../stdlib/Security/Cryptography/ECDsa.sl#L186)</sub>

#### VerifyHash *method*

```
bool VerifyHash(ReadOnlySpan<byte> hash, ReadOnlySpan<byte> signature)
```

Whether `signature`, as `r` then `s`, signs `hash` under this key.

**Parameters**

- `hash` — the digest of the message
- `signature` — `r` then `s`, each as wide as the order

<sub>[stdlib/Security/Cryptography/ECDsa.sl:212](../../stdlib/Security/Cryptography/ECDsa.sl#L212)</sub>

#### VerifyHash *method*

```
bool VerifyHash(ReadOnlySpan<byte> hash, ReadOnlySpan<byte> signature, DsaSignatureFormat signatureFormat)
```

Whether `signature`, laid out as `signatureFormat` says, signs `hash`
under this key.

**Parameters**

- `hash` — the digest of the message
- `signature` — the signature
- `signatureFormat` — how `r` and `s` are laid out

<sub>[stdlib/Security/Cryptography/ECDsa.sl:221](../../stdlib/Security/Cryptography/ECDsa.sl#L221)</sub>

#### VerifyData *method*

```
bool VerifyData(ReadOnlySpan<byte> data, ReadOnlySpan<byte> signature, HashAlgorithmName hashAlgorithm)
```

Whether `signature`, as `r` then `s`, signs `data` hashed with
`hashAlgorithm`.

**Parameters**

- `data` — the message
- `signature` — `r` then `s`, each as wide as the order
- `hashAlgorithm` — the hash the signer used

<sub>[stdlib/Security/Cryptography/ECDsa.sl:248](../../stdlib/Security/Cryptography/ECDsa.sl#L248)</sub>

#### VerifyData *method*

```
bool VerifyData(ReadOnlySpan<byte> data, ReadOnlySpan<byte> signature, HashAlgorithmName hashAlgorithm, DsaSignatureFormat signatureFormat)
```

Whether `signature`, laid out as `signatureFormat` says, signs `data`
hashed with `hashAlgorithm`.

**Parameters**

- `data` — the message
- `signature` — the signature
- `hashAlgorithm` — the hash the signer used
- `signatureFormat` — how `r` and `s` are laid out

<sub>[stdlib/Security/Cryptography/ECDsa.sl:260](../../stdlib/Security/Cryptography/ECDsa.sl#L260)</sub>

#### GetMaxSignatureSize *method*

```
nuint GetMaxSignatureSize(DsaSignatureFormat signatureFormat)
```

The most bytes a signature in `signatureFormat` can take: 64 or 96 for
the fixed-width form, and 72 or 104 for DER.

**Parameters**

- `signatureFormat` — the layout

<sub>[stdlib/Security/Cryptography/ECDsa.sl:274](../../stdlib/Security/Cryptography/ECDsa.sl#L274)</sub>

#### ImportSubjectPublicKeyInfo *method*

```
Result<nuint, CryptoError> ImportSubjectPublicKeyInfo(ReadOnlySpan<byte> source)
```

Replaces the key with the public key in an RFC 5480
`SubjectPublicKeyInfo`. On failure the key is unchanged.

**Parameters**

- `source` — the DER, perhaps with more after it

**Returns** &nbsp; how many bytes of `source` the structure took

**Fails with**

- [CryptoError.Encoding](#encoding-case) — not a `SubjectPublicKeyInfo` for an EC key
- [CryptoError.Unsupported](#unsupported-case) — a curve other than P-256 and P-384
- [CryptoError.InvalidPoint](#invalidpoint-case) — the point is not on the curve

<sub>[stdlib/Security/Cryptography/ECDsa.sl:292](../../stdlib/Security/Cryptography/ECDsa.sl#L292)</sub>

#### ExportSubjectPublicKeyInfo *method*

```
byte[] ExportSubjectPublicKeyInfo()
```

The public key as an RFC 5480 `SubjectPublicKeyInfo`, in DER.

<sub>[stdlib/Security/Cryptography/ECDsa.sl:302](../../stdlib/Security/Cryptography/ECDsa.sl#L302)</sub>

#### ExportSubjectPublicKeyInfoPem *method*

```
String ExportSubjectPublicKeyInfoPem()
```

The public key as a `PUBLIC KEY` PEM block.

<sub>[stdlib/Security/Cryptography/ECDsa.sl:305](../../stdlib/Security/Cryptography/ECDsa.sl#L305)</sub>

#### ImportECPrivateKey *method*

```
Result<nuint, CryptoError> ImportECPrivateKey(ReadOnlySpan<byte> source)
```

Replaces the key with the private key in an RFC 5915 `ECPrivateKey`,
which MUST name its curve. On failure the key is unchanged.

**Parameters**

- `source` — the DER, perhaps with more after it

**Returns** &nbsp; how many bytes of `source` the structure took

**Fails with**

- [CryptoError.Encoding](#encoding-case) — not an `ECPrivateKey`, or one with no curve
- [CryptoError.Unsupported](#unsupported-case) — a curve other than P-256 and P-384
- [CryptoError.InvalidKey](#invalidkey-case) — the scalar is not in `[1, n - 1]`, or does not give the public point beside it
- [CryptoError.InvalidPoint](#invalidpoint-case) — the public point is not on the curve

<sub>[stdlib/Security/Cryptography/ECDsa.sl:318](../../stdlib/Security/Cryptography/ECDsa.sl#L318)</sub>

#### ExportECPrivateKey *method*

```
Result<byte[], CryptoError> ExportECPrivateKey()
```

The private key as an RFC 5915 `ECPrivateKey`, in DER.

**Fails with**

- [CryptoError.InvalidKey](#invalidkey-case) — this is a public key

<sub>[stdlib/Security/Cryptography/ECDsa.sl:330](../../stdlib/Security/Cryptography/ECDsa.sl#L330)</sub>

#### ExportECPrivateKeyPem *method*

```
Result<String, CryptoError> ExportECPrivateKeyPem()
```

The private key as an `EC PRIVATE KEY` PEM block.

**Fails with**

- [CryptoError.InvalidKey](#invalidkey-case) — this is a public key

<sub>[stdlib/Security/Cryptography/ECDsa.sl:335](../../stdlib/Security/Cryptography/ECDsa.sl#L335)</sub>

#### ImportPkcs8PrivateKey *method*

```
Result<nuint, CryptoError> ImportPkcs8PrivateKey(ReadOnlySpan<byte> source)
```

Replaces the key with the private key in an unencrypted PKCS #8
`PrivateKeyInfo`. On failure the key is unchanged.

**Parameters**

- `source` — the DER, perhaps with more after it

**Returns** &nbsp; how many bytes of `source` the structure took

**Fails with**

- [CryptoError.Encoding](#encoding-case) — not a `PrivateKeyInfo` for an EC key
- [CryptoError.Unsupported](#unsupported-case) — a curve other than P-256 and P-384
- [CryptoError.InvalidKey](#invalidkey-case) — the scalar is not in `[1, n - 1]`, or does not give the public point beside it
- [CryptoError.InvalidPoint](#invalidpoint-case) — the public point is not on the curve

<sub>[stdlib/Security/Cryptography/ECDsa.sl:353](../../stdlib/Security/Cryptography/ECDsa.sl#L353)</sub>

#### ExportPkcs8PrivateKey *method*

```
Result<byte[], CryptoError> ExportPkcs8PrivateKey()
```

The private key as an unencrypted PKCS #8 `PrivateKeyInfo`, in DER.

**Fails with**

- [CryptoError.InvalidKey](#invalidkey-case) — this is a public key

<sub>[stdlib/Security/Cryptography/ECDsa.sl:365](../../stdlib/Security/Cryptography/ECDsa.sl#L365)</sub>

#### ExportPkcs8PrivateKeyPem *method*

```
Result<String, CryptoError> ExportPkcs8PrivateKeyPem()
```

The private key as a `PRIVATE KEY` PEM block.

**Fails with**

- [CryptoError.InvalidKey](#invalidkey-case) — this is a public key

<sub>[stdlib/Security/Cryptography/ECDsa.sl:370](../../stdlib/Security/Cryptography/ECDsa.sl#L370)</sub>

#### ImportFromPem *method*

```
Result<bool, CryptoError> ImportFromPem(String input)
```

Replaces the key with the first `PUBLIC KEY`, `EC PRIVATE KEY` or
`PRIVATE KEY` block in `input`. Blocks with other labels are passed
over. On failure the key is unchanged.

**Parameters**

- `input` — PEM text

**Fails with**

- [CryptoError.Encoding](#encoding-case) — no such block, or one whose contents are not what its label says
- [CryptoError.Unsupported](#unsupported-case) — an encrypted key, or a curve other than P-256 and P-384
- [CryptoError.InvalidKey](#invalidkey-case) — the key does not check

<sub>[stdlib/Security/Cryptography/ECDsa.sl:388](../../stdlib/Security/Cryptography/ECDsa.sl#L388)</sub>

### ECParameters *struct*

```
struct ECParameters
```

An elliptic-curve key as its numbers: .NET's `ECParameters`.

```csharp
var parameters = new ECParameters(ECCurve.NamedCurves.NistP256,
                                  new ECPoint(x, y), d);
var key = try ECDsa.Create(parameters);
```

`D` is empty for a public key. `Q`'s coordinates may be empty when `D` is
not, and the public point is then computed from `D`; when both are given
they MUST agree.

**Make one with a constructor.** The zero value's arrays are not arrays
yet, and reading one aborts.

<sub>[stdlib/Security/Cryptography/ECParameters.sl:38](../../stdlib/Security/Cryptography/ECParameters.sl#L38)</sub>

#### Curve *field*

```
ECCurve Curve
```

Which curve the key is on.

<sub>[stdlib/Security/Cryptography/ECParameters.sl:41](../../stdlib/Security/Cryptography/ECParameters.sl#L41)</sub>

#### Q *field*

```
ECPoint Q
```

The public point.

<sub>[stdlib/Security/Cryptography/ECParameters.sl:44](../../stdlib/Security/Cryptography/ECParameters.sl#L44)</sub>

#### D *field*

```
byte[] D
```

The private scalar, big-endian and as wide as the curve's order, or
empty.

<sub>[stdlib/Security/Cryptography/ECParameters.sl:48](../../stdlib/Security/Cryptography/ECParameters.sl#L48)</sub>

### ECPoint *struct*

```
struct ECPoint
```

A point on an elliptic curve, as its two affine coordinates: .NET's
`ECPoint`.

Each coordinate is big-endian and exactly as wide as the curve's field —
32 bytes for P-256, 48 for P-384 — leading zeros included.

**Make one with its constructor.** The zero value's arrays are not arrays
yet, and reading one aborts.

<sub>[stdlib/Security/Cryptography/ECPoint.sl:32](../../stdlib/Security/Cryptography/ECPoint.sl#L32)</sub>

#### X *field*

```
byte[] X
```

The x coordinate.

<sub>[stdlib/Security/Cryptography/ECPoint.sl:35](../../stdlib/Security/Cryptography/ECPoint.sl#L35)</sub>

#### Y *field*

```
byte[] Y
```

The y coordinate.

<sub>[stdlib/Security/Cryptography/ECPoint.sl:38](../../stdlib/Security/Cryptography/ECPoint.sl#L38)</sub>

### Ed25519 *class*

```
class Ed25519
```

Ed25519 (RFC 8032): signatures over edwards25519 with SHA-512, which is
what SSH, TLS 1.3, minisign and most new protocols sign with.

```csharp
byte[] privateKey = Ed25519.GeneratePrivateKey();
byte[] publicKey = try Ed25519.GetPublicKey(privateKey);
byte[] signature = try Ed25519.Sign(privateKey, message);
bool genuine = Ed25519.Verify(publicKey, message, signature);
```

This is pure Ed25519, the RFC's first variant: the message is signed as
it is, with no context string and no prehash. A private key is the RFC's
32-byte seed, a public key 32 bytes and a signature 64. Signing is
deterministic, so the same key and message always give the same
signature and no randomness is needed to sign.

**Verification is strict and cofactorless.** A signature whose S is not
below the group order is refused, as is a public key that is not the one
canonical encoding of a point on the curve. The check is
[S]B = R + [k]A, the equation RFC 8032 §5.1.7 names as sufficient, rather
than the same multiplied through by the cofactor 8. The two differ only on
a signature crafted with a component of small order, which no honest
signer makes; a protocol that needs every implementation to agree on such
signatures must specify one or the other.

**Constant time where the data is secret.** Signing multiplies by a
secret scalar with a fixed window read by mask, and reduces and combines
scalars with fixed loops. Verification touches nothing secret and uses a
faster variable-time multiplication.

<sub>[stdlib/Security/Cryptography/Ed25519.sl:57](../../stdlib/Security/Cryptography/Ed25519.sl#L57)</sub>

#### PrivateKeySize *constant*

```
const nuint PrivateKeySize = 32
```

The length of a private key: the RFC's seed.

**Value** &nbsp; thirty-two bytes.

<sub>[stdlib/Security/Cryptography/Ed25519.sl:62](../../stdlib/Security/Cryptography/Ed25519.sl#L62)</sub>

#### PublicKeySize *constant*

```
const nuint PublicKeySize = 32
```

The length of a public key.

**Value** &nbsp; thirty-two bytes.

<sub>[stdlib/Security/Cryptography/Ed25519.sl:67](../../stdlib/Security/Cryptography/Ed25519.sl#L67)</sub>

#### SignatureSize *constant*

```
const nuint SignatureSize = 64
```

The length of a signature: R, then S.

**Value** &nbsp; sixty-four bytes.

<sub>[stdlib/Security/Cryptography/Ed25519.sl:72](../../stdlib/Security/Cryptography/Ed25519.sl#L72)</sub>

#### GeneratePrivateKey *method*

```
static byte[] GeneratePrivateKey()
```

A new private key: 32 bytes from `RandomNumberGenerator`.

Aborts if the platform supplies no entropy, as
`RandomNumberGenerator.GetBytes` does.

<sub>[stdlib/Security/Cryptography/Ed25519.sl:78](../../stdlib/Security/Cryptography/Ed25519.sl#L78)</sub>

#### GetPublicKey *method*

```
static Result<byte[], CryptoError> GetPublicKey(ReadOnlySpan<byte> privateKey)
```

The public key that goes with `privateKey`.

**Parameters**

- `privateKey` — the 32-byte seed

**Fails with**

- [CryptoError.KeyLength](#keylength-case) — `privateKey` is not `PrivateKeySize` long

<sub>[stdlib/Security/Cryptography/Ed25519.sl:84](../../stdlib/Security/Cryptography/Ed25519.sl#L84)</sub>

#### Sign *method*

```
static Result<byte[], CryptoError> Sign(ReadOnlySpan<byte> privateKey, ReadOnlySpan<byte> message)
```

The 64-byte signature of `message` under `privateKey`.

**Parameters**

- `privateKey` — the 32-byte seed
- `message` — the bytes to sign, of any length

**Fails with**

- [CryptoError.KeyLength](#keylength-case) — `privateKey` is not `PrivateKeySize` long

**See also** &nbsp; [Ed25519.Verify](#verify-method)

<sub>[stdlib/Security/Cryptography/Ed25519.sl:104](../../stdlib/Security/Cryptography/Ed25519.sl#L104)</sub>

#### Verify *method*

```
static bool Verify(ReadOnlySpan<byte> publicKey, ReadOnlySpan<byte> message, ReadOnlySpan<byte> signature)
```

Whether `signature` is `publicKey`'s signature of `message`.

A key or signature of the wrong length answers false, as does a key
that is not a canonical point encoding and a signature whose S is not
below the group order. The equation checked is the cofactorless one;
the type's own documentation says what that means.

**Parameters**

- `publicKey` — the signer's 32-byte key
- `message` — the bytes that were signed
- `signature` — the 64 bytes `Sign` produced

**Returns** &nbsp; true only for a valid signature

**See also** &nbsp; [Ed25519.Sign](#sign-method)

<sub>[stdlib/Security/Cryptography/Ed25519.sl:154](../../stdlib/Security/Cryptography/Ed25519.sl#L154)</sub>

### HashAlgorithm *class*

```
abstract class HashAlgorithm : IHashAlgorithm
```

The buffering and the padding, which every Merkle-Damgard hash shares.

MD5, SHA-1, SHA-256, SHA-384 and SHA-512 differ in three things -- the
compression function, the state, and whether the length that terminates the
message is written big-endian -- and agree about everything else: fill a
block, compress it, and finish by appending a one bit, zeros, and the
length in bits. That is what is here, so a new algorithm of this family is
`CompressBlock`, `ComputeDigest` and `InitializeState` and nothing else.

<sub>[stdlib/Security/Cryptography/HashAlgorithm.sl:35](../../stdlib/Security/Cryptography/HashAlgorithm.sl#L35)</sub>

#### Name *property*

```
String Name { get; }
```

*No documentation.*

<sub>[stdlib/Security/Cryptography/HashAlgorithm.sl:64](../../stdlib/Security/Cryptography/HashAlgorithm.sl#L64)</sub>

#### HashSizeInBytes *property*

```
nuint HashSizeInBytes { get; }
```

*No documentation.*

<sub>[stdlib/Security/Cryptography/HashAlgorithm.sl:66](../../stdlib/Security/Cryptography/HashAlgorithm.sl#L66)</sub>

#### BlockSizeInBytes *property*

```
nuint BlockSizeInBytes { get; }
```

*No documentation.*

<sub>[stdlib/Security/Cryptography/HashAlgorithm.sl:68](../../stdlib/Security/Cryptography/HashAlgorithm.sl#L68)</sub>

#### AppendData *method*

```
void AppendData(ReadOnlySpan<byte> data)
```

*No documentation.*

<sub>[stdlib/Security/Cryptography/HashAlgorithm.sl:70](../../stdlib/Security/Cryptography/HashAlgorithm.sl#L70)</sub>

#### GetHashAndReset *method*

```
byte[] GetHashAndReset()
```

*No documentation.*

<sub>[stdlib/Security/Cryptography/HashAlgorithm.sl:95](../../stdlib/Security/Cryptography/HashAlgorithm.sl#L95)</sub>

#### Reset *method*

```
void Reset()
```

*No documentation.*

<sub>[stdlib/Security/Cryptography/HashAlgorithm.sl:102](../../stdlib/Security/Cryptography/HashAlgorithm.sl#L102)</sub>

#### ComputeHash *method*

```
byte[] ComputeHash(ReadOnlySpan<byte> data)
```

The digest of `data` on its own. Resets first, so an object that has
been appended to is still safe to ask.

<sub>[stdlib/Security/Cryptography/HashAlgorithm.sl:114](../../stdlib/Security/Cryptography/HashAlgorithm.sl#L114)</sub>

### HashAlgorithmName *struct*

```
struct HashAlgorithmName
```

Which hash a signature or a key derivation uses, as .NET's
`HashAlgorithmName` names it.

```csharp
var signature = try key.SignData(message, HashAlgorithmName.Sha256);
```

The zero value names no hash, and everything given it answers
`CryptoError.Unsupported`.

<sub>[stdlib/Security/Cryptography/HashAlgorithmName.sl:33](../../stdlib/Security/Cryptography/HashAlgorithmName.sl#L33)</sub>

#### Sha1 *property*

```
static HashAlgorithmName Sha1 { get; }
```

SHA-1, for verifying what older systems signed. Nothing new SHOULD be
signed with it.

<sub>[stdlib/Security/Cryptography/HashAlgorithmName.sl:70](../../stdlib/Security/Cryptography/HashAlgorithmName.sl#L70)</sub>

#### Sha256 *property*

```
static HashAlgorithmName Sha256 { get; }
```

SHA-256.

<sub>[stdlib/Security/Cryptography/HashAlgorithmName.sl:73](../../stdlib/Security/Cryptography/HashAlgorithmName.sl#L73)</sub>

#### Sha384 *property*

```
static HashAlgorithmName Sha384 { get; }
```

SHA-384.

<sub>[stdlib/Security/Cryptography/HashAlgorithmName.sl:76](../../stdlib/Security/Cryptography/HashAlgorithmName.sl#L76)</sub>

#### Sha512 *property*

```
static HashAlgorithmName Sha512 { get; }
```

SHA-512.

<sub>[stdlib/Security/Cryptography/HashAlgorithmName.sl:79](../../stdlib/Security/Cryptography/HashAlgorithmName.sl#L79)</sub>

#### Name *property*

```
String Name { get; }
```

The name .NET gives it — `SHA256` — and empty for the zero value.

<sub>[stdlib/Security/Cryptography/HashAlgorithmName.sl:82](../../stdlib/Security/Cryptography/HashAlgorithmName.sl#L82)</sub>

#### HashSizeInBytes *property*

```
nuint HashSizeInBytes { get; }
```

How many bytes its digest is, and zero for the zero value.

<sub>[stdlib/Security/Cryptography/HashAlgorithmName.sl:98](../../stdlib/Security/Cryptography/HashAlgorithmName.sl#L98)</sub>

#### CreateHashAlgorithm *method*

```
Result<IHashAlgorithm, CryptoError> CreateHashAlgorithm()
```

A fresh hash of this kind, to append to or to key an `Hmac` with.

**Fails with**

- [CryptoError.Unsupported](#unsupported-case) — this is the zero value

<sub>[stdlib/Security/Cryptography/HashAlgorithmName.sl:116](../../stdlib/Security/Cryptography/HashAlgorithmName.sl#L116)</sub>

#### Equals *method*

```
bool Equals(HashAlgorithmName other)
```

*No documentation.*

<sub>[stdlib/Security/Cryptography/HashAlgorithmName.sl:128](../../stdlib/Security/Cryptography/HashAlgorithmName.sl#L128)</sub>

#### operator == *operator*

```
static bool operator ==(HashAlgorithmName left, HashAlgorithmName right)
```

*No documentation.*

<sub>[stdlib/Security/Cryptography/HashAlgorithmName.sl:130](../../stdlib/Security/Cryptography/HashAlgorithmName.sl#L130)</sub>

#### operator != *operator*

```
static bool operator !=(HashAlgorithmName left, HashAlgorithmName right)
```

*No documentation.*

<sub>[stdlib/Security/Cryptography/HashAlgorithmName.sl:133](../../stdlib/Security/Cryptography/HashAlgorithmName.sl#L133)</sub>

#### ToString *method*

```
String ToString()
```

*No documentation.*

<sub>[stdlib/Security/Cryptography/HashAlgorithmName.sl:136](../../stdlib/Security/Cryptography/HashAlgorithmName.sl#L136)</sub>

### Hkdf *class*

```
class Hkdf
```

HKDF (RFC 5869), which .NET has as `HKDF` and which is what to use when the
input is already a key rather than a password.

PBKDF2 is slow on purpose because a password has little entropy. HKDF is
fast on purpose because its input -- a Diffie-Hellman shared secret, a
master key -- already has plenty, and all that is wanted is to spread it
into several keys that reveal nothing about each other.

<sub>[stdlib/Security/Cryptography/Hkdf.sl:34](../../stdlib/Security/Cryptography/Hkdf.sl#L34)</sub>

#### Extract *method*

```
static byte[] Extract(IHashAlgorithm hash, ReadOnlySpan<byte> inputKey, ReadOnlySpan<byte> salt)
```

The extract step: a uniformly random key from input that is random but
not uniform. `salt` may be empty, and then a block of zeros is used.

**Parameters**

- `hash` — the HMAC's inner hash
- `inputKey` — the secret that is random but not uniform
- `salt` — a non-secret value, or empty for a block of zeros

**See also** &nbsp; [Hkdf.Expand](#expand-method)

<sub>[stdlib/Security/Cryptography/Hkdf.sl:43](../../stdlib/Security/Cryptography/Hkdf.sl#L43)</sub>

#### Expand *method*

```
static Result<byte[], CryptoError> Expand(IHashAlgorithm hash, ReadOnlySpan<byte> pseudoKey, ReadOnlySpan<byte> info, nuint length)
```

The expand step: as many bytes as asked for, bound to `info`.

`info` is what separates one derived key from another -- "encryption"
and "authentication" from the same secret -- and is the argument that
makes this worth using over a bare hash.

**Parameters**

- `hash` — the HMAC's inner hash, the same one `Extract` used
- `pseudoKey` — what `Extract` answered
- `info` — what separates one derived key from another
- `length` — how many bytes to derive, at most 255 digests' worth

**Fails with**

- [CryptoError.Parameter](#parameter-case) — `length` is zero, or past 255 times the digest size

**See also** &nbsp; [Hkdf.Extract](#extract-method)

<sub>[stdlib/Security/Cryptography/Hkdf.sl:61](../../stdlib/Security/Cryptography/Hkdf.sl#L61)</sub>

#### DeriveKey *method*

```
static Result<byte[], CryptoError> DeriveKey(IHashAlgorithm hash, ReadOnlySpan<byte> inputKey, ReadOnlySpan<byte> salt, ReadOnlySpan<byte> info, nuint length)
```

Extract and expand together, which is how HKDF is nearly always used.

**Parameters**

- `hash` — the HMAC's inner hash
- `inputKey` — the secret that is random but not uniform
- `salt` — a non-secret value, or empty for a block of zeros
- `info` — what separates one derived key from another
- `length` — how many bytes to derive, at most 255 digests' worth

**Fails with**

- [CryptoError.Parameter](#parameter-case) — `length` is zero, or past 255 times the digest size

**See also** &nbsp; [Hkdf.Extract](#extract-method) &middot; [Hkdf.Expand](#expand-method)

<sub>[stdlib/Security/Cryptography/Hkdf.sl:108](../../stdlib/Security/Cryptography/Hkdf.sl#L108)</sub>

### Hmac *class*

```
sealed class Hmac : IHashAlgorithm
```

HMAC over any hash: RFC 2104, and .NET's `HMACSHA256` and its siblings.

A hash is not a MAC. `Sha256.HashData(key + message)` can be extended by
anyone who has the digest and not the key, because the digest *is* the
state; this is the construction that fixes that, and it is what every
protocol means when it says "keyed hash".

Any key length works. A key longer than the hash's block is replaced by its
digest, a shorter one is padded with zeros, and both of those are the
standard's rules rather than a convenience.

<sub>[stdlib/Security/Cryptography/Hmac.sl:39](../../stdlib/Security/Cryptography/Hmac.sl#L39)</sub>

#### Name *property*

```
String Name { get; }
```

*No documentation.*

<sub>[stdlib/Security/Cryptography/Hmac.sl:82](../../stdlib/Security/Cryptography/Hmac.sl#L82)</sub>

#### HashSizeInBytes *property*

```
nuint HashSizeInBytes { get; }
```

*No documentation.*

<sub>[stdlib/Security/Cryptography/Hmac.sl:84](../../stdlib/Security/Cryptography/Hmac.sl#L84)</sub>

#### BlockSizeInBytes *property*

```
nuint BlockSizeInBytes { get; }
```

*No documentation.*

<sub>[stdlib/Security/Cryptography/Hmac.sl:86](../../stdlib/Security/Cryptography/Hmac.sl#L86)</sub>

#### AppendData *method*

```
void AppendData(ReadOnlySpan<byte> data)
```

*No documentation.*

<sub>[stdlib/Security/Cryptography/Hmac.sl:88](../../stdlib/Security/Cryptography/Hmac.sl#L88)</sub>

#### GetHashAndReset *method*

```
byte[] GetHashAndReset()
```

*No documentation.*

<sub>[stdlib/Security/Cryptography/Hmac.sl:90](../../stdlib/Security/Cryptography/Hmac.sl#L90)</sub>

#### Reset *method*

```
void Reset()
```

*No documentation.*

<sub>[stdlib/Security/Cryptography/Hmac.sl:100](../../stdlib/Security/Cryptography/Hmac.sl#L100)</sub>

#### ComputeHash *method*

```
byte[] ComputeHash(ReadOnlySpan<byte> data)
```

The MAC of `data` under `key`, with no object to keep.

<sub>[stdlib/Security/Cryptography/Hmac.sl:107](../../stdlib/Security/Cryptography/Hmac.sl#L107)</sub>

### HmacMd5 *class*

```
class HmacMd5
```

HMAC-MD5, as .NET spells `HMACMD5`. Here for the protocols that specify it
-- and unlike a bare MD5 digest it is not broken by the collision attacks,
because a collision an attacker cannot compute without the key is no use.

<sub>[stdlib/Security/Cryptography/HmacMd5.sl:30](../../stdlib/Security/Cryptography/HmacMd5.sl#L30)</sub>

#### Create *method*

```
static Hmac Create(ReadOnlySpan<byte> key)
```

A keyed hash to append to.

<sub>[stdlib/Security/Cryptography/HmacMd5.sl:33](../../stdlib/Security/Cryptography/HmacMd5.sl#L33)</sub>

#### HashData *method*

```
static byte[] HashData(ReadOnlySpan<byte> key, ReadOnlySpan<byte> data)
```

The MAC of `data` under `key`.

<sub>[stdlib/Security/Cryptography/HmacMd5.sl:36](../../stdlib/Security/Cryptography/HmacMd5.sl#L36)</sub>

### HmacSha1 *class*

```
class HmacSha1
```

HMAC-SHA-1, as .NET spells `HMACSHA1`.

<sub>[stdlib/Security/Cryptography/HmacSha1.sl:28](../../stdlib/Security/Cryptography/HmacSha1.sl#L28)</sub>

#### Create *method*

```
static Hmac Create(ReadOnlySpan<byte> key)
```

A keyed hash to append to.

<sub>[stdlib/Security/Cryptography/HmacSha1.sl:31](../../stdlib/Security/Cryptography/HmacSha1.sl#L31)</sub>

#### HashData *method*

```
static byte[] HashData(ReadOnlySpan<byte> key, ReadOnlySpan<byte> data)
```

The MAC of `data` under `key`.

<sub>[stdlib/Security/Cryptography/HmacSha1.sl:34](../../stdlib/Security/Cryptography/HmacSha1.sl#L34)</sub>

### HmacSha256 *class*

```
class HmacSha256
```

HMAC-SHA-256, as .NET spells `HMACSHA256`. The default for anything new.

<sub>[stdlib/Security/Cryptography/HmacSha256.sl:28](../../stdlib/Security/Cryptography/HmacSha256.sl#L28)</sub>

#### Create *method*

```
static Hmac Create(ReadOnlySpan<byte> key)
```

A keyed hash to append to.

<sub>[stdlib/Security/Cryptography/HmacSha256.sl:31](../../stdlib/Security/Cryptography/HmacSha256.sl#L31)</sub>

#### HashData *method*

```
static byte[] HashData(ReadOnlySpan<byte> key, ReadOnlySpan<byte> data)
```

The MAC of `data` under `key`.

<sub>[stdlib/Security/Cryptography/HmacSha256.sl:34](../../stdlib/Security/Cryptography/HmacSha256.sl#L34)</sub>

### HmacSha384 *class*

```
class HmacSha384
```

HMAC-SHA-384, as .NET spells `HMACSHA384`.

<sub>[stdlib/Security/Cryptography/HmacSha384.sl:28](../../stdlib/Security/Cryptography/HmacSha384.sl#L28)</sub>

#### Create *method*

```
static Hmac Create(ReadOnlySpan<byte> key)
```

A keyed hash to append to.

<sub>[stdlib/Security/Cryptography/HmacSha384.sl:31](../../stdlib/Security/Cryptography/HmacSha384.sl#L31)</sub>

#### HashData *method*

```
static byte[] HashData(ReadOnlySpan<byte> key, ReadOnlySpan<byte> data)
```

The MAC of `data` under `key`.

<sub>[stdlib/Security/Cryptography/HmacSha384.sl:34](../../stdlib/Security/Cryptography/HmacSha384.sl#L34)</sub>

### HmacSha512 *class*

```
class HmacSha512
```

HMAC-SHA-512, as .NET spells `HMACSHA512`.

<sub>[stdlib/Security/Cryptography/HmacSha512.sl:28](../../stdlib/Security/Cryptography/HmacSha512.sl#L28)</sub>

#### Create *method*

```
static Hmac Create(ReadOnlySpan<byte> key)
```

A keyed hash to append to.

<sub>[stdlib/Security/Cryptography/HmacSha512.sl:31](../../stdlib/Security/Cryptography/HmacSha512.sl#L31)</sub>

#### HashData *method*

```
static byte[] HashData(ReadOnlySpan<byte> key, ReadOnlySpan<byte> data)
```

The MAC of `data` under `key`.

<sub>[stdlib/Security/Cryptography/HmacSha512.sl:34](../../stdlib/Security/Cryptography/HmacSha512.sl#L34)</sub>

### IHashAlgorithm *interface*

```
interface IHashAlgorithm
```

A hash function, one block at a time.

This is .NET's `IncrementalHash` rather than its `HashAlgorithm`: append
what there is, and ask for the digest when there is no more. `ComputeHash`
on the base class is the one-shot for the common case, and the static
`HashData` on each algorithm is the same thing without an object.

Implement it to add an algorithm; `Hmac` takes any implementation, so a
hash written outside this module gets a MAC for free.

**See also** &nbsp; [Hmac](#hmac-class)

<sub>[stdlib/Security/Cryptography/IHashAlgorithm.sl:40](../../stdlib/Security/Cryptography/IHashAlgorithm.sl#L40)</sub>

#### Name *property*

```
String Name { get; }
```

What the algorithm is called, as a standard names it -- `SHA-256`,
`HMAC-SHA-256`. This is the spelling that goes in a protocol field,
so it keeps the hyphens and the capitals.

<sub>[stdlib/Security/Cryptography/IHashAlgorithm.sl:45](../../stdlib/Security/Cryptography/IHashAlgorithm.sl#L45)</sub>

#### HashSizeInBytes *property*

```
nuint HashSizeInBytes { get; }
```

How many bytes the digest is.

<sub>[stdlib/Security/Cryptography/IHashAlgorithm.sl:48](../../stdlib/Security/Cryptography/IHashAlgorithm.sl#L48)</sub>

#### BlockSizeInBytes *property*

```
nuint BlockSizeInBytes { get; }
```

How many bytes the compression function eats at a time. HMAC needs it,
which is why it is on the interface rather than inside.

<sub>[stdlib/Security/Cryptography/IHashAlgorithm.sl:52](../../stdlib/Security/Cryptography/IHashAlgorithm.sl#L52)</sub>

#### AppendData *method*

```
void AppendData(ReadOnlySpan<byte> data)
```

Adds bytes to what is being hashed.

<sub>[stdlib/Security/Cryptography/IHashAlgorithm.sl:55](../../stdlib/Security/Cryptography/IHashAlgorithm.sl#L55)</sub>

#### GetHashAndReset *method*

```
byte[] GetHashAndReset()
```

The digest of everything appended since the last reset, and a reset.
Calling it twice in a row gives the digest of the empty input the
second time, which is what the reset means.

<sub>[stdlib/Security/Cryptography/IHashAlgorithm.sl:60](../../stdlib/Security/Cryptography/IHashAlgorithm.sl#L60)</sub>

#### Reset *method*

```
void Reset()
```

Throws away what has been appended and starts again.

<sub>[stdlib/Security/Cryptography/IHashAlgorithm.sl:63](../../stdlib/Security/Cryptography/IHashAlgorithm.sl#L63)</sub>

### Md5 *class*

```
sealed class Md5 : HashAlgorithm
```

MD5, which is **broken** and is here because formats still carry it.

Collisions are cheap and have been since 2004: two inputs with the same
digest can be produced on a laptop in seconds. That makes it unusable for a
signature, a certificate or anything else where an adversary chooses the
input. It remains what an old protocol field, a package manifest and a
legacy database column contain, and refusing to implement it does not make
those go away.

Use `Sha256` for anything new.

**See also** &nbsp; [Sha256](#sha256-class)

<sub>[stdlib/Security/Cryptography/Md5.sl:41](../../stdlib/Security/Cryptography/Md5.sl#L41)</sub>

#### Name *property*

```
String Name { get; }
```

*No documentation.*

<sub>[stdlib/Security/Cryptography/Md5.sl:90](../../stdlib/Security/Cryptography/Md5.sl#L90)</sub>

#### HashSizeInBytes *property*

```
nuint HashSizeInBytes { get; }
```

*No documentation.*

<sub>[stdlib/Security/Cryptography/Md5.sl:92](../../stdlib/Security/Cryptography/Md5.sl#L92)</sub>

#### HashData *method*

```
static byte[] HashData(ReadOnlySpan<byte> data)
```

The digest of `data`, with no object to keep.

<sub>[stdlib/Security/Cryptography/Md5.sl:95](../../stdlib/Security/Cryptography/Md5.sl#L95)</sub>

### PaddingMode *enum*

```
enum PaddingMode
```

What is added to make the plaintext a whole number of blocks.

<sub>[stdlib/Security/Cryptography/PaddingMode.sl:28](../../stdlib/Security/Cryptography/PaddingMode.sl#L28)</sub>

#### None *case*

```
None
```

Nothing. The input must already be a multiple of the block size, and
`CryptoError.BlockLength` says so when it is not.

<sub>[stdlib/Security/Cryptography/PaddingMode.sl:32](../../stdlib/Security/Cryptography/PaddingMode.sl#L32)</sub>

#### Pkcs7 *case*

```
Pkcs7
```

PKCS#7: N bytes of the value N, always at least one block-worth of
information added. The default everywhere, and what .NET uses unless
told otherwise.

<sub>[stdlib/Security/Cryptography/PaddingMode.sl:37](../../stdlib/Security/Cryptography/PaddingMode.sl#L37)</sub>

#### Zeros *case*

```
Zeros
```

Zeros to the block boundary. **Not removable**: a plaintext that ended
in a zero byte is indistinguishable from its padding, so decryption
leaves it in place.

<sub>[stdlib/Security/Cryptography/PaddingMode.sl:42](../../stdlib/Security/Cryptography/PaddingMode.sl#L42)</sub>

#### AnsiX923 *case*

```
AnsiX923
```

ANSI X9.23: zeros, and the last byte is the count.

<sub>[stdlib/Security/Cryptography/PaddingMode.sl:45](../../stdlib/Security/Cryptography/PaddingMode.sl#L45)</sub>

### PemEncoding *class*

```
class PemEncoding
```

The textual encoding of RFC 7468: DER in base64, between two boundary
lines that name what it is.

```csharp
if (PemEncoding.Find(text) is Some found)
{
    var reader = new AsnReader(found.Value.Data, AsnEncodingRules.Der);
    ...
}
String pem = PemEncoding.Write("CERTIFICATE", der);
```

As .NET's `PemEncoding`: a block may sit anywhere in surrounding text, the
base64 may be wrapped at any width and with CRLF or LF, and a block whose
`END` label is not its `BEGIN` label is not a block. `Find` passes over
anything malformed and answers the first block that is whole.

<sub>[stdlib/Security/Cryptography/PemEncoding.sl:43](../../stdlib/Security/Cryptography/PemEncoding.sl#L43)</sub>

#### Find *method*

```
static Optional<PemFields> Find(String text)
```

The first well-formed block in `text`.

**Parameters**

- `text` — where to look

**Returns** &nbsp; the block, or `None` when there is no well-formed one

**See also** &nbsp; [PemEncoding.Write](#write-method)

<sub>[stdlib/Security/Cryptography/PemEncoding.sl:50](../../stdlib/Security/Cryptography/PemEncoding.sl#L50)</sub>

#### Find *method*

```
static Optional<PemFields> Find(String text, nuint start)
```

The first well-formed block in `text` at or after byte `start`, which
is how to walk a file of several: pass the end of the last one's
`Location`.

A `BEGIN` boundary MUST start the text or follow whitespace, and an
`END` boundary MUST end it or be followed by whitespace. Between them is
base64 in the standard alphabet, padded, with whitespace anywhere.

**Parameters**

- `text` — where to look
- `start` — the byte to look from; past the end finds nothing

**Returns** &nbsp; the block, or `None` when there is no well-formed one

<sub>[stdlib/Security/Cryptography/PemEncoding.sl:63](../../stdlib/Security/Cryptography/PemEncoding.sl#L63)</sub>

#### Write *method*

```
static String Write(String label, ReadOnlySpan<byte> data)
```

`data` as a PEM block: the boundaries, and base64 in lines of 64
separated by `\n`. No newline follows the `END` boundary.

**Parameters**

- `label` — what the data is; MUST be valid, which `IsValidLabel` answers, and aborts when it is not
- `data` — the bytes to encode, usually DER

**See also** &nbsp; [PemEncoding.Find](#find-method)

<sub>[stdlib/Security/Cryptography/PemEncoding.sl:129](../../stdlib/Security/Cryptography/PemEncoding.sl#L129)</sub>

#### IsValidLabel *method*

```
static bool IsValidLabel(String label)
```

Whether RFC 7468 allows `label`: printable ASCII other than `-`, with a
single space or hyphen allowed between two such characters. Empty is
allowed.

<sub>[stdlib/Security/Cryptography/PemEncoding.sl:155](../../stdlib/Security/Cryptography/PemEncoding.sl#L155)</sub>

### PemFields *struct*

```
struct PemFields
```

One PEM block that `PemEncoding.Find` found: its label, its data decoded,
and where each part is in the text it was found in.

Every `Range` counts bytes of the text's UTF-8, which for the block itself
is ASCII and so counts characters too.

<sub>[stdlib/Security/Cryptography/PemFields.sl:29](../../stdlib/Security/Cryptography/PemFields.sl#L29)</sub>

#### Label *property*

```
String Label { get; }
```

What follows `BEGIN `: `CERTIFICATE`, `PRIVATE KEY`.

<sub>[stdlib/Security/Cryptography/PemFields.sl:47](../../stdlib/Security/Cryptography/PemFields.sl#L47)</sub>

#### Data *property*

```
byte[] Data { get; }
```

The base64 between the boundaries, decoded.

<sub>[stdlib/Security/Cryptography/PemFields.sl:50](../../stdlib/Security/Cryptography/PemFields.sl#L50)</sub>

#### Location *property*

```
Range Location { get; }
```

The whole block, from the first `-` of `-----BEGIN` to the last of
`-----END ...-----`. Its end is where to look for the next one.

<sub>[stdlib/Security/Cryptography/PemFields.sl:54](../../stdlib/Security/Cryptography/PemFields.sl#L54)</sub>

#### LabelLocation *property*

```
Range LabelLocation { get; }
```

Where the label is, in the `BEGIN` boundary.

<sub>[stdlib/Security/Cryptography/PemFields.sl:57](../../stdlib/Security/Cryptography/PemFields.sl#L57)</sub>

#### Base64Location *property*

```
Range Base64Location { get; }
```

Where the base64 is, from its first character to its last, whitespace
inside it included and around it not.

<sub>[stdlib/Security/Cryptography/PemFields.sl:61](../../stdlib/Security/Cryptography/PemFields.sl#L61)</sub>

### Poly1305 *class*

```
sealed class Poly1305
```

Poly1305, the one-time authenticator of RFC 8439 §2.5: a 32-byte key and a
message give a 16-byte tag.

```csharp
var tag = try Poly1305.ComputeTag(oneTimeKey, message);
```

**A key MUST authenticate one message and no more.** Two tags under one key
give an attacker enough to forge a third. `ChaCha20Poly1305` derives a
fresh key from every nonce, which is how this is meant to be used; a key
from anywhere else has to come with the same guarantee.

The arithmetic is modulo 2^130 - 5 in five 26-bit limbs, so every product
fits a `ulong` and nothing needs a 128-bit multiply. It is constant time:
the final reduction selects with a mask rather than a branch.

**See also** &nbsp; [ChaCha20Poly1305](#chacha20poly1305-class)

<sub>[stdlib/Security/Cryptography/Poly1305.sl:46](../../stdlib/Security/Cryptography/Poly1305.sl#L46)</sub>

#### KeySize *constant*

```
const nuint KeySize = 32
```

**Value** &nbsp; thirty-two bytes: `r`, then `s`.

<sub>[stdlib/Security/Cryptography/Poly1305.sl:49](../../stdlib/Security/Cryptography/Poly1305.sl#L49)</sub>

#### TagSize *constant*

```
const nuint TagSize = 16
```

**Value** &nbsp; sixteen bytes.

<sub>[stdlib/Security/Cryptography/Poly1305.sl:52](../../stdlib/Security/Cryptography/Poly1305.sl#L52)</sub>

#### FromKey *method*

```
static Result<Poly1305, CryptoError> FromKey(ReadOnlySpan<byte> key)
```

An authenticator under `key`, which must be 32 bytes and MUST NOT
have been used before.

**Fails with**

- [CryptoError.KeyLength](#keylength-case) — `key` is not 32 bytes

<sub>[stdlib/Security/Cryptography/Poly1305.sl:89](../../stdlib/Security/Cryptography/Poly1305.sl#L89)</sub>

#### ComputeTag *method*

```
static Result<byte[], CryptoError> ComputeTag(ReadOnlySpan<byte> key, ReadOnlySpan<byte> message)
```

The tag of `message` under `key`, with no object to keep.

**Parameters**

- `key` — thirty-two bytes, used for this message only
- `message` — what to authenticate

**Fails with**

- [CryptoError.KeyLength](#keylength-case) — `key` is not 32 bytes

<sub>[stdlib/Security/Cryptography/Poly1305.sl:101](../../stdlib/Security/Cryptography/Poly1305.sl#L101)</sub>

#### AppendData *method*

```
void AppendData(ReadOnlySpan<byte> data)
```

Adds bytes to what is being authenticated.

<sub>[stdlib/Security/Cryptography/Poly1305.sl:113](../../stdlib/Security/Cryptography/Poly1305.sl#L113)</sub>

#### GetTag *method*

```
byte[] GetTag()
```

The tag of everything appended. **The key is erased**, so the object
MUST NOT be used afterwards: it has done the one thing it may do.

<sub>[stdlib/Security/Cryptography/Poly1305.sl:129](../../stdlib/Security/Cryptography/Poly1305.sl#L129)</sub>

### RandomNumberGenerator *class*

```
class RandomNumberGenerator
```

Random bytes fit to be a key, which `Standard.Random` deliberately is not.

This is the platform's generator -- `BCryptGenRandom` on Windows,
`getrandom` on Linux -- reached through the runtime. `Random` is xoshiro256**
and its whole future is computable from 256 bits of state, which is what
makes a seeded run reproducible and what makes it unfit for a key, a nonce
or a token.

<sub>[stdlib/Security/Cryptography/RandomNumberGenerator.sl:36](../../stdlib/Security/Cryptography/RandomNumberGenerator.sl#L36)</sub>

#### Fill *method*

```
static bool Fill(byte[] buffer)
```

Fills `buffer` with random bytes, and says whether it could.

The failure is a machine with no entropy source at all, which in
practice means a misconfigured container. It is a `bool` rather than a
`Result` because there is exactly one reason and the name says it.

<sub>[stdlib/Security/Cryptography/RandomNumberGenerator.sl:43](../../stdlib/Security/Cryptography/RandomNumberGenerator.sl#L43)</sub>

#### GetBytes *method*

```
static byte[] GetBytes(nuint count)
```

`count` random bytes.

Aborts if the platform will supply none, which is the same judgement
`new Random()` makes: a key that is not random is worse than a program
that stops, and there is no useful value to return instead.

<sub>[stdlib/Security/Cryptography/RandomNumberGenerator.sl:55](../../stdlib/Security/Cryptography/RandomNumberGenerator.sl#L55)</sub>

#### GetInt32 *method*

```
static int GetInt32(int from, int to)
```

A number in `[from, to)`, drawn without the modulo bias that
`GetBytes(4) % range` has.

Aborts on an empty or backwards range, which names a bug rather than an
outcome -- the same judgement `Random.NextBelow` makes.

<sub>[stdlib/Security/Cryptography/RandomNumberGenerator.sl:68](../../stdlib/Security/Cryptography/RandomNumberGenerator.sl#L68)</sub>

### Rfc2898DeriveBytes *class*

```
class Rfc2898DeriveBytes
```

PBKDF2, which .NET calls `Rfc2898DeriveBytes`.

Turns a password into key material by making the derivation deliberately
slow: `iterations` passes of HMAC, so that guessing costs the attacker what
it cost you. The number is the whole security argument, and it has to rise
over the years -- OWASP's 2023 figure is 600,000 for HMAC-SHA-256, and a
count from an old program is a count that has stopped meaning anything.

**This is the weakest of the modern password hashes.** PBKDF2 costs an
attacker with a GPU very much less than it costs a server, because it needs
no memory. `Argon2id` and `Scrypt` exist to close that gap. Use PBKDF2
where a format specifies it, and understand what it does not buy.

<sub>[stdlib/Security/Cryptography/Rfc2898DeriveBytes.sl:41](../../stdlib/Security/Cryptography/Rfc2898DeriveBytes.sl#L41)</sub>

#### Pbkdf2 *method*

```
static Result<byte[], CryptoError> Pbkdf2(ReadOnlySpan<byte> password, ReadOnlySpan<byte> salt, nuint iterations, IHashAlgorithm hash, nuint length)
```

`length` bytes derived from `password` and `salt`.

`hash` is the HMAC's inner hash -- `new Sha256()` is the usual answer.
The salt should be at least sixteen random bytes and is not secret; its
job is to make one attack per password rather than one per database.

**Parameters**

- `password` — the secret to stretch
- `salt` — at least sixteen random bytes, stored beside the result
- `iterations` — how many HMAC passes; the whole security argument
- `hash` — the HMAC's inner hash, `new Sha256()` for the usual answer
- `length` — how many bytes to derive

**Fails with**

- [CryptoError.Parameter](#parameter-case) — `iterations` or `length` is zero

**See also** &nbsp; [Argon2id](#argon2id-class) &middot; [Scrypt](#scrypt-class)

<sub>[stdlib/Security/Cryptography/Rfc2898DeriveBytes.sl:57](../../stdlib/Security/Cryptography/Rfc2898DeriveBytes.sl#L57)</sub>

### Rsa *class*

```
sealed class Rsa
```

An RSA key, public or private: signatures and encryption under RFC 8017,
and the key formats of PKCS #1, PKCS #8 and X.509.

```csharp
var key = try Rsa.Create(2048);
byte[] signature = try key.SignData(message, HashAlgorithmName.Sha256,
                                    RsaSignaturePadding.Pss);

var peer = try Rsa.ImportFromPem(pem);
bool genuine = peer.VerifyData(message, signature, HashAlgorithmName.Sha256,
                               RsaSignaturePadding.Pss);
```

**The shape is .NET's `RSA`**, with two differences that follow from
failing by `Result`. An `Rsa` always holds a key, so what .NET does with
`RSA.Create()` and an `Import` method is a static method here that answers
the key: `Rsa.ImportFromPem(pem)` rather than `rsa.ImportFromPem(pem)`. And
a DER import takes exactly one value, where .NET reports how many bytes it
read and ignores the rest.

**What is constant time.** Every operation on a secret — the private
exponentiation, the reduction of its input modulo each prime, the
recombination, the inverse of the blinding factor, OAEP and PKCS #1 v1.5
decoding after decryption, and the generation of `d` from the primes — runs
in time and touches memory in a pattern fixed by the key's size alone. The
public operations, verifying and encrypting, are not constant time and do
not need to be. Key generation rejects candidates in variable time; see
`Create(int)`.

**The private operation is blinded and checked.** Its input is multiplied
by `r^e` for a fresh random `r`, so the exponentiation never sees a value
the caller chose, and its result is raised to `e` again and compared with
the input before it is used, so a fault in the arithmetic cannot leak a
prime through a wrong signature.

An `Rsa` is not changed by anything after it is made, so one MAY be used
from several threads at once.

<sub>[stdlib/Security/Cryptography/Rsa.sl:67](../../stdlib/Security/Cryptography/Rsa.sl#L67)</sub>

#### KeySize *property*

```
int KeySize { get; }
```

The modulus's size in bits: 2048 for a 2048-bit key.

<sub>[stdlib/Security/Cryptography/Rsa.sl:89](../../stdlib/Security/Cryptography/Rsa.sl#L89)</sub>

#### HasPrivateKey *property*

```
bool HasPrivateKey { get; }
```

Whether this holds the private key as well as the public one.

<sub>[stdlib/Security/Cryptography/Rsa.sl:92](../../stdlib/Security/Cryptography/Rsa.sl#L92)</sub>

#### Create *method*

```
static Result<Rsa, CryptoError> Create(int keySizeInBits)
```

A new key of `keySizeInBits` bits, with public exponent 65537.

FIPS 186-5 §A.1.3: two random probable primes of half the size each,
at least `sqrt(2) * 2^(half - 1)`, at least `2^(half - 100)` apart,
each passing Miller-Rabin with random bases as many times as Table B.1
asks; `d` is `65537^-1 mod lcm(p - 1, q - 1)` and at least `2^half`.

**The time taken is random**, since it is a search: from a few tens to
a few hundred milliseconds for 2048 bits on a current x64, and from
under one second to several for 4096.
A candidate is thrown away as soon as a small prime divides it or a
Miller-Rabin round finds a witness, so the time reveals something
about numbers that are not kept. What is kept is handled in constant
time, `d` included.

**Parameters**

- `keySizeInBits` — a multiple of 64 from 512 to 16384; 2048 or more for anything new

**Fails with**

- [CryptoError.KeyLength](#keylength-case) — `keySizeInBits` is not a size this makes
- [CryptoError.NoEntropy](#noentropy-case) — the platform would not supply randomness

<sub>[stdlib/Security/Cryptography/Rsa.sl:115](../../stdlib/Security/Cryptography/Rsa.sl#L115)</sub>

#### Create *method*

```
static Result<Rsa, CryptoError> Create(RsaParameters parameters)
```

The key `parameters` describes: public when it has only `Modulus` and
`Exponent`, private when it has all eight.

A private key is checked before it is accepted: `p * q` MUST be `n`,
and `d`, `DP`, `DQ` and `InverseQ` MUST agree with `e`, `p` and `q`.
A key that is only nearly right would sign wrongly, and a wrong
signature from a CRT key is enough to factor its modulus.

**Parameters**

- `parameters` — the numbers, big-endian; leading zeros are ignored

**Fails with**

- [CryptoError.InvalidKey](#invalidkey-case) — a number is missing, out of range or inconsistent with the others

**See also** &nbsp; [Rsa.ExportParameters](#exportparameters-method)

<sub>[stdlib/Security/Cryptography/Rsa.sl:143](../../stdlib/Security/Cryptography/Rsa.sl#L143)</sub>

#### ExportParameters *method*

```
Result<RsaParameters, CryptoError> ExportParameters(bool includePrivateParameters)
```

The key's numbers.

`Modulus` and `D` are the modulus's length in bytes, and `P`, `Q`,
`DP`, `DQ` and `InverseQ` half of it rounded up, each with leading
zeros where the number is shorter. `Exponent` has none.

**Parameters**

- `includePrivateParameters` — whether to include the six private numbers

**Fails with**

- [CryptoError.InvalidKey](#invalidkey-case) — the private numbers were asked for, and this is a public key

**See also** &nbsp; [Rsa.Create](#create-method)

<sub>[stdlib/Security/Cryptography/Rsa.sl:314](../../stdlib/Security/Cryptography/Rsa.sl#L314)</sub>

#### ExportRsaPublicKey *method*

```
byte[] ExportRsaPublicKey()
```

The public key as a PKCS #1 `RSAPublicKey` (RFC 8017 §A.1.1), DER.

<sub>[stdlib/Security/Cryptography/Rsa.sl:344](../../stdlib/Security/Cryptography/Rsa.sl#L344)</sub>

#### ExportRsaPrivateKey *method*

```
Result<byte[], CryptoError> ExportRsaPrivateKey()
```

The private key as a PKCS #1 `RSAPrivateKey` (RFC 8017 §A.1.2), DER.

**Fails with**

- [CryptoError.InvalidKey](#invalidkey-case) — this is a public key

<sub>[stdlib/Security/Cryptography/Rsa.sl:354](../../stdlib/Security/Cryptography/Rsa.sl#L354)</sub>

#### ExportSubjectPublicKeyInfo *method*

```
byte[] ExportSubjectPublicKeyInfo()
```

The public key as an X.509 `SubjectPublicKeyInfo` (RFC 5280 §4.1),
DER: what a certificate carries and what `PUBLIC KEY` PEM holds.

<sub>[stdlib/Security/Cryptography/Rsa.sl:366](../../stdlib/Security/Cryptography/Rsa.sl#L366)</sub>

#### ExportPkcs8PrivateKey *method*

```
Result<byte[], CryptoError> ExportPkcs8PrivateKey()
```

The private key as an unencrypted PKCS #8 `PrivateKeyInfo` (RFC 5208),
DER: what `PRIVATE KEY` PEM holds.

**Fails with**

- [CryptoError.InvalidKey](#invalidkey-case) — this is a public key

<sub>[stdlib/Security/Cryptography/Rsa.sl:383](../../stdlib/Security/Cryptography/Rsa.sl#L383)</sub>

#### ImportRsaPublicKey *method*

```
static Result<Rsa, CryptoError> ImportRsaPublicKey(ReadOnlySpan<byte> source)
```

A key from a PKCS #1 `RSAPublicKey`, DER.

**Parameters**

- `source` — exactly one DER value

**Fails with**

- [CryptoError.Encoding](#encoding-case) — `source` is not one `RSAPublicKey`
- [CryptoError.InvalidKey](#invalidkey-case) — the numbers are not an RSA key

<sub>[stdlib/Security/Cryptography/Rsa.sl:407](../../stdlib/Security/Cryptography/Rsa.sl#L407)</sub>

#### ImportRsaPrivateKey *method*

```
static Result<Rsa, CryptoError> ImportRsaPrivateKey(ReadOnlySpan<byte> source)
```

A key from a PKCS #1 `RSAPrivateKey`, DER.

**Parameters**

- `source` — exactly one DER value

**Fails with**

- [CryptoError.Encoding](#encoding-case) — `source` is not one `RSAPrivateKey`
- [CryptoError.Unsupported](#unsupported-case) — a multi-prime key, version 1
- [CryptoError.InvalidKey](#invalidkey-case) — the numbers are not a consistent RSA key

<sub>[stdlib/Security/Cryptography/Rsa.sl:422](../../stdlib/Security/Cryptography/Rsa.sl#L422)</sub>

#### ImportSubjectPublicKeyInfo *method*

```
static Result<Rsa, CryptoError> ImportSubjectPublicKeyInfo(ReadOnlySpan<byte> source)
```

A key from an X.509 `SubjectPublicKeyInfo`, DER.

**Parameters**

- `source` — exactly one DER value

**Fails with**

- [CryptoError.Encoding](#encoding-case) — `source` is not one `SubjectPublicKeyInfo` holding an RSA key
- [CryptoError.InvalidKey](#invalidkey-case) — the numbers are not an RSA key

<sub>[stdlib/Security/Cryptography/Rsa.sl:437](../../stdlib/Security/Cryptography/Rsa.sl#L437)</sub>

#### ImportPkcs8PrivateKey *method*

```
static Result<Rsa, CryptoError> ImportPkcs8PrivateKey(ReadOnlySpan<byte> source)
```

A key from an unencrypted PKCS #8 `PrivateKeyInfo` or
`OneAsymmetricKey`, DER. Attributes and an embedded public key are
passed over.

**Parameters**

- `source` — exactly one DER value

**Fails with**

- [CryptoError.Encoding](#encoding-case) — `source` is not one `PrivateKeyInfo` holding an RSA key
- [CryptoError.InvalidKey](#invalidkey-case) — the numbers are not a consistent RSA key

<sub>[stdlib/Security/Cryptography/Rsa.sl:461](../../stdlib/Security/Cryptography/Rsa.sl#L461)</sub>

#### ExportRsaPublicKeyPem *method*

```
String ExportRsaPublicKeyPem()
```

The public key as PKCS #1 in PEM: `-----BEGIN RSA PUBLIC KEY-----`.

<sub>[stdlib/Security/Cryptography/Rsa.sl:607](../../stdlib/Security/Cryptography/Rsa.sl#L607)</sub>

#### ExportRsaPrivateKeyPem *method*

```
Result<String, CryptoError> ExportRsaPrivateKeyPem()
```

The private key as PKCS #1 in PEM: `-----BEGIN RSA PRIVATE KEY-----`.

**Fails with**

- [CryptoError.InvalidKey](#invalidkey-case) — this is a public key

<sub>[stdlib/Security/Cryptography/Rsa.sl:613](../../stdlib/Security/Cryptography/Rsa.sl#L613)</sub>

#### ExportSubjectPublicKeyInfoPem *method*

```
String ExportSubjectPublicKeyInfoPem()
```

The public key as X.509 in PEM: `-----BEGIN PUBLIC KEY-----`.

<sub>[stdlib/Security/Cryptography/Rsa.sl:622](../../stdlib/Security/Cryptography/Rsa.sl#L622)</sub>

#### ExportPkcs8PrivateKeyPem *method*

```
Result<String, CryptoError> ExportPkcs8PrivateKeyPem()
```

The private key as PKCS #8 in PEM: `-----BEGIN PRIVATE KEY-----`.

**Fails with**

- [CryptoError.InvalidKey](#invalidkey-case) — this is a public key

<sub>[stdlib/Security/Cryptography/Rsa.sl:628](../../stdlib/Security/Cryptography/Rsa.sl#L628)</sub>

#### ImportFromPem *method*

```
static Result<Rsa, CryptoError> ImportFromPem(String input)
```

The one RSA key in `input`, which may hold other text and PEM blocks
of other kinds: `RSA PUBLIC KEY`, `RSA PRIVATE KEY`, `PUBLIC KEY` or
`PRIVATE KEY`, as .NET's `ImportFromPem` reads.

**Parameters**

- `input` — text holding exactly one key block

**Fails with**

- [CryptoError.Encoding](#encoding-case) — no key block, more than one, or one that does not parse
- [CryptoError.Unsupported](#unsupported-case) — the block is an `ENCRYPTED PRIVATE KEY`
- [CryptoError.InvalidKey](#invalidkey-case) — the numbers are not a consistent RSA key

<sub>[stdlib/Security/Cryptography/Rsa.sl:645](../../stdlib/Security/Cryptography/Rsa.sl#L645)</sub>

#### SignData *method*

```
Result<byte[], CryptoError> SignData(ReadOnlySpan<byte> data, HashAlgorithmName hashAlgorithm, RsaSignaturePadding padding)
```

The signature of `data`'s hash.

**Parameters**

- `data` — what to sign; it is hashed here
- `hashAlgorithm` — the hash, which the verifier MUST use too
- `padding` — PKCS #1 v1.5, or PSS with its salt length

**Fails with**

- [CryptoError.InvalidKey](#invalidkey-case) — this is a public key
- [CryptoError.Unsupported](#unsupported-case) — the hash is not one this module has
- [CryptoError.MessageLength](#messagelength-case) — the key is too small for the hash and padding
- [CryptoError.NoEntropy](#noentropy-case) — the platform would not supply randomness

**See also** &nbsp; [Rsa.VerifyData](#verifydata-method)

<sub>[stdlib/Security/Cryptography/Rsa.sl:742](../../stdlib/Security/Cryptography/Rsa.sl#L742)</sub>

#### SignHash *method*

```
Result<byte[], CryptoError> SignHash(ReadOnlySpan<byte> hash, HashAlgorithmName hashAlgorithm, RsaSignaturePadding padding)
```

The signature of a hash already computed.

**Parameters**

- `hash` — the digest, exactly as long as `hashAlgorithm`'s
- `hashAlgorithm` — the hash that made it
- `padding` — PKCS #1 v1.5, or PSS with its salt length

**Fails with**

- [CryptoError.Parameter](#parameter-case) — `hash` is not the digest's length
- [CryptoError.InvalidKey](#invalidkey-case) — this is a public key
- [CryptoError.Unsupported](#unsupported-case) — the hash is not one this module has
- [CryptoError.MessageLength](#messagelength-case) — the key is too small for the hash and padding
- [CryptoError.NoEntropy](#noentropy-case) — the platform would not supply randomness

**See also** &nbsp; [Rsa.VerifyHash](#verifyhash-method)

<sub>[stdlib/Security/Cryptography/Rsa.sl:762](../../stdlib/Security/Cryptography/Rsa.sl#L762)</sub>

#### VerifyData *method*

```
bool VerifyData(ReadOnlySpan<byte> data, ReadOnlySpan<byte> signature, HashAlgorithmName hashAlgorithm, RsaSignaturePadding padding)
```

Whether `signature` is this key's signature of `data`'s hash.

**Never fails**: a signature that is malformed, the wrong length or
for another message is simply not valid, and an unknown hash is false.

**Parameters**

- `data` — what was signed
- `signature` — the signature, as long as the modulus
- `hashAlgorithm` — the hash the signer used
- `padding` — the encoding the signer used

**See also** &nbsp; [Rsa.SignData](#signdata-method)

<sub>[stdlib/Security/Cryptography/Rsa.sl:796](../../stdlib/Security/Cryptography/Rsa.sl#L796)</sub>

#### VerifyHash *method*

```
bool VerifyHash(ReadOnlySpan<byte> hash, ReadOnlySpan<byte> signature, HashAlgorithmName hashAlgorithm, RsaSignaturePadding padding)
```

Whether `signature` is this key's signature of a hash already
computed. Never fails, as `VerifyData` does not.

**Parameters**

- `hash` — the digest
- `signature` — the signature, as long as the modulus
- `hashAlgorithm` — the hash that made the digest
- `padding` — the encoding the signer used

<sub>[stdlib/Security/Cryptography/Rsa.sl:814](../../stdlib/Security/Cryptography/Rsa.sl#L814)</sub>

#### Encrypt *method*

```
Result<byte[], CryptoError> Encrypt(ReadOnlySpan<byte> data, RsaEncryptionPadding padding)
```

`data` encrypted to this key.

**Parameters**

- `data` — at most the modulus's length less 11 bytes under PKCS #1 v1.5, or less twice the digest and 2 under OAEP
- `padding` — OAEP with its hash and label, or PKCS #1 v1.5

**Fails with**

- [CryptoError.MessageLength](#messagelength-case) — `data` is too long for the key and padding
- [CryptoError.Unsupported](#unsupported-case) — OAEP's hash is not one this module has
- [CryptoError.NoEntropy](#noentropy-case) — the platform would not supply randomness

**See also** &nbsp; [Rsa.Decrypt](#decrypt-method)

<sub>[stdlib/Security/Cryptography/Rsa.sl:1005](../../stdlib/Security/Cryptography/Rsa.sl#L1005)</sub>

#### Decrypt *method*

```
Result<byte[], CryptoError> Decrypt(ReadOnlySpan<byte> data, RsaEncryptionPadding padding)
```

`data` decrypted with this key.

**OAEP** decodes in constant time and fails with one error however the
encoding is wrong, so the failure says nothing about the plaintext.

**PKCS #1 v1.5 never fails on bad padding.** It uses implicit rejection
(draft-irtf-cfrg-rsa-guidance, as OpenSSL 3.2 does): a ciphertext whose
padding is wrong decrypts to a random-looking message derived from the
ciphertext and the key, the same every time, in the same time as a
valid one. That is what closes Bleichenbacher's oracle; the caller MUST
treat what comes back as untrusted and check it by other means.

**Parameters**

- `data` — the ciphertext, exactly as long as the modulus
- `padding` — what it was encrypted with

**Fails with**

- [CryptoError.InvalidKey](#invalidkey-case) — this is a public key
- [CryptoError.MessageLength](#messagelength-case) — `data` is not the modulus's length, or not below it
- [CryptoError.Padding](#padding-case) — OAEP only: the ciphertext is not a valid encoding under this key and label
- [CryptoError.Unsupported](#unsupported-case) — OAEP's hash is not one this module has
- [CryptoError.NoEntropy](#noentropy-case) — the platform would not supply randomness

**See also** &nbsp; [Rsa.Encrypt](#encrypt-method)

<sub>[stdlib/Security/Cryptography/Rsa.sl:1090](../../stdlib/Security/Cryptography/Rsa.sl#L1090)</sub>

### RsaEncryptionPadding *struct*

```
struct RsaEncryptionPadding
```

How an RSA ciphertext is encoded: OAEP with a hash and a label, or
PKCS #1 v1.5.

.NET's `RSAEncryptionPadding`, as a value. OAEP masks with MGF1 over the
same hash that digests the label, which is the only combination .NET
offers.

**See also** &nbsp; [Rsa.Encrypt](#encrypt-method)

<sub>[stdlib/Security/Cryptography/RsaEncryptionPadding.sl:32](../../stdlib/Security/Cryptography/RsaEncryptionPadding.sl#L32)</sub>

#### Pkcs1 *property*

```
static RsaEncryptionPadding Pkcs1 { get; }
```

PKCS #1 v1.5.

<sub>[stdlib/Security/Cryptography/RsaEncryptionPadding.sl:46](../../stdlib/Security/Cryptography/RsaEncryptionPadding.sl#L46)</sub>

#### OaepSha1 *property*

```
static RsaEncryptionPadding OaepSha1 { get; }
```

OAEP over SHA-1, which is still sound here: OAEP needs the hash to be
one-way, not collision-resistant.

<sub>[stdlib/Security/Cryptography/RsaEncryptionPadding.sl:52](../../stdlib/Security/Cryptography/RsaEncryptionPadding.sl#L52)</sub>

#### OaepSha256 *property*

```
static RsaEncryptionPadding OaepSha256 { get; }
```

OAEP over SHA-256.

<sub>[stdlib/Security/Cryptography/RsaEncryptionPadding.sl:55](../../stdlib/Security/Cryptography/RsaEncryptionPadding.sl#L55)</sub>

#### OaepSha384 *property*

```
static RsaEncryptionPadding OaepSha384 { get; }
```

OAEP over SHA-384.

<sub>[stdlib/Security/Cryptography/RsaEncryptionPadding.sl:58](../../stdlib/Security/Cryptography/RsaEncryptionPadding.sl#L58)</sub>

#### OaepSha512 *property*

```
static RsaEncryptionPadding OaepSha512 { get; }
```

OAEP over SHA-512.

<sub>[stdlib/Security/Cryptography/RsaEncryptionPadding.sl:61](../../stdlib/Security/Cryptography/RsaEncryptionPadding.sl#L61)</sub>

#### Mode *property*

```
RsaEncryptionPaddingMode Mode { get; }
```

Which encoding.

<sub>[stdlib/Security/Cryptography/RsaEncryptionPadding.sl:64](../../stdlib/Security/Cryptography/RsaEncryptionPadding.sl#L64)</sub>

#### OaepHashAlgorithm *property*

```
HashAlgorithmName OaepHashAlgorithm { get; }
```

The hash OAEP uses for the label and for MGF1. An empty name for
PKCS #1 v1.5.

<sub>[stdlib/Security/Cryptography/RsaEncryptionPadding.sl:68](../../stdlib/Security/Cryptography/RsaEncryptionPadding.sl#L68)</sub>

#### OaepLabel *property*

```
byte[] OaepLabel { get; }
```

The OAEP label, empty unless one was given.

<sub>[stdlib/Security/Cryptography/RsaEncryptionPadding.sl:71](../../stdlib/Security/Cryptography/RsaEncryptionPadding.sl#L71)</sub>

#### CreateOaep *method*

```
static RsaEncryptionPadding CreateOaep(HashAlgorithmName hashAlgorithm)
```

OAEP over `hashAlgorithm`, with an empty label.

<sub>[stdlib/Security/Cryptography/RsaEncryptionPadding.sl:74](../../stdlib/Security/Cryptography/RsaEncryptionPadding.sl#L74)</sub>

#### CreateOaep *method*

```
static RsaEncryptionPadding CreateOaep(HashAlgorithmName hashAlgorithm, ReadOnlySpan<byte> label)
```

OAEP over `hashAlgorithm`, bound to `label`: a ciphertext decrypts only
under the label it was made with. The label is not secret and is not
carried in the ciphertext.

**Parameters**

- `hashAlgorithm` — the hash for the label and for MGF1
- `label` — any bytes, copied

<sub>[stdlib/Security/Cryptography/RsaEncryptionPadding.sl:83](../../stdlib/Security/Cryptography/RsaEncryptionPadding.sl#L83)</sub>

### RsaEncryptionPaddingMode *enum*

```
enum RsaEncryptionPaddingMode
```

Which of RFC 8017's two encryption encodings an RSA ciphertext uses.

<sub>[stdlib/Security/Cryptography/RsaEncryptionPaddingMode.sl:25](../../stdlib/Security/Cryptography/RsaEncryptionPaddingMode.sl#L25)</sub>

#### Pkcs1 *case*

```
Pkcs1
```

RSAES-PKCS1-v1_5 (RFC 8017 §7.2), for talking to what cannot do
better. Its decryption is Bleichenbacher's oracle unless handled with
care; see `Rsa.Decrypt` for how it is here.

<sub>[stdlib/Security/Cryptography/RsaEncryptionPaddingMode.sl:30](../../stdlib/Security/Cryptography/RsaEncryptionPaddingMode.sl#L30)</sub>

#### Oaep *case*

```
Oaep
```

RSAES-OAEP (RFC 8017 §7.1), the one to choose.

<sub>[stdlib/Security/Cryptography/RsaEncryptionPaddingMode.sl:33](../../stdlib/Security/Cryptography/RsaEncryptionPaddingMode.sl#L33)</sub>

### RsaParameters *class*

```
sealed class RsaParameters
```

The numbers of an RSA key, each big-endian and unsigned.

```csharp
var key = try Rsa.Create(new RsaParameters { Modulus = n, Exponent = e });
```

.NET's `RSAParameters`. A public key has `Modulus` and `Exponent` and
nothing else; a private key has all eight. A number that is absent is an
empty array, which is what every field starts as.

**A class, where .NET's is a struct.** A struct's zero value would hold
null arrays, and an array here cannot be asked whether it is null; a class
gives every field an empty array to start from.

`Rsa.ExportParameters` gives `D` as many bytes as `Modulus` and the five
CRT values half as many, rounded up, with leading zeros where a value is
shorter, as .NET does; `Rsa.Create` takes any length and ignores leading
zeros.

**See also** &nbsp; [Rsa.Create](#create-method) &middot; [Rsa.ExportParameters](#exportparameters-method)

<sub>[stdlib/Security/Cryptography/RsaParameters.sl:45](../../stdlib/Security/Cryptography/RsaParameters.sl#L45)</sub>

#### Modulus *field*

```
byte[] Modulus
```

`n`.

<sub>[stdlib/Security/Cryptography/RsaParameters.sl:48](../../stdlib/Security/Cryptography/RsaParameters.sl#L48)</sub>

#### Exponent *field*

```
byte[] Exponent
```

`e`, the public exponent.

<sub>[stdlib/Security/Cryptography/RsaParameters.sl:51](../../stdlib/Security/Cryptography/RsaParameters.sl#L51)</sub>

#### D *field*

```
byte[] D
```

`d`, the private exponent.

<sub>[stdlib/Security/Cryptography/RsaParameters.sl:54](../../stdlib/Security/Cryptography/RsaParameters.sl#L54)</sub>

#### P *field*

```
byte[] P
```

`p`, the first prime.

<sub>[stdlib/Security/Cryptography/RsaParameters.sl:57](../../stdlib/Security/Cryptography/RsaParameters.sl#L57)</sub>

#### Q *field*

```
byte[] Q
```

`q`, the second prime.

<sub>[stdlib/Security/Cryptography/RsaParameters.sl:60](../../stdlib/Security/Cryptography/RsaParameters.sl#L60)</sub>

#### DP *field*

```
byte[] DP
```

`d mod (p - 1)`.

<sub>[stdlib/Security/Cryptography/RsaParameters.sl:63](../../stdlib/Security/Cryptography/RsaParameters.sl#L63)</sub>

#### DQ *field*

```
byte[] DQ
```

`d mod (q - 1)`.

<sub>[stdlib/Security/Cryptography/RsaParameters.sl:66](../../stdlib/Security/Cryptography/RsaParameters.sl#L66)</sub>

#### InverseQ *field*

```
byte[] InverseQ
```

`q^-1 mod p`.

<sub>[stdlib/Security/Cryptography/RsaParameters.sl:69](../../stdlib/Security/Cryptography/RsaParameters.sl#L69)</sub>

### RsaSignaturePadding *struct*

```
struct RsaSignaturePadding
```

How an RSA signature is encoded: PKCS #1 v1.5, or PSS with a salt length.

.NET's `RSASignaturePadding`, as a value. PSS masks with MGF1 over the same
hash that digests the message, which is the only combination .NET offers
and the one every protocol uses.

**See also** &nbsp; [Rsa.SignData](#signdata-method)

<sub>[stdlib/Security/Cryptography/RsaSignaturePadding.sl:31](../../stdlib/Security/Cryptography/RsaSignaturePadding.sl#L31)</sub>

#### PssSaltLengthIsHashLength *constant*

```
const int PssSaltLengthIsHashLength = -1
```

A salt as long as the hash's digest, which is what `Pss` uses.

<sub>[stdlib/Security/Cryptography/RsaSignaturePadding.sl:34](../../stdlib/Security/Cryptography/RsaSignaturePadding.sl#L34)</sub>

#### PssSaltLengthMax *constant*

```
const int PssSaltLengthMax = -2
```

The longest salt the key leaves room for. Verifying under it accepts
a salt of any length.

<sub>[stdlib/Security/Cryptography/RsaSignaturePadding.sl:38](../../stdlib/Security/Cryptography/RsaSignaturePadding.sl#L38)</sub>

#### Pkcs1 *property*

```
static RsaSignaturePadding Pkcs1 { get; }
```

PKCS #1 v1.5.

<sub>[stdlib/Security/Cryptography/RsaSignaturePadding.sl:50](../../stdlib/Security/Cryptography/RsaSignaturePadding.sl#L50)</sub>

#### Pss *property*

```
static RsaSignaturePadding Pss { get; }
```

PSS with a salt as long as the digest: RFC 8017's recommendation.

<sub>[stdlib/Security/Cryptography/RsaSignaturePadding.sl:54](../../stdlib/Security/Cryptography/RsaSignaturePadding.sl#L54)</sub>

#### Mode *property*

```
RsaSignaturePaddingMode Mode { get; }
```

Which encoding.

<sub>[stdlib/Security/Cryptography/RsaSignaturePadding.sl:58](../../stdlib/Security/Cryptography/RsaSignaturePadding.sl#L58)</sub>

#### PssSaltLength *property*

```
int PssSaltLength { get; }
```

The PSS salt's length in bytes, or one of the two constants. Zero for
PKCS #1 v1.5.

<sub>[stdlib/Security/Cryptography/RsaSignaturePadding.sl:62](../../stdlib/Security/Cryptography/RsaSignaturePadding.sl#L62)</sub>

#### CreatePss *method*

```
static Result<RsaSignaturePadding, CryptoError> CreatePss(int saltLength)
```

PSS with a salt of `saltLength` bytes.

**Parameters**

- `saltLength` — bytes of salt, or `PssSaltLengthIsHashLength`, or `PssSaltLengthMax`

**Fails with**

- [CryptoError.Parameter](#parameter-case) — `saltLength` is negative and neither constant

<sub>[stdlib/Security/Cryptography/RsaSignaturePadding.sl:69](../../stdlib/Security/Cryptography/RsaSignaturePadding.sl#L69)</sub>

#### Equals *method*

```
bool Equals(RsaSignaturePadding other)
```

*No documentation.*

<sub>[stdlib/Security/Cryptography/RsaSignaturePadding.sl:76](../../stdlib/Security/Cryptography/RsaSignaturePadding.sl#L76)</sub>

#### operator == *operator*

```
static bool operator ==(RsaSignaturePadding left, RsaSignaturePadding right)
```

*No documentation.*

<sub>[stdlib/Security/Cryptography/RsaSignaturePadding.sl:79](../../stdlib/Security/Cryptography/RsaSignaturePadding.sl#L79)</sub>

#### operator != *operator*

```
static bool operator !=(RsaSignaturePadding left, RsaSignaturePadding right)
```

*No documentation.*

<sub>[stdlib/Security/Cryptography/RsaSignaturePadding.sl:82](../../stdlib/Security/Cryptography/RsaSignaturePadding.sl#L82)</sub>

### RsaSignaturePaddingMode *enum*

```
enum RsaSignaturePaddingMode
```

Which of RFC 8017's two signature encodings an RSA signature uses.

<sub>[stdlib/Security/Cryptography/RsaSignaturePaddingMode.sl:25](../../stdlib/Security/Cryptography/RsaSignaturePaddingMode.sl#L25)</sub>

#### Pkcs1 *case*

```
Pkcs1
```

RSASSA-PKCS1-v1_5 (RFC 8017 §8.2): deterministic, and what most
certificates carry.

<sub>[stdlib/Security/Cryptography/RsaSignaturePaddingMode.sl:29](../../stdlib/Security/Cryptography/RsaSignaturePaddingMode.sl#L29)</sub>

#### Pss *case*

```
Pss
```

RSASSA-PSS (RFC 8017 §8.1): randomized, with a security proof, and
the one to choose where nothing else decides.

<sub>[stdlib/Security/Cryptography/RsaSignaturePaddingMode.sl:33](../../stdlib/Security/Cryptography/RsaSignaturePaddingMode.sl#L33)</sub>

### Scrypt *class*

```
class Scrypt
```

scrypt (RFC 7914): a password hash that costs memory as well as time.

```csharp
var key = try Scrypt.DeriveKey(password, salt, 32768u, 8u, 1u, 32u);
```

**Memory is the point.** PBKDF2 is a loop an attacker runs on a thousand
GPU cores at once. scrypt fills 128 · `blockSize` · `cost` bytes and reads
them back in an order it cannot predict, so each guess needs that memory
for its whole duration, and memory is what a GPU has least of per core.
`cost` = 2^15 with `blockSize` = 8 is 32 MiB, which is the usual interactive
answer. Raise `cost` rather than `parallelism`: the passes run one after
another here, so `parallelism` buys time and no memory.

**The second pass reads memory at addresses derived from the password.**
That is what makes it memory-hard, and it is also a cache-timing channel:
an attacker who shares the machine and can watch the cache learns
something about the password. It is inherent in scrypt. `Argon2id`
spends its first half on addresses that do not depend on the password,
which is why RFC 9106 prefers it.

Built on `Rfc2898DeriveBytes.Pbkdf2` over HMAC-SHA-256 and the Salsa20/8
core, as the RFC defines it.

**See also** &nbsp; [Argon2id](#argon2id-class) &middot; [Rfc2898DeriveBytes](#rfc2898derivebytes-class)

<sub>[stdlib/Security/Cryptography/Scrypt.sl:55](../../stdlib/Security/Cryptography/Scrypt.sl#L55)</sub>

#### MaxMemoryBytes *constant*

```
const ulong MaxMemoryBytes = 4294967296
```

The most working memory a derivation may ask for: 4 GiB, which is
`cost` = 2^22 at `blockSize` = 8. Parameters read from a stored hash
are input like any other, and this bounds what one can make a call
allocate.

**Value** &nbsp; 2^32 bytes.

<sub>[stdlib/Security/Cryptography/Scrypt.sl:63](../../stdlib/Security/Cryptography/Scrypt.sl#L63)</sub>

#### DeriveKey *method*

```
static Result<byte[], CryptoError> DeriveKey(ReadOnlySpan<byte> password, ReadOnlySpan<byte> salt, nuint cost, nuint blockSize, nuint parallelism, nuint length)
```

`length` bytes derived from `password` and `salt`.

**Parameters**

- `password` — the secret to stretch
- `salt` — at least sixteen random bytes, stored beside the result
- `cost` — N, the number of blocks the memory holds; a power of two greater than one
- `blockSize` — r, the width of a block in 128-byte units; 8 is the usual answer
- `parallelism` — p, how many independent passes to run, one after another here
- `length` — how many bytes to derive

**Fails with**

- [CryptoError.Parameter](#parameter-case) — `cost` is not a power of two above one; `blockSize`, `parallelism` or `length` is zero; `blockSize` times `parallelism` reaches 2^30; `cost` reaches 2^(16 · `blockSize`); `length` is past (2^32 - 1) · 32; or the memory needed is past `MaxMemoryBytes`

<sub>[stdlib/Security/Cryptography/Scrypt.sl:79](../../stdlib/Security/Cryptography/Scrypt.sl#L79)</sub>

### Sha1 *class*

```
sealed class Sha1 : HashAlgorithm
```

SHA-1, which is **broken for collisions** and still required by some
protocols.

SHAttered produced two PDFs with the same digest in 2017 and the cost has
only fallen since. It is not safe for a signature or a certificate. It is
still what Git names an object with, what HMAC-SHA-1 inside TOTP and
PBKDF2 uses -- where the collision resistance is not what is relied on --
and what a dozen older protocols specify.

<sub>[stdlib/Security/Cryptography/Sha1.sl:37](../../stdlib/Security/Cryptography/Sha1.sl#L37)</sub>

#### Name *property*

```
String Name { get; }
```

*No documentation.*

<sub>[stdlib/Security/Cryptography/Sha1.sl:48](../../stdlib/Security/Cryptography/Sha1.sl#L48)</sub>

#### HashSizeInBytes *property*

```
nuint HashSizeInBytes { get; }
```

*No documentation.*

<sub>[stdlib/Security/Cryptography/Sha1.sl:50](../../stdlib/Security/Cryptography/Sha1.sl#L50)</sub>

#### HashData *method*

```
static byte[] HashData(ReadOnlySpan<byte> data)
```

The digest of `data`, with no object to keep.

<sub>[stdlib/Security/Cryptography/Sha1.sl:53](../../stdlib/Security/Cryptography/Sha1.sl#L53)</sub>

### Sha256 *class*

```
sealed class Sha256 : HashAlgorithm
```

SHA-256: the one to reach for when nothing else decides.

<sub>[stdlib/Security/Cryptography/Sha256.sl:30](../../stdlib/Security/Cryptography/Sha256.sl#L30)</sub>

#### Name *property*

```
String Name { get; }
```

*No documentation.*

<sub>[stdlib/Security/Cryptography/Sha256.sl:62](../../stdlib/Security/Cryptography/Sha256.sl#L62)</sub>

#### HashSizeInBytes *property*

```
nuint HashSizeInBytes { get; }
```

*No documentation.*

<sub>[stdlib/Security/Cryptography/Sha256.sl:64](../../stdlib/Security/Cryptography/Sha256.sl#L64)</sub>

#### HashData *method*

```
static byte[] HashData(ReadOnlySpan<byte> data)
```

The digest of `data`, with no object to keep.

<sub>[stdlib/Security/Cryptography/Sha256.sl:67](../../stdlib/Security/Cryptography/Sha256.sl#L67)</sub>

### Sha2Wide *class*

```
abstract class Sha2Wide : HashAlgorithm
```

The 64-bit half of SHA-2, which SHA-384 and SHA-512 share entirely except
for where they start and how much of the answer they keep.

Public because a public class cannot usefully hide its base, and documented
as machinery: there is nothing here to construct. `Sha384` and `Sha512` are
the two that exist.

<sub>[stdlib/Security/Cryptography/Sha2Wide.sl:35](../../stdlib/Security/Cryptography/Sha2Wide.sl#L35)</sub>

### Sha384 *class*

```
sealed class Sha384 : Sha2Wide
```

SHA-384: SHA-512 from a different start, with half the answer thrown away.

The truncation is what makes it worth having rather than a curiosity --
a SHA-512 digest reveals the whole final state, and a SHA-384 one does
not, so length-extension does not apply to it.

<sub>[stdlib/Security/Cryptography/Sha384.sl:32](../../stdlib/Security/Cryptography/Sha384.sl#L32)</sub>

#### Name *property*

```
String Name { get; }
```

*No documentation.*

<sub>[stdlib/Security/Cryptography/Sha384.sl:40](../../stdlib/Security/Cryptography/Sha384.sl#L40)</sub>

#### HashSizeInBytes *property*

```
nuint HashSizeInBytes { get; }
```

*No documentation.*

<sub>[stdlib/Security/Cryptography/Sha384.sl:42](../../stdlib/Security/Cryptography/Sha384.sl#L42)</sub>

#### HashData *method*

```
static byte[] HashData(ReadOnlySpan<byte> data)
```

The digest of `data`, with no object to keep.

<sub>[stdlib/Security/Cryptography/Sha384.sl:45](../../stdlib/Security/Cryptography/Sha384.sl#L45)</sub>

### Sha512 *class*

```
sealed class Sha512 : Sha2Wide
```

SHA-512: the 64-bit member of the family, and faster than SHA-256 on a
64-bit machine for the same reason it is wider.

<sub>[stdlib/Security/Cryptography/Sha512.sl:29](../../stdlib/Security/Cryptography/Sha512.sl#L29)</sub>

#### Name *property*

```
String Name { get; }
```

*No documentation.*

<sub>[stdlib/Security/Cryptography/Sha512.sl:37](../../stdlib/Security/Cryptography/Sha512.sl#L37)</sub>

#### HashSizeInBytes *property*

```
nuint HashSizeInBytes { get; }
```

*No documentation.*

<sub>[stdlib/Security/Cryptography/Sha512.sl:39](../../stdlib/Security/Cryptography/Sha512.sl#L39)</sub>

#### HashData *method*

```
static byte[] HashData(ReadOnlySpan<byte> data)
```

The digest of `data`, with no object to keep.

<sub>[stdlib/Security/Cryptography/Sha512.sl:42](../../stdlib/Security/Cryptography/Sha512.sl#L42)</sub>

### X25519 *class*

```
class X25519
```

X25519 (RFC 7748): Diffie-Hellman over Curve25519, which is what TLS 1.3,
SSH, WireGuard and Signal agree keys with.

```csharp
byte[] mine = X25519.GeneratePrivateKey();
byte[] shared = try X25519.DeriveSharedSecret(mine, theirPublicKey);
byte[] key = try Hkdf.DeriveKey(new Sha256(), shared, salt, info, 32u);
```

Every key is 32 bytes, and so is the shared secret. **The shared secret is
not a key.** It is a point on a curve, not uniformly random bytes, and it
MUST go through a key derivation such as `Hkdf` before it keys anything.

.NET has no X25519; `ECDiffieHellman` there is over the NIST curves. The
shape here is the RFC's: a private key is any 32 bytes, clamped as it is
used, and a public key is the u-coordinate of a point.

**Constant time.** The Montgomery ladder runs 255 steps whatever the key,
and each step's swap is a mask rather than a branch. The only test on the
result is the all-zero check, and what it reveals the failure reveals
anyway.

<sub>[stdlib/Security/Cryptography/X25519.sl:49](../../stdlib/Security/Cryptography/X25519.sl#L49)</sub>

#### PrivateKeySize *constant*

```
const nuint PrivateKeySize = 32
```

The length of a private key.

**Value** &nbsp; thirty-two bytes.

<sub>[stdlib/Security/Cryptography/X25519.sl:54](../../stdlib/Security/Cryptography/X25519.sl#L54)</sub>

#### PublicKeySize *constant*

```
const nuint PublicKeySize = 32
```

The length of a public key.

**Value** &nbsp; thirty-two bytes.

<sub>[stdlib/Security/Cryptography/X25519.sl:59](../../stdlib/Security/Cryptography/X25519.sl#L59)</sub>

#### SharedSecretSize *constant*

```
const nuint SharedSecretSize = 32
```

The length of a shared secret.

**Value** &nbsp; thirty-two bytes.

<sub>[stdlib/Security/Cryptography/X25519.sl:64](../../stdlib/Security/Cryptography/X25519.sl#L64)</sub>

#### GeneratePrivateKey *method*

```
static byte[] GeneratePrivateKey()
```

A new private key: 32 bytes from `RandomNumberGenerator`.

Aborts if the platform supplies no entropy, as
`RandomNumberGenerator.GetBytes` does.

<sub>[stdlib/Security/Cryptography/X25519.sl:70](../../stdlib/Security/Cryptography/X25519.sl#L70)</sub>

#### GetPublicKey *method*

```
static Result<byte[], CryptoError> GetPublicKey(ReadOnlySpan<byte> privateKey)
```

The public key that goes with `privateKey`: the private key times the
base point, whose u-coordinate is 9.

**Parameters**

- `privateKey` — thirty-two bytes, clamped as they are used

**Fails with**

- [CryptoError.KeyLength](#keylength-case) — `privateKey` is not `PrivateKeySize` long

<sub>[stdlib/Security/Cryptography/X25519.sl:77](../../stdlib/Security/Cryptography/X25519.sl#L77)</sub>

#### DeriveSharedSecret *method*

```
static Result<byte[], CryptoError> DeriveSharedSecret(ReadOnlySpan<byte> privateKey, ReadOnlySpan<byte> publicKey)
```

The secret both sides arrive at: `privateKey` times the peer's public
key.

A public key of small order gives zero whatever the private key, which
would let the peer choose the secret. RFC 7748 §6.1 has that checked,
and it is refused here.

**Parameters**

- `privateKey` — this side's key
- `publicKey` — the peer's key; its top bit is ignored, as the RFC requires

**Fails with**

- [CryptoError.KeyLength](#keylength-case) — either key is not 32 bytes
- [CryptoError.InvalidKey](#invalidkey-case) — `publicKey` is of small order, and the secret came out zero

<sub>[stdlib/Security/Cryptography/X25519.sl:100](../../stdlib/Security/Cryptography/X25519.sl#L100)</sub>

