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
import Standard.Configuration;

/// What a `LoggerFactory` is made from: providers, and the minimum level for
/// each category. .NET's `ILoggingBuilder`.
public sealed class LoggingBuilder
{
    internal List<ILoggerProvider> Providers = new List<ILoggerProvider>();
    internal List<LoggingRule> Rules = new List<LoggingRule>();
    internal LogLevel Minimum = LogLevel.Information;

    /// Writes to standard output, as .NET's console logger does.
    public LoggingBuilder AddConsole() => AddProvider(new ConsoleLoggerProvider());

    /// Writes to `provider` as well.
    public LoggingBuilder AddProvider(ILoggerProvider provider)
    {
        Providers.Add(provider);
        return this;
    }

    /// Forgets every provider added so far, for a program that wants none of
    /// the defaults.
    public LoggingBuilder ClearProviders()
    {
        Providers = new List<ILoggerProvider>();
        return this;
    }

    /// The least a message must matter to be written, where no rule says
    /// otherwise. `Information` unless set.
    public LoggingBuilder SetMinimumLevel(LogLevel level)
    {
        Minimum = level;
        return this;
    }

    /// The least a message must matter in every category starting with
    /// `category`; the longest matching prefix wins.
    public LoggingBuilder AddFilter(String category, LogLevel level)
    {
        LoggingRule rule;
        rule.Prefix = category;
        rule.Minimum = level;
        Rules.Add(rule);
        return this;
    }

    /// The levels a configuration section names, as .NET reads `Logging`:
    /// `LogLevel:Default` is the minimum, and every other key below `LogLevel`
    /// a category prefix. A name that is not a level is skipped.
    public LoggingBuilder AddConfiguration(IConfiguration section)
    {
        var levels = section.GetSection("LogLevel").GetChildren();
        for (nuint i = 0u; i < levels.Count; i++)
        {
            String? written = levels[i].Value;
            if (written == null)
                continue;
            var level = ParseLogLevel(written);
            if (!level.HasValue)
                continue;
            if (levels[i].Key.EqualsIgnoreCaseAscii("Default"))
                Minimum = level.GetValue();
            else
                AddFilter(levels[i].Key, level.GetValue());
        }
        return this;
    }

    /// The factory these settings describe.
    public LoggerFactory Build() => new LoggerFactory(Providers, Rules, Minimum);
}

/// A level by its name, without regard to ASCII case.
Optional<LogLevel> ParseLogLevel(String text)
{
    String name = text.Trim();
    LogLevel[] levels = [LogLevel.Trace, LogLevel.Debug, LogLevel.Information, LogLevel.Warning,
                         LogLevel.Error, LogLevel.Critical, LogLevel.None];
    for (nuint i = 0u; i < levels.Length; i++)
    {
        if ($"{levels[i]}".EqualsIgnoreCaseAscii(name))
            return levels[i];
    }
    return Optional<LogLevel>.None;
}
