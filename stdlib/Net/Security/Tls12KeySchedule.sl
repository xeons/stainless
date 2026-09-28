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

import Standard.Security.Cryptography;

/// TLS 1.2's PRF (RFC 5246 §5): P_hash, HMAC under `secret` with `hash`,
/// over the label and the seed, cut to `length` bytes.
internal byte[] ComputeTls12Prf(HashAlgorithmName hash, ReadOnlySpan<byte> secret, String label,
                                ReadOnlySpan<byte> seed, nuint length)
{
    var hmac = new Hmac(CreateTlsHashAlgorithm(hash), secret);
    var labelAndSeed = new TlsBuffer(64u + seed.Length);
    labelAndSeed.WriteBytes(ConvertTlsTextToBytes(label));
    labelAndSeed.WriteBytes(seed);

    var output = new byte[length];
    byte[] chain = hmac.ComputeHash(labelAndSeed.Written);
    nuint done = 0u;
    while (done < length)
    {
        hmac.AppendData(chain);
        hmac.AppendData(labelAndSeed.Written);
        byte[] block = hmac.GetHashAndReset();
        nuint taking = length - done < block.Length ? length - done : block.Length;
        memcpy(&output[done], &block[0u], taking);
        done += taking;
        chain = hmac.ComputeHash(chain);
    }
    return output;
}

/// A fresh instance of `hash`, which MUST be SHA-256 or SHA-384.
internal IHashAlgorithm CreateTlsHashAlgorithm(HashAlgorithmName hash)
{
    if (hash == HashAlgorithmName.Sha384)
        return new Sha384();
    return new Sha256();
}

/// The TLS 1.2 key schedule: the extended master secret of RFC 7627, the key
/// block, the Finished values, and RFC 5705's exporter.
///
/// Only the extended master secret is made. The master secret of RFC 5246
/// §8.1 binds nothing but the two randoms, which is what the triple
/// handshake attack exploits, so a peer that will not negotiate the
/// extension is refused rather than given one.
internal sealed class Tls12KeySchedule
{
    private HashAlgorithmName _hash;
    private byte[] _clientRandom;
    private byte[] _serverRandom;

    internal byte[] _masterSecret;

    internal Tls12KeySchedule(HashAlgorithmName hash, byte[] clientRandom, byte[] serverRandom)
    {
        _hash = hash;
        _clientRandom = clientRandom;
        _serverRandom = serverRandom;
        _masterSecret = new byte[0u];
    }

    internal HashAlgorithmName Hash => _hash;

    internal byte[] HashTlsBytes(ReadOnlySpan<byte> data)
    {
        var hash = CreateTlsHashAlgorithm(_hash);
        hash.AppendData(data);
        return hash.GetHashAndReset();
    }

    /// The master secret from the premaster secret and the session hash: the
    /// hash of every handshake message through the ClientKeyExchange.
    internal void DeriveTlsExtendedMasterSecret(
        ReadOnlySpan<byte> premasterSecret, ReadOnlySpan<byte> sessionHash)
    {
        _masterSecret = ComputeTls12Prf(_hash, premasterSecret, "extended master secret",
                                        sessionHash, Tls12MasterSecretLength);
    }

    /// The key block (RFC 5246 §6.3): with an AEAD there are no MAC keys, so
    /// it is the client's key, the server's, the client's IV and the
    /// server's. The IV is 4 bytes of salt for AES-GCM and 12 for ChaCha20.
    internal byte[] ComputeTlsKeyBlock(TlsCipherSuite suite)
    {
        nuint keyLength = GetTlsSuiteKeyLength(suite);
        nuint ivLength = GetTls12IvLength(suite);
        var seed = new byte[64u];
        memcpy(&seed[0u], &_serverRandom[0u], 32u);
        memcpy(&seed[32u], &_clientRandom[0u], 32u);
        return ComputeTls12Prf(_hash, _masterSecret, "key expansion", seed,
                               2u * keyLength + 2u * ivLength);
    }

    /// The record protection one direction uses under `suite`.
    internal Result<TlsRecordCipher, TlsError> CreateTls12RecordCipher(
        TlsCipherSuite suite, bool forClient)
    {
        nuint keyLength = GetTlsSuiteKeyLength(suite);
        nuint ivLength = GetTls12IvLength(suite);
        byte[] block = ComputeTlsKeyBlock(suite);
        nuint keyAt = forClient ? 0u : keyLength;
        nuint ivAt = 2u * keyLength + (forClient ? 0u : ivLength);
        return TlsRecordCipher.CreateTls12(
            suite, block[keyAt:][:keyLength].ToArray(), block[ivAt:][:ivLength].ToArray());
    }

    /// The `verify_data` of a Finished over the hash of the handshake so far.
    internal byte[] ComputeTls12Finished(bool byClient, ReadOnlySpan<byte> transcriptHash) =>
        ComputeTls12Prf(_hash, _masterSecret, byClient ? "client finished" : "server finished",
                        transcriptHash, Tls12VerifyDataLength);

    /// RFC 5705's exporter. An empty `context` is taken as no context, which
    /// is how the protocols above TLS 1.2 that use it ask.
    internal byte[] ExportTlsKeyingMaterial(String label, ReadOnlySpan<byte> context, nuint length)
    {
        var seed = new TlsBuffer(66u + context.Length);
        seed.WriteBytes(_clientRandom);
        seed.WriteBytes(_serverRandom);
        if (context.Length > 0u)
        {
            nuint at = seed.BeginVector(2u);
            seed.WriteBytes(context);
            seed.EndVector(at, 2u);
        }
        return ComputeTls12Prf(_hash, _masterSecret, label, seed.Written, length);
    }
}

/// How much of the key block is each direction's IV under the TLS 1.2
/// `suite`: the implicit salt of RFC 5288 for AES-GCM, and RFC 7905's whole
/// nonce for ChaCha20.
internal nuint GetTls12IvLength(TlsCipherSuite suite) =>
    IsTlsChaChaCipherSuite(suite) ? 12u : 4u;
