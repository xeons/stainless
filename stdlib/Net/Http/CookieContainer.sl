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

module Standard.Net.Http;

import Standard.Collections;
import Standard.Text;
import Standard.Threading;
import Standard.Time;

/// The cookies a client has been given, and the rules for which it sends
/// where: RFC 6265.
///
///     var cookies = new CookieContainer();
///     cookies.SetCookies(uri, "id=a3fWa; Path=/; Secure; Max-Age=3600");
///     String header = cookies.GetCookieHeader(uri);        // id=a3fWa
///
/// **A cookie belongs to a host, or to a domain.** Without `Domain` it is
/// sent back only to the host that set it; with one it is sent to that domain
/// and every host below it, and a host may only name a domain it is itself
/// in. A domain that is a public suffix — one under which unrelated parties
/// register names, as `com` or `co.uk` — is refused, so that one site cannot
/// set a cookie for all of them. **The list of public suffixes here is
/// short**: every single-label name, and a few dozen well-known multi-label
/// ones. It is not the Public Suffix List, and a cookie for a suffix it lacks
/// is accepted.
///
/// **`Path` limits a cookie to part of a site**, `Secure` to https,
/// and `Expires` or `Max-Age` to a time. A cookie set from http cannot be
/// `Secure`. `HttpOnly` and `SameSite` are kept and not acted on.
///
/// One container MAY be shared by several clients and threads.
public sealed class CookieContainer
{
    private List<Cookie> _cookies = new List<Cookie>();
    private Mutex<int> _lock = new Mutex<int>(0);

    /// An empty container.
    public CookieContainer() { }

    /// How many cookies it holds, expired ones included until next looked at.
    public nuint Count
    {
        get
        {
            var held = _lock.Enter();
            return _cookies.Count;
        }
    }

    /// The most bytes a cookie's name and value may take together.
    public nuint MaxCookieSize { get; set; } = 4096u;

    /// Stores `cookie`, which MUST name its `Domain`, replacing one of the
    /// same name, domain and path. False when it names no domain or no name,
    /// or has already expired.
    public bool Add(Cookie cookie)
    {
        if (cookie.Name.IsEmpty || cookie.Domain.IsEmpty)
            return false;
        String domain = cookie.Domain.ToLowerAscii();
        if (domain.StartsWith("."))
            domain = domain.Substring(1u);
        cookie.Domain = domain;
        if (cookie.Path.IsEmpty)
            cookie.Path = "/";
        return StoreHttpCookie(cookie, DateTimeOffset.UtcNow);
    }

    /// Stores `cookie` as though `uri` had set it: its domain, if it names
    /// one, MUST contain `uri`'s host, and it defaults to that host and to the
    /// directory of `uri`'s path. False when it is refused.
    public bool Add(Uri uri, Cookie cookie)
    {
        if (cookie.Name.IsEmpty)
            return false;
        return AdmitHttpCookie(uri, cookie, cookie.Domain, cookie.Path, DateTimeOffset.UtcNow);
    }

    /// The cookies that would be sent to `uri`, longest path first.
    public List<Cookie> GetCookies(Uri uri) => SelectHttpCookies(uri, DateTimeOffset.UtcNow);

    /// Every cookie held that has not expired.
    public List<Cookie> GetAllCookies()
    {
        var now = DateTimeOffset.UtcNow;
        var held = _lock.Enter();
        RemoveExpiredHttpCookies(now);
        var all = new List<Cookie>();
        foreach (var cookie in _cookies)
            all.Add(cookie);
        return all;
    }

    /// What a request to `uri` sends as its `Cookie` field: `a=1; b=2`, or
    /// empty when nothing applies.
    public String GetCookieHeader(Uri uri)
    {
        var text = new StringBuilder();
        foreach (var cookie in GetCookies(uri))
        {
            if (!text.IsEmpty)
                text.Append("; ");
            text.Append(cookie.Name);
            text.Append("=");
            text.Append(cookie.Value);
        }
        return text.ToText();
    }

    /// Stores the cookies in `cookieHeader` as `uri` set them: one
    /// `Set-Cookie` value, or several separated by commas, as .NET's takes
    /// them. A comma inside an `Expires` date does not separate. Answers how
    /// many are held afterwards: a malformed or refused one is skipped, and an
    /// expired one only removes what it names.
    public nuint SetCookies(Uri uri, String cookieHeader)
    {
        nuint stored = 0u;
        var now = DateTimeOffset.UtcNow;
        foreach (var one in SplitHttpSetCookieList(cookieHeader))
        {
            if (StoreHttpSetCookie(uri, one, now))
                stored++;
        }
        return stored;
    }

    /// Stores one `Set-Cookie` value, received from `uri` at `now`, by RFC
    /// 6265 §5.2 and §5.3. False when it is ignored.
    internal bool StoreHttpSetCookie(Uri uri, String header, DateTimeOffset now)
    {
        String[] parts = header.Split(';');
        String pair = parts[0u];
        long equals = pair.IndexOf('=');
        if (equals < 0)
            return false;
        String name = TrimHttpWhitespace(pair.Substring(0u, (nuint)equals));
        String value = TrimHttpWhitespace(pair.Substring((nuint)equals + 1u));
        if (name.IsEmpty || !IsHttpCookieText(name) || !IsHttpCookieText(value))
            return false;
        if (name.ByteLength() + value.ByteLength() > MaxCookieSize)
            return false;

        var cookie = new Cookie(name, value);
        String domain = "";
        String path = "";
        bool hasMaxAge = false;
        for (nuint i = 1u; i < parts.Length; i++)
        {
            String setting = TrimHttpWhitespace(parts[i]);
            long settingEquals = setting.IndexOf('=');
            String key = TrimHttpWhitespace(settingEquals < 0 ? setting
                                                                : setting.Substring(0u, (nuint)settingEquals));
            String argument = settingEquals < 0 ? "" : TrimHttpWhitespace(setting.Substring((nuint)settingEquals + 1u));
            switch (key.ToLowerAscii())
            {
                case "expires":
                    if (!hasMaxAge && ParseHttpCookieDate(argument) is Ok expires)
                        cookie.Expires = expires.Value;
                    break;
                case "max-age":
                    if (TryParseHttpCookieMaxAge(argument, out long seconds))
                    {
                        hasMaxAge = true;
                        cookie.Expires = seconds <= 0 ? DateTimeOffset.UnixEpoch
                                                      : now + TimeSpan.FromSeconds(seconds);
                    }
                    break;
                case "domain":
                    if (!argument.IsEmpty)
                        domain = argument;
                    break;
                case "path":
                    path = argument;
                    break;
                case "secure":
                    cookie.Secure = true;
                    break;
                case "httponly":
                    cookie.HttpOnly = true;
                    break;
                case "samesite":
                    cookie.SameSite = argument;
                    break;
            }
        }
        return AdmitHttpCookie(uri, cookie, domain, path, now);
    }

    /// The cookies to send to `uri` at `now`, in RFC 6265 §5.4's order.
    internal List<Cookie> SelectHttpCookies(Uri uri, DateTimeOffset now)
    {
        String host = GetHttpBareHost(uri).ToLowerAscii();
        String path = uri.AbsolutePath;
        bool secure = uri.Scheme == "https" || uri.Scheme == "wss";
        var chosen = new List<Cookie>();
        {
            var held = _lock.Enter();
            RemoveExpiredHttpCookies(now);
            foreach (var cookie in _cookies)
            {
                bool hostMatches = cookie.IsHostOnly ? host == cookie.Domain : IsHttpDomainMatch(host, cookie.Domain);
                if (!hostMatches || !IsHttpPathMatch(path, cookie.Path))
                    continue;
                if (cookie.Secure && !secure)
                    continue;
                chosen.Add(cookie);
            }
        }
        SortHttpCookiesForSending(chosen);
        return chosen;
    }

    /// Applies §5.3 to a parsed cookie: its domain, its path, whether its
    /// origin may set it, and whether it replaces or removes one held.
    private bool AdmitHttpCookie(Uri uri, Cookie cookie, String domainAttribute, String pathAttribute,
                                 DateTimeOffset now)
    {
        String host = GetHttpBareHost(uri).ToLowerAscii();
        if (host.IsEmpty)
            return false;

        String domain = domainAttribute.ToLowerAscii();
        if (domain.StartsWith("."))
            domain = domain.Substring(1u);
        if (!domain.IsEmpty && IsHttpPublicSuffix(domain))
        {
            if (domain != host)
                return false;
            domain = "";
        }
        if (domain.IsEmpty)
        {
            cookie.IsHostOnly = true;
            cookie.Domain = host;
        }
        else
        {
            if (!IsHttpDomainMatch(host, domain))
                return false;
            cookie.IsHostOnly = false;
            cookie.Domain = domain;
        }

        cookie.Path = pathAttribute.StartsWith("/") ? pathAttribute : GetHttpDefaultCookiePath(uri.AbsolutePath);

        bool secureOrigin = uri.Scheme == "https" || uri.Scheme == "wss";
        if (cookie.Secure && !secureOrigin)
            return false;

        cookie.TimeStamp = now;
        return StoreHttpCookie(cookie, now);
    }

    /// Replaces the cookie of the same name, domain and path in its place,
    /// keeping when that one was first stored; or, for a cookie already
    /// expired, removes it and stores nothing. Answers whether it is held now.
    ///
    /// The list is in the order cookies were first stored, which is what
    /// breaks a tie between two stored within one tick of the clock.
    private bool StoreHttpCookie(Cookie cookie, DateTimeOffset now)
    {
        var held = _lock.Enter();
        bool expired = cookie.HasExpiredAt(now);
        for (nuint i = 0u; i < _cookies.Count; i++)
        {
            Cookie existing = _cookies[i];
            if (existing.Name == cookie.Name && existing.Domain == cookie.Domain &&
                existing.Path == cookie.Path)
            {
                if (expired)
                {
                    _cookies.RemoveAt(i);
                    return false;
                }
                cookie.TimeStamp = existing.TimeStamp;
                _cookies[i] = cookie;
                return true;
            }
        }
        if (expired)
            return false;
        _cookies.Add(cookie);
        return true;
    }

    /// The caller holds the lock.
    private void RemoveExpiredHttpCookies(DateTimeOffset now)
    {
        nuint i = _cookies.Count;
        while (i > 0u)
        {
            i--;
            if (_cookies[i].HasExpiredAt(now))
                _cookies.RemoveAt(i);
        }
    }
}

/// Longer paths first, and among equal paths the one stored first.
internal void SortHttpCookiesForSending(List<Cookie> cookies)
{
    for (nuint i = 1u; i < cookies.Count; i++)
    {
        Cookie moving = cookies[i];
        nuint j = i;
        while (j > 0u && ComesBeforeHttpCookie(moving, cookies[j - 1u]))
        {
            cookies[j] = cookies[j - 1u];
            j--;
        }
        cookies[j] = moving;
    }
}

internal bool ComesBeforeHttpCookie(Cookie first, Cookie second)
{
    nuint firstLength = first.Path.ByteLength();
    nuint secondLength = second.Path.ByteLength();
    if (firstLength != secondLength)
        return firstLength > secondLength;
    return first.TimeStamp < second.TimeStamp;
}

/// Whether a cookie name or value holds only what a `Cookie` field can carry:
/// no control characters, and no `;`.
internal bool IsHttpCookieText(String text)
{
    for (nuint i = 0u; i < text.ByteLength(); i++)
    {
        byte c = text.GetByteAt(i);
        if (c < 0x20 || c == 0x7F || c == (byte)';')
            return false;
    }
    return true;
}

/// `Max-Age`: an optional `-`, then digits, in seconds.
internal bool TryParseHttpCookieMaxAge(String text, out long seconds)
{
    seconds = 0;
    if (text.StartsWith("-"))
    {
        if (!TryParseHttpDecimal(text.Substring(1u), out long negative))
            return false;
        seconds = -negative;
        return true;
    }
    if (TryParseHttpDecimal(text, out long positive))
    {
        seconds = positive;
        return true;
    }
    // A delta too large for a long is still a real one: as long as can be.
    if (text.ByteLength() > 18u && IsHttpDigits(text))
    {
        seconds = 315360000000;
        return true;
    }
    return false;
}

internal bool IsHttpDigits(String text)
{
    if (text.IsEmpty)
        return false;
    for (nuint i = 0u; i < text.ByteLength(); i++)
    {
        byte c = text.GetByteAt(i);
        if (c < (byte)'0' || c > (byte)'9')
            return false;
    }
    return true;
}

/// RFC 6265 §5.1.3: `host` is `domain`, or a name under it. An IP address
/// matches only itself.
internal bool IsHttpDomainMatch(String host, String domain)
{
    if (host == domain)
        return true;
    if (!host.EndsWith("." + domain))
        return false;
    return !host.Contains(':') && !TryParseHttpIPv4(host, out uint address);
}

/// RFC 6265 §5.1.4: `requestPath` is `cookiePath` or below it.
internal bool IsHttpPathMatch(String requestPath, String cookiePath)
{
    if (requestPath == cookiePath)
        return true;
    if (!requestPath.StartsWith(cookiePath))
        return false;
    return cookiePath.EndsWith("/") || requestPath.GetByteAt(cookiePath.ByteLength()) == (byte)'/';
}

/// RFC 6265 §5.1.4: the directory of a request path, which a cookie without
/// `Path` is sent under.
internal String GetHttpDefaultCookiePath(String requestPath)
{
    if (!requestPath.StartsWith("/"))
        return "/";
    long slash = requestPath.LastIndexOf('/');
    if (slash <= 0)
        return "/";
    return requestPath.Substring(0u, (nuint)slash);
}

/// Whether unrelated parties register names directly under `domain`, so that
/// a cookie for all of it is refused. Every single-label name is; of longer
/// ones, only a short built-in list.
internal bool IsHttpPublicSuffix(String domain)
{
    if (!domain.Contains('.'))
        return true;
    switch (domain)
    {
        case "co.uk":
        case "org.uk":
        case "me.uk":
        case "ltd.uk":
        case "plc.uk":
        case "net.uk":
        case "ac.uk":
        case "gov.uk":
        case "sch.uk":
        case "nhs.uk":
        case "co.jp":
        case "ne.jp":
        case "or.jp":
        case "ac.jp":
        case "go.jp":
        case "com.au":
        case "net.au":
        case "org.au":
        case "edu.au":
        case "gov.au":
        case "co.nz":
        case "net.nz":
        case "org.nz":
        case "com.br":
        case "net.br":
        case "org.br":
        case "com.cn":
        case "net.cn":
        case "org.cn":
        case "gov.cn":
        case "co.in":
        case "net.in":
        case "org.in":
        case "co.za":
        case "com.mx":
        case "com.tr":
        case "co.kr":
        case "com.tw":
        case "com.hk":
        case "com.sg":
        case "github.io":
        case "gitlab.io":
        case "blogspot.com":
        case "herokuapp.com":
        case "appspot.com":
        case "azurewebsites.net":
        case "cloudfront.net":
        case "netlify.app":
        case "vercel.app":
        case "pages.dev":
        case "workers.dev":
            return true;
    }
    return false;
}

/// Splits a list of `Set-Cookie` values at the commas between them, leaving
/// the comma after the weekday of an `Expires` date alone.
internal List<String> SplitHttpSetCookieList(String header)
{
    var parts = new List<String>();
    nuint length = header.ByteLength();
    nuint start = 0u;
    for (nuint i = 0u; i < length; i++)
    {
        if (header.GetByteAt(i) != (byte)',')
            continue;
        if (IsHttpExpiresWeekdayComma(header, start, i))
            continue;
        String part = TrimHttpWhitespace(header.Substring(start, i - start));
        if (!part.IsEmpty)
            parts.Add(part);
        start = i + 1u;
    }
    String last = TrimHttpWhitespace(header.Substring(start));
    if (!last.IsEmpty)
        parts.Add(last);
    return parts;
}

/// Whether the comma at `comma` follows `expires=` and a weekday's name.
internal bool IsHttpExpiresWeekdayComma(String header, nuint start, nuint comma)
{
    String before = header.Substring(start, comma - start).ToLowerAscii();
    long semicolon = before.LastIndexOf(';');
    String setting = TrimHttpWhitespace(semicolon < 0 ? before : before.Substring((nuint)semicolon + 1u));
    if (!setting.StartsWith("expires"))
        return false;
    long equals = setting.IndexOf('=');
    if (equals < 0)
        return false;
    String value = TrimHttpWhitespace(setting.Substring((nuint)equals + 1u));
    if (value.IsEmpty)
        return false;
    for (nuint i = 0u; i < value.ByteLength(); i++)
    {
        byte c = value.GetByteAt(i);
        if (c < (byte)'a' || c > (byte)'z')
            return false;
    }
    return true;
}

/// RFC 6265 §5.1.1's date: the forgiving reading of `Expires`, which finds a
/// time, a day, a month and a year among whatever else is there.
internal Result<DateTimeOffset, TimeError> ParseHttpCookieDate(String text)
{
    int hour = -1;
    int minute = -1;
    int second = -1;
    int day = -1;
    int month = -1;
    int year = -1;

    foreach (var token in SplitHttpCookieDateTokens(text))
    {
        if (hour < 0 && TryParseHttpCookieTime(token, out int h, out int m, out int s))
        {
            hour = h;
            minute = m;
            second = s;
            continue;
        }
        if (day < 0 && ReadHttpLeadingDigits(token, 1u, 2u, out int dayValue))
        {
            day = dayValue;
            continue;
        }
        if (month < 0 && token.ByteLength() >= 3u)
        {
            int named = FindHttpCookieMonth(token.Substring(0u, 3u).ToLowerAscii());
            if (named > 0)
            {
                month = named;
                continue;
            }
        }
        if (year < 0 && ReadHttpLeadingDigits(token, 2u, 4u, out int yearValue))
        {
            year = yearValue;
            continue;
        }
    }

    if (hour < 0 || day < 0 || month < 0 || year < 0)
        return Fail(TimeError.Malformed);
    if (year >= 70 && year <= 99)
        year += 1900;
    else if (year >= 0 && year <= 69)
        year += 2000;
    if (day < 1 || day > 31 || year < 1601 || hour > 23 || minute > 59 || second > 59)
        return Fail(TimeError.OutOfRange);
    if (day > DaysInMonth(year, month))
        return Fail(TimeError.OutOfRange);
    return Ok(DateTimeOffset.FromUtc(year, month, day, hour, minute, second));
}

/// The date's tokens, split at RFC 6265's delimiters.
internal List<String> SplitHttpCookieDateTokens(String text)
{
    var tokens = new List<String>();
    nuint length = text.ByteLength();
    nuint start = 0u;
    for (nuint i = 0u; i <= length; i++)
    {
        if (i < length && !IsHttpCookieDateDelimiter(text.GetByteAt(i)))
            continue;
        if (i > start)
            tokens.Add(text.Substring(start, i - start));
        start = i + 1u;
    }
    return tokens;
}

internal bool IsHttpCookieDateDelimiter(byte c) =>
    c == 0x09 || (c >= 0x20 && c <= 0x2F) || (c >= 0x3B && c <= 0x40) ||
    (c >= 0x5B && c <= 0x60) || (c >= 0x7B && c <= 0x7E);

/// `min` to `max` digits at the start of `token`, followed by anything that
/// is not a digit.
internal bool ReadHttpLeadingDigits(String token, nuint min, nuint max, out int value)
{
    value = 0;
    nuint count = 0u;
    while (count < token.ByteLength())
    {
        byte c = token.GetByteAt(count);
        if (c < (byte)'0' || c > (byte)'9')
            break;
        value = value * 10 + (int)(c - (byte)'0');
        count++;
        if (count > max)
            return false;
    }
    return count >= min;
}

/// `h:m:s`, each one or two digits, followed by anything that is not a
/// digit.
internal bool TryParseHttpCookieTime(String token, out int hour, out int minute, out int second)
{
    hour = 0;
    minute = 0;
    second = 0;
    String[] fields = token.Split(':');
    if (fields.Length != 3u)
        return false;
    if (!IsHttpDigits(fields[0u]) || !IsHttpDigits(fields[1u]))
        return false;
    if (fields[0u].ByteLength() > 2u || fields[1u].ByteLength() > 2u)
        return false;
    if (!ReadHttpLeadingDigits(fields[2u], 1u, 2u, out int s))
        return false;
    hour = ParseHttpSmallNumber(fields[0u]);
    minute = ParseHttpSmallNumber(fields[1u]);
    second = s;
    return true;
}

internal int ParseHttpSmallNumber(String digits)
{
    int value = 0;
    for (nuint i = 0u; i < digits.ByteLength(); i++)
        value = value * 10 + (int)(digits.GetByteAt(i) - (byte)'0');
    return value;
}

internal int FindHttpCookieMonth(String name)
{
    switch (name)
    {
        case "jan": return 1;
        case "feb": return 2;
        case "mar": return 3;
        case "apr": return 4;
        case "may": return 5;
        case "jun": return 6;
        case "jul": return 7;
        case "aug": return 8;
        case "sep": return 9;
        case "oct": return 10;
        case "nov": return 11;
        case "dec": return 12;
    }
    return 0;
}
