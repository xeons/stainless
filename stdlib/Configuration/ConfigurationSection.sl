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

module Standard.Configuration;

import Standard.Collections;

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
