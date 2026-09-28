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

import Standard.Collections;

/// A ClientHello, read (RFC 8446 §4.1.2): the fields a server chooses by, and
/// what a client offered, for checking the server's answers against.
internal sealed class TlsClientHello
{
    internal byte[] _random = new byte[0u];
    internal byte[] _sessionId = new byte[0u];
    internal List<uint> _cipherSuites = new List<uint>();
    internal bool _nullCompressionOnly = false;
    internal List<uint> _extensionTypes = new List<uint>();

    internal bool _hasSupportedVersions = false;
    internal List<uint> _supportedVersions = new List<uint>();
    internal bool _hasSupportedGroups = false;
    internal List<uint> _supportedGroups = new List<uint>();
    internal bool _hasKeyShare = false;
    internal List<uint> _keyShareGroups = new List<uint>();
    internal List<byte[]> _keyShareKeys = new List<byte[]>();
    internal bool _hasSignatureAlgorithms = false;
    internal List<TlsSignatureScheme> _signatureAlgorithms = new List<TlsSignatureScheme>();
    internal String _serverName = "";
    internal bool _hasServerName = false;
    internal List<String> _applicationProtocols = new List<String>();
    internal bool _hasApplicationProtocols = false;
    internal byte[] _cookie = new byte[0u];
    internal bool _hasCookie = false;
    internal bool _hasPreSharedKey = false;
    internal bool _hasEarlyData = false;

    internal bool OfferedTlsExtension(TlsExtensionType type) => _extensionTypes.Contains((uint)type);

    /// The key share offered in `group`, or an empty array.
    internal byte[] FindTlsKeyShare(TlsNamedGroup group)
    {
        for (nuint i = 0u; i < _keyShareGroups.Count; i++)
        {
            if (_keyShareGroups[i] == (uint)group)
                return _keyShareKeys[i];
        }
        return new byte[0u];
    }

    /// Reads a whole ClientHello message, header included.
    ///
    /// @failure TlsError.Decode            a length or a vector is wrong
    /// @failure TlsError.IllegalParameter  an extension appears twice, a key
    ///                                     share names a group twice or one
    ///                                     not in supported_groups, or
    ///                                     pre_shared_key is not last
    internal static Result<TlsClientHello, TlsError> ParseTlsClientHello(byte[] message)
    {
        var hello = new TlsClientHello();
        var reader = new TlsReader(message, 4u, message.Length - 4u);

        reader.ReadUInt16();
        hello._random = reader.ReadArray(32u);
        hello._sessionId = reader.ReadVectorArray(1u, 0u, 32u);

        TlsReader suites = reader.ReadVector(2u, 2u, 65534u);
        if (suites.Remaining % 2u != 0u)
            return Fail(TlsError.Decode);
        while (!suites.IsAtEnd)
            hello._cipherSuites.Add(suites.ReadUInt16());

        byte[] compression = reader.ReadVectorArray(1u, 1u, 255u);
        hello._nullCompressionOnly = compression.Length == 1u && compression[0u] == 0;

        // A ClientHello with no extensions at all is legal before TLS 1.3,
        // and is then simply one without supported_versions.
        if (!reader.IsAtEnd)
        {
            TlsReader extensions = reader.ReadVector(2u, 0u, 65535u);
            if (reader.Failed || !reader.IsAtEnd)
                return Fail(TlsError.Decode);

            while (!extensions.IsAtEnd)
            {
                uint type = extensions.ReadUInt16();
                TlsReader data = extensions.ReadVector(2u, 0u, 65535u);
                if (extensions.Failed)
                    return Fail(TlsError.Decode);
                if (hello._extensionTypes.Contains(type))
                    return Fail(TlsError.IllegalParameter);
                if (hello._hasPreSharedKey)
                    return Fail(TlsError.IllegalParameter);
                hello._extensionTypes.Add(type);

                TlsError parsed = hello.ParseTlsClientExtension(type, data);
                if (parsed != TlsError.None)
                    return Fail(parsed);
            }
        }

        if (reader.Failed || !reader.IsAtEnd)
            return Fail(TlsError.Decode);

        for (nuint i = 0u; i < hello._keyShareGroups.Count; i++)
        {
            if (!hello._supportedGroups.Contains(hello._keyShareGroups[i]))
                return Fail(TlsError.IllegalParameter);
        }
        return Ok(hello);
    }

    private TlsError ParseTlsClientExtension(uint type, TlsReader data)
    {
        switch ((TlsExtensionType)(ushort)type)
        {
            case TlsExtensionType.ServerName:
            {
                TlsReader names = data.ReadVector(2u, 1u, 65535u);
                while (!names.IsAtEnd && !names.Failed)
                {
                    uint nameType = names.ReadByte();
                    byte[] name = names.ReadVectorArray(2u, 1u, 65535u);
                    if (nameType == 0u)
                    {
                        if (_hasServerName)
                            return TlsError.IllegalParameter;
                        _hasServerName = true;
                        _serverName = ConvertTlsBytesToText(name);
                    }
                }
                if (names.Failed)
                    return TlsError.Decode;
                break;
            }

            case TlsExtensionType.SupportedVersions:
            {
                _hasSupportedVersions = true;
                TlsReader versions = data.ReadVector(1u, 2u, 254u);
                if (versions.Remaining % 2u != 0u)
                    return TlsError.Decode;
                while (!versions.IsAtEnd)
                    _supportedVersions.Add(versions.ReadUInt16());
                break;
            }

            case TlsExtensionType.SupportedGroups:
            {
                _hasSupportedGroups = true;
                TlsReader groups = data.ReadVector(2u, 2u, 65534u);
                if (groups.Remaining % 2u != 0u)
                    return TlsError.Decode;
                while (!groups.IsAtEnd)
                    _supportedGroups.Add(groups.ReadUInt16());
                break;
            }

            case TlsExtensionType.KeyShare:
            {
                _hasKeyShare = true;
                TlsReader shares = data.ReadVector(2u, 0u, 65535u);
                while (!shares.IsAtEnd && !shares.Failed)
                {
                    uint group = shares.ReadUInt16();
                    byte[] key = shares.ReadVectorArray(2u, 1u, 65535u);
                    if (shares.Failed)
                        break;
                    if (_keyShareGroups.Contains(group))
                        return TlsError.IllegalParameter;
                    _keyShareGroups.Add(group);
                    _keyShareKeys.Add(key);
                }
                if (shares.Failed)
                    return TlsError.Decode;
                break;
            }

            case TlsExtensionType.SignatureAlgorithms:
            {
                _hasSignatureAlgorithms = true;
                TlsError read = ReadTlsSignatureSchemes(data, _signatureAlgorithms);
                if (read != TlsError.None)
                    return read;
                break;
            }

            case TlsExtensionType.ApplicationLayerProtocolNegotiation:
            {
                _hasApplicationProtocols = true;
                TlsReader names = data.ReadVector(2u, 2u, 65535u);
                while (!names.IsAtEnd && !names.Failed)
                {
                    byte[] name = names.ReadVectorArray(1u, 1u, 255u);
                    if (!names.Failed)
                        _applicationProtocols.Add(ConvertTlsBytesToText(name));
                }
                if (names.Failed)
                    return TlsError.Decode;
                break;
            }

            case TlsExtensionType.Cookie:
                _hasCookie = true;
                _cookie = data.ReadVectorArray(2u, 1u, 65535u);
                break;

            case TlsExtensionType.PreSharedKey:
                _hasPreSharedKey = true;
                return TlsError.None;

            case TlsExtensionType.EarlyData:
                _hasEarlyData = true;
                return TlsError.None;

            default:
                return TlsError.None;
        }

        if (data.Failed || !data.IsAtEnd)
            return TlsError.Decode;
        return TlsError.None;
    }
}

/// Reads a `signature_algorithms` list into `into`, keeping only the schemes
/// this library names.
internal TlsError ReadTlsSignatureSchemes(TlsReader data, List<TlsSignatureScheme> into)
{
    TlsReader schemes = data.ReadVector(2u, 2u, 65534u);
    if (schemes.Remaining % 2u != 0u)
        return TlsError.Decode;
    while (!schemes.IsAtEnd)
        into.Add((TlsSignatureScheme)(ushort)schemes.ReadUInt16());
    if (data.Failed || schemes.Failed || !data.IsAtEnd)
        return TlsError.Decode;
    return TlsError.None;
}

/// Writes a list of signature schemes as the body of `signature_algorithms`.
internal void WriteTlsSignatureSchemes(TlsBuffer into, List<TlsSignatureScheme> schemes)
{
    nuint at = into.BeginVector(2u);
    for (nuint i = 0u; i < schemes.Count; i++)
        into.WriteUInt16((uint)schemes[i]);
    into.EndVector(at, 2u);
}

/// Opens an extension: its type, and a length to be filled in by
/// `EndTlsExtension`.
internal nuint BeginTlsExtension(TlsBuffer into, TlsExtensionType type)
{
    into.WriteUInt16((uint)type);
    return into.BeginVector(2u);
}

internal void EndTlsExtension(TlsBuffer into, nuint at) => into.EndVector(at, 2u);

/// Writes a handshake message's header, and answers where its length goes
/// for `EndTlsHandshakeMessage`.
internal nuint BeginTlsHandshakeMessage(TlsBuffer into, TlsHandshakeType type)
{
    into.WriteByte((uint)type);
    return into.BeginVector(3u);
}

internal void EndTlsHandshakeMessage(TlsBuffer into, nuint at) => into.EndVector(at, 3u);
