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

/// The keys and values of a built configuration, shared by every section of it.
internal sealed class ConfigurationData
{
    /// By lowered key.
    public Dictionary<String, String> Values = new Dictionary<String, String>();

    /// Each lowered key as it was first written, in the order first written.
    public Dictionary<String, String> Spellings = new Dictionary<String, String>();

    public List<String> Order = new List<String>();

    public void SetValue(String key, String value)
    {
        String lowered = key.ToLowerAscii();
        if (!Spellings.ContainsKey(lowered))
        {
            Spellings.SetValue(lowered, key);
            Order.Add(lowered);
        }
        Values.SetValue(lowered, value);
    }

    public String? GetValue(String key)
    {
        var found = Values.TryGetValue(key.ToLowerAscii());
        if (found.HasValue)
            return found.GetValue();
        return null;
    }

    /// The parts directly below `path`, as first spelled, in the order first
    /// written; the whole tree's first parts for an empty path.
    public List<String> GetChildKeys(String path)
    {
        String prefix = path.ByteLength() == 0u ? "" : path.ToLowerAscii() + ":";
        var seen = new Dictionary<String, bool>();
        var children = new List<String>();
        for (nuint i = 0u; i < Order.Count; i++)
        {
            String lowered = Order[i];
            if (!lowered.StartsWith(prefix) || lowered.ByteLength() == prefix.ByteLength())
                continue;
            String rest = lowered.Substring(prefix.ByteLength());
            long colon = rest.IndexOf(":");
            String part = colon < 0 ? rest : rest.Substring(0u, (nuint)colon);
            if (seen.ContainsKey(part))
                continue;
            seen.SetValue(part, true);
            String spelled = Spellings.GetValue(lowered);
            children.Add(spelled.Substring(prefix.ByteLength(), part.ByteLength()));
        }
        return children;
    }
}

/// What both a whole configuration and a section of it answer.
/// .NET's `IConfiguration`.
public interface IConfiguration
{
    /// The value at `key`, below this one, or null.
    ///
    /// @param key  a path, its parts joined with `:`
    String? GetValue(String key);

    /// The section at `key`, below this one. A section nothing is under exists
    /// all the same, and answers null for every value.
    ///
    /// @param key  a path, its parts joined with `:`
    ConfigurationSection GetSection(String key);

    /// The sections directly below this one, in the order first written.
    List<ConfigurationSection> GetChildren();
}

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

/// The part of a configuration below one key. .NET's `IConfigurationSection`.
public sealed class ConfigurationSection : IConfiguration
{
    ConfigurationData _data;
    String _path;

    internal ConfigurationSection(ConfigurationData data, String path)
    {
        _data = data;
        _path = path;
    }

    /// The whole path from the root: `Logging:LogLevel`.
    public String Path => _path;

    /// The last part of the path: `LogLevel`.
    public String Key
    {
        get
        {
            long colon = _path.LastIndexOf(":");
            return colon < 0 ? _path : _path.Substring((nuint)colon + 1u);
        }
    }

    /// The value at this section's own key, or null.
    public String? Value => _data.GetValue(_path);

    /// Whether this section has a value or anything below it.
    public bool Exists => Value != null || _data.GetChildKeys(_path).Count > 0u;

    public String? GetValue(String key) => _data.GetValue(_path + ":" + key);

    public ConfigurationSection GetSection(String key) => new ConfigurationSection(_data, _path + ":" + key);

    public List<ConfigurationSection> GetChildren()
    {
        var keys = _data.GetChildKeys(_path);
        var sections = new List<ConfigurationSection>();
        for (nuint i = 0u; i < keys.Count; i++)
            sections.Add(new ConfigurationSection(_data, _path + ":" + keys[i]));
        return sections;
    }
}

/// Why a configuration could not be built or bound.
public sealed class ConfigurationError
{
    /// What went wrong, naming the file or the key.
    public String Message;

    internal ConfigurationError(String message)
    {
        Message = message;
    }
}
