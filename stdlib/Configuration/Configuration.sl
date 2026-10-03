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

/// Settings gathered from files, the environment and the command line into one
/// tree of text. .NET's `Microsoft.Extensions.Configuration`.
///
///     var configuration = try new ConfigurationBuilder()
///         .AddJsonFile("appsettings.json", optional: true)
///         .AddEnvironmentVariables("APP_")
///         .AddCommandLine(GetArguments())
///         .Build();
///     String? level = configuration.GetValue("Logging:LogLevel:Default");
///
/// **A key is a path**, its parts joined with `:`; a JSON object's members and
/// an array's indexes become parts, and an environment variable's `__` is one.
/// Keys are compared without regard to ASCII case, as .NET compares them.
///
/// **Every value is text.** A number from a JSON file is written back as text,
/// and `ConfigurationBinder.Bind` parses it onto the property it is for.
///
/// **A later source wins**: a value from the command line replaces the same key
/// from the environment, which replaces the file's.
module Standard.Configuration;

import Standard.Collections;

/// A built configuration: every source's keys and values, the later winning.
/// .NET's `IConfigurationRoot`.
public sealed class Configuration : IConfiguration
{
    ConfigurationData _data;

    internal Configuration(ConfigurationData data)
    {
        _data = data;
    }

    /// A configuration with nothing in it.
    public Configuration()
    {
        _data = new ConfigurationData();
    }

    public String? GetValue(String key) => _data.GetValue(key);

    /// The value at `key`, or `fallback` when there is none.
    ///
    /// @param key  a path, its parts joined with `:`
    /// @param fallback  what to answer instead
    public String GetValueOrDefault(String key, String fallback)
    {
        String? found = _data.GetValue(key);
        if (found != null)
            return found;
        return fallback;
    }

    public ConfigurationSection GetSection(String key) => new ConfigurationSection(_data, key);

    public List<ConfigurationSection> GetChildren()
    {
        var keys = _data.GetChildKeys("");
        var sections = new List<ConfigurationSection>();
        for (nuint i = 0u; i < keys.Count; i++)
            sections.Add(new ConfigurationSection(_data, keys[i]));
        return sections;
    }

    /// Every key with a value, as first spelled, in the order first written.
    public List<String> GetKeys()
    {
        var keys = new List<String>();
        for (nuint i = 0u; i < _data.Order.Count; i++)
            keys.Add(_data.Spellings.GetValue(_data.Order[i]));
        return keys;
    }
}
