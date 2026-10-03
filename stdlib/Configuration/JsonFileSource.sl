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

import Standard.File;
import Standard.Json;

internal sealed class JsonFileSource : IConfigurationSource
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
