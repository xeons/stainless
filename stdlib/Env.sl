// Stainless - an experimental systems language.
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

// What the program was started with and what surrounds it.
//
// The arguments are also reachable as `Main(String[] args)`, which is the
// better way to read them -- a function that takes what it needs beats one
// that goes looking. These are for the code that is nowhere near `Main`.
module Standard.Env;

import Standard.Collections;

extern "C" {
    void sl_fail(byte* message);

    nuint sl_args_count();
    String sl_args_at(nuint index);
    String sl_args_program();

    String? sl_env_get(String name);
    bool sl_env_set(String name, String? value);
    String sl_env_names();

    String sl_env_current_directory();
    bool sl_env_set_current_directory(String path);
}

// --------------------------------------------------------------- arguments

/// How many arguments the program was given, not counting its own name.
public nuint ArgumentCount() { return sl_args_count(); }

/// One argument, counting from zero. Aborts past the end, as an array does.
public String ArgumentAt(nuint index) {
    if (index >= sl_args_count()) { sl_fail("Env.ArgumentAt: no argument at that index"); }
    return sl_args_at(index);
}

/// Every argument, as an array. The same thing `Main(String[] args)` receives.
public String[] Arguments() {
    nuint count = sl_args_count();
    var all = new String[count];
    for (nuint i = 0u; i < count; i += 1u) { all[i] = sl_args_at(i); }
    return all;
}

/// The program's own path, as the operating system gave it. That is not
/// necessarily where the executable is: a shell may pass a bare name, and on
/// Linux nothing guarantees any relationship at all.
public String Program() { return sl_args_program(); }

// --------------------------------------------------------------- variables

/// A variable's value, or null when it is not set.
///
/// Null rather than empty, because "not set" and "set to nothing" are
/// different states and both platforms can tell them apart. `GetOr` is what
/// most callers want.
public String? Get(String name) { return sl_env_get(name); }

/// A variable's value, or `fallback` when it is not set.
public String GetOr(String name, String fallback) {
    var value = sl_env_get(name);
    if (value == null) { return fallback; }
    return value;
}

/// Whether a variable is set, whatever it is set to.
public bool Has(String name) { return sl_env_get(name) != null; }

/// Sets a variable for this process and anything it starts afterwards.
///
/// It does not reach the shell that started this program: a process's
/// environment is its own, and a child gets a copy. Reports whether the
/// platform accepted it.
///
/// **An empty value is not portable.** On Windows, setting a variable to the
/// empty string removes it -- `SetEnvironmentVariable` defines it that way,
/// and there is no way around it. On Unix the variable exists and is empty.
/// A program that needs the distinction should not encode it in a variable's
/// value; a program that reads one should use `GetOr` and treat empty and
/// unset alike.
public bool Set(String name, String value) { return sl_env_set(name, value); }

/// Removes a variable, reporting whether the platform accepted it. Removing
/// one that was never set is not a failure.
public bool Remove(String name) { return sl_env_set(name, null); }

/// The name of every variable, in whatever order the platform keeps them.
public String[] Names() {
    var listed = sl_env_names();
    if (listed.ByteLength() == 0u) { return new String[0]; }
    return listed.SplitLines();
}

// ------------------------------------------------------- working directory

/// The directory relative paths are resolved against.
public String CurrentDirectory() { return sl_env_current_directory(); }

/// Changes it, reporting whether the platform accepted it. It fails when the
/// path is not a directory, or is not reachable.
public bool SetCurrentDirectory(String path) {
    return sl_env_set_current_directory(path);
}
