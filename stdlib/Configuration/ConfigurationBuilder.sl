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
import Standard.Env;
import Standard.File;
import Standard.Json;

/// Where a configuration is read from, in the order added: a later source's
/// value for a key replaces an earlier one's. .NET's `ConfigurationBuilder`.
public sealed class ConfigurationBuilder
{
    List<ConfigurationSource> _sources = new List<ConfigurationSource>();

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

/// One place a configuration is read from.
internal interface ConfigurationSource
{
    /// Adds what it holds to `data`; null, or why it could not.
    ConfigurationError? Load(ConfigurationData data);
}

internal sealed class JsonFileSource : ConfigurationSource
{
    String _path;
    bool _optional;

    public JsonFileSource(String path, bool optional)
    {
        _path = path;
        _optional = optional;
    }

    public ConfigurationError? Load(ConfigurationData data)
    {
        if (!Exists(_path))
        {
            if (_optional)
                return null;
            return new ConfigurationError("the configuration file '" + _path + "' does not exist");
        }

        var text = ReadAllText(_path);
        if (!text.Ok)
            return new ConfigurationError("the configuration file '" + _path + "' could not be read");

        var parsed = Parse(text.Value);
        if (!parsed.Ok)
            return new ConfigurationError("the configuration file '" + _path + "' is not valid JSON");
        var document = parsed.Value;
        if (!document.Object)
            return new ConfigurationError("the configuration file '" + _path + "' is not a JSON object");

        FlattenJsonObject(document.Members, "", data);
        return null;
    }
}

/// Each member of `members` under `prefix`.
void FlattenJsonObject(JsonObject members, String prefix, ConfigurationData data)
{
    for (nuint i = 0u; i < members.Count; i++)
        FlattenJsonValue(members.GetValueAt(i), JoinConfigurationKey(prefix, members.GetNameAt(i)), data);
}

void FlattenJsonValue(JsonValue value, String key, ConfigurationData data)
{
    if (value.Object)
    {
        FlattenJsonObject(value.Members, key, data);
        return;
    }
    if (value.Array)
    {
        for (nuint i = 0u; i < value.Items.Count; i++)
            FlattenJsonValue(value.Items[i], JoinConfigurationKey(key, FromInteger(i)), data);
        return;
    }
    if (value.Text)
    {
        data.SetValue(key, value.Value);
        return;
    }
    if (value.Bool)
    {
        data.SetValue(key, value.Value ? "true" : "false");
        return;
    }
    if (value.Number)
    {
        data.SetValue(key, FormatConfigurationNumber(value.Value));
        return;
    }
    data.SetValue(key, "");
}

/// A whole number without a fraction, as a file wrote `8080`.
String FormatConfigurationNumber(double number)
{
    if (number >= -9007199254740992.0 && number <= 9007199254740992.0 && number == (double)(long)number)
        return FromInteger((long)number);
    return FromDouble(number);
}

String JoinConfigurationKey(String prefix, String part) =>
    prefix.ByteLength() == 0u ? part : prefix + ":" + part;

internal sealed class EnvironmentSource : ConfigurationSource
{
    String _prefix;

    public EnvironmentSource(String prefix)
    {
        _prefix = prefix;
    }

    public ConfigurationError? Load(ConfigurationData data)
    {
        String[] names = GetEnvironmentVariableNames();
        nuint skip = _prefix.ByteLength();
        for (nuint i = 0u; i < names.Length; i++)
        {
            String name = names[i];
            if (name.ByteLength() <= skip || !name.Substring(0u, skip).EqualsIgnoreCaseAscii(_prefix))
                continue;
            String? value = GetEnvironmentVariable(name);
            if (value != null)
                data.SetValue(name.Substring(skip).Replace("__", ":"), value);
        }
        return null;
    }
}

internal sealed class CommandLineSource : ConfigurationSource
{
    String[] _arguments;

    public CommandLineSource(String[] arguments)
    {
        _arguments = arguments;
    }

    public ConfigurationError? Load(ConfigurationData data)
    {
        nuint i = 0u;
        while (i < _arguments.Length)
        {
            String argument = _arguments[i];
            i++;

            String key;
            bool prefixed = true;
            if (argument.StartsWith("--"))
                key = argument.Substring(2u);
            else if (argument.StartsWith("/"))
                key = argument.Substring(1u);
            else
            {
                key = argument;
                prefixed = false;
            }

            long equals = key.IndexOf("=");
            if (equals >= 0)
            {
                String name = key.Substring(0u, (nuint)equals);
                if (name.ByteLength() > 0u)
                    data.SetValue(name, key.Substring((nuint)equals + 1u));
                continue;
            }

            // `--key value`: the next argument is the value, if there is one.
            if (prefixed && key.ByteLength() > 0u && i < _arguments.Length)
            {
                data.SetValue(key, _arguments[i]);
                i++;
            }
        }
        return null;
    }
}

internal sealed class MemorySource : ConfigurationSource
{
    Dictionary<String, String> _values;

    public MemorySource(Dictionary<String, String> values)
    {
        _values = values;
    }

    public ConfigurationError? Load(ConfigurationData data)
    {
        var keys = _values.GetKeys();
        for (nuint i = 0u; i < keys.Count; i++)
            data.SetValue(keys[i], _values.GetValue(keys[i]));
        return null;
    }
}
