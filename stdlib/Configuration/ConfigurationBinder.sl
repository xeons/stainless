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

import Standard.Convert;
import Standard.Reflection;

/// Sets an object's properties from a section's values. .NET's
/// `ConfigurationBinder`.
public static class ConfigurationBinder
{
    /// Sets each writable property of `target` whose name a key below `section`
    /// matches, without regard to ASCII case, parsing the text for its type:
    /// an integer, a floating number, `true` or `false`, a `String`, or an
    /// enum's member name. A property that is a `[Reflect]` class is bound in
    /// place from the section below it, so its object MUST already exist --
    /// made by the constructor. A property no key names keeps its value.
    ///
    /// @typeparam T  a `[Reflect]` class
    /// @param section  where the values are
    /// @param target  what to set
    /// @returns true, or the first value that does not parse, naming its key
    public static Result<bool, ConfigurationError> Bind<T>(IConfiguration section, T target)
        where T : class
    {
        ConfigurationError? failed = BindConfigurationInstance((byte*)target, typeof(T), section);
        if (failed != null)
            return Fail(failed);
        return Ok(true);
    }
}

ConfigurationError? BindConfigurationInstance(byte* instance, Type type, IConfiguration section)
{
    var children = section.GetChildren();
    for (nuint i = 0u; i < type.PropertyCount; i++)
    {
        var property = type.GetPropertyAt(i);
        ConfigurationSection? found = null;
        for (nuint j = 0u; j < children.Count; j++)
        {
            if (children[j].Key.EqualsIgnoreCaseAscii(property.Name))
                found = children[j];
        }
        if (found == null)
            continue;

        ConfigurationError? failed = BindConfigurationProperty(instance, property, found);
        if (failed != null)
            return failed;
    }
    return null;
}

ConfigurationError? BindConfigurationProperty(byte* instance, Property property, ConfigurationSection section)
{
    if (property.Kind == KindClass)
    {
        byte* nested = GetAggregate(instance, property);
        if (nested == null || !property.PropertyType.Exists)
            return null;
        return BindConfigurationInstance(nested, property.PropertyType, section);
    }

    String? written = section.Value;
    if (written == null || !property.CanWrite)
        return null;
    String text = written.Trim();

    if (property.IsText)
    {
        SetText(instance, property, written);
        return null;
    }

    if (property.Kind == KindBool)
    {
        if (text.EqualsIgnoreCaseAscii("true"))
            SetBool(instance, property, true);
        else if (text.EqualsIgnoreCaseAscii("false"))
            SetBool(instance, property, false);
        else
            return RefuseConfigurationValue(section, "true or false");
        return null;
    }

    if (property.IsInteger && property.PropertyType.Exists && property.PropertyType.IsEnum)
    {
        var enumType = property.PropertyType;
        for (nuint i = 0u; i < enumType.EnumMemberCount; i++)
        {
            if (enumType.GetEnumMemberName(i).EqualsIgnoreCaseAscii(text))
            {
                SetInteger(instance, property, enumType.GetEnumMemberValue(i));
                return null;
            }
        }
        return RefuseConfigurationValue(section, "one of the names of '" + enumType.Name + "'");
    }

    if (property.IsInteger)
    {
        var parsed = ToLong(text);
        if (!parsed.Ok)
            return RefuseConfigurationValue(section, "an integer");
        SetInteger(instance, property, parsed.Value);
        return null;
    }

    if (property.IsFloating)
    {
        var parsed = ToDouble(text);
        if (!parsed.Ok)
            return RefuseConfigurationValue(section, "a number");
        SetDouble(instance, property, parsed.Value);
        return null;
    }

    return null;
}

ConfigurationError RefuseConfigurationValue(ConfigurationSection section, String wanted)
{
    String? written = section.Value;
    return new ConfigurationError("'" + section.Path + "' is '" + (written ?? "") + "', which is not " + wanted);
}
