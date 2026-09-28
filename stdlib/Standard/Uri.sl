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

module Standard;

import Standard.Collections;

/// A URI, read by RFC 3986: C#'s `System.Uri`.
///
///     var page = new Uri("https://example.com/docs/guide/intro.html?v=2#top");
///     page.Host;                               // "example.com"
///     new Uri(page, "../api/").AbsoluteUri;    // "https://example.com/docs/api/"
///
/// An absolute one is kept in its normal form: the scheme and host in lower
/// case, `.` and `..` segments resolved, the scheme's default port dropped,
/// and a character that may not appear escaped. A Windows path or a UNC path
/// reads as a `file:` URI, as in C#. A relative one is kept as written, and
/// asking it for a part only an absolute URI has aborts, where C#'s throws.
///
/// `TryCreate` answers with a `Result`; the constructors abort on what is not a
/// URI, as C#'s throw.
public sealed class Uri : IEquatable<Uri>, IHashable
{
    String _original;
    bool _absolute;
    String _scheme;
    bool _hasAuthority;
    String _userInfo;
    String _host;
    int _port;
    String _path;
    String _query;
    String _fragment;

    /// `text`, absolute or relative. Aborts when it is neither.
    public Uri(String text) : this(text, UriKind.RelativeOrAbsolute) { }

    /// `text`, read as `kind` says. Aborts when it cannot be.
    public Uri(String text, UriKind kind)
    {
        _original = text;
        _scheme = "";
        _userInfo = "";
        _host = "";
        _port = -1;
        _path = "";
        _query = "";
        _fragment = "";

        if (!Read(text, kind))
            sl_fail(("Uri: '" + text + "' is not a URI").ToPointer());
    }

    /// `relative` resolved against `baseUri`, which MUST be absolute.
    public Uri(Uri baseUri, String relative) : this(baseUri, new Uri(relative)) { }

    /// `relative` resolved against `baseUri`, which MUST be absolute. An
    /// absolute `relative` is itself.
    public Uri(Uri baseUri, Uri relative)
    {
        if (!baseUri._absolute)
            sl_fail("Uri: the base is not absolute");

        _original = relative._original;
        _scheme = "";
        _userInfo = "";
        _host = "";
        _port = -1;
        _path = "";
        _query = "";
        _fragment = "";
        Resolve(baseUri, relative);
    }

    /// `text` read as `kind` says, or why it could not be.
    public static Result<Uri, ParseError> TryCreate(String text, UriKind kind)
    {
        if (text.IsEmpty && kind == UriKind.Absolute)
            return Fail(ParseError.Empty);

        var made = new Uri();
        made._original = text;
        return made.Read(text, kind) ? Ok(made) : Fail(ParseError.Malformed);
    }

    /// `relative` resolved against `baseUri`, or why it could not be.
    public static Result<Uri, ParseError> TryCreate(Uri baseUri, String relative)
    {
        if (!baseUri._absolute)
            return Fail(ParseError.Malformed);
        if (TryCreate(relative, UriKind.RelativeOrAbsolute) is not Ok parsed)
            return Fail(ParseError.Malformed);
        return Ok(new Uri(baseUri, parsed.Value));
    }

    /// Whether `text` reads as `kind` says.
    public static bool IsWellFormedUriString(String text, UriKind kind) =>
        TryCreate(text, kind) is Ok;

    Uri()
    {
        _original = "";
        _scheme = "";
        _userInfo = "";
        _host = "";
        _port = -1;
        _path = "";
        _query = "";
        _fragment = "";
    }

    // ---------------------------------------------------------------- schemes

    public static String UriSchemeHttp => "http";
    public static String UriSchemeHttps => "https";
    public static String UriSchemeFile => "file";
    public static String UriSchemeFtp => "ftp";
    public static String UriSchemeMailto => "mailto";
    public static String UriSchemeWs => "ws";
    public static String UriSchemeWss => "wss";

    /// The port a scheme means when it names none, or -1.
    static int DefaultPort(String scheme) => scheme switch
    {
        "http" => 80,
        "https" => 443,
        "ws" => 80,
        "wss" => 443,
        "ftp" => 21,
        "gopher" => 70,
        "nntp" => 119,
        "telnet" => 23,
        "ldap" => 389,
        "mailto" => 25,
        _ => -1,
    };

    /// Whether `name` is a scheme: a letter, then letters, digits, `+`, `-` and `.`.
    public static bool CheckSchemeName(String name)
    {
        if (name.IsEmpty || !IsLetter(name.GetByteAt(0u)))
            return false;
        for (nuint i = 1u; i < name.ByteLength(); i++)
        {
            byte c = name.GetByteAt(i);
            if (!IsLetter(c) && !IsDigit(c) && c != (byte)'+' && c != (byte)'-' && c != (byte)'.')
                return false;
        }
        return true;
    }

    static bool IsLetter(byte c) => (c >= (byte)'a' && c <= (byte)'z') || (c >= (byte)'A' && c <= (byte)'Z');
    static bool IsDigit(byte c) => c >= (byte)'0' && c <= (byte)'9';

    // ---------------------------------------------------------------- reading

    /// Fills this from `text`, and answers whether it is a URI of `kind`.
    bool Read(String text, UriKind kind)
    {
        if (kind != UriKind.Relative && WindowsPathAsUri(text) is Some file)
            return Read(file.Value, UriKind.Absolute);

        long colon = text.IndexOf(':');
        long firstEnd = FirstOf(text, "/?#");
        bool hasScheme = colon > 0 && (firstEnd < 0 || colon < firstEnd) &&
                         CheckSchemeName(text.Substring(0u, (nuint)colon));

        if (!hasScheme)
        {
            if (kind == UriKind.Absolute)
                return false;
            _absolute = false;
            _path = text;
            return true;
        }

        if (kind == UriKind.Relative)
            return false;

        _absolute = true;
        _scheme = text.Substring(0u, (nuint)colon).ToLowerAscii();
        String rest = text.Substring((nuint)colon + 1u);

        if (rest.StartsWith("//"))
        {
            _hasAuthority = true;
            rest = rest.Substring(2u);
            long authorityEnd = FirstOf(rest, "/?#");
            String authority = authorityEnd < 0 ? rest : rest.Substring(0u, (nuint)authorityEnd);
            rest = authorityEnd < 0 ? "" : rest.Substring((nuint)authorityEnd);
            if (!ReadAuthority(authority))
                return false;
        }

        long hash = rest.IndexOf('#');
        if (hash >= 0)
        {
            _fragment = Escaped(rest.Substring((nuint)hash));
            rest = rest.Substring(0u, (nuint)hash);
        }

        long question = rest.IndexOf('?');
        if (question >= 0)
        {
            _query = Escaped(rest.Substring((nuint)question));
            rest = rest.Substring(0u, (nuint)question);
        }

        // A path that names a hierarchy uses `/`, whichever way it was written.
        if (_hasAuthority)
            rest = rest.Replace("\\", "/");
        _path = Escaped(_hasAuthority ? RemoveDotSegments(rest) : rest);
        if (_hasAuthority && _path.IsEmpty)
            _path = "/";
        return true;
    }

    /// `user@host:port`, into its three parts.
    bool ReadAuthority(String authority)
    {
        long at = authority.LastIndexOf('@');
        if (at >= 0)
        {
            _userInfo = authority.Substring(0u, (nuint)at);
            authority = authority.Substring((nuint)at + 1u);
        }

        // An IPv6 address is bracketed, and has colons of its own.
        long portColon = authority.LastIndexOf(':');
        long bracket = authority.LastIndexOf(']');
        if (portColon >= 0 && portColon > bracket)
        {
            String digits = authority.Substring((nuint)portColon + 1u);
            authority = authority.Substring(0u, (nuint)portColon);
            if (!digits.IsEmpty)
            {
                if (ParseDecimal(digits) is not Ok port || port.Value > 65535)
                    return false;
                _port = port.Value;
            }
        }

        _host = authority.ToLowerAscii();
        if (_port == DefaultPort(_scheme))
            _port = -1;
        return !_host.Contains(' ');
    }

    /// `C:\dir\file.txt` and `\\server\share\file.txt` as the `file:` URIs they
    /// name, as C# reads them.
    static Optional<String> WindowsPathAsUri(String text)
    {
        nuint length = text.ByteLength();
        if (length >= 2u && IsLetter(text.GetByteAt(0u)) && text.GetByteAt(1u) == (byte)':' &&
            (length == 2u || text.GetByteAt(2u) == (byte)'\\' || text.GetByteAt(2u) == (byte)'/'))
            return Some("file:///" + text.Replace("\\", "/"));

        if (text.StartsWith("\\\\"))
            return Some("file:" + text.Replace("\\", "/"));

        return None;
    }

    /// Where the first of `characters` is in `text`, or -1.
    static long FirstOf(String text, String characters)
    {
        for (nuint i = 0u; i < text.ByteLength(); i++)
        {
            if (characters.Contains((char)text.GetByteAt(i)))
                return (long)i;
        }
        return -1;
    }

    // -------------------------------------------------------------- resolving

    /// RFC 3986 section 5.2.2: `reference` read against `baseUri`.
    void Resolve(Uri baseUri, Uri reference)
    {
        _absolute = true;

        if (reference._absolute)
        {
            CopyFrom(reference);
            _path = RemoveDotSegments(reference._path);
            return;
        }

        // A relative reference is read into its parts first.
        String rest = reference._original;
        String refFragment = "";
        String refQuery = "";
        long hash = rest.IndexOf('#');
        if (hash >= 0)
        {
            refFragment = Escaped(rest.Substring((nuint)hash));
            rest = rest.Substring(0u, (nuint)hash);
        }
        long question = rest.IndexOf('?');
        bool hasQuery = question >= 0;
        if (hasQuery)
        {
            refQuery = Escaped(rest.Substring((nuint)question));
            rest = rest.Substring(0u, (nuint)question);
        }
        rest = rest.Replace("\\", "/");

        _scheme = baseUri._scheme;
        if (rest.StartsWith("//"))
        {
            var authority = new Uri(_scheme + ":" + rest + refQuery + refFragment, UriKind.Absolute);
            CopyFrom(authority);
            return;
        }

        _hasAuthority = baseUri._hasAuthority;
        _userInfo = baseUri._userInfo;
        _host = baseUri._host;
        _port = baseUri._port;
        _fragment = refFragment;

        if (rest.IsEmpty)
        {
            _path = baseUri._path;
            _query = hasQuery ? refQuery : baseUri._query;
            return;
        }

        _query = refQuery;
        if (rest.StartsWith("/"))
        {
            _path = Escaped(RemoveDotSegments(rest));
            return;
        }

        // RFC 3986 section 5.2.3: the base's directory, then the reference.
        long slash = baseUri._path.LastIndexOf('/');
        String directory = slash < 0 ? (_hasAuthority ? "/" : "") : baseUri._path.Substring(0u, (nuint)slash + 1u);
        _path = Escaped(RemoveDotSegments(directory + rest));
    }

    void CopyFrom(Uri other)
    {
        _scheme = other._scheme;
        _hasAuthority = other._hasAuthority;
        _userInfo = other._userInfo;
        _host = other._host;
        _port = other._port;
        _path = other._path;
        _query = other._query;
        _fragment = other._fragment;
    }

    /// RFC 3986 section 5.2.4: `.` and `..` resolved out of a path.
    static String RemoveDotSegments(String path)
    {
        if (path.IsEmpty)
            return path;

        bool rooted = path.StartsWith("/");
        String[] parts = (rooted ? path.Substring(1u) : path).Split('/');
        var kept = new List<String>();
        bool endsInDirectory = false;

        foreach (var part in parts)
        {
            endsInDirectory = part == "." || part == "..";
            if (part == ".")
                continue;
            if (part == "..")
            {
                if (kept.Count > 0u)
                    kept.RemoveAt(kept.Count - 1u);
                continue;
            }
            kept.Add(part);
        }

        String joined = "/".Join(ToArray(kept));
        if (endsInDirectory && !kept.IsEmpty)
            joined += "/";
        return (rooted ? "/" : "") + joined;
    }

    // --------------------------------------------------------------- escaping

    /// `text` with every byte that may not appear in a URI escaped, and every
    /// `%` that does not begin an escape escaped too.
    static String Escaped(String text)
    {
        var escaped = new StringBuilder();
        for (nuint i = 0u; i < text.ByteLength(); i++)
        {
            byte c = text.GetByteAt(i);
            bool beginsEscape = c == (byte)'%' && i + 2u < text.ByteLength() &&
                                HexValue(text.GetByteAt(i + 1u)) >= 0 && HexValue(text.GetByteAt(i + 2u)) >= 0;
            if ((c == (byte)'%' && !beginsEscape) || c <= (byte)' ' || c >= 0x7F ||
                "\"<>\\^`{|}".Contains((char)c))
                AppendEscape(escaped, c);
            else
                escaped.AppendByte(c);
        }
        return escaped.ToText();
    }

    /// `text` with everything but letters, digits and `-._~` escaped, as a
    /// query value or a path segment needs.
    public static String EscapeDataString(String text)
    {
        var escaped = new StringBuilder();
        for (nuint i = 0u; i < text.ByteLength(); i++)
        {
            byte c = text.GetByteAt(i);
            if (IsLetter(c) || IsDigit(c) || c == (byte)'-' || c == (byte)'.' || c == (byte)'_' || c == (byte)'~')
                escaped.AppendByte(c);
            else
                AppendEscape(escaped, c);
        }
        return escaped.ToText();
    }

    /// `text` with every `%XX` replaced by the byte it stands for.
    public static String UnescapeDataString(String text)
    {
        var plain = new StringBuilder();
        nuint i = 0u;
        while (i < text.ByteLength())
        {
            byte c = text.GetByteAt(i);
            if (c == (byte)'%' && i + 2u < text.ByteLength())
            {
                int high = HexValue(text.GetByteAt(i + 1u));
                int low = HexValue(text.GetByteAt(i + 2u));
                if (high >= 0 && low >= 0)
                {
                    plain.AppendByte((byte)((high << 4) | low));
                    i += 3u;
                    continue;
                }
            }
            plain.AppendByte(c);
            i++;
        }
        return plain.ToText();
    }

    static void AppendEscape(StringBuilder text, byte c)
    {
        text.Append("%");
        text.Append("0123456789ABCDEF".Substring((nuint)(c >> 4), 1u));
        text.Append("0123456789ABCDEF".Substring((nuint)(c & 0x0F), 1u));
    }

    static int HexValue(byte digit)
    {
        if (IsDigit(digit))
            return digit - (byte)'0';
        if (digit >= (byte)'a' && digit <= (byte)'f')
            return digit - (byte)'a' + 10;
        if (digit >= (byte)'A' && digit <= (byte)'F')
            return digit - (byte)'A' + 10;
        return -1;
    }

    // ------------------------------------------------------------------ parts

    /// Aborts on a relative URI, which has none of what follows.
    void RequireAbsolute(String member)
    {
        if (!_absolute)
            sl_fail(("Uri." + member + ": the URI is relative").ToPointer());
    }

    /// Whether it names a scheme.
    public bool IsAbsoluteUri => _absolute;

    /// What it was made from, unchanged.
    public String OriginalString => _original;

    /// `https`, in lower case.
    public String Scheme
    {
        get
        {
            RequireAbsolute("Scheme");
            return _scheme;
        }
    }

    /// What came before an `@` in the authority, or "".
    public String UserInfo
    {
        get
        {
            RequireAbsolute("UserInfo");
            return _userInfo;
        }
    }

    /// The host, in lower case, bracketed when it is an IPv6 address.
    public String Host
    {
        get
        {
            RequireAbsolute("Host");
            return _host;
        }
    }

    /// The port, the scheme's default when none was written, and -1 when the
    /// scheme has none.
    public int Port
    {
        get
        {
            RequireAbsolute("Port");
            return _port >= 0 ? _port : DefaultPort(_scheme);
        }
    }

    /// Whether the port is the one the scheme means anyway.
    public bool IsDefaultPort
    {
        get
        {
            RequireAbsolute("IsDefaultPort");
            return _port < 0;
        }
    }

    /// The host, and the port when it is not the default.
    public String Authority
    {
        get
        {
            RequireAbsolute("Authority");
            return _port < 0 ? _host : _host + ":" + Text.FromInteger((long)_port);
        }
    }

    /// The path, escaped, `/` when an authority was given with none.
    public String AbsolutePath
    {
        get
        {
            RequireAbsolute("AbsolutePath");
            return _path;
        }
    }

    /// `?` and what follows it up to the fragment, or "".
    public String Query
    {
        get
        {
            RequireAbsolute("Query");
            return _query;
        }
    }

    /// `#` and what follows it, or "".
    public String Fragment
    {
        get
        {
            RequireAbsolute("Fragment");
            return _fragment;
        }
    }

    /// The path and the query.
    public String PathAndQuery
    {
        get
        {
            RequireAbsolute("PathAndQuery");
            return _path + _query;
        }
    }

    /// The whole of it, in normal form.
    public String AbsoluteUri
    {
        get
        {
            RequireAbsolute("AbsoluteUri");
            return GetLeftPart(UriPartial.Query) + _fragment;
        }
    }

    /// The path's segments, each with the `/` that ends it: `/a/b` is `/`,
    /// `a/` and `b`.
    public String[] Segments
    {
        get
        {
            RequireAbsolute("Segments");
            var segments = new List<String>();
            nuint start = 0u;
            for (nuint i = 0u; i < _path.ByteLength(); i++)
            {
                if (_path.GetByteAt(i) != (byte)'/')
                    continue;
                segments.Add(_path.Substring(start, i + 1u - start));
                start = i + 1u;
            }
            if (start < _path.ByteLength())
                segments.Add(_path.Substring(start));
            return ToArray(segments);
        }
    }

    /// Whether the scheme is `file`.
    public bool IsFile
    {
        get
        {
            RequireAbsolute("IsFile");
            return _scheme == UriSchemeFile;
        }
    }

    /// Whether it is a `file:` URI naming a machine, as a UNC path does.
    public bool IsUnc
    {
        get
        {
            RequireAbsolute("IsUnc");
            return _scheme == UriSchemeFile && !_host.IsEmpty && _host != "localhost";
        }
    }

    /// Whether the host is this machine.
    public bool IsLoopback
    {
        get
        {
            RequireAbsolute("IsLoopback");
            return _host == "localhost" || _host == "[::1]" || _host.StartsWith("127.") ||
                   (_scheme == UriSchemeFile && _host.IsEmpty);
        }
    }

    /// The path as the operating system writes it, unescaped: a Windows path
    /// or a UNC path for a `file:` URI there, and the path elsewhere.
    public String LocalPath
    {
        get
        {
            RequireAbsolute("LocalPath");
            String path = UnescapeDataString(_path);
            if (_scheme != UriSchemeFile)
                return path;

#if WINDOWS
            if (IsUnc)
                return "\\\\" + _host + path.Replace("/", "\\");
            if (path.ByteLength() >= 3u && path.GetByteAt(2u) == (byte)':')
                path = path.Substring(1u);
            return path.Replace("/", "\\");
#else
            return IsUnc ? "//" + _host + path : path;
#endif
        }
    }

    /// As much of it as `part` says, from the left.
    ///
    /// @param part  up to the scheme, the authority, the path or the query
    public String GetLeftPart(UriPartial part)
    {
        RequireAbsolute("GetLeftPart");

        String text = _scheme + ":" + (_hasAuthority ? "//" : "");
        if (part == UriPartial.Scheme)
            return text;

        if (!_userInfo.IsEmpty)
            text += _userInfo + "@";
        text += Authority;
        if (part == UriPartial.Authority)
            return text;

        text += _path;
        return part == UriPartial.Path ? text : text + _query;
    }

    /// Whether `uri` is at or below where this points: the same scheme and
    /// authority, and a path inside this one's directory.
    ///
    /// @param uri  the URI that may be below this one
    public bool IsBaseOf(Uri uri)
    {
        RequireAbsolute("IsBaseOf");
        var resolved = uri._absolute ? uri : new Uri(this, uri);

        if (_scheme != resolved._scheme || _host != resolved._host || _port != resolved._port ||
            _userInfo != resolved._userInfo)
            return false;

        long slash = _path.LastIndexOf('/');
        String directory = slash < 0 ? "" : _path.Substring(0u, (nuint)slash + 1u);
        return resolved._path.StartsWith(directory);
    }

    /// The relative URI that `uri` is from here: `uri` itself when the two do
    /// not share a scheme and authority.
    ///
    /// @param uri  where the result leads, resolved against this
    public Uri MakeRelativeUri(Uri uri)
    {
        RequireAbsolute("MakeRelativeUri");
        if (_scheme != uri._scheme || _host != uri._host || _port != uri._port || _userInfo != uri._userInfo)
            return uri;

        String[] from = _path.Split('/');
        String[] to = uri._path.Split('/');

        // Only the directories of `from` count: its last part is a file.
        nuint shared = 0u;
        while (shared + 1u < from.Length && shared + 1u < to.Length && from[shared] == to[shared])
            shared++;

        String relative = "";
        for (nuint i = shared; i + 1u < from.Length; i++)
            relative += "../";
        for (nuint i = shared; i < to.Length; i++)
            relative += to[i] + (i + 1u < to.Length ? "/" : "");

        return new Uri(relative + uri._query + uri._fragment, UriKind.Relative);
    }

    /// The whole of it in normal form, or a relative one as it was written.
    public String ToString() => _absolute ? AbsoluteUri : _original;

    /// Whether the two name the same resource: equal in everything but the
    /// fragment and the user, as C# compares them.
    public bool Equals(Uri other)
    {
        if (_absolute != other._absolute)
            return false;
        if (!_absolute)
            return _original == other._original;
        return _scheme == other._scheme && _host == other._host && _port == other._port &&
               _path == other._path && _query == other._query;
    }

    public nuint GetHashCode()
    {
        String key = _absolute ? _scheme + "://" + _host + ":" + Text.FromInteger((long)_port) + _path + _query : _original;
        nuint hash = 0u;
        for (nuint i = 0u; i < key.ByteLength(); i++)
            hash = MixHash(hash, (ulong)key.GetByteAt(i));
        return hash;
    }

    public static bool operator ==(Uri left, Uri right) => left.Equals(right);
    public static bool operator !=(Uri left, Uri right) => !left.Equals(right);
}
