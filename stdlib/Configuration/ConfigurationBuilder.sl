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

/// Where a configuration is read from, in the order added: a later source's
/// value for a key replaces an earlier one's. .NET's `ConfigurationBuilder`.
public sealed class ConfigurationBuilder
{
    List<IConfigurationSource> _sources = new List<IConfigurationSource>();

    /// The members of the JSON object in the file at `path`, flattened to
    /// keys: `{ "Logging": { "Level": "Debug" } }` is `Logging:Level`, and an
    /// array's elements are `Items:0`, `Items:1`.
    ///
    /// @param path  the file, relative to the working directory
    /// @param optional  whether a missing file is skipped rather than an error
    public ConfigurationBuilder AddJsonFile(String path, bool optional = false)
    {
        _sources.Add(new JsonFileSource(path, optional));
        return this;
    }

    /// Every environment variable whose name starts with `prefix`, without
    /// it, `__` in a name standing for `:`. With no prefix, every variable.
    ///
    /// @param prefix  what a name MUST start with, compared without regard to ASCII case
    public ConfigurationBuilder AddEnvironmentVariables(String prefix = "")
    {
        _sources.Add(new EnvironmentSource(prefix));
        return this;
    }

    /// Settings written on the command line: `--key=value`, `--key value`,
    /// `/key=value`, `/key value` and `key=value`. An argument of none of those
    /// shapes is skipped.
    ///
    /// @param arguments  the program's arguments, without its own name
    public ConfigurationBuilder AddCommandLine(String[] arguments)
    {
        _sources.Add(new CommandLineSource(arguments));
        return this;
    }

    /// The keys and values of `values`, as they are.
    ///
    /// @param values  keys joined with `:`, and their values
    public ConfigurationBuilder AddInMemoryCollection(Dictionary<String, String> values)
    {
        _sources.Add(new MemorySource(values));
        return this;
    }

    /// Reads every source, in order.
    ///
    /// @returns the configuration, or the first source that could not be read:
    ///          a required file that is missing or is not a JSON object
    public Result<Configuration, ConfigurationError> Build()
    {
        var data = new ConfigurationData();
        for (nuint i = 0u; i < _sources.Count; i++)
        {
            ConfigurationError? failed = _sources[i].Load(data);
            if (failed != null)
                return Fail(failed);
        }
        return Ok(new Configuration(data));
    }
}
