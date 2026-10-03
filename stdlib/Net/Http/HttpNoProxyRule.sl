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

/// One entry of `no_proxy`.
internal sealed class HttpNoProxyRule
{
    private String _host = "";
    private int _port = -1;
    private bool _isRange = false;
    private uint _network = 0u;
    private uint _mask = 0u;
    private bool _isMalformed = false;

    internal HttpNoProxyRule(String entry)
    {
        String text = entry;
        // A port, after a bracketed IPv6 literal or after the one colon of a
        // name or an IPv4 address.
        long bracket = text.IndexOf(']');
        long colon = text.LastIndexOf(':');
        bool hasPort = text.StartsWith("[") ? colon > bracket : colon >= 0 && text.IndexOf(':') == colon;
        if (hasPort)
        {
            if (TryParseHttpDecimal(text.Substring((nuint)colon + 1u), out long port) && port <= 65535)
            {
                _port = (int)port;
            }
            else
            {
                // An entry for a port that cannot be read is no entry, not
                // one for every port.
                _isMalformed = true;
                return;
            }
            text = text.Substring(0u, (nuint)colon);
        }
        if (text.StartsWith("[") && text.EndsWith("]"))
            text = text.Substring(1u, text.ByteLength() - 2u);

        long slash = text.IndexOf('/');
        if (slash > 0 && TryParseHttpIPv4(text.Substring(0u, (nuint)slash), out uint network) &&
            TryParseHttpDecimal(text.Substring((nuint)slash + 1u), out long bits) && bits <= 32)
        {
            _isRange = true;
            _mask = bits == 0 ? 0u : 0xFFFFFFFFu << (int)(32 - bits);
            _network = network & _mask;
            return;
        }

        if (text.StartsWith("*."))
            text = text.Substring(2u);
        else if (text.StartsWith("."))
            text = text.Substring(1u);
        _host = text;
    }

    /// Whether a lower-case bare host, on `port`, is this entry's.
    internal bool MatchesHttpHost(String host, int port)
    {
        if (_isMalformed || (_port >= 0 && _port != port))
            return false;
        if (_isRange)
            return TryParseHttpIPv4(host, out uint address) && (address & _mask) == _network;
        if (_host.IsEmpty)
            return false;
        return host == _host || host.EndsWith("." + _host);
    }
}
