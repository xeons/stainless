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

module Standard.Options;

import Standard.Collections;
import Standard.Configuration;
import Standard.DependencyInjection;

/// How a `T` is made: the sections to bind, the actions to run, the checks to
/// make, in the order they were given. .NET's `OptionsBuilder<T>`.
public sealed class OptionsBuilder<T> : IServiceCollectionState
    where T : new()
{
    List<IConfiguration> _sections = new List<IConfiguration>();
    List<Action<T>> _actions = new List<Action<T>>();
    List<Predicate<T>> _checks = new List<Predicate<T>>();
    List<String> _messages = new List<String>();

    /// Binds `section` onto the object, after any earlier step.
    public OptionsBuilder<T> Bind(IConfiguration section)
    {
        _sections.Add(section);
        _actions.Add((T value) => BindOptionsSection<T>(section, value));
        return this;
    }

    /// Runs `configure` on the object, after any earlier step.
    public OptionsBuilder<T> Configure(Action<T> configure)
    {
        _actions.Add(configure);
        return this;
    }

    /// Stops the program with `message` when `check` is false of the made
    /// object.
    public OptionsBuilder<T> Validate(Predicate<T> check, String message)
    {
        _checks.Add(check);
        _messages.Add(message);
        return this;
    }

    internal T MakeOptions()
    {
        var value = new T();
        for (nuint i = 0u; i < _actions.Count; i++)
        {
            var action = _actions[i];
            action(value);
        }
        for (nuint i = 0u; i < _checks.Count; i++)
        {
            var check = _checks[i];
            if (!check(value))
                sl_fail(("options '" + RuntimeHelpers.GetTypeName<T>() + "' are not valid: " +
                         _messages[i]).ToPointer());
        }
        return value;
    }
}
