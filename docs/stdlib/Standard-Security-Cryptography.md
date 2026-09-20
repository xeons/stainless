# Standard.Security.Cryptography

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

Hashes, message authentication codes, key derivation and block ciphers.

```csharp
var digest = Sha256.HashData(Encoding.Utf8().GetBytes("hello"));
Console.WriteLine(Convert.ToHex(digest));

var cipher = try Aes.FromKey(key);
var sealed = try cipher.EncryptCbc(plaintext, iv, PaddingMode.Pkcs7);
```

**The shape is `System.Security.Cryptography`'s**, so a program being
ported finds the names where it left them: `Sha256`, `Hmac`, `Aes`,
`AesGcm`, `Rfc2898DeriveBytes.Pbkdf2`, `RandomNumberGenerator.Fill`,
`CryptographicOperations.FixedTimeEquals`. Three things about it differ,
and each is a rule this language already has rather than a choice made
here:

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

**This is a software implementation and makes no constant-time claim
beyond the obvious.** `FixedTimeEquals` is constant time and is the one
comparison a caller should use on a secret. The AES here is a byte-oriented
reference implementation with a table-driven S-box, which is the shape that
is known to leak through the data cache on a machine an attacker shares. It
is right for a file, a protocol and a password store, and it is not the
thing to put under a remote attacker who can time it. AES-NI and a
bitsliced fallback are what would answer that, and neither is written --
TODO.md carries the note.

**What is not here yet is public-key.** RSA, ECDsa, ECDiffieHellman and
X.509 all rest on arbitrary-precision integer arithmetic, which this
standard library does not have; see TODO.md for the shape that would take.
So this module is the symmetric half, and it is complete: every hash, MAC,
key derivation and cipher .NET ships that does not need a bignum.

## Contents

**Types** &nbsp; [Aes](#aes-class) &middot; [AesGcm](#aesgcm-class) &middot; [CipherMode](#ciphermode-enum) &middot; [CryptoError](#cryptoerror-enum) &middot; [CryptographicOperations](#cryptographicoperations-class) &middot; [HashAlgorithm](#hashalgorithm-class) &middot; [Hkdf](#hkdf-class) &middot; [Hmac](#hmac-class) &middot; [HmacMd5](#hmacmd5-class) &middot; [HmacSha1](#hmacsha1-class) &middot; [HmacSha256](#hmacsha256-class) &middot; [HmacSha384](#hmacsha384-class) &middot; [HmacSha512](#hmacsha512-class) &middot; [IHashAlgorithm](#ihashalgorithm-interface) &middot; [Md5](#md5-class) &middot; [PaddingMode](#paddingmode-enum) &middot; [RandomNumberGenerator](#randomnumbergenerator-class) &middot; [Rfc2898DeriveBytes](#rfc2898derivebytes-class) &middot; [Sha1](#sha1-class) &middot; [Sha256](#sha256-class) &middot; [Sha2Wide](#sha2wide-class) &middot; [Sha384](#sha384-class) &middot; [Sha512](#sha512-class)

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

The one-shot methods are .NET 6's `EncryptCbc` and friends rather than its
older `CreateEncryptor`/`ICryptoTransform` pair. A transform object exists
to stream a message larger than memory; `CryptoStream` is the piece that
would want one and is not written, so the object with no stream to feed
would be a shape with no user.

<sub>[stdlib/Cryptography.sl:1267](../../stdlib/Cryptography.sl#L1267)</sub>

#### BlockSize *constant*

```
const nuint BlockSize = 16
```

One block, for every key length. AES is a 128-bit block cipher; it is
Rijndael that had others, and no standard uses them.

<sub>[stdlib/Cryptography.sl:1271](../../stdlib/Cryptography.sl#L1271)</sub>

#### FromKey *method*

```
static Result<Aes, CryptoError> FromKey(byte[:] key)
```

A cipher under `key`, which must be 16, 24 or 32 bytes -- AES-128,
AES-192 or AES-256.

<sub>[stdlib/Cryptography.sl:1299](../../stdlib/Cryptography.sl#L1299)</sub>

#### Create *method*

```
static Aes Create()
```

A cipher under a fresh 256-bit key from the platform, which is what
.NET's `Aes.Create()` gives. Aborts if the machine will supply no
entropy, which is a broken machine rather than an outcome to plan for.

<sub>[stdlib/Cryptography.sl:1309](../../stdlib/Cryptography.sl#L1309)</sub>

#### Rounds *property*

```
nuint Rounds { get; }
```

How many rounds this key length runs: 10, 12 or 14.

<sub>[stdlib/Cryptography.sl:1318](../../stdlib/Cryptography.sl#L1318)</sub>

#### EncryptBlock *method*

```
void EncryptBlock(byte[] block, nuint offset)
```

One block enciphered in place, at `offset` in `block`.

Public because AES-GCM and a CTR keystream are built on it and a caller
implementing a mode this class does not have needs the same door.
**Not a way to encrypt a message**: a bare block cipher applied twice
to the same input gives the same output, which is what a mode exists to
fix.

<sub>[stdlib/Cryptography.sl:1329](../../stdlib/Cryptography.sl#L1329)</sub>

#### DecryptBlock *method*

```
void DecryptBlock(byte[] block, nuint offset)
```

One block deciphered in place, at `offset` in `block`.

<sub>[stdlib/Cryptography.sl:1347](../../stdlib/Cryptography.sl#L1347)</sub>

#### EncryptEcb *method*

```
Result<byte[], CryptoError> EncryptEcb(byte[:] plaintext, PaddingMode padding)
```

Every block on its own. See `CipherMode.Ecb` for why this is almost
always the wrong answer.

<sub>[stdlib/Cryptography.sl:1368](../../stdlib/Cryptography.sl#L1368)</sub>

#### DecryptEcb *method*

```
Result<byte[], CryptoError> DecryptEcb(byte[:] ciphertext, PaddingMode padding)
```

The inverse of `EncryptEcb`.

<sub>[stdlib/Cryptography.sl:1382](../../stdlib/Cryptography.sl#L1382)</sub>

#### EncryptCbc *method*

```
Result<byte[], CryptoError> EncryptCbc(byte[:] plaintext, byte[:] iv, PaddingMode padding)
```

Chained blocks. `iv` must be one block and must never be reused with
this key; `RandomNumberGenerator.GetBytes(16u)` is how to make one, and
it is not secret -- send it alongside the ciphertext.

<sub>[stdlib/Cryptography.sl:1399](../../stdlib/Cryptography.sl#L1399)</sub>

#### DecryptCbc *method*

```
Result<byte[], CryptoError> DecryptCbc(byte[:] ciphertext, byte[:] iv, PaddingMode padding)
```

The inverse of `EncryptCbc`.

A wrong key shows up as `CryptoError.Padding` about 255 times in 256,
and as a plausible-looking wrong plaintext the rest of the time. That
is the whole reason to authenticate a ciphertext before decrypting it.

<sub>[stdlib/Cryptography.sl:1431](../../stdlib/Cryptography.sl#L1431)</sub>

#### EncryptCfb *method*

```
Result<byte[], CryptoError> EncryptCfb(byte[:] plaintext, byte[:] iv)
```

Cipher feedback over whole blocks, which is .NET's `CipherMode.CFB`
with a feedback size of 128 bits. No padding: the mode is a stream.

<sub>[stdlib/Cryptography.sl:1464](../../stdlib/Cryptography.sl#L1464)</sub>

#### DecryptCfb *method*

```
Result<byte[], CryptoError> DecryptCfb(byte[:] ciphertext, byte[:] iv)
```

The inverse of `EncryptCfb`.

<sub>[stdlib/Cryptography.sl:1491](../../stdlib/Cryptography.sl#L1491)</sub>

#### ApplyCtr *method*

```
Result<byte[], CryptoError> ApplyCtr(byte[:] data, byte[:] counter)
```

Counter mode, which is its own inverse: the same call decrypts.

`counter` is sixteen bytes and is incremented as one big-endian number
per block, which is what NIST SP 800-38A and every protocol built on it
do. **A counter value used twice under one key is fatal** -- the two
messages XOR to the XOR of their plaintexts -- so the usual arrangement
is a random nonce in the high bytes and a block counter in the low.

<sub>[stdlib/Cryptography.sl:1527](../../stdlib/Cryptography.sl#L1527)</sub>

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

<sub>[stdlib/Cryptography.sl:1925](../../stdlib/Cryptography.sl#L1925)</sub>

#### TagSize *constant*

```
const nuint TagSize = 16
```

What the tag is, and the only length this produces. .NET allows 12 to
16; a shorter tag weakens forgery resistance by exactly the bits it
drops, and no format here asks for one.

<sub>[stdlib/Cryptography.sl:1930](../../stdlib/Cryptography.sl#L1930)</sub>

#### NonceSize *constant*

```
const nuint NonceSize = 12
```

What every protocol built on GCM uses, and the only length for which
the nonce is used directly rather than hashed.

<sub>[stdlib/Cryptography.sl:1934](../../stdlib/Cryptography.sl#L1934)</sub>

#### FromKey *method*

```
static Result<AesGcm, CryptoError> FromKey(byte[:] key)
```

A GCM box under `key`, which must be 16, 24 or 32 bytes.

<sub>[stdlib/Cryptography.sl:1947](../../stdlib/Cryptography.sl#L1947)</sub>

#### Encrypt *method*

```
Result<byte[], CryptoError> Encrypt(byte[:] nonce, byte[:] plaintext, byte[:] associatedData, byte[] tag)
```

The ciphertext, with the tag written into `tag`.

`associatedData` is authenticated and not encrypted -- a message header,
a record number, anything the recipient must be sure of and that is not
secret. Pass an empty array when there is none.

<sub>[stdlib/Cryptography.sl:1960](../../stdlib/Cryptography.sl#L1960)</sub>

#### Decrypt *method*

```
Result<byte[], CryptoError> Decrypt(byte[:] nonce, byte[:] ciphertext, byte[:] associatedData, byte[:] tag)
```

The plaintext, or `AuthenticationFailed` and nothing.

<sub>[stdlib/Cryptography.sl:1987](../../stdlib/Cryptography.sl#L1987)</sub>

### CipherMode *enum*

```
enum CipherMode
```

How the blocks of a message are chained together.

.NET's `CipherMode`, minus the two nobody should pick: `Ofb` and `Cts` are
not implemented by .NET's own AES either, and a mode that exists only to be
rejected is worse than a name that is not there.

<sub>[stdlib/Cryptography.sl:1202](../../stdlib/Cryptography.sl#L1202)</sub>

#### Cbc *case*

```
Cbc
```

Cipher block chaining: each block is XORed with the one before it, and
the first with the IV. Needs a unique, unpredictable IV per message,
and provides no authentication at all.

<sub>[stdlib/Cryptography.sl:1207](../../stdlib/Cryptography.sl#L1207)</sub>

#### Ecb *case*

```
Ecb
```

Electronic codebook: each block alone. **Equal plaintext blocks give
equal ciphertext blocks**, which is why the penguin picture is famous.
Right for exactly one thing -- enciphering a single block that is
already a key.

<sub>[stdlib/Cryptography.sl:1213](../../stdlib/Cryptography.sl#L1213)</sub>

#### Cfb *case*

```
Cfb
```

Cipher feedback, as a full-block stream. Needs a unique IV and, like
CBC, authenticates nothing.

<sub>[stdlib/Cryptography.sl:1217](../../stdlib/Cryptography.sl#L1217)</sub>

#### Ctr *case*

```
Ctr
```

Counter mode: the cipher makes a keystream, and the message is XORed
with it. Not in .NET's enum, and here because it is what AES-GCM is
built on and what most modern protocols specify. **Reusing a counter
value with the same key destroys the message pair completely.**

<sub>[stdlib/Cryptography.sl:1223](../../stdlib/Cryptography.sl#L1223)</sub>

### CryptoError *enum*

```
enum CryptoError
```

Why an operation did not happen.

One enum for the module, as `IOError` is for `Standard.IO`: a caller
switching on the failure of a decrypt wants the same vocabulary as one
checking a key length.

<sub>[stdlib/Cryptography.sl:85](../../stdlib/Cryptography.sl#L85)</sub>

#### KeyLength *case*

```
KeyLength
```

The key is not a length this algorithm takes. AES takes 16, 24 or 32
bytes; an HMAC key may be any length at all, so this never comes from
one.

<sub>[stdlib/Cryptography.sl:90](../../stdlib/Cryptography.sl#L90)</sub>

#### IvLength *case*

```
IvLength
```

The initialization vector is not one block long.

<sub>[stdlib/Cryptography.sl:93](../../stdlib/Cryptography.sl#L93)</sub>

#### NonceLength *case*

```
NonceLength
```

The nonce is not a length this mode takes. AES-GCM takes any non-empty
nonce and wants twelve bytes.

<sub>[stdlib/Cryptography.sl:97](../../stdlib/Cryptography.sl#L97)</sub>

#### TagLength *case*

```
TagLength
```

The authentication tag is not a length this mode produces.

<sub>[stdlib/Cryptography.sl:100](../../stdlib/Cryptography.sl#L100)</sub>

#### BlockLength *case*

```
BlockLength
```

The input is not a whole number of blocks, and the padding mode in
force does not add any.

<sub>[stdlib/Cryptography.sl:104](../../stdlib/Cryptography.sl#L104)</sub>

#### Padding *case*

```
Padding
```

The padding on a decrypted block does not describe itself. Usually the
wrong key, and deliberately says no more than that.

<sub>[stdlib/Cryptography.sl:108](../../stdlib/Cryptography.sl#L108)</sub>

#### AuthenticationFailed *case*

```
AuthenticationFailed
```

The tag did not match. **The plaintext is not returned**, because a
plaintext that failed authentication is attacker-controlled and
handling it at all is the mistake AEAD exists to prevent.

<sub>[stdlib/Cryptography.sl:113](../../stdlib/Cryptography.sl#L113)</sub>

#### Parameter *case*

```
Parameter
```

An iteration count of zero, or an output length of zero, where neither
is meaningful.

<sub>[stdlib/Cryptography.sl:117](../../stdlib/Cryptography.sl#L117)</sub>

#### NoEntropy *case*

```
NoEntropy
```

The platform would not supply entropy.

<sub>[stdlib/Cryptography.sl:120](../../stdlib/Cryptography.sl#L120)</sub>

### CryptographicOperations *class*

```
class CryptographicOperations
```

The two operations on a secret that are easy to write wrongly.

<sub>[stdlib/Cryptography.sl:2205](../../stdlib/Cryptography.sl#L2205)</sub>

#### FixedTimeEquals *method*

```
static bool FixedTimeEquals(byte[:] left, byte[:] right)
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

<sub>[stdlib/Cryptography.sl:2218](../../stdlib/Cryptography.sl#L2218)</sub>

#### ZeroMemory *method*

```
static void ZeroMemory(byte[] buffer)
```

Overwrites `buffer` with zeros.

**Not a guarantee.** An optimiser is entitled to remove a write nothing
reads, and this is an ordinary loop in an ordinary language -- .NET's
version is a compiler intrinsic and this one is not. It is worth doing
because a key that is overwritten is a key that is not in the next core
dump, and it is not worth relying on.

<sub>[stdlib/Cryptography.sl:2237](../../stdlib/Cryptography.sl#L2237)</sub>

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
`Compress`, `Digest` and `StartOver` and nothing else.

<sub>[stdlib/Cryptography.sl:218](../../stdlib/Cryptography.sl#L218)</sub>

#### Name *property*

```
String Name { get; }
```

*No documentation.*

<sub>[stdlib/Cryptography.sl:247](../../stdlib/Cryptography.sl#L247)</sub>

#### HashSizeInBytes *property*

```
nuint HashSizeInBytes { get; }
```

*No documentation.*

<sub>[stdlib/Cryptography.sl:249](../../stdlib/Cryptography.sl#L249)</sub>

#### BlockSizeInBytes *property*

```
nuint BlockSizeInBytes { get; }
```

*No documentation.*

<sub>[stdlib/Cryptography.sl:251](../../stdlib/Cryptography.sl#L251)</sub>

#### Append *method*

```
void Append(byte[:] data)
```

*No documentation.*

<sub>[stdlib/Cryptography.sl:253](../../stdlib/Cryptography.sl#L253)</sub>

#### GetHashAndReset *method*

```
byte[] GetHashAndReset()
```

*No documentation.*

<sub>[stdlib/Cryptography.sl:278](../../stdlib/Cryptography.sl#L278)</sub>

#### Reset *method*

```
void Reset()
```

*No documentation.*

<sub>[stdlib/Cryptography.sl:285](../../stdlib/Cryptography.sl#L285)</sub>

#### ComputeHash *method*

```
byte[] ComputeHash(byte[:] data)
```

The digest of `data` on its own. Resets first, so an object that has
been appended to is still safe to ask.

<sub>[stdlib/Cryptography.sl:297](../../stdlib/Cryptography.sl#L297)</sub>

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

<sub>[stdlib/Cryptography.sl:1125](../../stdlib/Cryptography.sl#L1125)</sub>

#### Extract *method*

```
static byte[] Extract(IHashAlgorithm hash, byte[:] inputKey, byte[:] salt)
```

The extract step: a uniformly random key from input that is random but
not uniform. `salt` may be empty, and then a block of zeros is used.

<sub>[stdlib/Cryptography.sl:1129](../../stdlib/Cryptography.sl#L1129)</sub>

#### Expand *method*

```
static Result<byte[], CryptoError> Expand(IHashAlgorithm hash, byte[:] pseudoKey, byte[:] info, nuint length)
```

The expand step: as many bytes as asked for, bound to `info`.

`info` is what separates one derived key from another -- "encryption"
and "authentication" from the same secret -- and is the argument that
makes this worth using over a bare hash.

<sub>[stdlib/Cryptography.sl:1140](../../stdlib/Cryptography.sl#L1140)</sub>

#### DeriveKey *method*

```
static Result<byte[], CryptoError> DeriveKey(IHashAlgorithm hash, byte[:] inputKey, byte[:] salt, byte[:] info, nuint length)
```

Extract and expand together, which is how HKDF is nearly always used.

<sub>[stdlib/Cryptography.sl:1178](../../stdlib/Cryptography.sl#L1178)</sub>

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

<sub>[stdlib/Cryptography.sl:909](../../stdlib/Cryptography.sl#L909)</sub>

#### Name *property*

```
String Name { get; }
```

*No documentation.*

<sub>[stdlib/Cryptography.sl:952](../../stdlib/Cryptography.sl#L952)</sub>

#### HashSizeInBytes *property*

```
nuint HashSizeInBytes { get; }
```

*No documentation.*

<sub>[stdlib/Cryptography.sl:954](../../stdlib/Cryptography.sl#L954)</sub>

#### BlockSizeInBytes *property*

```
nuint BlockSizeInBytes { get; }
```

*No documentation.*

<sub>[stdlib/Cryptography.sl:956](../../stdlib/Cryptography.sl#L956)</sub>

#### Append *method*

```
void Append(byte[:] data)
```

*No documentation.*

<sub>[stdlib/Cryptography.sl:958](../../stdlib/Cryptography.sl#L958)</sub>

#### GetHashAndReset *method*

```
byte[] GetHashAndReset()
```

*No documentation.*

<sub>[stdlib/Cryptography.sl:960](../../stdlib/Cryptography.sl#L960)</sub>

#### Reset *method*

```
void Reset()
```

*No documentation.*

<sub>[stdlib/Cryptography.sl:970](../../stdlib/Cryptography.sl#L970)</sub>

#### ComputeHash *method*

```
byte[] ComputeHash(byte[:] data)
```

The MAC of `data` under `key`, with no object to keep.

<sub>[stdlib/Cryptography.sl:977](../../stdlib/Cryptography.sl#L977)</sub>

### HmacMd5 *class*

```
class HmacMd5
```

HMAC-MD5, as .NET spells `HMACMD5`. Here for the protocols that specify it
-- and unlike a bare MD5 digest it is not broken by the collision attacks,
because a collision an attacker cannot compute without the key is no use.

<sub>[stdlib/Cryptography.sl:1032](../../stdlib/Cryptography.sl#L1032)</sub>

#### Create *method*

```
static Hmac Create(byte[:] key)
```

A keyed hash to append to.

<sub>[stdlib/Cryptography.sl:1035](../../stdlib/Cryptography.sl#L1035)</sub>

#### HashData *method*

```
static byte[] HashData(byte[:] key, byte[:] data)
```

The MAC of `data` under `key`.

<sub>[stdlib/Cryptography.sl:1038](../../stdlib/Cryptography.sl#L1038)</sub>

### HmacSha1 *class*

```
class HmacSha1
```

HMAC-SHA-1, as .NET spells `HMACSHA1`.

<sub>[stdlib/Cryptography.sl:986](../../stdlib/Cryptography.sl#L986)</sub>

#### Create *method*

```
static Hmac Create(byte[:] key)
```

A keyed hash to append to.

<sub>[stdlib/Cryptography.sl:989](../../stdlib/Cryptography.sl#L989)</sub>

#### HashData *method*

```
static byte[] HashData(byte[:] key, byte[:] data)
```

The MAC of `data` under `key`.

<sub>[stdlib/Cryptography.sl:992](../../stdlib/Cryptography.sl#L992)</sub>

### HmacSha256 *class*

```
class HmacSha256
```

HMAC-SHA-256, as .NET spells `HMACSHA256`. The default for anything new.

<sub>[stdlib/Cryptography.sl:997](../../stdlib/Cryptography.sl#L997)</sub>

#### Create *method*

```
static Hmac Create(byte[:] key)
```

A keyed hash to append to.

<sub>[stdlib/Cryptography.sl:1000](../../stdlib/Cryptography.sl#L1000)</sub>

#### HashData *method*

```
static byte[] HashData(byte[:] key, byte[:] data)
```

The MAC of `data` under `key`.

<sub>[stdlib/Cryptography.sl:1003](../../stdlib/Cryptography.sl#L1003)</sub>

### HmacSha384 *class*

```
class HmacSha384
```

HMAC-SHA-384, as .NET spells `HMACSHA384`.

<sub>[stdlib/Cryptography.sl:1008](../../stdlib/Cryptography.sl#L1008)</sub>

#### Create *method*

```
static Hmac Create(byte[:] key)
```

A keyed hash to append to.

<sub>[stdlib/Cryptography.sl:1011](../../stdlib/Cryptography.sl#L1011)</sub>

#### HashData *method*

```
static byte[] HashData(byte[:] key, byte[:] data)
```

The MAC of `data` under `key`.

<sub>[stdlib/Cryptography.sl:1014](../../stdlib/Cryptography.sl#L1014)</sub>

### HmacSha512 *class*

```
class HmacSha512
```

HMAC-SHA-512, as .NET spells `HMACSHA512`.

<sub>[stdlib/Cryptography.sl:1019](../../stdlib/Cryptography.sl#L1019)</sub>

#### Create *method*

```
static Hmac Create(byte[:] key)
```

A keyed hash to append to.

<sub>[stdlib/Cryptography.sl:1022](../../stdlib/Cryptography.sl#L1022)</sub>

#### HashData *method*

```
static byte[] HashData(byte[:] key, byte[:] data)
```

The MAC of `data` under `key`.

<sub>[stdlib/Cryptography.sl:1025](../../stdlib/Cryptography.sl#L1025)</sub>

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

<sub>[stdlib/Cryptography.sl:184](../../stdlib/Cryptography.sl#L184)</sub>

#### Name *property*

```
String Name { get; }
```

What the algorithm is called, as a standard names it -- `SHA-256`,
`HMAC-SHA-256`. This is the spelling that goes in a protocol field,
so it keeps the hyphens and the capitals.

<sub>[stdlib/Cryptography.sl:189](../../stdlib/Cryptography.sl#L189)</sub>

#### HashSizeInBytes *property*

```
nuint HashSizeInBytes { get; }
```

How many bytes the digest is.

<sub>[stdlib/Cryptography.sl:192](../../stdlib/Cryptography.sl#L192)</sub>

#### BlockSizeInBytes *property*

```
nuint BlockSizeInBytes { get; }
```

How many bytes the compression function eats at a time. HMAC needs it,
which is why it is on the interface rather than inside.

<sub>[stdlib/Cryptography.sl:196](../../stdlib/Cryptography.sl#L196)</sub>

#### Append *method*

```
void Append(byte[:] data)
```

Adds bytes to what is being hashed.

<sub>[stdlib/Cryptography.sl:199](../../stdlib/Cryptography.sl#L199)</sub>

#### GetHashAndReset *method*

```
byte[] GetHashAndReset()
```

The digest of everything appended since the last reset, and a reset.
Calling it twice in a row gives the digest of the empty input the
second time, which is what the reset means.

<sub>[stdlib/Cryptography.sl:204](../../stdlib/Cryptography.sl#L204)</sub>

#### Reset *method*

```
void Reset()
```

Throws away what has been appended and starts again.

<sub>[stdlib/Cryptography.sl:207](../../stdlib/Cryptography.sl#L207)</sub>

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

<sub>[stdlib/Cryptography.sl:373](../../stdlib/Cryptography.sl#L373)</sub>

#### Name *property*

```
String Name { get; }
```

*No documentation.*

<sub>[stdlib/Cryptography.sl:422](../../stdlib/Cryptography.sl#L422)</sub>

#### HashSizeInBytes *property*

```
nuint HashSizeInBytes { get; }
```

*No documentation.*

<sub>[stdlib/Cryptography.sl:424](../../stdlib/Cryptography.sl#L424)</sub>

#### HashData *method*

```
static byte[] HashData(byte[:] data)
```

The digest of `data`, with no object to keep.

<sub>[stdlib/Cryptography.sl:427](../../stdlib/Cryptography.sl#L427)</sub>

### PaddingMode *enum*

```
enum PaddingMode
```

What is added to make the plaintext a whole number of blocks.

<sub>[stdlib/Cryptography.sl:1227](../../stdlib/Cryptography.sl#L1227)</sub>

#### None *case*

```
None
```

Nothing. The input must already be a multiple of the block size, and
`CryptoError.BlockLength` says so when it is not.

<sub>[stdlib/Cryptography.sl:1231](../../stdlib/Cryptography.sl#L1231)</sub>

#### Pkcs7 *case*

```
Pkcs7
```

PKCS#7: N bytes of the value N, always at least one block-worth of
information added. The default everywhere, and what .NET uses unless
told otherwise.

<sub>[stdlib/Cryptography.sl:1236](../../stdlib/Cryptography.sl#L1236)</sub>

#### Zeros *case*

```
Zeros
```

Zeros to the block boundary. **Not removable**: a plaintext that ended
in a zero byte is indistinguishable from its padding, so decryption
leaves it in place.

<sub>[stdlib/Cryptography.sl:1241](../../stdlib/Cryptography.sl#L1241)</sub>

#### AnsiX923 *case*

```
AnsiX923
```

ANSI X9.23: zeros, and the last byte is the count.

<sub>[stdlib/Cryptography.sl:1244](../../stdlib/Cryptography.sl#L1244)</sub>

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

<sub>[stdlib/Cryptography.sl:2144](../../stdlib/Cryptography.sl#L2144)</sub>

#### Fill *method*

```
static bool Fill(byte[] buffer)
```

Fills `buffer` with random bytes, and says whether it could.

The failure is a machine with no entropy source at all, which in
practice means a misconfigured container. It is a `bool` rather than a
`Result` because there is exactly one reason and the name says it.

<sub>[stdlib/Cryptography.sl:2151](../../stdlib/Cryptography.sl#L2151)</sub>

#### GetBytes *method*

```
static byte[] GetBytes(nuint count)
```

`count` random bytes.

Aborts if the platform will supply none, which is the same judgement
`new Random()` makes: a key that is not random is worse than a program
that stops, and there is no useful value to return instead.

<sub>[stdlib/Cryptography.sl:2163](../../stdlib/Cryptography.sl#L2163)</sub>

#### GetInt32 *method*

```
static int GetInt32(int from, int to)
```

A number in `[from, to)`, drawn without the modulo bias that
`GetBytes(4) % range` has.

Aborts on an empty or backwards range, which names a bug rather than an
outcome -- the same judgement `Random.NextBelow` makes.

<sub>[stdlib/Cryptography.sl:2176](../../stdlib/Cryptography.sl#L2176)</sub>

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

**This is the weakest of the modern password hashes and the only one
here.** PBKDF2 costs an attacker with a GPU very much less than it costs a
server, because it needs no memory. scrypt and Argon2 exist to close that
gap and neither is written; TODO.md carries them. Use PBKDF2 where a format
specifies it, and understand what it does not buy.

<sub>[stdlib/Cryptography.sl:1057](../../stdlib/Cryptography.sl#L1057)</sub>

#### Pbkdf2 *method*

```
static Result<byte[], CryptoError> Pbkdf2(byte[:] password, byte[:] salt, nuint iterations, IHashAlgorithm hash, nuint length)
```

`length` bytes derived from `password` and `salt`.

`hash` is the HMAC's inner hash -- `new Sha256()` is the usual answer.
The salt should be at least sixteen random bytes and is not secret; its
job is to make one attack per password rather than one per database.

<sub>[stdlib/Cryptography.sl:1064](../../stdlib/Cryptography.sl#L1064)</sub>

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

<sub>[stdlib/Cryptography.sl:508](../../stdlib/Cryptography.sl#L508)</sub>

#### Name *property*

```
String Name { get; }
```

*No documentation.*

<sub>[stdlib/Cryptography.sl:519](../../stdlib/Cryptography.sl#L519)</sub>

#### HashSizeInBytes *property*

```
nuint HashSizeInBytes { get; }
```

*No documentation.*

<sub>[stdlib/Cryptography.sl:521](../../stdlib/Cryptography.sl#L521)</sub>

#### HashData *method*

```
static byte[] HashData(byte[:] data)
```

The digest of `data`, with no object to keep.

<sub>[stdlib/Cryptography.sl:524](../../stdlib/Cryptography.sl#L524)</sub>

### Sha256 *class*

```
sealed class Sha256 : HashAlgorithm
```

SHA-256: the one to reach for when nothing else decides.

<sub>[stdlib/Cryptography.sl:607](../../stdlib/Cryptography.sl#L607)</sub>

#### Name *property*

```
String Name { get; }
```

*No documentation.*

<sub>[stdlib/Cryptography.sl:639](../../stdlib/Cryptography.sl#L639)</sub>

#### HashSizeInBytes *property*

```
nuint HashSizeInBytes { get; }
```

*No documentation.*

<sub>[stdlib/Cryptography.sl:641](../../stdlib/Cryptography.sl#L641)</sub>

#### HashData *method*

```
static byte[] HashData(byte[:] data)
```

The digest of `data`, with no object to keep.

<sub>[stdlib/Cryptography.sl:644](../../stdlib/Cryptography.sl#L644)</sub>

### Sha2Wide *class*

```
abstract class Sha2Wide : HashAlgorithm
```

The 64-bit half of SHA-2, which SHA-384 and SHA-512 share entirely except
for where they start and how much of the answer they keep.

Public because a public class cannot usefully hide its base, and documented
as machinery: there is nothing here to construct. `Sha384` and `Sha512` are
the two that exist.

<sub>[stdlib/Cryptography.sl:728](../../stdlib/Cryptography.sl#L728)</sub>

### Sha384 *class*

```
sealed class Sha384 : Sha2Wide
```

SHA-384: SHA-512 from a different start, with half the answer thrown away.

The truncation is what makes it worth having rather than a curiosity --
a SHA-512 digest reveals the whole final state, and a SHA-384 one does
not, so length-extension does not apply to it.

<sub>[stdlib/Cryptography.sl:869](../../stdlib/Cryptography.sl#L869)</sub>

#### Name *property*

```
String Name { get; }
```

*No documentation.*

<sub>[stdlib/Cryptography.sl:877](../../stdlib/Cryptography.sl#L877)</sub>

#### HashSizeInBytes *property*

```
nuint HashSizeInBytes { get; }
```

*No documentation.*

<sub>[stdlib/Cryptography.sl:879](../../stdlib/Cryptography.sl#L879)</sub>

#### HashData *method*

```
static byte[] HashData(byte[:] data)
```

The digest of `data`, with no object to keep.

<sub>[stdlib/Cryptography.sl:882](../../stdlib/Cryptography.sl#L882)</sub>

### Sha512 *class*

```
sealed class Sha512 : Sha2Wide
```

SHA-512: the 64-bit member of the family, and faster than SHA-256 on a
64-bit machine for the same reason it is wider.

<sub>[stdlib/Cryptography.sl:836](../../stdlib/Cryptography.sl#L836)</sub>

#### Name *property*

```
String Name { get; }
```

*No documentation.*

<sub>[stdlib/Cryptography.sl:844](../../stdlib/Cryptography.sl#L844)</sub>

#### HashSizeInBytes *property*

```
nuint HashSizeInBytes { get; }
```

*No documentation.*

<sub>[stdlib/Cryptography.sl:846](../../stdlib/Cryptography.sl#L846)</sub>

#### HashData *method*

```
static byte[] HashData(byte[:] data)
```

The digest of `data`, with no object to keep.

<sub>[stdlib/Cryptography.sl:849](../../stdlib/Cryptography.sl#L849)</sub>

