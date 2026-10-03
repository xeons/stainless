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

/// Settings as a typed object a service asks for. .NET's
/// `Microsoft.Extensions.Options`.
///
///     [Reflect]
///     public class MailOptions
///     {
///         public String Host { get; set; } = "localhost";
///         public int Port { get; set; } = 25;
///     }
///
///     services.Configure<MailOptions>(configuration.GetSection("Mail"));
///     // ...
///     public Mailer(IOptions<MailOptions> options) { _host = options.Value.Host; }
///
/// The object is made by its parameterless constructor, which sets the
/// defaults, and then bound from the section and passed to each `Configure`
/// action in the order they were registered, the first time it is asked for.
/// A value that does not parse, or a `Validate` that fails, stops the program
/// with the message, as .NET's `OptionsValidationException` would end it.
module Standard.Options;

import Standard.Collections;
import Standard.Configuration;
import Standard.DependencyInjection;

[DoesNotReturn]
extern "C" void sl_fail(byte* message);

/// A `T` made from configuration. .NET's `IOptions<T>`.
public interface IOptions<T>
{
    /// The settings, made the first time any service asked for them.
    T Value { get; }
}

/// The `IOptions<T>` a provider makes.
public sealed class Options<T> : IOptions<T>
    where T : class
{
    T _value;

    public Options(T value)
    {
        _value = value;
    }

    public T Value => _value;
}

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

void BindOptionsSection<T>(IConfiguration section, T value)
    where T : class
{
    var bound = ConfigurationBinder.Bind<T>(section, value);
    if (!bound.Ok)
        sl_fail(("options '" + RuntimeHelpers.GetTypeName<T>() + "' could not be bound: " +
                 bound.Error.Message).ToPointer());
}

/// Registers `IOptions<T>` and answers the builder that says how it is made;
/// call it as `services.AddOptions<T>()`. A second call answers the same
/// builder, so every step for a type adds to one.
///
/// @typeparam T  a `[Reflect]` class with a parameterless constructor
public OptionsBuilder<T> AddOptions<T>(ServiceCollection services)
    where T : new()
{
    int key = ServiceKey<IOptions<T>>.Id;
    var existing = services.State.TryGetValue(key);
    if (existing.HasValue)
        return (OptionsBuilder<T>)existing.GetValue();

    var builder = new OptionsBuilder<T>();
    services.State.SetValue(key, builder);
    services.AddSingleton<IOptions<T>>(
        (ServiceProvider provider) => new Options<T>(builder.MakeOptions()));
    return builder;
}

/// `T`'s settings from `section`; call it as `services.Configure<T>(section)`.
///
/// @typeparam T  a `[Reflect]` class with a parameterless constructor
public ServiceCollection Configure<T>(ServiceCollection services, IConfiguration section)
    where T : new()
{
    AddOptions<T>(services).Bind(section);
    return services;
}

/// `T`'s settings set by `configure`; call it as `services.Configure<T>(...)`.
///
/// @typeparam T  a class with a parameterless constructor
public ServiceCollection Configure<T>(ServiceCollection services, Action<T> configure)
    where T : new()
{
    AddOptions<T>(services).Configure(configure);
    return services;
}
