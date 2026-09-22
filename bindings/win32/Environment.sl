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

// Environment variables, the command line, and the directories a process is
// told about.
//
// A convenience layer over `Win32.Kernel32`. Nothing here needs a `-l`.
module Win32.Environment;

#if WINDOWS

import Win32;
import Win32.Kernel32;

/// A variable's value, or an empty string when it is not set.
///
/// The two are told apart with `Win32.GetLastErrorCode()`, which is
/// `ErrorEnvvarNotFound` for the second — a distinction that matters rarely
/// enough not to be worth a `Result` here.
public String GetEnvironmentVariable(String name)
{
    var buffer = new WideBuffer(32768u);
    uint units = GetEnvironmentVariableW(name.ToUtf16().ToPointer(),
                                         buffer.Pointer, buffer.Capacity);
    if (units == 0u)
        return "";
    return buffer.ReadText(units);
}

/// Sets a variable for this process and the children it starts after this
/// point. It does not reach the parent, and it is not persistent.
public bool SetEnvironmentVariable(String name, String value)
{
    return Win32.IsBoolSuccess(SetEnvironmentVariableW(name.ToUtf16().ToPointer(),
                                                   value.ToUtf16().ToPointer()));
}

/// Removes a variable from this process's environment.
public bool ClearEnvironmentVariable(String name)
{
    return Win32.IsBoolSuccess(SetEnvironmentVariableW(name.ToUtf16().ToPointer(), null));
}

/// True when the variable is set, including when it is set to an empty string.
public bool HasEnvironmentVariable(String name)
{
    GetEnvironmentVariableW(name.ToUtf16().ToPointer(), null, 0u);
    return Win32.GetLastErrorCode() != ErrorEnvvarNotFound;
}

/// `%TEMP%\log.txt` with the variables filled in.
public String ExpandEnvironmentVariables(String text)
{
    var buffer = new WideBuffer(32768u);
    uint units = ExpandEnvironmentStringsW(text.ToUtf16().ToPointer(),
                                           buffer.Pointer, buffer.Capacity);
    if (units == 0u)
        return "";

    // This one counts the terminator, unlike its neighbours.
    return Text.FromUtf16(buffer.Pointer, (nuint)(units - 1u));
}

/// The whole command line as one string, exactly as Windows keeps it —
/// unsplit, and including the program name.
public String GetCommandLine()
{
    return Text.FromNullTerminatedUtf16(GetCommandLineW());
}

public String GetCurrentDirectory()
{
    var buffer = new WideBuffer(32768u);
    uint units = GetCurrentDirectoryW(buffer.Capacity, buffer.Pointer);
    if (units == 0u)
        return "";
    return buffer.ReadText(units);
}

public bool SetCurrentDirectory(String path)
{
    return Win32.IsBoolSuccess(SetCurrentDirectoryW(path.ToUtf16().ToPointer()));
}

public String GetSystemDirectory()
{
    var buffer = new WideBuffer(32768u);
    uint units = GetSystemDirectoryW(buffer.Pointer, buffer.Capacity);
    if (units == 0u)
        return "";
    return buffer.ReadText(units);
}

public String GetWindowsDirectory()
{
    var buffer = new WideBuffer(32768u);
    uint units = GetWindowsDirectoryW(buffer.Pointer, buffer.Capacity);
    if (units == 0u)
        return "";
    return buffer.ReadText(units);
}

/// The NetBIOS name of this machine, which is at most 15 characters.
public String GetComputerName()
{
    var buffer = new WideBuffer(256u);
    uint size = buffer.Capacity;
    if (!Win32.IsBoolSuccess(GetComputerNameW(buffer.Pointer, &size)))
        return "";
    return buffer.ReadText(size);
}

#endif
