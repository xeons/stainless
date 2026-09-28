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

import Standard.Time;

/// One cookie: a name, a value, and where and until when it is sent.
///
/// .NET's `System.Net.Cookie`, kept here beside the container that is its
/// only user. `Expires` is none for a session cookie, which lives as long as
/// its container.
public sealed class Cookie
{
    /// A cookie with no name, which a container refuses until it has one.
    public Cookie() { }

    /// `name=value`, for the path and domain a container will give it.
    public Cookie(String name, String value)
    {
        Name = name;
        Value = value;
    }

    /// `name=value` under `path`.
    public Cookie(String name, String value, String path)
    {
        Name = name;
        Value = value;
        Path = path;
    }

    /// `name=value` under `path` on `domain` and every host below it.
    public Cookie(String name, String value, String path, String domain)
    {
        Name = name;
        Value = value;
        Path = path;
        Domain = domain;
    }

    public String Name { get; set; } = "";

    public String Value { get; set; } = "";

    /// The path it is sent under: `/` and everything below, for `/`.
    public String Path { get; set; } = "";

    /// The host it came from, when `IsHostOnly`, and otherwise the domain
    /// whose every host it is sent to. Lower case, with no leading dot.
    public String Domain { get; set; } = "";

    /// Whether it is sent only over https.
    public bool Secure { get; set; } = false;

    /// Whether the server asked that script not see it. Stored, and sent
    /// like any other: there is no script here.
    public bool HttpOnly { get; set; } = false;

    /// The `SameSite` the server asked for — `Strict`, `Lax` or `None` — or
    /// empty. Stored and not enforced: a client with no notion of a site
    /// has nothing to enforce it against.
    public String SameSite { get; set; } = "";

    /// When it expires, or none for a session cookie.
    public Optional<DateTimeOffset> Expires { get; set; } = None;

    /// Whether it is sent to exactly the host it came from, rather than to a
    /// domain and every host below it.
    public bool IsHostOnly { get; set; } = false;

    /// When it was first stored.
    public DateTimeOffset TimeStamp { get; set; } = DateTimeOffset.UtcNow;

    /// Whether it had expired at `now`.
    public bool HasExpiredAt(DateTimeOffset now)
    {
        if (Expires is Some expires)
            return expires.Value <= now;
        return false;
    }

    /// `name=value`, as a `Cookie` field sends it.
    public String ToString() => Name + "=" + Value;
}
