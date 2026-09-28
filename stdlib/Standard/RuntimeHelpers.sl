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

module Standard;

/// What the compiler knows about a type, asked from inside a generic. C#'s
/// `System.Runtime.CompilerServices.RuntimeHelpers`.
public static class RuntimeHelpers
{
    /// Whether a `T` is a counted reference or holds one anywhere: a class, an
    /// interface, an array, a `String`, a closure, a weak reference, or a
    /// struct, tuple or variant with one of those in it at any depth.
    ///
    /// **Each call is a constant.** A generic is compiled once per type
    /// argument, so the compiler answers the call where it is bound, and an
    /// `if` on the answer compiles to the one arm it takes. That is what lets
    /// a generic copy move reference-free elements with `memmove` and still
    /// count every reference it copies.
    ///
    ///     if (!RuntimeHelpers.IsReferenceOrContainsReferences<T>())
    ///     {
    ///         // raw bytes: no count can go out of step
    ///     }
    ///
    /// @typeparam T  the type asked about
    /// @returns false when a `T` is all of what it holds, so its bytes may be
    ///          copied, compared or cleared with no count to keep
    public static bool IsReferenceOrContainsReferences<T>() => IsReferenceOrContainsReferences<T>();
}
