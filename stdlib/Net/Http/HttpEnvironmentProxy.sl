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
import Standard.Env;
import Standard.Text;

/// Reads an environment variable: its value, or null when it is not set.
public closure String? HttpEnvironmentVariableReader(String name);

/// The proxy the environment names, as curl reads it.
///
///     http_proxy=http://proxy.example:3128
///     https_proxy=http://user:secret@proxy.example:3128
///     no_proxy=localhost,.internal.example,10.0.0.0/8,example.com:8080
///
/// **Each variable is read in lower case first and upper case second**, as
/// curl reads them: `http_proxy` for http requests, `https_proxy` for https,
/// `all_proxy` for either when its own is unset, and `no_proxy` for the
/// exceptions. Upper-case `HTTP_PROXY` is ignored when `REQUEST_METHOD` is
/// set, because a CGI program finds a request's `Proxy` header there
/// ("httpoxy"). Names are matched with their case exactly, on Windows too,
/// where the environment itself would answer `http_proxy` with `HTTP_PROXY`.
/// A value without a scheme is taken as `http://`; one naming any
/// other scheme is ignored, since only HTTP proxies are spoken to.
///
/// **`no_proxy`** is a comma-separated list: `*` for everything; a domain,
/// which matches itself and every name below it, with or without a leading
/// `.` or `*.`; an IP address, matched exactly, or an IPv4 range as
/// `10.0.0.0/8`; any of them with `:port` to match that port alone.
///
/// **A loopback destination always goes direct** — `localhost`, 127/8, `::1`
/// — since no proxy elsewhere can reach this machine's loopback.
public sealed class HttpEnvironmentProxy : IWebProxy
{
    private Uri? _httpProxy;
    private Uri? _httpsProxy;
    private List<HttpNoProxyRule> _exceptions = new List<HttpNoProxyRule>();
    private bool _bypassAll = false;

    private HttpEnvironmentProxy() { }

    /// The proxy this process's environment names, or null when it names
    /// none.
    public static IWebProxy? FromEnvironment()
    {
        String[] names = Env.GetEnvironmentVariableNames();
        return FromEnvironment((name) => ReadHttpEnvironmentVariableExactly(names, name));
    }

    /// The proxy the variables `read` answers name, or null when they name
    /// none.
    public static IWebProxy? FromEnvironment(HttpEnvironmentVariableReader read)
    {
        var proxy = new HttpEnvironmentProxy();
        bool isCgi = IsHttpVariableSet(read("REQUEST_METHOD"));

        String? all = ReadHttpProxyVariable(read, "all_proxy", "ALL_PROXY", false);
        String? http = ReadHttpProxyVariable(read, "http_proxy", "HTTP_PROXY", isCgi);
        String? https = ReadHttpProxyVariable(read, "https_proxy", "HTTPS_PROXY", false);
        proxy._httpProxy = ParseHttpProxyAddress(http == null ? all : http);
        proxy._httpsProxy = ParseHttpProxyAddress(https == null ? all : https);
        if (proxy._httpProxy == null && proxy._httpsProxy == null)
            return null;

        String? exceptions = ReadHttpProxyVariable(read, "no_proxy", "NO_PROXY", false);
        if (exceptions != null)
            proxy.ParseHttpNoProxyList(exceptions);
        return proxy;
    }

    /// The proxy for http requests, or null.
    public Uri? HttpProxy => _httpProxy;

    /// The proxy for https requests, or null.
    public Uri? HttpsProxy => _httpsProxy;

    /// The credentials in the proxy URI's user information, when it had any.
    public NetworkCredential? Credentials { get; set; }

    public Uri? GetProxy(Uri destination)
    {
        if (IsBypassed(destination))
            return null;
        return destination.Scheme == "https" ? _httpsProxy : _httpProxy;
    }

    public bool IsBypassed(Uri host)
    {
        String name = GetHttpBareHost(host).ToLowerAscii();
        if (_bypassAll || IsHttpLoopbackHost(name))
            return true;
        int port = host.Port;
        foreach (var rule in _exceptions)
        {
            if (rule.MatchesHttpHost(name, port))
                return true;
        }
        return false;
    }

    private void ParseHttpNoProxyList(String list)
    {
        foreach (var entry in list.Split(','))
        {
            String trimmed = entry.Trim().ToLowerAscii();
            if (trimmed.IsEmpty)
                continue;
            if (trimmed == "*")
            {
                _bypassAll = true;
                continue;
            }
            _exceptions.Add(new HttpNoProxyRule(trimmed));
        }
    }
}

/// A variable's value, lower-case name first. Empty counts as unset.
internal String? ReadHttpProxyVariable(HttpEnvironmentVariableReader read, String lower, String upper,
                                       bool ignoreUpper)
{
    String? value = read(lower);
    if (IsHttpVariableSet(value))
        return value;
    if (ignoreUpper)
        return null;
    String? fallback = read(upper);
    return IsHttpVariableSet(fallback) ? fallback : null;
}

/// A variable's value when one is set under exactly `name`, case and all.
internal String? ReadHttpEnvironmentVariableExactly(String[] names, String name)
{
    foreach (var each in names)
    {
        if (each == name)
            return Env.GetEnvironmentVariable(name);
    }
    return null;
}

internal bool IsHttpVariableSet(String? value) => value != null && !value.Trim().IsEmpty;

/// A proxy variable's value as a URI: `http://` assumed when no scheme is
/// written, and null for any scheme but http.
internal Uri? ParseHttpProxyAddress(String? value)
{
    if (value == null)
        return null;
    String text = value.Trim();
    if (!text.Contains("://"))
        text = "http://" + text;
    if (Uri.TryCreate(text, UriKind.Absolute) is not Ok parsed)
        return null;
    Uri address = parsed.Value;
    if (address.Scheme != "http" || address.Host.IsEmpty)
        return null;
    return address;
}

/// The user information of a proxy URI as credentials, or null.
internal NetworkCredential? ReadHttpProxyCredentials(Uri address)
{
    String userInfo = address.UserInfo;
    if (userInfo.IsEmpty)
        return null;
    long colon = userInfo.IndexOf(':');
    if (colon < 0)
        return new NetworkCredential(Uri.UnescapeDataString(userInfo), "");
    return new NetworkCredential(Uri.UnescapeDataString(userInfo.Substring(0u, (nuint)colon)),
                                 Uri.UnescapeDataString(userInfo.Substring((nuint)colon + 1u)));
}

/// A dotted IPv4 address as a number.
internal bool TryParseHttpIPv4(String text, out uint address)
{
    address = 0u;
    String[] parts = text.Split('.');
    if (parts.Length != 4u)
        return false;
    uint value = 0u;
    foreach (var part in parts)
    {
        if (part.ByteLength() > 3u || !TryParseHttpDecimal(part, out long octet) || octet > 255)
            return false;
        value = (value << 8) | (uint)octet;
    }
    address = value;
    return true;
}
