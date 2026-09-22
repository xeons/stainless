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

/// What the program was started with and what surrounds it.
///
/// The arguments are also reachable as `Main(String[] args)`, which is the
/// better way to read them -- a function that takes what it needs beats one
/// that goes looking. These are for the code that is nowhere near `Main`.
module Standard.Env;

import Standard.Collections;

extern "C"
{
    void sl_fail(byte* message);

    // The arguments stay the runtime's: the entry point hands it argv before
    // any Stainless code could run, and there is nowhere earlier to stand.
    nuint sl_args_count();
    String sl_args_at(nuint index);
    String sl_args_program();
}

#if WINDOWS

/// The wide half of the environment, declared rather than included.
///
/// Wide and not narrow: the `A` functions answer in the active code page, and
/// a `String` is UTF-8 by definition -- a variable holding a character the
/// code page cannot spell would arrive as question marks rather than as
/// itself.
extern "C" __stdcall
{
    uint GetEnvironmentVariableW(char16* name, char16* buffer, uint size);
    int  SetEnvironmentVariableW(char16* name, char16* value);

    uint GetLastError();
    void SetLastError(uint code);

    char16* GetEnvironmentStringsW();
    int     FreeEnvironmentStringsW(char16* block);

    uint GetCurrentDirectoryW(uint size, char16* buffer);
    int  SetCurrentDirectoryW(char16* path);
}

#else

extern "C"
{
    byte* getenv(byte* name);
    int   setenv(byte* name, byte* value, int overwrite);
    int   unsetenv(byte* name);

    byte* getcwd(byte* buffer, nuint size);
    int   chdir(byte* path);
}

/// Every variable, as `name=value` pointers ending in a null one. POSIX gives
/// the block a name rather than a function.
extern "C" byte** environ;

#endif

// --------------------------------------------------------------- arguments

/// How many arguments the program was given, not counting its own name.
public nuint ArgumentCount() => sl_args_count();

/// One argument, counting from zero. Aborts past the end, as an array does.
public String GetArgument(nuint index)
{
    if (index >= sl_args_count())
        sl_fail("Env.GetArgument: no argument at that index");
    return sl_args_at(index);
}

/// Every argument, as an array. The same thing `Main(String[] args)` receives.
public String[] GetArguments()
{
    nuint count = sl_args_count();
    var all = new String[count];
    for (nuint i = 0u; i < count; i++)
        all[i] = sl_args_at(i);
    return all;
}

/// The program's own path, as the operating system gave it. That is not
/// necessarily where the executable is: a shell may pass a bare name, and on
/// Linux nothing guarantees any relationship at all.
public String ProgramPath() => sl_args_program();

// --------------------------------------------------------------- variables

/// A variable's value, or null when it is not set.
///
/// Null rather than empty, because "not set" and "set to nothing" are
/// different states and both platforms can tell them apart. `GetVariableOrDefault` is what
/// most callers want.
#if WINDOWS
public String? GetVariable(String name)
{
    var wanted = name.ToUtf16();

    // The size, terminator included, and then the value. A variable that grew
    // in between answers with the size it needs now, and is asked again. One
    // set to nothing has a size of 1 and reads as 0 units with no error.
    uint units = GetEnvironmentVariableW(wanted.ToPointer(), null, 0u);
    while (units != 0u)
    {
        var buffer = new char16[(nuint)units];
        SetLastError(0u);
        uint written = GetEnvironmentVariableW(wanted.ToPointer(), &buffer[0], units);

        if (written < units)
        {
            if (written == 0u && GetLastError() == ErrorVariableNotFound)
                return null;
            return FromUtf16(&buffer[0], (nuint)written);
        }

        units = written;
    }
    return null;
}

/// ERROR_ENVVAR_NOT_FOUND.
const uint ErrorVariableNotFound = 203u;
#else
public String? GetVariable(String name)
{
    byte* value = getenv(name.ToPointer());
    if (value == null)
        return null;
    return FromNullTerminated(value);
}
#endif

/// A variable's value, or `fallback` when it is not set.
public String GetVariableOrDefault(String name, String fallback)
{
    var value = GetVariable(name);
    if (value == null)
        return fallback;
    return value;
}

/// Whether a variable is set, whatever it is set to.
public bool HasVariable(String name) => GetVariable(name) != null;

/// Sets a variable for this process and anything it starts afterwards.
///
/// It does not reach the shell that started this program: a process's
/// environment is its own, and a child gets a copy. Reports whether the
/// platform accepted it.
///
/// An empty value leaves the variable set and empty, on both platforms, and
/// `GetVariable` answers with the empty string rather than null.
public bool SetVariable(String name, String value) => StoreVariable(name, value);

/// Removes a variable, reporting whether the platform accepted it. Removing
/// one that was never set is not a failure.
public bool RemoveVariable(String name) => StoreVariable(name, null);

#if WINDOWS

/// Sets a variable, or removes it when `value` is null. A null value is what
/// `SetEnvironmentVariableW` takes to mean "remove".
bool StoreVariable(String name, String? value)
{
    var wanted = name.ToUtf16();
    if (value == null)
        return IsWin32Success(SetEnvironmentVariableW(wanted.ToPointer(), null));

    var text = ((String)value).ToUtf16();
    return IsWin32Success(SetEnvironmentVariableW(wanted.ToPointer(), text.ToPointer()));
}

/// Nonzero is success for a Win32 BOOL, which is not what the rest of this
/// file means by an int.
bool IsWin32Success(int result) => result != 0;

/// The name of every variable, in whatever order the platform keeps them.
///
/// The block is one run of NUL-terminated wide strings ending in an empty one.
/// A name beginning with `=` is Windows' per-drive working directory (`=C:`),
/// which is not a variable anybody set.
public String[] GetVariableNames()
{
    char16* block = GetEnvironmentStringsW();
    if (block == null)
        return new String[0];

    var found = new List<String>();

    nuint at = 0u;
    while (block[at] != (char16)0)
    {
        nuint start = at;
        while (block[at] != (char16)0)
            at++;

        nuint units = at - start;
        if (units > 0u && block[start] != (char16)0x3D)
        {
            nuint equals = start;
            while (equals < at && block[equals] != (char16)0x3D)
                equals++;

            if (equals < at)
                found.Add(FromUtf16(&block[start], equals - start));
        }

        at++;
    }

    FreeEnvironmentStringsW(block);
    return found.ToArray();
}

#else

/// Sets a variable, or removes it when `value` is null.
bool StoreVariable(String name, String? value)
{
    if (value == null)
        return unsetenv(name.ToPointer()) == 0;
    return setenv(name.ToPointer(), ((String)value).ToPointer(), 1) == 0;
}

/// The name of every variable, in whatever order the platform keeps them.
///
/// `environ` is a null-terminated run of `name=value`, and an entry without an
/// `=` is not one the C library put there.
public String[] GetVariableNames()
{
    var found = new List<String>();

    if (environ == null)
        return found.ToArray();

    for (nuint i = 0u; environ[i] != null; i++)
    {
        byte* entry = environ[i];

        nuint length = 0u;
        while (entry[length] != 0 && entry[length] != 0x3D)
            length++;

        if (entry[length] == 0x3D && length > 0u)
            found.Add(FromBytes(entry, length));
    }

    return found.ToArray();
}

#endif

// ------------------------------------------------------- working directory

#if WINDOWS

/// The directory relative paths are resolved against.
public String CurrentDirectory()
{
    // Size first, then the path: the same two-call shape the variables use,
    // and for the same reason.
    uint units = GetCurrentDirectoryW(0u, null);
    if (units == 0u)
        return "";

    var buffer = new char16[(nuint)units];
    uint written = GetCurrentDirectoryW(units, &buffer[0]);
    if (written == 0u || written >= units)
        return "";

    return FromUtf16(&buffer[0], (nuint)written);
}

/// Changes it, reporting whether the platform accepted it. It fails when the
/// path is not a directory, or is not reachable.
public bool SetCurrentDirectory(String path)
{
    var wide = path.ToUtf16();
    return SetCurrentDirectoryW(wide.ToPointer()) != 0;
}

#else

/// The directory relative paths are resolved against.
public String CurrentDirectory()
{
    // 4096 is PATH_MAX on Linux and the number every shell assumes. A path
    // longer than it answers with nothing rather than with half of itself.
    var buffer = new byte[4096u];
    if (getcwd(&buffer[0], 4096u) == null)
        return "";
    return FromNullTerminated(&buffer[0]);
}

/// Changes it, reporting whether the platform accepted it. It fails when the
/// path is not a directory, or is not reachable.
public bool SetCurrentDirectory(String path)
{
    return chdir(path.ToPointer()) == 0;
}

#endif
