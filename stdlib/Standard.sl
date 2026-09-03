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

// The language's own vocabulary: the markers and types that are rules rather
// than library features, and so need no import to reach.
module Standard;

/// What an operation produced, or why it did not.
///
/// This is the language's answer to an exception. Stainless does not unwind, so
/// a function that can fail says so in its return type and the caller cannot
/// quietly ignore it: `Value` is unreadable until the compiler has seen `Ok`
/// checked, and `Error` unreadable until it has seen it fail.
///
/// ```
/// Result<Config, IOError> Load(String path) {
///     var text = File.ReadAllText(path);
///     if (!text.Ok) { return Fail(text.Error); }
///     return Ok(Parse(text.Value));
/// }
/// ```
///
/// It is a struct, so a call that succeeds allocates nothing. Holding a `T`
/// that is a reference is what made structs reference-aware; see the note on
/// SL0284 for what that costs at a C boundary.
///
/// `Ok` and `Fail` are not functions here. They are written without type
/// arguments, which cannot be inferred from one value, so the compiler builds
/// them from the type they are being returned or assigned into -- the same rule
/// a lambda obeys. A module-level function may not be named either of them.
public struct Result<T, E> {
    // Read through `Ok`, `Value` and `Error`, which the compiler resolves to
    // these directly. They are storage rather than API: reaching them by name
    // would be reading `Value` without the check that makes it meaningful.
    bool ok;
    T value;
    E error;

    /// The value if there is one, and `fallback` if there is not.
    ///
    /// The one reader that needs no proof, because it supplies its own: a
    /// caller with a sensible default has nothing to check.
    public T ValueOr(T fallback) {
        if (ok) { return value; }
        return fallback;
    }
}
