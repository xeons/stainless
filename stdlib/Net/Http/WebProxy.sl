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

import Standard.Text;

/// One HTTP proxy, and the hosts that go around it.
///
///     var handler = new HttpClientHandler();
///     handler.Proxy = new WebProxy("http://proxy.example:3128", true,
///                                  ["*.internal.example", "10.*"]);
///
/// .NET's `System.Net.WebProxy`, with one difference: a `BypassList` entry is
/// a pattern in which `*` stands for any run of characters, matched against
/// the host without regard to case — or against `host:port` when it names a
/// port — rather than a regular expression.
public class WebProxy : IWebProxy
{
    /// No proxy: everything goes direct until `Address` is set.
    public WebProxy() { }

    /// The proxy at `address`, `http://host:port`.
    public WebProxy(String address)
    {
        if (Uri.TryCreate(address, UriKind.Absolute) is Ok parsed)
            Address = parsed.Value;
    }

    /// The proxy at `address`.
    public WebProxy(Uri? address) => Address = address;

    /// The proxy at `address`, bypassed for local hosts when `bypassOnLocal`.
    public WebProxy(String address, bool bypassOnLocal) : this(address) => BypassProxyOnLocal = bypassOnLocal;

    /// The proxy at `address`, bypassed for local hosts when `bypassOnLocal`
    /// and for any host `bypassList` matches.
    public WebProxy(String address, bool bypassOnLocal, String[] bypassList) : this(address)
    {
        BypassProxyOnLocal = bypassOnLocal;
        BypassList = bypassList;
    }

    /// Where the proxy is, or null for none.
    public Uri? Address { get; set; }

    /// Whether a host with no dot in its name, or a loopback address, goes
    /// direct.
    public bool BypassProxyOnLocal { get; set; } = false;

    /// Patterns of hosts that go direct.
    public String[] BypassList { get; set; } = new String[0u];

    /// Sent to the proxy as Basic credentials, when not null.
    public NetworkCredential? Credentials { get; set; }

    /// `Address`, or `destination` itself when it goes direct.
    public Uri? GetProxy(Uri destination)
    {
        if (IsBypassed(destination))
            return destination;
        if (Address is Uri address)
            return address;
        return destination;
    }

    /// Whether `host` goes direct: there is no proxy, it is local and local
    /// hosts go direct, or a pattern matches it.
    public bool IsBypassed(Uri host)
    {
        if (Address == null)
            return true;
        String name = GetHttpBareHost(host).ToLowerAscii();
        if (BypassProxyOnLocal && (!name.Contains('.') || IsHttpLoopbackHost(name)))
            return true;
        String withPort = name + ":" + Text.FromInteger((long)host.Port);
        foreach (var pattern in BypassList)
        {
            String lowered = pattern.ToLowerAscii();
            if (MatchesHttpWildcard(lowered.Contains(':') ? withPort : name, lowered))
                return true;
        }
        return false;
    }
}

/// Whether `text` matches `pattern`, in which `*` is any run of characters.
internal bool MatchesHttpWildcard(String text, String pattern)
{
    nuint textLength = text.ByteLength();
    nuint patternLength = pattern.ByteLength();
    nuint t = 0u;
    nuint p = 0u;
    bool starred = false;
    nuint starAt = 0u;
    nuint resumeAt = 0u;
    while (t < textLength)
    {
        if (p < patternLength && pattern.GetByteAt(p) == (byte)'*')
        {
            starred = true;
            starAt = p;
            resumeAt = t;
            p++;
        }
        else if (p < patternLength && pattern.GetByteAt(p) == text.GetByteAt(t))
        {
            p++;
            t++;
        }
        else if (starred)
        {
            p = starAt + 1u;
            resumeAt++;
            t = resumeAt;
        }
        else
        {
            return false;
        }
    }
    while (p < patternLength && pattern.GetByteAt(p) == (byte)'*')
        p++;
    return p == patternLength;
}

/// Whether a lower-case bare host is this machine: `localhost`, 127/8 or
/// `::1`.
internal bool IsHttpLoopbackHost(String host) =>
    host == "localhost" || host.EndsWith(".localhost") || host.StartsWith("127.") || host == "::1";
