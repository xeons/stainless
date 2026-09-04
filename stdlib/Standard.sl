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
/// It is an ordinary variant, and every rule it appears to have is a rule
/// variants have. `Ok` and `Fail` are its two cases, so `r.Ok` asks the tag;
/// `Value` and `Error` are the fields those cases carry, so reading one needs
/// the compiler to have established which case is there; and both are written
/// without type arguments because a case takes its variant from where it is
/// going, the way a lambda takes its type from what it is assigned to.
///
/// Being a variant is also what makes it small. Only one case is ever present,
/// so the payloads overlap: a `Result<String, IOError>` is a tag and one
/// pointer, not a flag and both halves. Nothing allocates either way.
public variant Result<T, E> {
    Ok(T Value);
    Fail(E Error);

    /// The value if there is one, and `fallback` if there is not.
    ///
    /// The one reader that needs no proof, because it supplies its own: a
    /// caller with a sensible default has nothing to check.
    public T ValueOr(T fallback) {
        switch (this) {
            case Ok ok: return ok.Value;
            case Fail:  return fallback;
        }
    }
}
