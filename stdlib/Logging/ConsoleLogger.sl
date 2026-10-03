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

import Standard.Console;

/// Writes to standard output in .NET's simple console format:
///
///     info: App.Worker[0]
///           Started.
///
/// The level is coloured at a terminal and plain in a file or a pipe. Each
/// message is one write, so two threads' messages never interleave.
public sealed threadsafe class ConsoleLoggerProvider : ILoggerProvider
{
    bool _colors;

    public ConsoleLoggerProvider()
    {
        _colors = EnableTerminalColors();
    }

    public ILogger CreateLogger(String category) => new ConsoleLogger(category, _colors);
}

internal sealed class ConsoleLogger : ILogger
{
    String _category;
    bool _colors;

    public ConsoleLogger(String category, bool colors)
    {
        _category = category;
        _colors = colors;
    }

    public bool IsEnabled(LogLevel level) => level != LogLevel.None;

    public void Log(LogLevel level, String message)
    {
        String label = GetLogLevelLabel(level);
        if (_colors)
            label = GetConsoleLogColor(level) + label + "\u001b[0m";
        Write(label + ": " + _category + "[0]\n      " + message.Replace("\n", "\n      ") + "\n");
    }
}

/// The escape that colours a level as .NET's console logger does.
String GetConsoleLogColor(LogLevel level)
{
    switch (level)
    {
        case LogLevel.Information: return "\u001b[32m";
        case LogLevel.Warning: return "\u001b[33m";
        case LogLevel.Error: return "\u001b[31m";
        case LogLevel.Critical: return "\u001b[37;41m";
        default: return "\u001b[90m";
    }
}
