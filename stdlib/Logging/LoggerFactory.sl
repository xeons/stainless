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

module Standard.Logging;

import Standard.Collections;
import Standard.DependencyInjection;

/// Makes a logger for each category from its providers, the minimum level
/// fixed when the logger is made. .NET's `LoggerFactory`.
public sealed threadsafe class LoggerFactory : ILoggerFactory
{
    List<ILoggerProvider> _providers;
    List<LoggingRule> _rules;
    LogLevel _minimum;

    public LoggerFactory(List<ILoggerProvider> providers, List<LoggingRule> rules, LogLevel minimum)
    {
        _providers = providers;
        _rules = rules;
        _minimum = minimum;
    }

    public ILogger CreateLogger(String category)
    {
        var loggers = new List<ILogger>();
        for (nuint i = 0u; i < _providers.Count; i++)
            loggers.Add(_providers[i].CreateLogger(category));
        return new FactoryLogger(loggers, FindMinimumLevel(category));
    }

    LogLevel FindMinimumLevel(String category)
    {
        LogLevel minimum = _minimum;
        nuint longest = 0u;
        for (nuint i = 0u; i < _rules.Count; i++)
        {
            var rule = _rules[i];
            nuint length = rule.Prefix.ByteLength();
            bool matches = category.ByteLength() >= length &&
                           category.Substring(0u, length).EqualsIgnoreCaseAscii(rule.Prefix);
            if (matches && length >= longest)
            {
                minimum = rule.Minimum;
                longest = length;
            }
        }
        return minimum;
    }
}

/// Registers `ILoggerFactory`, made from the settings `configure` gives; call
/// it as `services.AddLogging(...)`. `ILogger<T>` needs no registration.
public ServiceCollection AddLogging(ServiceCollection services, Action<LoggingBuilder> configure)
{
    var builder = new LoggingBuilder();
    configure(builder);
    services.AddSingleton<ILoggerFactory>((ServiceProvider provider) => builder.Build());
    return services;
}
