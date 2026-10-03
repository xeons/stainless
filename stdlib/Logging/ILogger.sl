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

/// Writes messages for one category. .NET's `ILogger`, with its extension
/// methods as default members.
public interface ILogger
{
    /// Writes `message` if `level` is enabled.
    void Log(LogLevel level, String message);

    /// Whether a message at `level` would be written.
    bool IsEnabled(LogLevel level);

    void LogTrace(String message) => Log(LogLevel.Trace, message);
    void LogDebug(String message) => Log(LogLevel.Debug, message);
    void LogInformation(String message) => Log(LogLevel.Information, message);
    void LogWarning(String message) => Log(LogLevel.Warning, message);
    void LogError(String message) => Log(LogLevel.Error, message);
    void LogCritical(String message) => Log(LogLevel.Critical, message);
}
