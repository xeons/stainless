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

/// Messages from a program's parts, filtered by level and category and
/// written by providers. .NET's `Microsoft.Extensions.Logging`.
///
///     services.AddLogging((LoggingBuilder logging) => logging.AddConsole());
///     // ...
///     public Worker(ILogger<Worker> logger) { logger.LogInformation("started"); }
///
/// **A category is a type's name.** `ILogger<Worker>` writes under
/// `App.Worker`, and filters match a category by its prefix, so a rule for
/// `App` covers it. Nothing registers `ILogger<T>`: the interface names
/// `Logger<T>` as its default implementation, which a provider makes for
/// every `T`.
///
/// **A message is text.** Interpolation builds it where it is written, so a
/// call below the minimum level still pays for building it; `IsEnabled` asks
/// first where that matters. There are no message templates or scopes.
module Standard.Logging;

/// A logger under `T`'s name from `factory`; call it as
/// `factory.CreateLogger<T>()`.
public ILogger<T> CreateLogger<T>(ILoggerFactory factory) => new Logger<T>(factory);

/// The short name .NET's console logger writes for a level.
String GetLogLevelLabel(LogLevel level)
{
    switch (level)
    {
        case LogLevel.Trace: return "trce";
        case LogLevel.Debug: return "dbug";
        case LogLevel.Information: return "info";
        case LogLevel.Warning: return "warn";
        case LogLevel.Error: return "fail";
        case LogLevel.Critical: return "crit";
        default: return "none";
    }
}
